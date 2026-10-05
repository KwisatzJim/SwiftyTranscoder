import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct HDFrameProfileTests {
    @Test func rendersLightweightPilotWhenOptedIn() async throws {
        guard ProcessInfo.processInfo.environment["SWIFTY_FSRCNN_REVIEW"] == "1" else { return }
        let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let app = ProcessInfo.processInfo.environment["SWIFTY_REVIEW_APP"].map { URL(fileURLWithPath: $0) }
            ?? project.appendingPathComponent(".build/Milestone113DerivedData/Build/Products/Release/SwiftyTranscoder.app")
        let helpers = app.appendingPathComponent("Contents/Helpers")
        let ffprobe = helpers.appendingPathComponent("ffprobe")
        let source = project.appendingPathComponent(".build/milestone110-review/inputs/Pilot-HD-10s.mp4")
        let process = Process()
        let pipe = Pipe()
        process.executableURL = ffprobe
        process.arguments = ["-v", "error", "-show_streams", "-show_format", "-show_chapters", "-of", "json", source.path]
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let inspection = try JSONDecoder().decode(MediaInspection.self, from: data)
        guard case .eligible(let plan) = RestorationPlanner().plan(for: inspection, method: .lightweightFSRCNN) else {
            Issue.record("Pilot fixture must be eligible")
            return
        }
        let count = try #require(inspection.videoStreams.first?.numberOfFrames.flatMap(Int64.init))
        let rate = try #require(RestorationVideoAssembly.frameRateValue(plan.frameRate))
        let review = ProcessInfo.processInfo.environment["SWIFTY_REVIEW_OUTPUT_DIRECTORY"].map { URL(fileURLWithPath: $0) }
            ?? project.appendingPathComponent(".build/milestone113-review")
        try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
        let output = review.appendingPathComponent("Pilot-Lightweight-AI.mp4")
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftyTranscoder-Restoration-Lightweight-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let request = try FullVideoRestorationRequest(
            sourceURL: source, workspaceURL: workspace, finalOutputURL: output, plan: plan,
            totalFrameCount: count, durationSeconds: Double(count) / rate,
            sourceAudio: try #require(inspection.audioStreams.first), gainEnabled: false,
            aacStereoEnabled: true, expectedChapterCount: 0, expectedContainerTitle: nil
        )
        let resources = try FullVideoRestorationResources.locate(
            bundleURL: app, developmentModelURL: nil, developmentSDModelURL: nil,
            ffmpegFallbackPaths: [], ffprobeFallbackPaths: []
        )
        #expect(resources.lightweightModelURL != nil)
        let pipeline = try FullVideoRestorationPipelineFactory(resources: resources).makePipeline(for: request)
        let started = ProcessInfo.processInfo.systemUptime
        #expect(await pipeline.run(request) == .completed(output: output))
        print("Lightweight Pilot ten-second production run: \(ProcessInfo.processInfo.systemUptime - started)s")
        #expect(!FileManager.default.fileExists(atPath: workspace.path))
        let verifier = Process()
        let verificationPipe = Pipe()
        verifier.executableURL = ffprobe
        verifier.arguments = ["-v", "error", "-show_streams", "-show_format", "-show_chapters", "-of", "json", output.path]
        verifier.standardOutput = verificationPipe
        try verifier.run()
        let verification = verificationPipe.fileHandleForReading.readDataToEndOfFile()
        verifier.waitUntilExit()
        #expect(verifier.terminationStatus == 0)
        let result = try JSONDecoder().decode(MediaInspection.self, from: verification)
        #expect(result.videoStreams.first?.width == 1920 && result.videoStreams.first?.height == 1080)
        #expect(result.videoStreams.first?.numberOfFrames == String(count))
        #expect(result.audioStreams.map(\.codecName) == ["ac3", "aac"])
    }

    @Test func profilesCompactPilotFramesWhenOptedIn() async throws {
        guard ProcessInfo.processInfo.environment["SWIFTY_HD_PROFILE"] == "1" else { return }
        let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let helpers = project.appendingPathComponent(".build/Milestone110DerivedData/Build/Products/Release/SwiftyTranscoder.app/Contents/Helpers")
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftyTranscoder-Restoration-HDProfile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let extractionStart = ProcessInfo.processInfo.systemUptime
        let frames = try await RestorationFrameExtractor(executableURL: helpers.appendingPathComponent("ffmpeg")).extract(
            RestorationFrameExtraction(
                sourceURL: project.appendingPathComponent(".build/milestone110-review/inputs/Pilot-HD-10s.mp4"),
                workspaceURL: workspace, startSeconds: 0, frameCount: 8
            )
        )
        let extraction = ProcessInfo.processInfo.systemUptime - extractionStart
        let setupStart = ProcessInfo.processInfo.systemUptime
        let modelPath = ProcessInfo.processInfo.environment["SWIFTY_HD_PROFILE_MODEL"]
            ?? ".build/restoration-evaluation/fast-candidate/RealESRGAN_general_x2_522_fp16.mlpackage"
        let tiles = try CoreMLRestorationTileProcessor(modelURL: project.appendingPathComponent(modelPath))
        let processor = RestorationFrameProcessor(tileProcessor: tiles)
        let setup = ProcessInfo.processInfo.systemUptime - setupStart
        let outputDirectory = workspace.appendingPathComponent("restored-frames")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var totals = ["decoding": 0.0, "tensorPreparation": 0.0, "inference": 0.0, "blending": 0.0, "output": 0.0]
        let start = ProcessInfo.processInfo.systemUptime
        var outputs: [URL] = []
        for frame in frames {
            outputs.append(try await processor.process(
                sourceURL: frame, outputURL: outputDirectory.appendingPathComponent(frame.lastPathComponent),
                expectedWidth: 1280, expectedHeight: 720
            ))
            let value = await processor.latestTimings
            totals["decoding"]! += value.decoding
            totals["tensorPreparation"]! += value.tensorPreparation
            totals["inference"]! += value.inference
            totals["blending"]! += value.blending
            totals["output"]! += value.output
            totals["pixelPacking", default: 0] += value.pixelPacking
            totals["pngWriting", default: 0] += value.pngWriting
        }
        let processing = ProcessInfo.processInfo.systemUptime - start
        totals["modelPrediction"] = await tiles.totalPredictionSeconds
        totals["tensorValidation"] = await tiles.totalValidationSeconds
        let plan = RestorationPlan(
            method: .compactGeneral, sourceWidth: 1280, sourceHeight: 720, outputWidth: 1920, outputHeight: 1080,
            frameRate: "24000/1001", colorRange: "tv", colorSpace: "bt709", colorTransfer: "bt709", colorPrimaries: "bt709"
        )
        let assemblyStart = ProcessInfo.processInfo.systemUptime
        let output = try await RestorationVideoAssembler(ffmpegURL: helpers.appendingPathComponent("ffmpeg"), ffprobeURL: helpers.appendingPathComponent("ffprobe"))
            .assemble(RestorationVideoAssembly(frameURLs: outputs, workspaceURL: workspace, plan: plan))
        #expect(FileManager.default.fileExists(atPath: output.path))
        totals["encodingAndValidation"] = ProcessInfo.processInfo.systemUptime - assemblyStart
        totals["extraction"] = extraction
        totals["setup"] = setup
        totals["processingTotal"] = processing
        totals["restoredPNGBytes"] = try outputs.reduce(0.0) { total, url in
            total + Double(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        print("HD profile eight frames: \(totals)")
        let evidence = project.appendingPathComponent(".build/milestone111-evidence")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let label = ProcessInfo.processInfo.environment["SWIFTY_PROFILE_LABEL"] ?? "baseline"
        try JSONSerialization.data(withJSONObject: totals, options: [.prettyPrinted, .sortedKeys])
            .write(to: evidence.appendingPathComponent("\(label).json"))
    }
}
