import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationSegmentConcatenatorTests {
    @Test func buildsOrderedCopyOnlyConcatRequest() throws {
        let fixture = try SegmentFixture(segmentCount: 3)
        defer { fixture.remove() }

        #expect(fixture.request.ffmpegArguments.contains("concat"))
        #expect(fixture.request.ffmpegArguments.contains("copy"))
        #expect(!fixture.request.ffmpegArguments.contains("hevc_videotoolbox"))
        #expect(fixture.request.manifestContents.contains("segment-000001.partial.mp4"))
        #expect(fixture.request.outputURL.lastPathComponent == "restored-silent.partial.mp4")
    }

    @Test func rejectsMissingOrOutOfOrderSegmentSequence() throws {
        let fixture = try SegmentFixture(segmentCount: 3)
        defer { fixture.remove() }

        #expect(throws: RestorationSegmentConcatenatorError.invalidSegmentSequence) {
            try RestorationSegmentConcatenation(
                segmentURLs: [fixture.segmentURLs[0], fixture.segmentURLs[2]],
                workspaceURL: fixture.workspaceURL,
                plan: fixture.plan,
                totalFrameCount: 301
            )
        }
    }

    @Test func joinsThenIndependentlyValidatesSilentVideo() async throws {
        let fixture = try SegmentFixture(segmentCount: 3)
        defer { fixture.remove() }
        let helpers = try fixture.makeSuccessfulHelpers()
        let concatenator = RestorationSegmentConcatenator(
            ffmpegURL: helpers.ffmpeg,
            ffprobeURL: helpers.ffprobe
        )

        let output = try await concatenator.concatenate(fixture.request)

        #expect(output == fixture.request.outputURL)
        #expect(await concatenator.progress == 1)
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.request.manifestURL.path))
        #expect(fixture.segmentURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func joinsRealHEVCSegmentsWithStagedHelperWhenAvailable() async throws {
        let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let referenceDirectory = projectURL.appendingPathComponent(
            ".build/restoration-evaluation/comparisons/Alphas - s01e11 - Original Sin"
        )
        let referenceURLs = (1...4).map {
            referenceDirectory.appendingPathComponent(
                String(format: "frame-%02d-real-esrgan.png", $0)
            )
        }
        let toolDirectory = projectURL.appendingPathComponent(".build/toolchain/stage/bin")
        let ffmpeg = toolDirectory.appendingPathComponent("ffmpeg")
        let ffprobe = toolDirectory.appendingPathComponent("ffprobe")
        guard referenceURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }),
              FileManager.default.isExecutableFile(atPath: ffmpeg.path),
              FileManager.default.isExecutableFile(atPath: ffprobe.path) else { return }

        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftyTranscoder-Restoration-RealConcat-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        let segmentDirectory = workspaceURL.appendingPathComponent("segments")
        try FileManager.default.createDirectory(at: segmentDirectory, withIntermediateDirectories: true)

        var segmentURLs: [URL] = []
        for index in 1...2 {
            let chunkURL = workspaceURL.appendingPathComponent("chunk-\(index)")
            let framesURL = chunkURL.appendingPathComponent("restored-frames")
            try FileManager.default.createDirectory(at: framesURL, withIntermediateDirectories: true)
            let frameURLs = try zip(1...4, referenceURLs).map { number, referenceURL in
                let target = framesURL.appendingPathComponent(
                    String(format: "frame-%08d.png", number)
                )
                try FileManager.default.copyItem(at: referenceURL, to: target)
                return target
            }
            let assembly = try RestorationVideoAssembly(
                frameURLs: frameURLs,
                workspaceURL: chunkURL,
                plan: Self.realPlan
            )
            let encodedURL = try await RestorationVideoAssembler(
                ffmpegURL: ffmpeg, ffprobeURL: ffprobe
            ).assemble(assembly)
            let segmentURL = segmentDirectory.appendingPathComponent(
                String(format: "segment-%06d.partial.mp4", index)
            )
            try FileManager.default.moveItem(at: encodedURL, to: segmentURL)
            segmentURLs.append(segmentURL)
        }

        let request = try RestorationSegmentConcatenation(
            segmentURLs: segmentURLs,
            workspaceURL: workspaceURL,
            plan: Self.realPlan,
            totalFrameCount: 8
        )
        let output = try await RestorationSegmentConcatenator(
            ffmpegURL: ffmpeg, ffprobeURL: ffprobe
        ).concatenate(request)
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(!FileManager.default.fileExists(atPath: request.manifestURL.path))
    }

    @Test func cancellationKeepsOnlyClearlyLabeledPartialVideo() async throws {
        let fixture = try SegmentFixture(segmentCount: 2)
        defer { fixture.remove() }
        let helpers = try fixture.makeCancellableHelpers()
        let concatenator = RestorationSegmentConcatenator(
            ffmpegURL: helpers.ffmpeg,
            ffprobeURL: helpers.ffprobe
        )
        let task = Task { try await concatenator.concatenate(fixture.request) }

        while !FileManager.default.fileExists(atPath: fixture.request.outputURL.path) {
            await Task.yield()
        }
        await concatenator.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.request.outputURL.lastPathComponent.hasSuffix(".partial.mp4"))
        #expect(FileManager.default.fileExists(atPath: fixture.request.outputURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.request.manifestURL.path))
    }

    private static let realPlan = RestorationPlan(
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

private struct SegmentFixture {
    let rootURL: URL
    let workspaceURL: URL
    let segmentURLs: [URL]
    let plan = RestorationPlan(
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
    let request: RestorationSegmentConcatenation

    init(segmentCount: Int) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftyTranscoder-SegmentTests-\(UUID().uuidString)")
        workspaceURL = rootURL.appendingPathComponent("SwiftyTranscoder-Restoration-Segments")
        let segmentDirectory = workspaceURL.appendingPathComponent("segments")
        try FileManager.default.createDirectory(at: segmentDirectory, withIntermediateDirectories: true)
        segmentURLs = try (1...segmentCount).map { index in
            let url = segmentDirectory.appendingPathComponent(
                String(format: "segment-%06d.partial.mp4", index)
            )
            try Data("segment \(index)".utf8).write(to: url)
            return url
        }
        request = try RestorationSegmentConcatenation(
            segmentURLs: segmentURLs,
            workspaceURL: workspaceURL,
            plan: plan,
            totalFrameCount: 301
        )
    }

    func makeSuccessfulHelpers() throws -> (ffmpeg: URL, ffprobe: URL) {
        let ffmpeg = rootURL.appendingPathComponent("fake-ffmpeg")
        let ffprobe = rootURL.appendingPathComponent("fake-ffprobe")
        let joiner = """
        #!/bin/sh
        for output in "$@"; do :; done
        printf "joined video" > "$output"
        exit 0
        """
        let probe = """
        #!/bin/sh
        printf '%s' '{"streams":[{"index":0,"codec_name":"hevc","codec_tag_string":"hvc1","profile":"Main","codec_type":"video","width":1248,"height":704,"pix_fmt":"yuv420p","color_range":"tv","color_space":"smpte170m","color_transfer":"bt709","color_primaries":"smpte170m","avg_frame_rate":"24000/1001"}],"chapters":[],"format":{"duration":"12.554","size":"12"}}'
        exit 0
        """
        try writeExecutable(joiner, to: ffmpeg)
        try writeExecutable(probe, to: ffprobe)
        return (ffmpeg, ffprobe)
    }

    func makeCancellableHelpers() throws -> (ffmpeg: URL, ffprobe: URL) {
        let helpers = try makeSuccessfulHelpers()
        let joiner = """
        #!/bin/sh
        for output in "$@"; do :; done
        printf "partial joined video" > "$output"
        while :; do :; done
        """
        try writeExecutable(joiner, to: helpers.ffmpeg)
        return helpers
    }

    func remove() { try? FileManager.default.removeItem(at: rootURL) }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
