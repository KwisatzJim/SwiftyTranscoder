import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct MediaToolLocatorTests {
    @Test func bundledHelperIsPreferredOverFallback() throws {
        let fixture = try ToolLocatorFixture()
        defer { fixture.remove() }
        let bundled = try fixture.makeExecutable(relativePath: "Test.app/Contents/Helpers/ffprobe")
        _ = try fixture.makeExecutable(relativePath: "fallback/ffprobe")

        let result = MediaToolLocator.executableURL(
            for: .ffprobe,
            bundleURL: fixture.root.appendingPathComponent("Test.app"),
            fallbackPaths: [fixture.root.appendingPathComponent("fallback/ffprobe").path]
        )

        #expect(result == bundled)
    }

    @Test func homebrewPathRemainsADevelopmentFallback() throws {
        let fixture = try ToolLocatorFixture()
        defer { fixture.remove() }
        let fallback = try fixture.makeExecutable(relativePath: "fallback/ffmpeg")

        let result = MediaToolLocator.executableURL(
            for: .ffmpeg,
            bundleURL: fixture.root.appendingPathComponent("Test.app"),
            fallbackPaths: [fallback.path]
        )

        #expect(result == fallback)
    }

    @Test func missingHelpersReturnNil() throws {
        let fixture = try ToolLocatorFixture()
        defer { fixture.remove() }

        let result = MediaToolLocator.executableURL(
            for: .ffmpeg,
            bundleURL: fixture.root.appendingPathComponent("Test.app"),
            fallbackPaths: []
        )

        #expect(result == nil)
    }
}

private struct ToolLocatorFixture {
    let root: URL

    init(fileManager: FileManager = .default) throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("SwiftyTranscoder-ToolLocatorTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeExecutable(relativePath: String, fileManager: FileManager = .default) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("tool".utf8).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func remove(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: root)
    }
}
