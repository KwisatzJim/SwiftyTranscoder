import AppKit
import CoreML
import Foundation

struct RestorationFrameGeometry: Equatable, Sendable {
    static let tileSize = 522
    static let overlap = 64
    static let scale = 2

    let sourceWidth: Int
    let sourceHeight: Int
    let paddedWidth: Int
    let paddedHeight: Int
    let leftPadding: Int
    let topPadding: Int
    let xPositions: [Int]
    let yPositions: [Int]

    init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw RestorationFrameProcessorError.invalidDimensions
        }
        sourceWidth = width
        sourceHeight = height
        paddedWidth = max(width, Self.tileSize)
        paddedHeight = max(height, Self.tileSize)
        leftPadding = (paddedWidth - width) / 2
        topPadding = (paddedHeight - height) / 2
        xPositions = Self.tilePositions(length: paddedWidth)
        yPositions = Self.tilePositions(length: paddedHeight)
    }

    var outputWidth: Int { sourceWidth * Self.scale }
    var outputHeight: Int { sourceHeight * Self.scale }
    var tileCount: Int { xPositions.count * yPositions.count }

    static func tilePositions(length: Int) -> [Int] {
        guard length > tileSize else { return [0] }
        let step = tileSize - overlap
        var positions = Array(Swift.stride(from: 0, through: length - tileSize, by: step))
        let final = length - tileSize
        if positions.last != final { positions.append(final) }
        return positions
    }

    static func reflectedIndex(_ index: Int, length: Int) -> Int {
        guard length > 1 else { return 0 }
        var reflected = index
        while reflected < 0 || reflected >= length {
            reflected = reflected < 0 ? -reflected : 2 * length - reflected - 2
        }
        return reflected
    }
}

protocol RestorationFrameProcessing: Sendable {
    func process(
        sourceURL: URL,
        outputURL: URL,
        expectedWidth: Int,
        expectedHeight: Int
    ) async throws -> URL
    func cancel() async
}

struct RestorationFrameTimings: Sendable {
    var decoding = 0.0
    var tensorPreparation = 0.0
    var inference = 0.0
    var blending = 0.0
    var output = 0.0
}

