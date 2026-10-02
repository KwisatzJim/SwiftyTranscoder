import AppKit
import CoreML
import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationFrameProcessorTests {
    @Test func restoresApprovedSDFrameWithNativeSingleFrameModelWhenAvailable() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let research = root.appendingPathComponent(".build/restoration-evaluation")
        let model = research.appendingPathComponent("sd-shape-experiment/RealESRGAN_x2plus_656x384_fp16.mlpackage")
        let source = research.appendingPathComponent("sd-shape-experiment/face/source-frames/frame-0001.png")
        let reference = research.appendingPathComponent("sd-shape-experiment/face/experimental-frame.png")
        guard FileManager.default.fileExists(atPath: model.path),
              FileManager.default.fileExists(atPath: reference.path) else { return }
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftyTranscoder-SDNative-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let worker = try CoreMLRestorationTileProcessor(modelURL: model, layout: .sdFrame)
        let frames = RestorationFrameProcessor(tileProcessor: worker, sdFrameProcessor: worker)
        let output = try await frames.process(sourceURL: source, outputURL: workspace.appendingPathComponent("frame.png"), expectedWidth: 624, expectedHeight: 352)
        try Data(contentsOf: output).write(to: research.appendingPathComponent("sd-shape-experiment/native-frame.png"), options: .atomic)
        let actual = try #require(NSBitmapImageRep(data: Data(contentsOf: output)))
        let expected = try #require(NSBitmapImageRep(data: Data(contentsOf: reference)))
        #expect(actual.pixelsWide == 1248 && actual.pixelsHigh == 704)
        func rgba(_ representation: NSBitmapImageRep) throws -> [UInt8] {
            let image = try #require(representation.cgImage)
            var bytes = [UInt8](repeating: 0, count: 1248 * 704 * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(
                    data: buffer.baseAddress, width: 1248, height: 704, bitsPerComponent: 8,
                    bytesPerRow: 1248 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1248, height: 704))
            }
            return bytes
        }
        let a = try rgba(actual)
        let b = try rgba(expected)
        var difference = 0.0
        for y in 0..<704 {
            for x in 0..<1248 {
                for c in 0..<3 {
                    difference += abs(Double(a[(y * 1248 + x) * 4 + c]) - Double(b[(y * 1248 + x) * 4 + c]))
                }
            }
        }
        let mean = difference / Double(1248 * 704 * 3)
        print("Native SD frame mean RGB difference from approved research output: \(mean)")
        // The native AppKit RGB path also differs slightly from Pillow in the
        // previously validated tiled processor. Bound drift and review the frame.
        #expect(mean < 5.0)
        #expect(await frames.progress == 1)
    }
    @Test func matchesConfirmedSDTileGeometry() throws {
        let geometry = try RestorationFrameGeometry(width: 624, height: 352)
        #expect(geometry.paddedWidth == 624)
        #expect(geometry.paddedHeight == 522)
        #expect(geometry.leftPadding == 0)
        #expect(geometry.topPadding == 85)
        #expect(geometry.xPositions == [0, 102])
        #expect(geometry.yPositions == [0])
        #expect(geometry.tileCount == 2)
        #expect(geometry.outputWidth == 1248)
        #expect(geometry.outputHeight == 704)
    }

    @Test func addsFinalOverlappingTileForNonMultipleWidth() throws {
        let geometry = try RestorationFrameGeometry(width: 1280, height: 720)
        #expect(geometry.xPositions == [0, 458, 758])
        #expect(geometry.yPositions == [0, 198])
        #expect(geometry.tileCount == 6)
    }

    @Test func reflectionExcludesEdgePixelLikeReferenceHarness() {
        #expect(RestorationFrameGeometry.reflectedIndex(-1, length: 4) == 1)
        #expect(RestorationFrameGeometry.reflectedIndex(-2, length: 4) == 2)
        #expect(RestorationFrameGeometry.reflectedIndex(4, length: 4) == 2)
        #expect(RestorationFrameGeometry.reflectedIndex(5, length: 4) == 1)
    }

    @Test func restoresRepresentativeFrameWhenResearchModelIsAvailable() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let modelURL = root.appendingPathComponent(
            ".build/restoration-evaluation/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage"
        )
        let sourceURL = root.appendingPathComponent(
            ".build/restoration-evaluation/comparisons/Alphas - s01e11 - Original Sin/source-frames/frame-01.png"
        )
        guard FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        let outputURL = URL(fileURLWithPath: "/private/tmp/SwiftyTranscoder-Milestone70-native-frame-01.png")
        try? FileManager.default.removeItem(at: outputURL)

        let tiles = try CoreMLRestorationTileProcessor(modelURL: modelURL)
        let processor = RestorationFrameProcessor(tileProcessor: tiles)
        let result = try await processor.process(
            sourceURL: sourceURL,
            outputURL: outputURL,
            expectedWidth: 624,
            expectedHeight: 352
        )

        #expect(result == outputURL)
        #expect(await processor.progress == 1)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }
}
