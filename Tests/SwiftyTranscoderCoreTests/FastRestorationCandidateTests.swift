import Foundation
import CoreML
import Testing
@testable import SwiftyTranscoderCore

struct FastRestorationCandidateTests {
    @Test func benchmarksAndRendersPilotWhenOptedIn() async throws {
        guard ProcessInfo.processInfo.environment["SWIFTY_FAST_CANDIDATE"] == "1" else { return }
        let gpuOnly = ProcessInfo.processInfo.environment["SWIFTY_FAST_GPU"] == "1"
        let compactUnits: MLComputeUnits = gpuOnly ? .cpuAndGPU : .all
        let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let research = project.appendingPathComponent(".build/restoration-evaluation")
        let helpers = project.appendingPathComponent(".build/Milestone101DerivedData/Build/Products/Debug/SwiftyTranscoder.app/Contents/Helpers")
        let ffmpeg = helpers.appendingPathComponent("ffmpeg")
        let ffprobe = helpers.appendingPathComponent("ffprobe")
        let source = project.appendingPathComponent(".build/milestone108-dimensions/inputs/Pilot-HD.mp4")
        let fastModel = research.appendingPathComponent("fast-candidate/RealESRGAN_general_x2_522_fp16.mlpackage")
        let slowModel = research.appendingPathComponent("converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage")
        let review = project.appendingPathComponent(".build/milestone110-review")
        try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftyTranscoder-Restoration-FastBenchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputFrames = try await RestorationFrameExtractor(executableURL: ffmpeg).extract(
            RestorationFrameExtraction(sourceURL: source, workspaceURL: workspace, startSeconds: 0, frameCount: 4)
        )
        var timings: [String: Double] = [:]
        for (name, model) in [("current", slowModel), ("compact", fastModel)] {
            let setupStart = ProcessInfo.processInfo.systemUptime
            let tiles = try CoreMLRestorationTileProcessor(modelURL: model, computeUnits: name == "compact" ? compactUnits : .all)
            let processor = RestorationFrameProcessor(tileProcessor: tiles)
            let setup = ProcessInfo.processInfo.systemUptime - setupStart
            let directory = workspace.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let start = ProcessInfo.processInfo.systemUptime
            for input in inputFrames {
                _ = try await processor.process(
                    sourceURL: input, outputURL: directory.appendingPathComponent(input.lastPathComponent),
                    expectedWidth: 1280, expectedHeight: 720
                )
            }
            timings[name] = ProcessInfo.processInfo.systemUptime - start
            print("Pilot benchmark \(name): setup \(setup)s; four frames \(timings[name]!)s")
        }
        let compact = try #require(timings["compact"])
        let current = try #require(timings["current"])
        #expect(compact < current)
        print("Pilot benchmark speedup: \(current / compact)x")
        try JSONSerialization.data(withJSONObject: timings, options: [.prettyPrinted, .sortedKeys])
            .write(to: review.appendingPathComponent("timings.json"))

        let inspection = try probe(source, executable: ffprobe)
        guard case .eligible(let plan) = RestorationPlanner().plan(for: inspection) else {
            Issue.record("Pilot fixture must be eligible")
            return
        }
        let frameCount = try #require(inspection.videoStreams.first?.numberOfFrames.flatMap(Int64.init))
        let frameRate = try #require(RestorationVideoAssembly.frameRateValue(plan.frameRate))
        let output = review.appendingPathComponent(gpuOnly ? "Faster-Pilot-GPU.mp4" : "Faster-Pilot-Validated.mp4")
        let request = try FullVideoRestorationRequest(
            sourceURL: source, workspaceURL: workspace.appendingPathComponent("SwiftyTranscoder-Restoration-Production"),
            finalOutputURL: output, plan: plan, totalFrameCount: frameCount,
            durationSeconds: Double(frameCount) / frameRate, sourceAudio: try #require(inspection.audioStreams.first),
            gainEnabled: false, aacStereoEnabled: true, expectedChapterCount: 0, expectedContainerTitle: nil
        )
        let resources = FullVideoRestorationResources(ffmpegURL: ffmpeg, ffprobeURL: ffprobe, modelURL: fastModel, computeUnits: compactUnits)
        let pipeline = try FullVideoRestorationPipelineFactory(resources: resources).makePipeline(for: request)
        #expect(await pipeline.run(request) == .completed(output: output))
        let result = try probe(output, executable: ffprobe)
        #expect(result.videoStreams.first?.width == 1920)
        #expect(result.videoStreams.first?.height == 1080)
        #expect(result.videoStreams.first?.numberOfFrames == String(frameCount))
        #expect(result.audioStreams.map(\.codecName) == ["ac3", "aac"])
        #expect(!FileManager.default.fileExists(atPath: request.workspaceURL.path))
    }

    private func probe(_ url: URL, executable: URL) throws -> MediaInspection {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["-v", "error", "-show_streams", "-show_format", "-show_chapters", "-of", "json", url.path]
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return try JSONDecoder().decode(MediaInspection.self, from: data)
    }
}
