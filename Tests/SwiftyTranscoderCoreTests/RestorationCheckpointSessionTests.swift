import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationCheckpointSessionTests {
    @Test func retainsAndReusesOnlyRecordedBlocksWithExclusiveOwnership() async throws {
        let f = try SavedJobFixture()
        defer { f.remove() }
        let session = try f.session(.create)
        try await session.prepare()
        let competitor = try f.session(.resume)
        await #expect(throws: RestorationCheckpointSessionError.alreadyActive) { try await competitor.prepare() }
        let plan = try f.chunkPlan()
        let processor = SavedJobProcessor(workspace: f.workspace, failSecond: true)
        let first = RestorationChunkCoordinator(processor: processor, checkpointSession: session)
        await #expect(throws: CancellationError.self) { try await first.run(plan) }
        let firstBytes = try Data(contentsOf: f.segment(1))
        await session.finish(success: false)
        #expect(FileManager.default.fileExists(atPath: f.workspace.path))
        // Simulate a force quit after writing unfinished frames and an unrecorded segment.
        try FileManager.default.createDirectory(at: plan.chunks[1].workspaceURL, withIntermediateDirectories: false)
        try Data("unfinished".utf8).write(to: f.segment(2))
        let resumed = try f.session(.resume)
        try await resumed.prepare()
        #expect(!FileManager.default.fileExists(atPath: f.segment(2).path))
        #expect(!FileManager.default.fileExists(atPath: plan.chunks[1].workspaceURL.path))
        let remaining = SavedJobProcessor(workspace: f.workspace, failSecond: false)
        let coordinator = RestorationChunkCoordinator(processor: remaining, checkpointSession: resumed)
        let segments = try await coordinator.run(plan)
        #expect(segments == [f.segment(1), f.segment(2)])
        #expect(await remaining.indices == [2])
        #expect(try Data(contentsOf: f.segment(1)) == firstBytes)
        #expect(await coordinator.currentProgress() == 1)
        await resumed.finish(success: true)
        #expect(!FileManager.default.fileExists(atPath: f.workspace.path))
    }

    @Test func reusesEntireCompletedPrefixWithoutRunningInferenceAgain() async throws {
        let f = try SavedJobFixture()
        defer { f.remove() }
        let first = try f.session(.create)
        try await first.prepare()
        let plan = try f.chunkPlan()
        _ = try await RestorationChunkCoordinator(processor: SavedJobProcessor(workspace: f.workspace, failSecond: false), checkpointSession: first).run(plan)
        await first.finish(success: false)
        let reopened = try f.session(.resume)
        try await reopened.prepare()
        let processor = SavedJobProcessor(workspace: f.workspace, failSecond: false)
        let coordinator = RestorationChunkCoordinator(processor: processor, checkpointSession: reopened)
        #expect(try await coordinator.run(plan).count == 2)
        #expect(await processor.indices.isEmpty)
        #expect(await reopened.savedFrameCountAtStart() == 240)
        #expect(await coordinator.currentProgress() == 1)
        await reopened.finish(success: false)
    }

    @Test func refusesChangedIdentityAndUnknownFilesWithoutCleanup() async throws {
        let f = try SavedJobFixture()
        defer { f.remove() }
        let session = try f.session(.create)
        try await session.prepare()
        await session.finish(success: false)
        let unrelated = f.workspace.appendingPathComponent("my-notes.txt")
        try Data("keep me".utf8).write(to: unrelated)
        let mismatched = try f.session(.resume, engine: "different-model")
        await #expect(throws: RestorationCheckpointError.identityMismatch) { try await mismatched.prepare() }
        let unknown = try f.session(.resume)
        await #expect(throws: RestorationCheckpointError.invalidRecord) { try await unknown.prepare() }
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep me")
        #expect(FileManager.default.fileExists(atPath: f.workspace.appendingPathComponent("restoration-checkpoint.json").path))
    }

    @Test func refusesFreshReuseAndDetectsHelperOrModelChanges() async throws {
        let f = try SavedJobFixture()
        defer { f.remove() }
        let session = try f.session(.create)
        try await session.prepare()
        await session.finish(success: false)
        let another = try f.session(.create)
        await #expect(throws: FullVideoRestorationError.workspaceExists) { try await another.prepare() }
        let model = f.root.appendingPathComponent("model.mlpackage")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: false)
        let weights = model.appendingPathComponent("weights.bin")
        let helper = f.root.appendingPathComponent("ffmpeg")
        try Data("model-v1".utf8).write(to: weights)
        try Data("helper-v1".utf8).write(to: helper)
        let first = try RestorationCheckpointSession.engineSignature(model: model, ffmpeg: helper)
        try Data("model-v2".utf8).write(to: weights)
        #expect(try RestorationCheckpointSession.engineSignature(model: model, ffmpeg: helper) != first)
        try Data("model-v1".utf8).write(to: weights)
        try Data("helper-v2".utf8).write(to: helper)
        #expect(try RestorationCheckpointSession.engineSignature(model: model, ffmpeg: helper) != first)
    }
}

private actor SavedJobProcessor: RestorationChunkProcessing {
    let workspace: URL
    let failSecond: Bool
    var indices: [Int] = []
    init(workspace: URL, failSecond: Bool) { self.workspace = workspace; self.failSecond = failSecond }
    func process(_ chunk: RestorationChunk) throws -> URL {
        indices.append(chunk.index)
        if failSecond && chunk.index == 2 { throw CancellationError() }
        let directory = workspace.appendingPathComponent("segments")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent(String(format: "segment-%06d.partial.mp4", chunk.index))
        try Data("validated segment \(chunk.index)".utf8).write(to: output, options: .withoutOverwriting)
        return output
    }
    func cancel() {}
}

private struct SavedJobFixture {
    let root: URL
    let workspace: URL
    let request: FullVideoRestorationRequest
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftySavedJobTests-\(UUID().uuidString)")
        workspace = root.appendingPathComponent("SwiftyTranscoder-Restoration-Test")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("source.mp4")
        try Data("source".utf8).write(to: source)
        request = try FullVideoRestorationRequest(sourceURL: source, workspaceURL: workspace,
            finalOutputURL: root.appendingPathComponent("output.mp4"),
            plan: RestorationPlan(method: .lightweightFSRCNN, sourceWidth: 624, sourceHeight: 352, outputWidth: 1248, outputHeight: 704, frameRate: "24/1", colorRange: "tv", colorSpace: "bt709", colorTransfer: "bt709", colorPrimaries: "bt709"),
            totalFrameCount: 240, durationSeconds: 10,
            sourceAudio: mediaStream(index: 1, codecName: "aac", codecType: "audio", channels: 2, channelLayout: "stereo", sampleRate: "48000"),
            gainEnabled: false, aacStereoEnabled: true, expectedChapterCount: 0, expectedContainerTitle: nil)
    }
    func session(_ mode: RestorationCheckpointMode, engine: String = "engine-v1") throws -> RestorationCheckpointSession {
        try RestorationCheckpointSession(request: request, identity: RestorationCheckpointIdentity.make(for: request, engineSignature: engine), mode: mode)
    }
    func chunkPlan() throws -> RestorationChunkPlan { try RestorationChunkPlan(totalFrameCount: 240, frameRate: "24/1", workspaceURL: workspace) }
    func segment(_ index: Int) -> URL { workspace.appendingPathComponent(String(format: "segments/segment-%06d.partial.mp4", index)) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
