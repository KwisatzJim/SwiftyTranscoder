import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationCheckpointTests {
    @Test func reloadsSavedBlocksWithoutCountingUnfinishedFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let identity = try fixture.identity()
        let store = try fixture.store()
        try await store.create(identity: identity)
        try Data("validated segment bytes".utf8).write(to: fixture.segment(1))
        try await store.recordValidatedSegment(fixture.plan.chunks[0], identity: identity)
        try Data("unfinished segment bytes".utf8).write(to: fixture.segment(2))
        // A fresh store represents reopening after an interrupted process.
        let reopened = try fixture.store()
        let record = try await reopened.load(identity: identity)
        #expect(record.segments.count == 1)
        #expect(record.segments[0].frameCount == 120)
        #expect(record.segments[0].startFrame == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.segment(2).path))
    }

    @Test func refusesChangedSourceSettingsAndEngine() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let identity = try fixture.identity()
        let store = try fixture.store()
        try await store.create(identity: identity)
        let changedGain = try fixture.identity(gain: true)
        let changedEngine = try fixture.identity(engine: "engine-2")
        #expect(changedGain != identity && changedEngine != identity)
        await #expect(throws: RestorationCheckpointError.identityMismatch) { try await store.load(identity: changedGain) }
        await #expect(throws: RestorationCheckpointError.identityMismatch) { try await store.load(identity: changedEngine) }
        try Data("altered input".utf8).write(to: fixture.source)
        let changedSource = try fixture.identity()
        #expect(changedSource.sourceSHA256 != identity.sourceSHA256)
        await #expect(throws: RestorationCheckpointError.identityMismatch) { try await store.load(identity: changedSource) }
    }

    @Test func rejectsAlteredBlocksAndOutOfOrderRecordsWithoutReplacingProgress() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let identity = try fixture.identity()
        let store = try fixture.store()
        try await store.create(identity: identity)
        let recordURL = fixture.workspace.appendingPathComponent("restoration-checkpoint.json")
        let initial = try Data(contentsOf: recordURL)
        await #expect(throws: RestorationCheckpointError.invalidRecord) {
            try await store.recordValidatedSegment(fixture.plan.chunks[1], identity: identity)
        }
        #expect(try Data(contentsOf: recordURL) == initial)
        try Data("original".utf8).write(to: fixture.segment(1))
        try await store.recordValidatedSegment(fixture.plan.chunks[0], identity: identity)
        try Data("modified".utf8).write(to: fixture.segment(1)) // Same length.
        await #expect(throws: RestorationCheckpointError.segmentChanged) { try await store.load(identity: identity) }
    }

    @Test func refusesExistingAndUnrecognizedRecords() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let identity = try fixture.identity()
        let store = try fixture.store()
        try await store.create(identity: identity)
        await #expect(throws: RestorationCheckpointError.recordExists) { try await store.create(identity: identity) }
        let recordURL = fixture.workspace.appendingPathComponent("restoration-checkpoint.json")
        let encoder = JSONEncoder()
        try encoder.encode(RestorationCheckpoint(schemaVersion: 99, identity: identity, segments: [])).write(to: recordURL)
        let unsupported = try Data(contentsOf: recordURL)
        await #expect(throws: RestorationCheckpointError.identityMismatch) { try await store.load(identity: identity) }
        await #expect(throws: RestorationCheckpointError.identityMismatch) {
            try await store.recordValidatedSegment(fixture.plan.chunks[0], identity: identity)
        }
        #expect(try Data(contentsOf: recordURL) == unsupported)
    }

    @Test func refusesLinkedSegmentAndPreservesExternalFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let identity = try fixture.identity()
        let store = try fixture.store()
        try await store.create(identity: identity)
        let outside = fixture.root.appendingPathComponent("unrelated.mp4")
        let bytes = Data("unrelated file".utf8)
        try bytes.write(to: outside)
        try FileManager.default.createSymbolicLink(at: fixture.segment(1), withDestinationURL: outside)
        await #expect(throws: RestorationCheckpointError.invalidRecord) {
            try await store.recordValidatedSegment(fixture.plan.chunks[0], identity: identity)
        }
        #expect(try Data(contentsOf: outside) == bytes)
    }
}

private struct Fixture {
    let root: URL
    let workspace: URL
    let source: URL
    let plan: RestorationChunkPlan

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftyCheckpointTests-\(UUID().uuidString)")
        workspace = root.appendingPathComponent("SwiftyTranscoder-Restoration-Saved")
        source = root.appendingPathComponent("source.m4v")
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("segments"), withIntermediateDirectories: true)
        try Data("initial input".utf8).write(to: source)
        plan = try RestorationChunkPlan(totalFrameCount: 240, frameRate: "24/1", workspaceURL: workspace)
    }

    func identity(gain: Bool = false, engine: String = "engine-1") throws -> RestorationCheckpointIdentity {
        let request = try FullVideoRestorationRequest(
            sourceURL: source, workspaceURL: workspace, finalOutputURL: root.appendingPathComponent("result.mp4"),
            plan: RestorationPlan(method: .lightweightFSRCNN, sourceWidth: 624, sourceHeight: 352,
                                  outputWidth: 1248, outputHeight: 704, frameRate: "24/1",
                                  colorRange: "tv", colorSpace: "bt709", colorTransfer: "bt709", colorPrimaries: "bt709"),
            totalFrameCount: 240, durationSeconds: 10,
            sourceAudio: mediaStream(index: 1, codecName: "aac", codecType: "audio", channels: 2, channelLayout: "stereo", sampleRate: "48000"),
            gainEnabled: gain, aacStereoEnabled: true, expectedChapterCount: 0, expectedContainerTitle: nil
        )
        return try RestorationCheckpointIdentity.make(for: request, engineSignature: engine)
    }

    func store() throws -> RestorationCheckpointStore { try RestorationCheckpointStore(workspace: workspace, plan: plan) }
    func segment(_ index: Int) -> URL { workspace.appendingPathComponent("segments/segment-\(String(format: "%06d", index)).partial.mp4") }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
