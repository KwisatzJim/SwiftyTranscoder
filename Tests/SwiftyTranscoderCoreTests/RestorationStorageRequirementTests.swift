import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationStorageRequirementTests {
    @Test func estimatesBoundedSourceAndRestoredFrameSequences() throws {
        let estimate = try #require(RestorationStorageRequirement.estimate(
            sourceBytes: 2_000_000_000,
            durationSeconds: 2_700,
            frameRate: "24000/1001",
            plan: Self.plan
        ))

        #expect(estimate.frameCount == 64_736)
        #expect(estimate.chunkCount == 540)
        #expect(estimate.maximumResidentFrameCount == 120)
        #expect(estimate.temporaryBytes == 5_601_327_224)
    }

    @Test func accountsForFullDoubleSizeFramesBeforeHDOutputCap() throws {
        let plan = RestorationPlan(
            method: .lightweightFSRCNN, sourceWidth: 1280, sourceHeight: 720,
            outputWidth: 1920, outputHeight: 1080, frameRate: "24/1",
            colorRange: "tv", colorSpace: "bt709", colorTransfer: "bt709", colorPrimaries: "bt709"
        )
        let estimate = try #require(RestorationStorageRequirement.estimate(
            sourceBytes: 0, durationSeconds: 10, frameRate: "24/1", plan: plan
        ))
        let source = try #require(RestorationPNGEncoder.maximumFileBytes(width: 1280, height: 720))
        let restored = try #require(RestorationPNGEncoder.maximumFileBytes(width: 2560, height: 1440))
        #expect(estimate.temporaryBytes == (source + 1024 + restored) * 120 + RestorationStorageRequirement.reserveBytes)
        #expect(estimate.temporaryBytes > 3_200_000_000)
    }

    @Test func rejectsInvalidAndOverflowingInputs() {
        #expect(RestorationStorageRequirement.estimate(
            sourceBytes: -1, durationSeconds: 60, frameRate: "24/1", plan: Self.plan
        ) == nil)
        #expect(RestorationStorageRequirement.estimate(
            sourceBytes: 1, durationSeconds: 0, frameRate: "24/1", plan: Self.plan
        ) == nil)
        #expect(RestorationStorageRequirement.estimate(
            sourceBytes: .max, durationSeconds: .greatestFiniteMagnitude,
            frameRate: "24/1", plan: Self.plan
        ) == nil)
    }

    @Test func exactProbeCountOverridesLongerContainerDuration() throws {
        let estimate = try #require(RestorationStorageRequirement.estimate(
            sourceBytes: 284_751_879,
            durationSeconds: 2_702.613_333,
            frameRate: "77756400/3243011",
            exactFrameCount: 64_797,
            plan: Self.plan
        ))

        #expect(estimate.frameCount == 64_797)
        #expect(estimate.chunkCount == 540)
        let chunks = try RestorationChunkPlan(
            totalFrameCount: estimate.frameCount,
            frameRate: "77756400/3243011",
            workspaceURL: URL(fileURLWithPath: "/private/tmp/SwiftyTranscoder-Restoration-Test")
        ).chunks
        #expect(chunks.last?.frameCount == 117)
    }

    private static let plan = RestorationPlan(
        method: .realESRGANX2Plus,
        sourceWidth: 624,
        sourceHeight: 352,
        outputWidth: 1248,
        outputHeight: 704,
        frameRate: "24000/1001",
        colorRange: "tv",
        colorSpace: "smpte170m",
        colorTransfer: "bt709",
        colorPrimaries: "smpte170m"
    )
}
