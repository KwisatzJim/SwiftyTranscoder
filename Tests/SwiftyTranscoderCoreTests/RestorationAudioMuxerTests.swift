import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationAudioMuxerTests {
    @Test func buildsProtectedGainCompatibilityCommand() throws {
        let fixture = try AudioMuxFixture()
        defer { fixture.remove() }
        let arguments = fixture.request.ffmpegArguments

        #expect(arguments.contains("volume=6dB,alimiter=limit=0.630957:level=false:latency=true"))
        #expect(arguments.contains("aformat=channel_layouts=stereo,volume=6dB,alimiter=limit=0.630957:level=false:latency=true"))
        #expect(arguments.contains("ac3"))
        #expect(arguments.contains("aac"))
        #expect(arguments.contains("-map_metadata"))
        #expect(arguments.contains("-1"))
        #expect(arguments.contains("copy"))
        #expect(fixture.request.outputURL.lastPathComponent == "restored-preview.partial.mp4")
    }

    @Test func rejectsSilentVideoOutsideWorkspace() throws {
        let fixture = try AudioMuxFixture()
        defer { fixture.remove() }
        #expect(throws: RestorationAudioMuxerError.invalidSilentVideoLocation) {
            try RestorationAudioMux(
                sourceURL: fixture.sourceURL,
                silentVideoURL: fixture.rootURL.appendingPathComponent("restored-video.partial.mp4"),
                workspaceURL: fixture.workspaceURL,
                startSeconds: 1,
                durationSeconds: 5,
                sourceAudio: fixture.sourceAudio,
                gainEnabled: true,
                aacStereoEnabled: true
            )
        }
    }

    @Test func muxesAndValidatesThroughMediaHelperBoundary() async throws {
        let fixture = try AudioMuxFixture()
        defer { fixture.remove() }
        let helpers = try fixture.makeSuccessfulHelpers()
        let muxer = RestorationAudioMuxer(ffmpegURL: helpers.ffmpeg, ffprobeURL: helpers.ffprobe)

        let output = try await muxer.mux(fixture.request)

        #expect(output == fixture.request.outputURL)
        #expect(await muxer.progress == 1)
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test func refusesExistingPartialOutput() async throws {
        let fixture = try AudioMuxFixture()
        defer { fixture.remove() }
        let helpers = try fixture.makeSuccessfulHelpers()
        try Data("existing".utf8).write(to: fixture.request.outputURL)
        let muxer = RestorationAudioMuxer(ffmpegURL: helpers.ffmpeg, ffprobeURL: helpers.ffprobe)

        await #expect(throws: RestorationAudioMuxerError.outputExists) {
            try await muxer.mux(fixture.request)
        }
    }
}

private struct AudioMuxFixture {
    let rootURL: URL
    let workspaceURL: URL
    let sourceURL: URL
    let silentVideoURL: URL
    let sourceAudio: MediaStream
    let request: RestorationAudioMux

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftyTranscoder-AudioMuxTests-\(UUID().uuidString)")
        workspaceURL = rootURL.appendingPathComponent("workspace")
        sourceURL = rootURL.appendingPathComponent("source.m4v")
        silentVideoURL = workspaceURL.appendingPathComponent("restored-video.partial.mp4")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: sourceURL)
        try Data("video".utf8).write(to: silentVideoURL)
        sourceAudio = mediaStream(
            index: 1, codecName: "aac", codecType: "audio", channels: 2,
            channelLayout: "stereo", sampleRate: "48000", tags: ["language": "eng"]
        )
        request = try RestorationAudioMux(
            sourceURL: sourceURL,
            silentVideoURL: silentVideoURL,
            workspaceURL: workspaceURL,
            startSeconds: 540,
            durationSeconds: 5,
            sourceAudio: sourceAudio,
            gainEnabled: true,
            aacStereoEnabled: true
        )
    }

    func makeSuccessfulHelpers() throws -> (ffmpeg: URL, ffprobe: URL) {
        let ffmpeg = rootURL.appendingPathComponent("fake-ffmpeg")
        let ffprobe = rootURL.appendingPathComponent("fake-ffprobe")
        let encoder = """
        #!/bin/sh
        for output in "$@"; do :; done
        printf "preview" > "$output"
        printf "out_time_us=5000000\\n"
        exit 0
        """
        let probe = """
        #!/bin/sh
        printf '%s' '{"streams":[{"index":0,"codec_name":"hevc","codec_tag_string":"hvc1","codec_type":"video"},{"index":1,"codec_name":"ac3","codec_type":"audio","channels":2,"channel_layout":"stereo","sample_rate":"48000","bit_rate":"192000","tags":{"language":"eng"},"disposition":{"default":1}},{"index":2,"codec_name":"aac","codec_type":"audio","channels":2,"channel_layout":"stereo","sample_rate":"48000","bit_rate":"192000","tags":{"language":"eng"},"disposition":{"default":0}}],"chapters":[],"format":{"duration":"5.000","size":"7"}}'
        exit 0
        """
        try writeExecutable(encoder, to: ffmpeg)
        try writeExecutable(probe, to: ffprobe)
        return (ffmpeg, ffprobe)
    }

    func remove() { try? FileManager.default.removeItem(at: rootURL) }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
