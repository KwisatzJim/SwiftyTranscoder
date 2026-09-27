import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationJobTests {
    @Test func runsStagesInOrderAndPromotesOnlyAfterValidation() async throws {
        let fixture = try JobFixture()
        defer { fixture.remove() }
        let executor = RecordingRestorationExecutor()
        let runner = RestorationJobRunner(executor: executor)

        let result = try await runner.run(fixture.job)

        #expect(result == .completed(output: fixture.job.finalOutputURL))
        #expect(await executor.performedStages == RestorationStage.allCases)
        #expect(FileManager.default.fileExists(atPath: fixture.job.finalOutputURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.job.partialOutputURL.path))
    }

    @Test func validationFailureKeepsClearlyLabeledPartialOutput() async throws {
        let fixture = try JobFixture()
        defer { fixture.remove() }
        let executor = RecordingRestorationExecutor(failingStage: .validatingPartialOutput)
        let runner = RestorationJobRunner(executor: executor)

        let result = try await runner.run(fixture.job)

        guard case .failed(let message, let partialOutput) = result else {
            Issue.record("Expected validation failure")
            return
        }
        #expect(message.contains("deliberate test failure"))
        #expect(partialOutput == fixture.job.partialOutputURL)
        #expect(FileManager.default.fileExists(atPath: fixture.job.partialOutputURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.job.finalOutputURL.path))
    }

    @Test func refusesExistingDestinationBeforeAnyStageRuns() async throws {
        let fixture = try JobFixture()
        defer { fixture.remove() }
        try Data("existing".utf8).write(to: fixture.job.finalOutputURL)
        let executor = RecordingRestorationExecutor()
        let runner = RestorationJobRunner(executor: executor)

        let result = try await runner.run(fixture.job)

        guard case .failed(let message, partialOutput: nil) = result else {
            Issue.record("Expected an existing-output failure")
            return
        }
        #expect(message.contains("already exists"))
        #expect(await executor.performedStages.isEmpty)
        #expect(try String(contentsOf: fixture.job.finalOutputURL, encoding: .utf8) == "existing")
    }

    @Test func cancellationStopsTheActiveStageAndNeverPromotes() async throws {
        let fixture = try JobFixture()
        defer { fixture.remove() }
        let executor = CancellableRestorationExecutor()
        let runner = RestorationJobRunner(executor: executor)
        let task = Task { try await runner.run(fixture.job) }

        await executor.waitUntilRestorationStarts()
        await runner.cancel()
        let result = try await task.value

        #expect(result == .cancelled(partialOutput: nil))
        #expect(await executor.wasCancelled)
        #expect(!FileManager.default.fileExists(atPath: fixture.job.finalOutputURL.path))
    }
}

private struct JobFixture {
    let rootURL: URL
    let job: RestorationJob

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftyTranscoder-RestorationJobTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceURL = rootURL.appendingPathComponent("source.m4v")
        try Data("source".utf8).write(to: sourceURL)
        job = RestorationJob(
            sourceURL: sourceURL,
            finalOutputURL: rootURL.appendingPathComponent("restored.mp4"),
            workspaceURL: rootURL.appendingPathComponent("workspace"),
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
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private actor RecordingRestorationExecutor: RestorationStageExecuting {
    private(set) var performedStages: [RestorationStage] = []
    private let failingStage: RestorationStage?

    init(failingStage: RestorationStage? = nil) {
        self.failingStage = failingStage
    }

    func perform(_ stage: RestorationStage, for job: RestorationJob) async throws {
        performedStages.append(stage)
        if stage == .assemblingPartialOutput {
            try Data("partial".utf8).write(to: job.partialOutputURL)
        }
        if stage == failingStage {
            throw TestRestorationError.deliberateFailure
        }
    }

    func cancel() async {}
}

private actor CancellableRestorationExecutor: RestorationStageExecuting {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var restorationStarted = false
    private(set) var wasCancelled = false

    func perform(_ stage: RestorationStage, for job: RestorationJob) async throws {
        guard stage == .restoringFrames else { return }
        restorationStarted = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll()
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() async {
        wasCancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func waitUntilRestorationStarts() async {
        if restorationStarted { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}

private enum TestRestorationError: LocalizedError {
    case deliberateFailure

    var errorDescription: String? { "A deliberate test failure occurred." }
}
