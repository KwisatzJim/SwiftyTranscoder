import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationBatchCoordinatorTests {
    @Test func completesTwoShortJobsWithRealResourcesWhenAvailable() async throws {
        let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = project.appendingPathComponent("Alphas - s01e11 - Original Sin.m4v")
        let tiled = project.appendingPathComponent(".build/restoration-evaluation/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage")
        let sd = project.appendingPathComponent(".build/restoration-evaluation/sd-shape-experiment/RealESRGAN_x2plus_656x384_fp16.mlpackage")
        guard FileManager.default.fileExists(atPath: source.path),
              FileManager.default.fileExists(atPath: tiled.path),
              FileManager.default.fileExists(atPath: sd.path),
              let ffmpeg = MediaToolLocator.executableURL(for: .ffmpeg, bundleURL: project),
              let ffprobe = MediaToolLocator.executableURL(for: .ffprobe, bundleURL: project) else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftyTranscoder-BatchReal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = RestorationPlan(
            method: .realESRGANX2Plus, sourceWidth: 624, sourceHeight: 352, outputWidth: 1248, outputHeight: 704,
            frameRate: "24000/1001", colorRange: "tv", colorSpace: "smpte170m", colorTransfer: "bt709", colorPrimaries: "smpte170m"
        )
        let requests = try (0..<2).map { index in
            try FullVideoRestorationRequest(
                sourceURL: source,
                workspaceURL: root.appendingPathComponent("SwiftyTranscoder-Restoration-\(index)"),
                finalOutputURL: root.appendingPathComponent("output-\(index).mp4"),
                plan: plan, totalFrameCount: 2, durationSeconds: 2.0 / (24_000.0 / 1_001.0),
                sourceAudio: mediaStream(index: 1, codecName: "aac", codecType: "audio", channels: 2, channelLayout: "stereo", sampleRate: "48000"),
                gainEnabled: index == 0, aacStereoEnabled: index == 1,
                expectedChapterCount: 0, expectedContainerTitle: nil
            )
        }
        let resources = FullVideoRestorationResources(ffmpegURL: ffmpeg, ffprobeURL: ffprobe, modelURL: tiled, sdModelURL: sd)
        let coordinator = RestorationBatchCoordinator(builder: FullVideoRestorationPipelineFactory(resources: resources))
        let result = await coordinator.run(requests)
        #expect(result.phase == .finished)
        #expect(result.items == requests.map { .completed($0.finalOutputURL) })
        for (index, request) in requests.enumerated() {
            #expect(!FileManager.default.fileExists(atPath: request.workspaceURL.path))
            #expect(!FileManager.default.fileExists(atPath: request.partialOutputURL.path))
            let process = Process()
            let output = Pipe()
            process.executableURL = ffprobe
            process.arguments = ["-v", "error", "-show_streams", "-show_format", "-show_chapters", "-of", "json", request.finalOutputURL.path]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            let inspection = try JSONDecoder().decode(MediaInspection.self, from: data)
            #expect(inspection.videoStreams.first?.codecName == "hevc")
            #expect(inspection.videoStreams.first?.numberOfFrames == "2")
            #expect(inspection.audioStreams.map(\.codecName) == (index == 0 ? ["ac3"] : ["ac3", "aac"]))
        }
    }

    @Test func runsInOrderWithOneActivePipelineAndSourceSpecificSettings() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let recorder = BatchRecorder()
        let builder = BatchBuilder(recorder: recorder)
        let clock = RestorationSummaryTestClock([100, 105, 125, 130, 160, 165])
        let coordinator = RestorationBatchCoordinator(builder: builder, preflight: fixture.preflight, now: { clock.next() })
        let result = await coordinator.run(fixture.requests)

        #expect(result.phase == .finished)
        #expect(result.items == fixture.requests.map { .completed($0.finalOutputURL) })
        #expect(result.progress == 1)
        #expect(result.activeIndex == nil)
        #expect(await recorder.maximumActive == 1)
        #expect(await recorder.started == ["first.mp4", "second.mp4"])
        #expect(builder.requests.map(\.gainEnabled) == [true, false])
        #expect(builder.requests.map(\.aacStereoEnabled) == [false, true])
        #expect(builder.requests.map(\.subtitleStreamOrdinal) == [0, nil])
        #expect(result.elapsedSeconds == 65)
        #expect(result.completionSummaries[0]?.elapsedSeconds == 20)
        #expect(result.completionSummaries[1]?.elapsedSeconds == 30)
        #expect(result.completionSummaries[0]?.averageFramesPerSecond == 0.15)
        #expect(result.completionSummaries[1]?.averageFramesPerSecond == 0.1)

    }

    @Test func recordsFailureAndContinuesToNextFile() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let builder = BatchBuilder(recorder: BatchRecorder(), firstMode: .fail)
        let coordinator = RestorationBatchCoordinator(builder: builder, preflight: fixture.preflight)
        let result = await coordinator.run(fixture.requests)
        #expect(result.phase == .finished)
        #expect(result.items[0] == .failed("test job failure", partialOutput: fixture.requests[0].partialOutputURL))
        #expect(result.items[1] == .completed(fixture.requests[1].finalOutputURL))
        #expect(result.completionSummaries[0] == nil)
        #expect(result.completionSummaries[1] != nil)
        #expect(builder.requests.count == 2)
    }

    @Test func cancelsActiveJobAndLeavesRemainingJobsUnstarted() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let recorder = BatchRecorder()
        let builder = BatchBuilder(recorder: recorder, firstMode: .waitForCancellation)
        let coordinator = RestorationBatchCoordinator(builder: builder, preflight: fixture.preflight)
        let task = Task { await coordinator.run(fixture.requests) }
        try await waitUntil { await recorder.started.count == 1 }
        await coordinator.cancel()
        let result = await task.value
        #expect(result.phase == .cancelled)
        #expect(result.items == [.cancelled(partialOutput: fixture.requests[0].partialOutputURL), .notRun])
        #expect(result.completionSummaries.isEmpty)
        #expect(builder.requests.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.requests[0].finalOutputURL.path))
    }

    @Test func cancellationDuringPreparationDoesNotStartThePipeline() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let recorder = BatchRecorder()
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let builder = BatchBuilder(recorder: recorder, preparationGate: gate)
        let coordinator = RestorationBatchCoordinator(builder: builder, preflight: fixture.preflight)
        let task = Task { await coordinator.run(fixture.requests) }
        try await waitUntil { builder.requests.count == 1 }
        await coordinator.cancel()
        gate.signal()
        let result = await task.value
        #expect(result.phase == .cancelled)
        #expect(result.items == [.cancelled(partialOutput: nil), .notRun])
        #expect(await recorder.started.isEmpty)
    }

    @Test func callerTaskCancellationStopsBatch() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let recorder = BatchRecorder()
        let builder = BatchBuilder(recorder: recorder, firstMode: .waitForCancellation)
        let coordinator = RestorationBatchCoordinator(builder: builder, preflight: fixture.preflight)
        let task = Task { await coordinator.run(fixture.requests) }
        try await waitUntil { await recorder.started.count == 1 }
        task.cancel()
        let result = await task.value
        #expect(result.phase == .cancelled)
        #expect(result.items[1] == .notRun)
        #expect(builder.requests.count == 1)
    }

    @Test func rejectsOverlappingDestinationsBeforeBuildingAnything() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let builder = BatchBuilder(recorder: BatchRecorder())
        let coordinator = RestorationBatchCoordinator(builder: builder, preflight: fixture.preflight)
        let second = try fixture.request(name: "other", output: fixture.requests[0].partialOutputURL)
        let result = await coordinator.run([fixture.requests[0], second])
        guard case .rejected = result.phase else { Issue.record("Expected path conflict"); return }
        #expect(builder.requests.isEmpty)
    }

    @Test func protectsOtherJobsSourcesAndWorkspaceTrees() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let builder = BatchBuilder(recorder: BatchRecorder())
        let coordinator = RestorationBatchCoordinator(builder: builder, preflight: fixture.preflight)
        let conflict = try fixture.request(name: "other", output: fixture.requests[0].sourceURL)
        let result = await coordinator.run([fixture.requests[0], conflict])
        guard case .rejected = result.phase else { Issue.record("Expected source conflict"); return }
        let nested = try fixture.request(
            name: "other", workspace: fixture.requests[0].workspaceURL.appendingPathComponent("SwiftyTranscoder-Restoration-nested")
        )
        let nestedResult = await coordinator.run([fixture.requests[0], nested])
        guard case .rejected = nestedResult.phase else { Issue.record("Expected workspace conflict"); return }
        #expect(builder.requests.isEmpty)
        #expect(try String(contentsOf: fixture.requests[0].sourceURL, encoding: .utf8) == "source")
    }

    @Test func checksCapacityAgainBeforeEachJobAndPreservesCompletedResults() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let capacity = CapacityCounter()
        let preflight = RestorationBatchPreflight(availableBytes: { _ in capacity.next() })
        let builder = BatchBuilder(recorder: BatchRecorder())
        let coordinator = RestorationBatchCoordinator(builder: builder, preflight: preflight)
        let result = await coordinator.run(fixture.requests)
        #expect(result.items[0] == .completed(fixture.requests[0].finalOutputURL))
        guard case .failed(let message, partialOutput: nil) = result.items[1] else {
            Issue.record("Expected second-job capacity refusal"); return
        }
        #expect(message.contains("storage is insufficient"))
        #expect(builder.requests.count == 1)
    }

    @Test func refusesExistingPartialWithoutChangingIt() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let partial = fixture.requests[0].partialOutputURL
        try Data("existing partial".utf8).write(to: partial)
        let builder = BatchBuilder(recorder: BatchRecorder())
        let coordinator = RestorationBatchCoordinator(builder: builder, preflight: fixture.preflight)
        let result = await coordinator.run([fixture.requests[0]])
        guard case .failed = result.items[0] else { Issue.record("Expected partial conflict"); return }
        #expect(builder.requests.isEmpty)
        #expect(try String(contentsOf: partial, encoding: .utf8) == "existing partial")
    }

    @Test func rejectsConcurrentRunWithoutReplacingActiveState() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let recorder = BatchRecorder()
        let coordinator = RestorationBatchCoordinator(
            builder: BatchBuilder(recorder: recorder, firstMode: .waitForCancellation), preflight: fixture.preflight
        )
        let task = Task { await coordinator.run(fixture.requests) }
        try await waitUntil { await recorder.started.count == 1 }
        let rejected = await coordinator.run(fixture.requests)
        guard case .rejected = rejected.phase else { Issue.record("Expected active-batch refusal"); return }
        #expect(await coordinator.snapshot.phase == .running)
        await coordinator.cancel()
        _ = await task.value
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw BatchTestError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private struct BatchFixture {
    let root: URL
    let requests: [FullVideoRestorationRequest]
    var preflight: RestorationBatchPreflight { RestorationBatchPreflight(availableBytes: { _ in Int64.max }) }

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftyTranscoder-BatchTests-\(UUID().uuidString)")
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["first", "second"] {
            try Data("source".utf8).write(to: root.appendingPathComponent("\(name)-source.mp4"))
        }
        requests = try ["first", "second"].map { try Self.makeRequest(root: root, name: $0) }
    }

    func request(name: String, output: URL? = nil, workspace: URL? = nil) throws -> FullVideoRestorationRequest {
        try Self.makeRequest(root: root, name: name, output: output, workspace: workspace)
    }

    static func makeRequest(root: URL, name: String, output: URL? = nil, workspace: URL? = nil) throws -> FullVideoRestorationRequest {
        try FullVideoRestorationRequest(
            sourceURL: root.appendingPathComponent(name == "other" ? "second-source.mp4" : "\(name)-source.mp4"),
            workspaceURL: workspace ?? root.appendingPathComponent("SwiftyTranscoder-Restoration-\(name)"),
            finalOutputURL: output ?? root.appendingPathComponent("\(name).mp4"),
            plan: RestorationPlan(
                method: .realESRGANX2Plus, sourceWidth: 624, sourceHeight: 352, outputWidth: 1248, outputHeight: 704,
                frameRate: "24/1", colorRange: "tv", colorSpace: "bt709", colorTransfer: "bt709", colorPrimaries: "bt709"
            ),
            totalFrameCount: 3, durationSeconds: 0.125,
            sourceAudio: mediaStream(index: 1, codecName: "aac", codecType: "audio", channels: 2, channelLayout: "stereo", sampleRate: "48000"),
            gainEnabled: name == "first", aacStereoEnabled: name != "first",
            subtitleStreamOrdinal: name == "first" ? 0 : nil,
            expectedChapterCount: 0, expectedContainerTitle: nil
        )
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private enum BatchTestError: Error { case timeout }
private enum BatchMode: Sendable { case complete, fail, waitForCancellation }

private actor BatchRecorder {
    private(set) var started: [String] = []
    private var active = 0
    private(set) var maximumActive = 0
    func begin(_ name: String) { started.append(name); active += 1; maximumActive = max(maximumActive, active) }
    func end() { active -= 1 }
}

private final class BatchBuilder: FullVideoRestorationPipelineBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [FullVideoRestorationRequest] = []
    private let recorder: BatchRecorder
    private let firstMode: BatchMode
    private let preparationGate: DispatchSemaphore?
    var requests: [FullVideoRestorationRequest] { lock.withLock { recordedRequests } }

    init(recorder: BatchRecorder, firstMode: BatchMode = .complete, preparationGate: DispatchSemaphore? = nil) {
        self.recorder = recorder; self.firstMode = firstMode; self.preparationGate = preparationGate
    }

    func makePipeline(for request: FullVideoRestorationRequest) throws -> any FullVideoRestorationPipelineRunning {
        let index = lock.withLock { let index = recordedRequests.count; recordedRequests.append(request); return index }
        if let preparationGate, index == 0 { preparationGate.wait() }
        return BatchPipeline(recorder: recorder, mode: index == 0 ? firstMode : .complete)
    }
}

private actor BatchPipeline: FullVideoRestorationPipelineRunning {
    let recorder: BatchRecorder
    let mode: BatchMode
    private var cancelled = false
    private var state: FullVideoRestorationState = .idle
    init(recorder: BatchRecorder, mode: BatchMode) { self.recorder = recorder; self.mode = mode }

    func run(_ request: FullVideoRestorationRequest) async -> FullVideoRestorationState {
        state = .running(.processingChunks)
        await recorder.begin(request.finalOutputURL.lastPathComponent)
        if mode == .waitForCancellation {
            while !cancelled { try? await Task.sleep(for: .milliseconds(5)) }
            state = .cancelled(partialOutput: request.partialOutputURL)
        } else if mode == .fail {
            state = .failed("test job failure", partialOutput: request.partialOutputURL)
        } else {
            try? Data("restored".utf8).write(to: request.finalOutputURL)
            state = .completed(output: request.finalOutputURL)
        }
        await recorder.end()
        return state
    }
    func cancel() { cancelled = true }
    func currentProgress() -> Double { 0.42 }
    func currentState() -> FullVideoRestorationState { state }
}

private final class CapacityCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int64 { lock.withLock { count += 1; return count <= 2 ? Int64.max : 0 } }
}
