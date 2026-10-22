import Testing
@testable import SwiftyTranscoderCore

struct AppLaunchArgumentsTests {
    @Test func xcodeLaunchOpensGUI() {
        #expect(AppLaunchArguments.userArguments(["-NSDocumentRevisionsDebugMode", "YES"]).isEmpty)
        #expect(AppLaunchArguments.userArguments(["-NSPersistenceIgnoreState", "NO", "-psn_0_123"]).isEmpty)
    }

    @Test func conversionArgumentsSurviveXcodeOptions() throws {
        let arguments = ["-NSDocumentRevisionsDebugMode", "YES", "/tmp/input.mkv", "--output", "/tmp/output.mp4"]
        let filtered = AppLaunchArguments.userArguments(arguments)
        #expect(filtered == Array(arguments.dropFirst(2)))
        #expect(try CLIArguments(filtered).input == "/tmp/input.mkv")
    }

    @Test func unknownAndMalformedOptionsRemainErrors() {
        for arguments in [["--typo"], ["-NSDocumentRevisionsDebugMode"], ["-NSDocumentRevisionsDebugMode", "unexpected"]] {
            #expect(AppLaunchArguments.userArguments(arguments) == arguments)
            #expect(throws: CLIUsageError.self) { try CLIArguments(AppLaunchArguments.userArguments(arguments)) }
        }
    }

    @Test func explicitPositionalPathsAreUntouched() {
        let arguments = ["--", "-NSDocumentRevisionsDebugMode", "YES", "-psn_example"]
        #expect(AppLaunchArguments.userArguments(arguments) == arguments)
    }
}
