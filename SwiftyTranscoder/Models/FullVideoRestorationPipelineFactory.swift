import Foundation

struct FullVideoRestorationResources: Equatable, Sendable {
    static let modelName = "RealESRGAN_x2plus_522_fp16.mlpackage"
    static let sdModelName = "RealESRGAN_x2plus_656x384_fp16.mlpackage"

    let ffmpegURL: URL
    let ffprobeURL: URL
    let modelURL: URL
    var sdModelURL: URL? = nil

    static func locate(
        bundleURL: URL = Bundle.main.bundleURL,
        developmentModelURL: URL? = defaultDevelopmentModelURL,
        developmentSDModelURL: URL? = defaultDevelopmentSDModelURL,
        ffmpegFallbackPaths: [String]? = nil,
        ffprobeFallbackPaths: [String]? = nil,
        fileManager: FileManager = .default
    ) throws -> Self {
        guard let ffmpegURL = MediaToolLocator.executableURL(
            for: .ffmpeg,
            bundleURL: bundleURL,
            fileManager: fileManager,
            fallbackPaths: ffmpegFallbackPaths
        ) else {
            throw FullVideoRestorationFactoryError.ffmpegUnavailable
        }
        guard let ffprobeURL = MediaToolLocator.executableURL(
            for: .ffprobe,
            bundleURL: bundleURL,
            fileManager: fileManager,
            fallbackPaths: ffprobeFallbackPaths
        ) else {
            throw FullVideoRestorationFactoryError.ffprobeUnavailable
        }

        let bundledModelURL = bundleURL
            .appendingPathComponent("Contents/Resources/Models", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)
        let modelCandidates = [bundledModelURL, developmentModelURL].compactMap { $0 }
        guard let modelURL = modelCandidates.first(where: {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: $0.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }) else {
            throw FullVideoRestorationFactoryError.modelUnavailable
        }

        let bundledSDModel = bundleURL.appendingPathComponent("Contents/Resources/Models")
            .appendingPathComponent(sdModelName)
        let sdModelURL = [bundledSDModel, developmentSDModelURL].compactMap { $0 }.first {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        return Self(ffmpegURL: ffmpegURL, ffprobeURL: ffprobeURL, modelURL: modelURL, sdModelURL: sdModelURL)
    }

    func makeFrameProcessor(for plan: RestorationPlan) throws -> RestorationFrameProcessor {
        let tiles = try CoreMLRestorationTileProcessor(modelURL: modelURL)
        let sd = try (plan.sourceWidth == 624 && plan.sourceHeight == 352 ? sdModelURL : nil).map {
            try CoreMLRestorationTileProcessor(modelURL: $0, layout: .sdFrame)
        }
        return RestorationFrameProcessor(tileProcessor: tiles, sdFrameProcessor: sd)
    }

    private static var defaultDevelopmentSDModelURL: URL {
        defaultDevelopmentModelURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("sd-shape-experiment/\(sdModelName)")
    }

    private static var defaultDevelopmentModelURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".build/restoration-evaluation/converter/weights/\(modelName)",
                isDirectory: true
            )
    }
}

protocol FullVideoRestorationPipelineBuilding: Sendable {
    func makePipeline(
        for request: FullVideoRestorationRequest
    ) throws -> any FullVideoRestorationPipelineRunning
}

struct BundledFullVideoRestorationPipelineBuilder: FullVideoRestorationPipelineBuilding, Sendable {
    let bundleURL: URL

    init(bundleURL: URL = Bundle.main.bundleURL) {
        self.bundleURL = bundleURL
    }

    func makePipeline(
        for request: FullVideoRestorationRequest
    ) throws -> any FullVideoRestorationPipelineRunning {
        try FullVideoRestorationPipelineFactory(bundleURL: bundleURL)
            .makePipeline(for: request)
    }
}

struct FullVideoRestorationPipelineFactory: FullVideoRestorationPipelineBuilding, Sendable {
    let resources: FullVideoRestorationResources

    init(resources: FullVideoRestorationResources) {
        self.resources = resources
    }

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) throws {
        resources = try FullVideoRestorationResources.locate(
            bundleURL: bundleURL,
            fileManager: fileManager
        )
    }

    func makePipeline(
        for request: FullVideoRestorationRequest
    ) throws -> any FullVideoRestorationPipelineRunning {
        guard Self.supportsConcatDemuxer(at: resources.ffmpegURL) else {
            throw FullVideoRestorationFactoryError.concatUnavailable
        }
        let frameProcessor = try resources.makeFrameProcessor(for: request.plan)
        let chunkProcessor = try FullRestorationChunkProcessor(
            sourceURL: request.sourceURL,
            workspaceURL: request.workspaceURL,
            plan: request.plan,
            subtitleStreamOrdinal: request.subtitleStreamOrdinal,
            extractor: RestorationFrameExtractor(executableURL: resources.ffmpegURL),
            sequenceProcessor: RestorationFrameSequenceProcessor(
                frameProcessor: frameProcessor
            ),
            assembler: RestorationVideoAssembler(
                ffmpegURL: resources.ffmpegURL,
                ffprobeURL: resources.ffprobeURL
            )
        )

        return FullVideoRestorationPipeline(
            chunkCoordinator: RestorationChunkCoordinator(processor: chunkProcessor),
            segmentConcatenator: RestorationSegmentConcatenator(
                ffmpegURL: resources.ffmpegURL,
                ffprobeURL: resources.ffprobeURL
            ),
            audioMuxer: RestorationAudioMuxer(
                ffmpegURL: resources.ffmpegURL,
                ffprobeURL: resources.ffprobeURL
            ),
            outputPromoter: RestorationOutputPromotionService()
        )
    }

    static func supportsConcatDemuxer(at ffmpegURL: URL) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = ffmpegURL
        process.arguments = ["-hide_banner", "-demuxers"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        let text = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        process.waitUntilExit()
        return process.terminationStatus == 0 && text.split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count >= 2 && fields[0] == "D" && fields[1] == "concat"
        }
    }
}

enum FullVideoRestorationFactoryError: LocalizedError, Equatable {
    case ffmpegUnavailable
    case ffprobeUnavailable
    case modelUnavailable
    case concatUnavailable

    var errorDescription: String? {
        switch self {
        case .ffmpegUnavailable:
            "The bundled FFmpeg helper required for full-video restoration is unavailable."
        case .ffprobeUnavailable:
            "The bundled FFprobe helper required for full-video restoration is unavailable."
        case .modelUnavailable:
            "The bundled AI restoration model is unavailable. Rebuild SwiftyTranscoder after running Scripts/prepare-restoration-model.sh."
        case .concatUnavailable:
            "The FFmpeg helper cannot join restored video segments. Rebuild the bundled toolchain before starting full-video restoration."
        }
    }
}
