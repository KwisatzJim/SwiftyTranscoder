import Foundation
import Testing
@testable import SwiftyTranscoderCore

@MainActor
struct RestorationBatchControllerTests {
    @Test(arguments: [RestorationMethod.compactGeneral, .lightweightFSRCNN])
    func preservesSelectedMethodThroughReviewedBatch(method: RestorationMethod) async throws {
        let builder = UIBatchBuilder()
        let controller = makeController(builder)
        let jobs = try makeJobs().map { job in
            guard case .eligible(let plan) = RestorationPlanner().plan(for: job.inspection, method: method) else {
                throw UIBatchError.timeout
            }
            return ReviewedRestorationJob(
                sourceURL: job.sourceURL, inspection: job.inspection, outputURL: job.outputURL,
                plan: plan, gainEnabled: job.gainEnabled, aacStereoEnabled: job.aacStereoEnabled,
                subtitleSelection: job.subtitleSelection
            )
        }
        controller.start(jobs)
        try await waitUntil { !controller.isActive }
        #expect(controller.snapshot.phase == .finished)
        #expect(builder.requests.map(\.plan.method) == [method, method])
        #expect(controller.snapshot.completionSummaries[0]?.method == method)
        #expect(controller.snapshot.completionSummaries[1]?.method == method)
    }

