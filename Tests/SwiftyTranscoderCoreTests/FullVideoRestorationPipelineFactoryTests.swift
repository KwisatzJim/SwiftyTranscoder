import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct FullVideoRestorationPipelineFactoryTests {
    @Test func locatesOnlyApprovedBundledResources() throws {
        let fixture = try RestorationResourceFixture(includeFFmpeg: true, includeFFprobe: true)
        defer { fixture.remove() }

        let resources = try FullVideoRestorationResources.locate(
            bundleURL: fixture.bundleURL,
            developmentModelURL: nil,
            ffmpegFallbackPaths: [],
            ffprobeFallbackPaths: []
        )

        #expect(resources.ffmpegURL == fixture.ffmpegURL)
        #expect(resources.ffprobeURL == fixture.ffprobeURL)
        #expect(resources.modelURL == fixture.modelURL)
    }

    @Test func refusesMissingFFmpegBeforeConstructingPipeline() throws {
        let fixture = try RestorationResourceFixture(includeFFmpeg: false, includeFFprobe: true)
        defer { fixture.remove() }

        #expect(throws: FullVideoRestorationFactoryError.ffmpegUnavailable) {
            try FullVideoRestorationResources.locate(
                bundleURL: fixture.bundleURL,
                developmentModelURL: nil,
                ffmpegFallbackPaths: [],
                ffprobeFallbackPaths: []
            )
        }
    }

    @Test func refusesMissingFFprobeBeforeConstructingPipeline() throws {
        let fixture = try RestorationResourceFixture(includeFFmpeg: true, includeFFprobe: false)
        defer { fixture.remove() }

        #expect(throws: FullVideoRestorationFactoryError.ffprobeUnavailable) {
            try FullVideoRestorationResources.locate(
                bundleURL: fixture.bundleURL,
                developmentModelURL: nil,
                ffmpegFallbackPaths: [],
                ffprobeFallbackPaths: []
            )
        }
    }

    @Test func refusesMissingModelBeforeConstructingPipeline() throws {
        let fixture = try RestorationResourceFixture(
            includeFFmpeg: true,
            includeFFprobe: true,
            includeModel: false
        )
        defer { fixture.remove() }

        #expect(throws: FullVideoRestorationFactoryError.modelUnavailable) {
            try FullVideoRestorationResources.locate(
                bundleURL: fixture.bundleURL,
                developmentModelURL: nil,
                ffmpegFallbackPaths: [],
                ffprobeFallbackPaths: []
            )
        }
    }

    @Test func constructsProductionPipelineWhenDevelopmentResourcesAreAvailable() throws {
        let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = projectURL.appendingPathComponent(
            "Alphas - s01e11 - Original Sin.m4v"
        )
        let modelURL = projectURL.appendingPathComponent(
            ".build/restoration-evaluation/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage"
        )
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              FileManager.default.fileExists(atPath: modelURL.path),
              let ffmpeg = MediaToolLocator.executableURL(for: .ffmpeg, bundleURL: projectURL),
              let ffprobe = MediaToolLocator.executableURL(for: .ffprobe, bundleURL: projectURL)
        else { return }

        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftyTranscoder-Restoration-Factory-\(UUID().uuidString)"
        )
        let request = try FullVideoRestorationRequest(
            sourceURL: sourceURL,
            workspaceURL: workspaceURL,
            finalOutputURL: projectURL.appendingPathComponent("factory-test-output.mp4"),
            plan: RestorationPlan(
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
            ),
            totalFrameCount: 4,
            durationSeconds: 4.0 / (24_000.0 / 1_001.0),
            sourceAudio: mediaStream(
                index: 1,
                codecName: "aac",
                codecType: "audio",
                channels: 2,
                channelLayout: "stereo",
                sampleRate: "48000"
            ),
            gainEnabled: false,
            aacStereoEnabled: false,
            subtitleStreamOrdinal: 0,
            expectedChapterCount: 0,
            expectedContainerTitle: nil
        )
        let resources = FullVideoRestorationResources(
            ffmpegURL: ffmpeg,
            ffprobeURL: ffprobe,
            modelURL: modelURL
        )

        _ = try FullVideoRestorationPipelineFactory(resources: resources)
            .makePipeline(for: request)
    }
}

private struct RestorationResourceFixture {
    let rootURL: URL
    let bundleURL: URL
    let ffmpegURL: URL
    let ffprobeURL: URL
    let modelURL: URL

    init(
        includeFFmpeg: Bool,
        includeFFprobe: Bool,
        includeModel: Bool = true
    ) throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftyTranscoder-ResourceTests-\(UUID().uuidString)"
        )
        bundleURL = rootURL.appendingPathComponent("SwiftyTranscoder.app", isDirectory: true)
        let helperURL = bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        let modelsURL = bundleURL.appendingPathComponent(
            "Contents/Resources/Models",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: helperURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        ffmpegURL = helperURL.appendingPathComponent("ffmpeg")
        ffprobeURL = helperURL.appendingPathComponent("ffprobe")
        modelURL = modelsURL.appendingPathComponent(
            FullVideoRestorationResources.modelName,
            isDirectory: true
        )
        if includeFFmpeg { try makeExecutable(at: ffmpegURL) }
        if includeFFprobe { try makeExecutable(at: ffprobeURL) }
        if includeModel {
            try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        }
    }

    func remove() { try? FileManager.default.removeItem(at: rootURL) }

    private func makeExecutable(at url: URL) throws {
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }
}
