import Testing
@testable import SwiftyTranscoderCore

struct OutputResolutionTests {
    @Test func reducesHDAndPreservesSmallerSources() {
        #expect(OutputResolution.p720.dimensions(width: 1920, height: 1080) == .init(width: 1280, height: 720))
        #expect(OutputResolution.p480.dimensions(width: 1920, height: 1080) == .init(width: 852, height: 480))
        #expect(OutputResolution.p480.dimensions(width: 1280, height: 720) == .init(width: 852, height: 480))
        #expect(OutputResolution.p720.dimensions(width: 624, height: 352) == .init(width: 624, height: 352))
        #expect(OutputResolution.original.dimensions(width: 1920, height: 1080) == .init(width: 1920, height: 1080))
    }

    @Test func boundsPortraitAndWideVideoWithEvenDimensions() {
        #expect(OutputResolution.p720.dimensions(width: 1080, height: 1920) == .init(width: 720, height: 1280))
        #expect(OutputResolution.p480.dimensions(width: 1920, height: 800) == .init(width: 854, height: 354))
        #expect(OutputResolution.p480.dimensions(width: 0, height: 1080) == nil)
    }

    @Test func parsesExplicitSizeAndRejectsIncompatibleAI() throws {
        let args = try CLIArguments(["/tmp/input.mp4", "--output", "/tmp/out.mp4", "--resolution", "480p", "--audio", "omit"])
        #expect(args.outputResolution == .p480)
        #expect(throws: CLIUsageError.self) { try CLIArguments(["/tmp/input.mp4", "--output", "/tmp/out.mp4", "--resolution", "1080p"]) }
        #expect(throws: CLIUsageError.self) { try CLIArguments(["/tmp/input.mp4", "--output", "/tmp/out.mp4", "--resolution", "720p", "--restore", "lightweight"]) }
    }
}