    @Test func completesPreparedReviewClipsWhenOptedIn() async throws {
        guard ProcessInfo.processInfo.environment["SWIFTY_BATCH_UI_SMOKE"] == "1" else { return }
        let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let inputs = project.appendingPathComponent(".build/milestone108-review/inputs")
        let ffmpeg = project.appendingPathComponent(".build/toolchain/stage/bin/ffmpeg")
        let ffprobe = project.appendingPathComponent(".build/toolchain/stage/bin/ffprobe")
        let resources = FullVideoRestorationResources(
            ffmpegURL: ffmpeg, ffprobeURL: ffprobe,
            modelURL: project.appendingPathComponent(".build/restoration-evaluation/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage"),
            sdModelURL: project.appendingPathComponent(".build/restoration-evaluation/sd-shape-experiment/RealESRGAN_x2plus_656x384_fp16.mlpackage")
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftyTranscoder-BatchUIReal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jobs = try ["Alphas-SD-A.mp4", "Alphas-SD-B.mp4"].enumerated().map { index, name in
            let source = inputs.appendingPathComponent(name)
            let process = Process()
            let output = Pipe()
            process.executableURL = ffprobe
            process.arguments = ["-v", "error", "-show_streams", "-show_format", "-show_chapters", "-of", "json", source.path]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            let inspection = try JSONDecoder().decode(MediaInspection.self, from: data)
            guard case .eligible(let plan) = RestorationPlanner().plan(for: inspection) else { throw UIBatchError.ineligible }
            return ReviewedRestorationJob(
                sourceURL: source, inspection: inspection, outputURL: root.appendingPathComponent(name), plan: plan,
                gainEnabled: index == 1, aacStereoEnabled: index == 0, subtitleSelection: .omit
            )
        }
        let controller = RestorationBatchController(
            coordinator: RestorationBatchCoordinator(builder: FullVideoRestorationPipelineFactory(resources: resources)),
            temporaryDirectory: root
        )
        controller.start(jobs)
        let deadline = ContinuousClock.now + .seconds(120)
        while controller.isActive {
            guard ContinuousClock.now < deadline else { controller.cancel(); throw UIBatchError.timeout }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(controller.snapshot.phase == .finished)
        #expect(controller.snapshot.items == jobs.map { .completed($0.outputURL) })
        #expect(controller.snapshot.progress == 1)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        #expect(Set(files.map(\.lastPathComponent)) == Set(jobs.map { $0.outputURL.lastPathComponent }))
    }

    @Test func publishesResultsAndPreservesReviewedChoices() async throws {
        let builder = UIBatchBuilder()
        let controller = makeController(builder)
        let jobs = try makeJobs()
        controller.start(jobs)
        try await waitUntil { !controller.isActive }
        #expect(controller.snapshot.phase == .finished)
        #expect(controller.snapshot.items == jobs.map { .completed($0.outputURL) })
        #expect(builder.requests.map(\.gainEnabled) == [true, false])
        #expect(builder.requests.map(\.aacStereoEnabled) == [false, true])
        #expect(builder.requests.map(\.subtitleStreamOrdinal) == [1, nil])
        #expect(builder.requests.map(\.totalFrameCount) == [237, 237])
        #expect(builder.requests.allSatisfy { $0.expectedContainerTitle == "Review Test" })
        #expect(Set(builder.requests.map(\.workspaceURL)).count == 2)
    }

    @Test func immediateCancellationDoesNotStartAJob() async throws {
        let builder = UIBatchBuilder(waitForCancellation: true)
        let controller = makeController(builder)
        controller.start(try makeJobs())
        controller.cancel()
        try await waitUntil { !controller.isActive }
        #expect(controller.snapshot.phase == .cancelled)
        #expect(controller.snapshot.items == [.notRun, .notRun])
        #expect(builder.requests.isEmpty)
    }

    @Test func cancellationUpdatesUIAndKeepsRemainingJobsUnstarted() async throws {
        let builder = UIBatchBuilder(waitForCancellation: true)
        let controller = makeController(builder)
        let jobs = try makeJobs()
        controller.start(jobs)
        try await waitUntil { controller.snapshot.progress > 0 }
        controller.start([jobs[1]]) // Active UI must ignore a second start.
        #expect(controller.snapshot.items.count == 2)
        controller.cancel()
        #expect(controller.snapshot.phase == .cancelling)
        try await waitUntil { !controller.isActive }
        #expect(controller.snapshot.phase == .cancelled)
        #expect(controller.snapshot.items[1] == .notRun)
        #expect(builder.requests.count == 1)
    }

    @Test func refusesChangedEligibilityBeforeStartingAnyJob() throws {
        let builder = UIBatchBuilder()
        let controller = makeController(builder)
        let jobs = try makeJobs()
        let job = jobs[0]
        let changedPlan = RestorationPlan(
            method: .realESRGANX2Plus, sourceWidth: 640, sourceHeight: 352, outputWidth: 1280, outputHeight: 704,
            frameRate: job.plan.frameRate, colorRange: "tv", colorSpace: "smpte170m", colorTransfer: "bt709", colorPrimaries: "smpte170m"
        )
        controller.start([ReviewedRestorationJob(
            sourceURL: job.sourceURL, inspection: job.inspection, outputURL: job.outputURL, plan: changedPlan,
            gainEnabled: true, aacStereoEnabled: false, subtitleSelection: .omit
        )])
        guard case .rejected(let message) = controller.snapshot.phase else { Issue.record("Expected ineligible-plan refusal"); return }
        #expect(message.contains("no longer eligible"))
        #expect(builder.requests.isEmpty)
    }

    @Test func refusesUnresolvedSubtitlesBeforeStartingAnyJob() throws {
        let builder = UIBatchBuilder()
        let controller = makeController(builder)
        let jobs = try makeJobs()
        let job = jobs[1]
        controller.start([jobs[0], ReviewedRestorationJob(
            sourceURL: job.sourceURL, inspection: job.inspection, outputURL: job.outputURL, plan: job.plan,
            gainEnabled: false, aacStereoEnabled: true, subtitleSelection: .needsChoice
        )])
        guard case .rejected = controller.snapshot.phase else { Issue.record("Expected subtitle refusal"); return }
        #expect(builder.requests.isEmpty)
        #expect(controller.snapshot.items == [.notRun, .notRun])
    }

    @Test func resetAndNewBatchDoNotPublishOldResults() async throws {
        let builder = UIBatchBuilder()
        let controller = makeController(builder)
        let jobs = try makeJobs()
        controller.start(jobs)
        try await waitUntil { !controller.isActive }
        controller.reset()
        #expect(!controller.hasStarted)
        #expect(controller.snapshot.completionSummaries.isEmpty)
        #expect(controller.snapshot.elapsedSeconds == nil)
        controller.start([jobs[1]])
        #expect(controller.snapshot.items == [.queued])
        #expect(controller.snapshot.completionSummaries.isEmpty)
        try await waitUntil { !controller.isActive }
        #expect(controller.snapshot.items == [.completed(jobs[1].outputURL)])
        #expect(controller.snapshot.completionSummaries.count == 1)
    }

    private func makeController(_ builder: UIBatchBuilder) -> RestorationBatchController {
        RestorationBatchController(coordinator: RestorationBatchCoordinator(builder: builder, preflight: UIBatchPreflight()))
    }

    private func makeJobs() throws -> [ReviewedRestorationJob] {
        let inspection = MediaInspection(
            streams: [
                mediaStream(index: 0, codecName: "h264", codecType: "video", width: 624, height: 352, pixelFormat: "yuv420p",
                            colorRange: "tv", colorSpace: "smpte170m", colorTransfer: "bt709", colorPrimaries: "smpte170m",
                            averageFrameRate: "24000/1001", numberOfFrames: "237"),
                mediaStream(index: 1, codecName: "aac", codecType: "audio", channels: 2, channelLayout: "stereo", sampleRate: "48000"),
                mediaStream(index: 4, codecName: "subrip", codecType: "subtitle"),
                mediaStream(index: 7, codecName: "subrip", codecType: "subtitle")
            ], chapters: [],
            format: MediaFormat(filename: "source.mkv", streamCount: 4, formatName: "matroska", formatLongName: nil,
                                duration: "10", size: "1000000", bitRate: nil, tags: ["TITLE": "Review Test"])
        )
        guard case .eligible(let plan) = RestorationPlanner().plan(for: inspection) else { throw UIBatchError.ineligible }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftyTranscoder-UIBatch-\(UUID().uuidString)")
        return (0..<2).map { index in
            ReviewedRestorationJob(
                sourceURL: root.appendingPathComponent("source-\(index).mkv"), inspection: inspection,
                outputURL: root.appendingPathComponent("output-\(index).mp4"), plan: plan,
                gainEnabled: index == 0, aacStereoEnabled: index == 1,
                subtitleSelection: index == 0 ? .burnIn(streamIndex: 7) : .omit
            )
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw UIBatchError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private enum UIBatchError: Error { case ineligible, timeout }
private struct UIBatchPreflight: RestorationBatchPreflighting { func check(_ request: FullVideoRestorationRequest) {} }

private final class UIBatchBuilder: FullVideoRestorationPipelineBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [FullVideoRestorationRequest] = []
    private let waitForCancellation: Bool
    var requests: [FullVideoRestorationRequest] { lock.withLock { recorded } }
    init(waitForCancellation: Bool = false) { self.waitForCancellation = waitForCancellation }
    func makePipeline(for request: FullVideoRestorationRequest) throws -> any FullVideoRestorationPipelineRunning {
        lock.withLock { recorded.append(request) }
        return UIBatchPipeline(waitForCancellation: waitForCancellation)
    }
}

private actor UIBatchPipeline: FullVideoRestorationPipelineRunning {
    let waitForCancellation: Bool
    private var cancelled = false
    private var state: FullVideoRestorationState = .idle
    init(waitForCancellation: Bool) { self.waitForCancellation = waitForCancellation }
    func run(_ request: FullVideoRestorationRequest) async -> FullVideoRestorationState {
        state = .running(.processingChunks)
        if waitForCancellation {
            while !cancelled { try? await Task.sleep(for: .milliseconds(5)) }
            state = .cancelled(partialOutput: request.partialOutputURL)
        } else { state = .completed(output: request.finalOutputURL) }
        return state
    }
    func cancel() { cancelled = true }
    func currentProgress() -> Double { 0.42 }
    func currentState() -> FullVideoRestorationState { state }
}