actor RestorationFrameProcessor: RestorationFrameProcessing {
    private let tileProcessor: any RestorationTileProcessing
    private let sdFrameProcessor: (any RestorationTileProcessing)?
    private var cancellationRequested = false
    private(set) var progress = 0.0
    private(set) var latestTimings = RestorationFrameTimings()

    init(tileProcessor: any RestorationTileProcessing, sdFrameProcessor: (any RestorationTileProcessing)? = nil) {
        self.tileProcessor = tileProcessor
        self.sdFrameProcessor = sdFrameProcessor
    }

    func process(
        sourceURL: URL,
        outputURL: URL,
        expectedWidth: Int,
        expectedHeight: Int
    ) async throws -> URL {
        cancellationRequested = false
        progress = 0
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
            throw RestorationFrameProcessorError.sourceMissing
        }
        guard outputURL.pathExtension.lowercased() == "png" else {
            throw RestorationFrameProcessorError.outputMustBePNG
        }
        guard !fileManager.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
            throw RestorationFrameProcessorError.outputExists
        }

        var timings = RestorationFrameTimings()
        var started = ProcessInfo.processInfo.systemUptime
        let source = try Self.loadRGBA(sourceURL)
        timings.decoding = ProcessInfo.processInfo.systemUptime - started
        guard source.width == expectedWidth, source.height == expectedHeight else {
            throw RestorationFrameProcessorError.unexpectedDimensions(
                expectedWidth: expectedWidth,
                expectedHeight: expectedHeight,
                actualWidth: source.width,
                actualHeight: source.height
            )
        }
        if source.width == 624, source.height == 352, let sdFrameProcessor {
            return try await processSDFrame(source, outputURL: outputURL, processor: sdFrameProcessor, timings: timings)
        }
        let geometry = try RestorationFrameGeometry(width: source.width, height: source.height)
        let accumulatedWidth = geometry.paddedWidth * RestorationFrameGeometry.scale
        let accumulatedHeight = geometry.paddedHeight * RestorationFrameGeometry.scale
        var accumulated = [Float](
            repeating: 0,
            count: accumulatedWidth * accumulatedHeight * 3
        )
        var counts = [Float](repeating: 0, count: accumulatedWidth * accumulatedHeight)
        var completedTiles = 0

        for (yIndex, y) in geometry.yPositions.enumerated() {
            for (xIndex, x) in geometry.xPositions.enumerated() {
                try checkCancellation()
                started = ProcessInfo.processInfo.systemUptime
                let input = try Self.makeInputTensor(
                    source: source,
                    geometry: geometry,
                    tileX: x,
                    tileY: y
                )
                timings.tensorPreparation += ProcessInfo.processInfo.systemUptime - started
                started = ProcessInfo.processInfo.systemUptime
                let restored = try await tileProcessor.process(input)
                timings.inference += ProcessInfo.processInfo.systemUptime - started
                try checkCancellation()
                started = ProcessInfo.processInfo.systemUptime
                Self.accumulate(
                    restored.values,
                    into: &accumulated,
                    counts: &counts,
                    accumulatedWidth: accumulatedWidth,
                    tileX: x,
                    tileY: y,
                    xIndex: xIndex,
                    yIndex: yIndex,
                    xPositions: geometry.xPositions,
                    yPositions: geometry.yPositions
                )
                timings.blending += ProcessInfo.processInfo.systemUptime - started
                completedTiles += 1
                progress = Double(completedTiles) / Double(geometry.tileCount)
            }
        }

        started = ProcessInfo.processInfo.systemUptime
        let output = try Self.makeOutputRGBA(
            accumulated: accumulated,
            counts: counts,
            accumulatedWidth: accumulatedWidth,
            geometry: geometry
        )
        try Self.writePNG(output, width: geometry.outputWidth, height: geometry.outputHeight, to: outputURL)
        timings.output = ProcessInfo.processInfo.systemUptime - started
        latestTimings = timings
        return outputURL
    }

    func cancel() async {
        cancellationRequested = true
        await tileProcessor.cancel()
        await sdFrameProcessor?.cancel()
    }

    private func processSDFrame(
        _ source: RGBAImage, outputURL: URL,
        processor: any RestorationTileProcessing, timings initialTimings: RestorationFrameTimings
    ) async throws -> URL {
        var timings = initialTimings
        var started = ProcessInfo.processInfo.systemUptime
        let shape = RestorationModelLayout.sdFrame.inputShape
        let input = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .float16)
        let inputPointer = input.dataPointer.bindMemory(to: Float16.self, capacity: input.count)
        let inputStrides = input.strides.map(\.intValue)
        for y in 0..<shape[2] {
            try checkCancellation()
            let sourceY = RestorationFrameGeometry.reflectedIndex(y - 16, length: source.height)
            for x in 0..<shape[3] {
                let sourceX = RestorationFrameGeometry.reflectedIndex(x - 16, length: source.width)
                let offset = (sourceY * source.width + sourceX) * 4
                for channel in 0..<3 {
                    inputPointer[channel * inputStrides[1] + y * inputStrides[2] + x * inputStrides[3]] =
                        Float16(Float(source.bytes[offset + channel]) / 255)
                }
            }
        }
        timings.tensorPreparation = ProcessInfo.processInfo.systemUptime - started
        started = ProcessInfo.processInfo.systemUptime
        let restored = try await processor.process(RestorationTileTensor(values: input))
        try checkCancellation()
        guard restored.values.shape.map(\.intValue) == RestorationModelLayout.sdFrame.outputShape,
              restored.values.dataType == .float16 else {
            throw CoreMLRestorationError.invalidOutputTensor
        }
        timings.inference = ProcessInfo.processInfo.systemUptime - started
        started = ProcessInfo.processInfo.systemUptime
        let outputWidth = source.width * 2
        let outputHeight = source.height * 2
        var bytes = [UInt8](repeating: 255, count: outputWidth * outputHeight * 4)
        let values = restored.values.dataPointer.bindMemory(to: Float16.self, capacity: restored.values.count)
        let strides = restored.values.strides.map(\.intValue)
        for y in 0..<outputHeight {
            try checkCancellation()
            for x in 0..<outputWidth {
                for channel in 0..<3 {
                    let value = Float(values[channel * strides[1] + (y + 32) * strides[2] + (x + 32) * strides[3]])
                    guard value.isFinite else { throw CoreMLRestorationError.nonFiniteOutput }
                    bytes[(y * outputWidth + x) * 4 + channel] =
                        UInt8(clamping: Int((min(max(value, 0), 1) * 255).rounded()))
                }
            }
        }
        try Self.writePNG(bytes, width: outputWidth, height: outputHeight, to: outputURL)
        timings.output = ProcessInfo.processInfo.systemUptime - started
        latestTimings = timings
        progress = 1
        return outputURL
    }

    private func checkCancellation() throws {
        if cancellationRequested || Task.isCancelled { throw CancellationError() }
    }

    private struct RGBAImage {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    private static func loadRGBA(_ url: URL) throws -> RGBAImage {
        guard let data = try? Data(contentsOf: url),
              let source = NSBitmapImageRep(data: data),
              let destination = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: source.pixelsWide,
                pixelsHigh: source.pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: source.pixelsWide * 4,
                bitsPerPixel: 32
              ), let context = NSGraphicsContext(bitmapImageRep: destination) else {
            throw RestorationFrameProcessorError.couldNotDecode
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(in: NSRect(x: 0, y: 0, width: source.pixelsWide, height: source.pixelsHigh))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = destination.bitmapData else {
            throw RestorationFrameProcessorError.couldNotDecode
        }
        return RGBAImage(
            width: destination.pixelsWide,
            height: destination.pixelsHigh,
            bytes: Array(UnsafeBufferPointer(start: data, count: destination.bytesPerRow * destination.pixelsHigh))
        )
    }

    private static func makeInputTensor(
        source: RGBAImage,
        geometry: RestorationFrameGeometry,
        tileX: Int,
        tileY: Int
    ) throws -> RestorationTileTensor {
        let values = try MLMultiArray(
            shape: RestorationModelContract.expectedInputShape.map(NSNumber.init),
            dataType: .float16
        )
        let pointer = values.dataPointer.bindMemory(to: Float16.self, capacity: values.count)
        let strides = values.strides.map(\.intValue)
        for tileYPosition in 0..<RestorationFrameGeometry.tileSize {
            let paddedY = tileY + tileYPosition
            let sourceY = RestorationFrameGeometry.reflectedIndex(
                paddedY - geometry.topPadding,
                length: source.height
            )
            for tileXPosition in 0..<RestorationFrameGeometry.tileSize {
                let paddedX = tileX + tileXPosition
                let sourceX = RestorationFrameGeometry.reflectedIndex(
                    paddedX - geometry.leftPadding,
                    length: source.width
                )
                let sourceOffset = (sourceY * source.width + sourceX) * 4
                for channel in 0..<3 {
                    let tensorOffset = channel * strides[1]
                        + tileYPosition * strides[2]
                        + tileXPosition * strides[3]
                    pointer[tensorOffset] = Float16(Float(source.bytes[sourceOffset + channel]) / 255)
                }
            }
        }
        return RestorationTileTensor(values: values)
    }

    private static func accumulate(
        _ tile: MLMultiArray,
        into accumulated: inout [Float],
        counts: inout [Float],
        accumulatedWidth: Int,
        tileX: Int,
        tileY: Int,
        xIndex: Int,
        yIndex: Int,
        xPositions: [Int],
        yPositions: [Int]
    ) {
        let outputTileSize = RestorationFrameGeometry.tileSize * RestorationFrameGeometry.scale
        let pointer = tile.dataPointer.bindMemory(to: Float16.self, capacity: tile.count)
        let strides = tile.strides.map(\.intValue)
        let horizontal = axisWeights(index: xIndex, positions: xPositions)
        let vertical = axisWeights(index: yIndex, positions: yPositions)
        let destinationX = tileX * RestorationFrameGeometry.scale
        let destinationY = tileY * RestorationFrameGeometry.scale

        for localY in 0..<outputTileSize {
            for localX in 0..<outputTileSize {
                let weight = vertical[localY] * horizontal[localX]
                let destinationOffset = (destinationY + localY) * accumulatedWidth + destinationX + localX
                counts[destinationOffset] += weight
                for channel in 0..<3 {
                    let tileOffset = channel * strides[1]
                        + localY * strides[2]
                        + localX * strides[3]
                    accumulated[destinationOffset * 3 + channel] += Float(pointer[tileOffset]) * weight
                }
            }
        }
    }

    private static func axisWeights(index: Int, positions: [Int]) -> [Float] {
        let outputTileSize = RestorationFrameGeometry.tileSize * RestorationFrameGeometry.scale
        var weights = [Float](repeating: 1, count: outputTileSize)
        let position = positions[index]
        if index > 0 {
            let overlap = (positions[index - 1] + RestorationFrameGeometry.tileSize - position)
                * RestorationFrameGeometry.scale
            for offset in 0..<overlap {
                weights[offset] = Float(offset) / Float(overlap - 1)
            }
        }
        if index + 1 < positions.count {
            let overlap = (position + RestorationFrameGeometry.tileSize - positions[index + 1])
                * RestorationFrameGeometry.scale
            for offset in 0..<overlap {
                let value = 1 - Float(offset) / Float(overlap - 1)
                let destination = outputTileSize - overlap + offset
                weights[destination] = min(weights[destination], value)
            }
        }
        return weights
    }

    private static func makeOutputRGBA(
        accumulated: [Float],
        counts: [Float],
        accumulatedWidth: Int,
        geometry: RestorationFrameGeometry
    ) throws -> [UInt8] {
        var output = [UInt8](repeating: 255, count: geometry.outputWidth * geometry.outputHeight * 4)
        let cropX = geometry.leftPadding * RestorationFrameGeometry.scale
        let cropY = geometry.topPadding * RestorationFrameGeometry.scale
        for y in 0..<geometry.outputHeight {
            for x in 0..<geometry.outputWidth {
                let sourceOffset = (cropY + y) * accumulatedWidth + cropX + x
                guard counts[sourceOffset] > 0 else {
                    throw RestorationFrameProcessorError.uncoveredOutputPixel
                }
                let outputOffset = (y * geometry.outputWidth + x) * 4
                for channel in 0..<3 {
                    let value = accumulated[sourceOffset * 3 + channel] / counts[sourceOffset]
                    output[outputOffset + channel] = UInt8(clamping: Int((min(max(value, 0), 1) * 255).rounded()))
                }
            }
        }
        return output
    }

    private static func writePNG(_ bytes: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ), let destination = representation.bitmapData else {
            throw RestorationFrameProcessorError.couldNotEncode
        }
        destination.update(from: bytes, count: bytes.count)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw RestorationFrameProcessorError.couldNotEncode
        }
        try data.write(to: url, options: .withoutOverwriting)
    }
}

enum RestorationFrameProcessorError: LocalizedError, Equatable {
    case sourceMissing
    case outputMustBePNG
    case outputExists
    case couldNotDecode
    case invalidDimensions
    case unexpectedDimensions(expectedWidth: Int, expectedHeight: Int, actualWidth: Int, actualHeight: Int)
    case uncoveredOutputPixel
    case couldNotEncode

    var errorDescription: String? {
        switch self {
        case .sourceMissing: "The restoration source frame is unavailable."
        case .outputMustBePNG: "The restored frame must use the .png extension."
        case .outputExists: "The restored frame already exists and will not be overwritten."
        case .couldNotDecode: "The restoration source frame could not be decoded as RGB pixels."
        case .invalidDimensions: "The restoration frame dimensions are invalid."
        case .unexpectedDimensions(let expectedWidth, let expectedHeight, let actualWidth, let actualHeight):
            "Expected a \(expectedWidth) × \(expectedHeight) frame but found \(actualWidth) × \(actualHeight)."
        case .uncoveredOutputPixel: "Tile blending left an output pixel uncovered."
        case .couldNotEncode: "The restored frame could not be encoded as PNG."
        }
    }
}
