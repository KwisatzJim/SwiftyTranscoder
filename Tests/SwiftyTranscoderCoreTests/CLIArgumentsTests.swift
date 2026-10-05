import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct CLIArgumentsTests {
    @Test func parsesPlexExampleAndMP4Gain() throws {
        let options = try CLIArguments(["/tmp/input with spaces.mp4", "--preset", "plex",
                                        "--output", "/tmp/output with spaces.mp4", "--gain-db", "6"])
        #expect(options.input == "/tmp/input with spaces.mp4")
        #expect(options.gainDB == 6)
        #expect(options.aacStereo)
        #expect(options.restorationMethod == nil)
    }

    @Test func parsesExplicitChoicesAndDryRun() throws {
        let options = try CLIArguments(["input.mkv", "--output", "output.mp4", "--gain-db", "0",
                                        "--aac-stereo", "off", "--subtitles", "3", "--assume-bt709", "--dry-run"])
        #expect(options.gainDB == 0)
        #expect(!options.aacStereo)
        #expect(options.subtitles == "3")
        #expect(options.assumeBT709 && options.dryRun)
    }

    @Test func parsesExplicitLightweightRestoration() throws {
        let options = try CLIArguments(["input.m4v", "--output", "output.mp4", "--restore", "lightweight", "--dry-run"])
        #expect(options.restorationMethod == .lightweightFSRCNN)
        #expect(options.dryRun)
    }

    @Test func parsesExplicitSavedJobAndResume() throws {
        let args = ["input.m4v", "--output", "output.mp4", "--restore", "lightweight", "--checkpoint-dir", "/tmp/SwiftyTranscoder-Restoration-Pilot"]
        #expect(try CLIArguments(args).checkpointDirectory == "/tmp/SwiftyTranscoder-Restoration-Pilot")
        #expect(try CLIArguments(args + ["--resume"]).resume)
        #expect(throws: CLIUsageError.self) { try CLIArguments(["input.m4v", "--output", "output.mp4", "--resume"]) }
        #expect(throws: CLIUsageError.self) { try CLIArguments(["input.m4v", "--output", "output.mp4", "--checkpoint-dir", "/tmp/SwiftyTranscoder-Restoration-Pilot"]) }
        #expect(throws: CLIUsageError.self) { try CLIArguments(args.dropLast().map { $0 } + ["/tmp/unrelated"]) }
    }

    @Test func acceptsHelpWithoutPathsAndDashPrefixedInput() throws {
        #expect(try CLIArguments(["--help"]).help)
        let options = try CLIArguments(["--output", "result.mp4", "--", "-input.mkv"])
        #expect(options.input == "-input.mkv")
    }

    @Test(arguments: [
        ["input.mkv"],
        ["input.mkv", "--output"],
        ["input.mkv", "--output", "result.mp4", "--gain-db", "12"],
        ["input.mkv", "--output", "result.mp4", "--gain-db", "6", "--gain-db", "0"],
        ["input.mkv", "--output", "result.mp4", "--preset", "unknown"],
        ["input.mkv", "--output", "result.mp4", "--subtitles", "-1"],
        ["input.mp4", "--output", "input.mp4"],
        ["input.avi", "--output", "result.mp4"],
        ["input.mkv", "--output", "result.mkv"],
        ["input.mkv", "second.mkv", "--output", "result.mp4"],
        ["input.mkv", "--output", "result.mp4", "--unknown"],
        ["input.mkv", "--output", "result.mp4", "--restore"],
        ["input.mkv", "--output", "result.mp4", "--restore", "unknown"],
        ["input.mkv", "--output", "result.mp4", "--restore", "lightweight", "--restore", "lightweight"]
    ]) func rejectsInvalidOrAmbiguousRequests(_ arguments: [String]) {
        #expect(throws: CLIUsageError.self) { try CLIArguments(arguments) }
    }
}
