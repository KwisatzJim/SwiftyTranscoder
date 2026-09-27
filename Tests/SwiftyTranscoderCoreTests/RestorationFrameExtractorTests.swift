import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationFrameExtractorTests {
    @Test func buildsBoundedNonOverwritingFFmpegArguments() throws {
        let extraction = try RestorationFrameExtraction(
            sourceURL: URL(fileURLWithPath: "/Media/Older Show.m4v"),
            workspaceURL: URL(fileURLWithPath: "/tmp/job-1"),
            startSeconds: 12.3456,
            frameCount: 48
        )

        #expect(extraction.outputDirectoryURL.path == "/tmp/job-1/source-frames")
        #expect(extraction.ffmpegArguments.contains("-n"))
        #expect(extraction.ffmpegArguments.contains("12.346"))
        #expect(extraction.ffmpegArguments.contains("48"))
        #expect(extraction.ffmpegArguments.contains("rgb24"))
        #expect(extraction.ffmpegArguments.last == "/tmp/job-1/source-frames/frame-%08d.png")
    }

    @Test(arguments: [0, -1, 241])
    func rejectsUnboundedFrameCounts(frameCount: Int) {
        #expect(throws: RestorationFrameExtractorError.invalidFrameCount) {
            try RestorationFrameExtraction(
                sourceURL: URL(fileURLWithPath: "/Media/source.m4v"),
                workspaceURL: URL(fileURLWithPath: "/tmp/job"),
                startSeconds: 0,
                frameCount: frameCount
            )
        }
    }

    @Test func extractsAndValidatesExactNonemptyFrameSequence() async throws {
        let fixture = try FrameExtractorFixture(mode: .success)
        defer { fixture.remove() }
        let extraction = try fixture.extraction(frameCount: 3)
        let extractor = RestorationFrameExtractor(executableURL: fixture.executableURL)

        let frames = try await extractor.extract(extraction)

        #expect(frames.map(\.lastPathComponent) == [
            "frame-00000001.png", "frame-00000002.png", "frame-00000003.png",
        ])
        #expect(await extractor.progress == 1)
    }

    @Test func refusesToReuseExistingFrameDirectory() async throws {
        let fixture = try FrameExtractorFixture(mode: .success)
        defer { fixture.remove() }
        let extraction = try fixture.extraction(frameCount: 1)
        try FileManager.default.createDirectory(
            at: extraction.outputDirectoryURL,
            withIntermediateDirectories: true
        )
        let extractor = RestorationFrameExtractor(executableURL: fixture.executableURL)

        await #expect(throws: RestorationFrameExtractorError.outputDirectoryExists) {
            try await extractor.extract(extraction)
        }
    }

    @Test func cancellationTerminatesActiveExtraction() async throws {
        let fixture = try FrameExtractorFixture(mode: .waitForCancellation)
        defer { fixture.remove() }
        let extraction = try fixture.extraction(frameCount: 3)
        let extractor = RestorationFrameExtractor(executableURL: fixture.executableURL)
        let task = Task { try await extractor.extract(extraction) }

        while await extractor.progress == 0 {
            await Task.yield()
        }
        await extractor.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}

private struct FrameExtractorFixture {
    enum Mode { case success, waitForCancellation }

    let rootURL: URL
    let executableURL: URL
    let sourceURL: URL
    let workspaceURL: URL

    init(mode: Mode) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftyTranscoder-FrameExtractorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        sourceURL = rootURL.appendingPathComponent("source.m4v")
        workspaceURL = rootURL.appendingPathComponent("workspace")
        executableURL = rootURL.appendingPathComponent("fake-ffmpeg")
        try Data("source".utf8).write(to: sourceURL)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let waitForCancellation = mode == .waitForCancellation
            ? "if [ \"$index\" -eq 1 ]; then while :; do :; done; fi"
            : ""
        let script = """
        #!/bin/sh
        count=0
        previous=""
        for argument in "$@"; do
            if [ "$previous" = "-frames:v" ]; then count="$argument"; fi
            previous="$argument"
            pattern="$argument"
        done
        index=1
        while [ "$index" -le "$count" ]; do
            number=$(printf "%08d" "$index")
            output=$(printf "%s" "$pattern" | sed "s/%08d/$number/")
            printf "frame data" > "$output"
            printf "frame=%s\\n" "$index"
            \(waitForCancellation)
            index=$((index + 1))
        done
        exit 0
        """
        try Data(script.utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    func extraction(frameCount: Int) throws -> RestorationFrameExtraction {
        try RestorationFrameExtraction(
            sourceURL: sourceURL,
            workspaceURL: workspaceURL,
            startSeconds: 9,
            frameCount: frameCount
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
