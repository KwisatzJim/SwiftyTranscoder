import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationVideoAssemblerTests {
    @Test func buildsHardwareOnlySilentHEVCCommand() throws {
        let fixture = try VideoAssemblerFixture(frameCount: 4)
        defer { fixture.remove() }
        let arguments = fixture.assembly.ffmpegArguments

        #expect(arguments.contains("hevc_videotoolbox"))
        #expect(arguments.contains("-allow_sw"))
        #expect(arguments.contains("0"))
        #expect(arguments.contains("-an"))
        #expect(arguments.contains("hvc1"))
        #expect(arguments.contains("24000/1001"))
        #expect(arguments.contains("setparams=range=limited:color_primaries=smpte170m:color_trc=bt709:colorspace=smpte170m"))
        #expect(fixture.assembly.inputPatternURL.lastPathComponent == "frame-%08d.png")
        #expect(fixture.assembly.outputURL.lastPathComponent == "restored-video.partial.mp4")
    }

    @Test func acceptsEquivalentContainerFrameRateButRejectsChangedCadence() {
        #expect(RestorationVideoAssembler.frameRatesMatch("23976/1000", "24000/1001"))
        #expect(RestorationVideoAssembler.frameRatesMatch("77756400/3243011", "24000/1001"))
        #expect(!RestorationVideoAssembler.frameRatesMatch("24/1", "24000/1001"))
    }

    @Test func burnsApprovedSubtitleAtAbsoluteChunkTimeDuringOnlyVideoEncode() throws {
        let fixture = try VideoAssemblerFixture(frameCount: 2)
        defer { fixture.remove() }
        let source = fixture.rootURL.appendingPathComponent("source with subtitle.mkv")
        try Data("source".utf8).write(to: source)
        let subtitle = try RestorationSubtitleBurn(
            sourceURL: source,
            subtitleStreamOrdinal: 1,
            chunkStartSeconds: 5.005
        )
        let assembly = try RestorationVideoAssembly(
            frameURLs: fixture.frameURLs,
            workspaceURL: fixture.workspaceURL,
            plan: fixture.plan,
            subtitleBurn: subtitle
        )
        let filter = try #require(assembly.ffmpegArguments.dropFirst().first { $0.contains("subtitles=") })

        #expect(filter.contains("setpts=PTS+5.005000000/TB"))
        #expect(filter.contains("stream_index=1"))
        #expect(filter.contains("setpts=PTS-STARTPTS"))
        #expect(filter.contains("setparams=range=limited"))
    }

    @Test func rejectsIncompleteNumericSequence() throws {
        let fixture = try VideoAssemblerFixture(frameCount: 2)
        defer { fixture.remove() }
        let second = fixture.frameURLs[1].deletingLastPathComponent()
            .appendingPathComponent("frame-00000003.png")

        #expect(throws: RestorationVideoAssemblerError.invalidFrameSequence) {
            try RestorationVideoAssembly(
                frameURLs: [fixture.frameURLs[0], second],
                workspaceURL: fixture.workspaceURL,
                plan: fixture.plan
            )
        }
    }

    @Test func assemblesAndValidatesWithMediaHelperBoundary() async throws {
        let fixture = try VideoAssemblerFixture(frameCount: 4)
        defer { fixture.remove() }
        let helpers = try fixture.makeSuccessfulHelpers()
        let assembler = RestorationVideoAssembler(
            ffmpegURL: helpers.ffmpeg,
            ffprobeURL: helpers.ffprobe
        )

        let output = try await assembler.assemble(fixture.assembly)

        #expect(output == fixture.assembly.outputURL)
        #expect(await assembler.progress == 1)
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test func refusesExistingPartialOutput() async throws {
        let fixture = try VideoAssemblerFixture(frameCount: 1)
        defer { fixture.remove() }
        let helpers = try fixture.makeSuccessfulHelpers()
        try Data("existing".utf8).write(to: fixture.assembly.outputURL)
        let assembler = RestorationVideoAssembler(
            ffmpegURL: helpers.ffmpeg,
            ffprobeURL: helpers.ffprobe
        )

        await #expect(throws: RestorationVideoAssemblerError.outputExists) {
            try await assembler.assemble(fixture.assembly)
        }
    }

    @Test func cancellationStopsEncodingAndKeepsLabeledPartialOutput() async throws {
        let fixture = try VideoAssemblerFixture(frameCount: 4)
        defer { fixture.remove() }
        let helpers = try fixture.makeCancellableHelpers()
        let assembler = RestorationVideoAssembler(
            ffmpegURL: helpers.ffmpeg,
            ffprobeURL: helpers.ffprobe
        )
        let task = Task { try await assembler.assemble(fixture.assembly) }

        while await assembler.progress == 0 { await Task.yield() }
        await assembler.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(FileManager.default.fileExists(atPath: fixture.assembly.outputURL.path))
        #expect(fixture.assembly.outputURL.lastPathComponent.hasSuffix(".partial.mp4"))
    }

    @Test func assemblesRepresentativeSequenceWithHardwareHEVCWhenAvailable() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let referenceDirectory = root.appendingPathComponent(
            ".build/restoration-evaluation/comparisons/Alphas - s01e11 - Original Sin"
        )
        let referenceURLs = (1...4).map {
            referenceDirectory.appendingPathComponent(
                String(format: "frame-%02d-real-esrgan.png", $0)
            )
        }
        guard referenceURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }),
              let ffmpeg = MediaToolLocator.executableURL(for: .ffmpeg, bundleURL: root),
              let ffprobe = MediaToolLocator.executableURL(for: .ffprobe, bundleURL: root) else { return }
        let workspaceURL = URL(fileURLWithPath: "/private/tmp/SwiftyTranscoder-Milestone72-video")
        try? FileManager.default.removeItem(at: workspaceURL)
        let frameDirectory = workspaceURL.appendingPathComponent("restored-frames")
        try FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true)
        let frameURLs = try zip(1...4, referenceURLs).map { index, referenceURL in
            let url = frameDirectory.appendingPathComponent(String(format: "frame-%02d.png", index))
            try FileManager.default.copyItem(at: referenceURL, to: url)
            return url
        }
        let assembly = try RestorationVideoAssembly(
            frameURLs: frameURLs,
            workspaceURL: workspaceURL,
            plan: Self.plan
        )
        let assembler = RestorationVideoAssembler(ffmpegURL: ffmpeg, ffprobeURL: ffprobe)

        let output = try await assembler.assemble(assembly)

        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(await assembler.progress == 1)
    }

    fileprivate static let plan = RestorationPlan(
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

private struct VideoAssemblerFixture {
    let rootURL: URL
    let workspaceURL: URL
    let frameURLs: [URL]
    let plan = RestorationVideoAssemblerTests.plan
    let assembly: RestorationVideoAssembly

    init(frameCount: Int) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftyTranscoder-VideoAssemblerTests-\(UUID().uuidString)")
        workspaceURL = rootURL.appendingPathComponent("workspace")
        let frames = workspaceURL.appendingPathComponent("restored-frames")
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        frameURLs = try (1...frameCount).map { index in
            let url = frames.appendingPathComponent(String(format: "frame-%08d.png", index))
            try Data("frame \(index)".utf8).write(to: url)
            return url
        }
        assembly = try RestorationVideoAssembly(
            frameURLs: frameURLs,
            workspaceURL: workspaceURL,
            plan: plan
        )
    }

    func makeSuccessfulHelpers() throws -> (ffmpeg: URL, ffprobe: URL) {
        let ffmpeg = rootURL.appendingPathComponent("fake-ffmpeg")
        let ffprobe = rootURL.appendingPathComponent("fake-ffprobe")
        let encoder = """
        #!/bin/sh
        for output in "$@"; do :; done
        printf "video" > "$output"
        printf "frame=4\\n"
        exit 0
        """
        let probe = """
        #!/bin/sh
        printf '%s' '{"streams":[{"index":0,"codec_name":"hevc","codec_tag_string":"hvc1","profile":"Main","codec_type":"video","width":1248,"height":704,"pix_fmt":"yuv420p","color_range":"tv","color_space":"smpte170m","color_transfer":"bt709","color_primaries":"smpte170m","avg_frame_rate":"24000/1001"}],"chapters":[],"format":{"duration":"0.167","size":"5"}}'
        exit 0
        """
        try writeExecutable(encoder, to: ffmpeg)
        try writeExecutable(probe, to: ffprobe)
        return (ffmpeg, ffprobe)
    }

    func makeCancellableHelpers() throws -> (ffmpeg: URL, ffprobe: URL) {
        let helpers = try makeSuccessfulHelpers()
        let encoder = """
        #!/bin/sh
        for output in "$@"; do :; done
        printf "partial video" > "$output"
        printf "frame=1\\n"
        while :; do :; done
        """
        try writeExecutable(encoder, to: helpers.ffmpeg)
        return helpers
    }

    func remove() { try? FileManager.default.removeItem(at: rootURL) }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
