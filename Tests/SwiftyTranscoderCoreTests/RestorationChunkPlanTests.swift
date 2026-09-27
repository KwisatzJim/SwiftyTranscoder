import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationChunkPlanTests {
    @Test func dividesWholeVideoIntoBoundedContiguousChunks() throws {
        let plan = try RestorationChunkPlan(
            totalFrameCount: 301,
            frameRate: "24000/1001",
            workspaceURL: workspaceURL
        )

        #expect(plan.chunks.map(\.frameCount) == [120, 120, 61])
        #expect(plan.chunks.map(\.startFrame) == [0, 120, 240])
        #expect(plan.chunks.map(\.index) == [1, 2, 3])
        #expect(abs(plan.chunks[1].startSeconds - 5.005) < 0.000_001)
    }

    @Test func coordinatorRemovesEachFrameWorkspaceBeforeAdvancing() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try RestorationChunkPlan(
            totalFrameCount: 241,
            frameRate: "24/1",
            workspaceURL: root
        )
        let processor = RecordingChunkProcessor(segmentDirectoryURL: root.appendingPathComponent("segments"))
        let coordinator = RestorationChunkCoordinator(processor: processor)

        let segments = try await coordinator.run(plan)

        #expect(segments.count == 3)
        #expect(await processor.maximumExistingChunkCount == 1)
        #expect(plan.chunks.allSatisfy { !FileManager.default.fileExists(atPath: $0.workspaceURL.path) })
        #expect(await coordinator.completedChunkCount == 3)
        #expect(await coordinator.progress == 1)
    }

    @Test func rejectsSegmentStoredInsideDisposableChunk() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try RestorationChunkPlan(
            totalFrameCount: 1,
            frameRate: "24/1",
            workspaceURL: root
        )
        let coordinator = RestorationChunkCoordinator(processor: UnsafeChunkProcessor())

        await #expect(throws: RestorationChunkError.segmentInsideDisposableWorkspace) {
            try await coordinator.run(plan)
        }
        #expect(!FileManager.default.fileExists(atPath: plan.chunks[0].workspaceURL.path))
        await #expect(throws: RestorationChunkError.alreadyRun) {
            try await coordinator.run(plan)
        }
    }

    private var workspaceURL: URL {
        URL(fileURLWithPath: "/private/tmp/SwiftyTranscoder-Restoration-ChunkPlan")
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftyTranscoder-Restoration-ChunkTests-\(UUID().uuidString)"
        )
    }
}

private actor RecordingChunkProcessor: RestorationChunkProcessing {
    let segmentDirectoryURL: URL
    private(set) var maximumExistingChunkCount = 0

    init(segmentDirectoryURL: URL) {
        self.segmentDirectoryURL = segmentDirectoryURL
    }

    func process(_ chunk: RestorationChunk) async throws -> URL {
        try FileManager.default.createDirectory(at: chunk.workspaceURL, withIntermediateDirectories: true)
        let root = chunk.workspaceURL.deletingLastPathComponent()
        let existing = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("chunk-") }.count
        maximumExistingChunkCount = max(maximumExistingChunkCount, existing)
        try FileManager.default.createDirectory(at: segmentDirectoryURL, withIntermediateDirectories: true)
        let segment = segmentDirectoryURL.appendingPathComponent(String(format: "segment-%06d.mp4", chunk.index))
        try Data("segment".utf8).write(to: segment)
        return segment
    }

    func cancel() async {}
}

private actor UnsafeChunkProcessor: RestorationChunkProcessing {
    func process(_ chunk: RestorationChunk) async throws -> URL {
        try FileManager.default.createDirectory(at: chunk.workspaceURL, withIntermediateDirectories: true)
        let segment = chunk.workspaceURL.appendingPathComponent("segment.mp4")
        try Data("segment".utf8).write(to: segment)
        return segment
    }

    func cancel() async {}
}
