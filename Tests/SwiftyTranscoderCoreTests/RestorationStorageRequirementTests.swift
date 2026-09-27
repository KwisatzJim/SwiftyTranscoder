import Testing
@testable import SwiftyTranscoderCore

struct RestorationStorageRequirementTests {
    @Test func estimatesCompleteSourceAndRestoredFrameSequences() throws {
        let estimate = try #require(RestorationStorageRequirement.estimate(
            sourceBytes: 2_000_000_000,
            durationSeconds: 2_700,
            frameRate: "24000/1001",
            plan: Self.plan
        ))

        #expect(estimate.frameCount == 64_736)
        #expect(estimate.temporaryBytes == 289_456_400_384)
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
