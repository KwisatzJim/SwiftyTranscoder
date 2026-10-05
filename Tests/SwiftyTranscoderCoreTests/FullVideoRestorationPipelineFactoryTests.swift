import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct FullVideoRestorationPipelineFactoryTests {
    @Test(arguments: [RestorationMethod.compactGeneral, .lightweightFSRCNN])
    func refusesMissingSelectedModelInsteadOfUsingDetailedModel(method: RestorationMethod) throws {
        let unavailable = URL(fileURLWithPath: "/private/tmp/missing-compact-model-\(UUID().uuidString)")
        let plan = RestorationPlan(
            method: method, sourceWidth: 624, sourceHeight: 352,
            outputWidth: 1248, outputHeight: 704, frameRate: "24000/1001",
            colorRange: "tv", colorSpace: "smpte170m", colorTransfer: "bt709", colorPrimaries: "smpte170m"
        )
        let resources = FullVideoRestorationResources(ffmpegURL: unavailable, ffprobeURL: unavailable, modelURL: unavailable)
        #expect(throws: FullVideoRestorationFactoryError.modelUnavailable) {
            try resources.makeFrameProcessor(for: plan)
        }
        var selected = resources
        if method == .lightweightFSRCNN { selected.lightweightModelURL = unavailable }
        else { selected.fastModelURL = unavailable }
        #expect(throws: CoreMLRestorationError.modelMissing) {
            try selected.makeFrameProcessor(for: plan)
        }
    }

    @Test func completesCapped720pRestorationWhenOptedIn() async throws {
        guard ProcessInfo.processInfo.environment["SWIFTY_HD_SMOKE"] == "1" else { return }
        let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = project.appendingPathComponent(".build/milestone108-dimensions/inputs/Pilot-HD.mp4")
        let helpers = project.appendingPathComponent(".build/Milestone101DerivedData/Build/Products/Debug/SwiftyTranscoder.app/Contents/Helpers")
        let ffprobe = helpers.appendingPathComponent("ffprobe")
        let inspection = try probe(source, with: ffprobe)
        guard case .eligible(let plan) = RestorationPlanner().plan(for: inspection) else {
            Issue.record("The HD fixture must be eligible for restoration.")
            return
        }
        #expect(plan.sourceWidth == 1280 && plan.sourceHeight == 720)
        #expect(plan.outputWidth == 1920 && plan.outputHeight == 1080)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftyTranscoder-HDRegression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("restored.mp4")
        let request = try FullVideoRestorationRequest(
            sourceURL: source, workspaceURL: root.appendingPathComponent("SwiftyTranscoder-Restoration-HD"),
            finalOutputURL: output, plan: plan, totalFrameCount: 4,
            durationSeconds: 4 / (try #require(RestorationVideoAssembly.frameRateValue(plan.frameRate))),
            sourceAudio: try #require(inspection.audioStreams.first), gainEnabled: false,
            aacStereoEnabled: false, expectedChapterCount: 0, expectedContainerTitle: nil
        )
        let resources = FullVideoRestorationResources(
            ffmpegURL: helpers.appendingPathComponent("ffmpeg"), ffprobeURL: ffprobe,
            modelURL: project.appendingPathComponent(".build/restoration-evaluation/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage")
        )
        let pipeline = try FullVideoRestorationPipelineFactory(resources: resources).makePipeline(for: request)
        #expect(await pipeline.run(request) == .completed(output: output))
        let result = try probe(output, with: ffprobe)
        let video = try #require(result.videoStreams.first)
        #expect(video.width == 1920 && video.height == 1080)
        #expect(video.numberOfFrames == "4")
        #expect(!FileManager.default.fileExists(atPath: request.workspaceURL.path))
    }

    @Test func restoresSDFrameWithoutLoadingTiledModelWhenResourcesAreAvailable() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let research = root.appendingPathComponent(".build/restoration-evaluation/sd-shape-experiment")
        let sdModel = research.appendingPathComponent(FullVideoRestorationResources.sdModelName)
        let source = research.appendingPathComponent("face/source-frames/frame-0001.png")
        guard FileManager.default.fileExists(atPath: sdModel.path),
              FileManager.default.fileExists(atPath: source.path) else { return }
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftyTranscoder-SDSelection-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let missingTiledModel = workspace.appendingPathComponent("missing.mlpackage")
        let resources = FullVideoRestorationResources(
            ffmpegURL: workspace, ffprobeURL: workspace,
            modelURL: missingTiledModel, sdModelURL: sdModel
        )
        let plan = RestorationPlan(
            method: .realESRGANX2Plus, sourceWidth: 624, sourceHeight: 352,
            outputWidth: 1248, outputHeight: 704, frameRate: "24000/1001",
            colorRange: "tv", colorSpace: "smpte170m", colorTransfer: "bt709",
            colorPrimaries: "smpte170m"
        )
        let processor = try resources.makeFrameProcessor(for: plan)
        let output = try await processor.process(
            sourceURL: source, outputURL: workspace.appendingPathComponent("frame.png"),
            expectedWidth: 624, expectedHeight: 352
        )
        #expect(FileManager.default.fileExists(atPath: output.path))

        // A present but invalid selected SD model must fail, not use tiled fallback.
        let invalidResources = FullVideoRestorationResources(
            ffmpegURL: workspace, ffprobeURL: workspace,
            modelURL: missingTiledModel, sdModelURL: workspace.appendingPathComponent("invalid.mlpackage")
        )
        #expect(throws: CoreMLRestorationError.modelMissing) {
            try invalidResources.makeFrameProcessor(for: plan)
        }
        let fallbackResources = FullVideoRestorationResources(
            ffmpegURL: workspace, ffprobeURL: workspace, modelURL: missingTiledModel
        )
        #expect(throws: CoreMLRestorationError.modelMissing) {
            try fallbackResources.makeFrameProcessor(for: plan)
        }
    }

    @Test func rejectsHelperWithoutSegmentJoinCapability() throws {
        let fixture = try RestorationResourceFixture(includeFFmpeg: true, includeFFprobe: true)
        defer { fixture.remove() }

        #expect(!FullVideoRestorationPipelineFactory.supportsConcatDemuxer(
            at: fixture.ffmpegURL
        ))
    }

    @Test func locatesOnlyApprovedBundledResources() throws {
        let fixture = try RestorationResourceFixture(includeFFmpeg: true, includeFFprobe: true)
        defer { fixture.remove() }

        let resources = try FullVideoRestorationResources.locate(
            bundleURL: fixture.bundleURL,
            developmentModelURL: nil,
            developmentSDModelURL: nil,
            ffmpegFallbackPaths: [],
            ffprobeFallbackPaths: []
        )

        #expect(resources.ffmpegURL == fixture.ffmpegURL)
        #expect(resources.ffprobeURL == fixture.ffprobeURL)
        #expect(resources.modelURL == fixture.modelURL)
        #expect(resources.sdModelURL == nil)
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

    @Test func completesShortProductionRestorationWhenDevelopmentResourcesAreAvailable() async throws {
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

        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftyTranscoder-Restoration-CompletionTest-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let workspaceURL = rootURL.appendingPathComponent(
            "SwiftyTranscoder-Restoration-Workspace",
            isDirectory: true
        )
        let outputURL = rootURL.appendingPathComponent("restored-complete.mp4")
        let frameRate = 24_000.0 / 1_001.0
        let request = try FullVideoRestorationRequest(
            sourceURL: sourceURL,
            workspaceURL: workspaceURL,
            finalOutputURL: outputURL,
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
            totalFrameCount: 2,
            durationSeconds: 2.0 / frameRate,
            sourceAudio: mediaStream(
                index: 1,
                codecName: "aac",
                codecType: "audio",
                channels: 2,
                channelLayout: "stereo",
                sampleRate: "48000"
            ),
            gainEnabled: true,
            aacStereoEnabled: true,
            expectedChapterCount: 0,
            expectedContainerTitle: nil
        )
        let resources = FullVideoRestorationResources(
            ffmpegURL: ffmpeg,
            ffprobeURL: ffprobe,
            modelURL: modelURL
        )
        var selectedResources = resources
        let sdModel = projectURL.appendingPathComponent(".build/restoration-evaluation/sd-shape-experiment/RealESRGAN_x2plus_656x384_fp16.mlpackage")
        if FileManager.default.fileExists(atPath: sdModel.path) { selectedResources.sdModelURL = sdModel }
        let pipeline = try FullVideoRestorationPipelineFactory(resources: selectedResources)
            .makePipeline(for: request)

        let result = await pipeline.run(request)

        #expect(result == .completed(output: outputURL))
        #expect(await pipeline.currentProgress() == 1)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(!FileManager.default.fileExists(atPath: request.partialOutputURL.path))
        #expect(!FileManager.default.fileExists(atPath: workspaceURL.path))

        let inspection = try probe(outputURL, with: ffprobe)
        let video = try #require(inspection.videoStreams.first)
        #expect(video.codecName == "hevc")
        #expect(video.width == 1248)
        #expect(video.height == 704)
        #expect(video.averageFrameRate == "24000/1001")
        #expect(video.numberOfFrames == "2")
        #expect(inspection.audioStreams.map(\.codecName) == ["ac3", "aac"])
        #expect(inspection.audioStreams.first?.disposition?.isDefault == 1)
    }

    private func probe(_ url: URL, with ffprobe: URL) throws -> MediaInspection {
        let process = Process()
        let output = Pipe()
        let diagnostics = Pipe()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "error", "-print_format", "json",
            "-show_format", "-show_streams", "-show_chapters", url.path,
        ]
        process.standardOutput = output
        process.standardError = diagnostics
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let reason = String(
                data: diagnostics.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw CompletionProbeError.failed(reason)
        }
        return try JSONDecoder().decode(MediaInspection.self, from: data)
    }
}

private enum CompletionProbeError: Error {
    case failed(String)
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
