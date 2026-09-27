import CoreML
import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationFrameProcessorTests {
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
