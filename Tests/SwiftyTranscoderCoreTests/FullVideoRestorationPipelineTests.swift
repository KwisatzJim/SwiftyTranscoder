import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct FullVideoRestorationPipelineTests {
    @Test func runsValidatedBoundariesInOrderAndPromotesFinalOutput() async throws {
        let fixture = try FullPipelineFixture()
        defer { fixture.remove() }
        let recorder = FullPipelineRecorder()
        let pipeline = FullVideoRestorationPipeline(
            chunkCoordinator: MockFullChunkCoordinator(recorder: recorder),
            segmentConcatenator: MockFullConcatenator(recorder: recorder),
            audioMuxer: MockFullAudioMuxer(recorder: recorder),
            outputPromoter: MockFullPromoter(recorder: recorder)
        )

        let result = await pipeline.run(fixture.request)

        #expect(result == .completed(output: fixture.finalOutputURL))
        #expect(await recorder.stages == [
            .processingChunks,
            .assemblingSilentVideo,
            .muxingAudioAndMetadata,
            .stagingDestination,
            .promotingDestination,
        ])
        #expect(await pipeline.progress == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.finalOutputURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.workspaceURL.path))
    }

    @Test func cancellationRoutesToChunksAndCleansOwnedWorkspace() async throws {
        let fixture = try FullPipelineFixture()
        defer { fixture.remove() }
        let chunks = CancellableFullChunkCoordinator()
        let pipeline = FullVideoRestorationPipeline(
            chunkCoordinator: chunks,
            segmentConcatenator: MockFullConcatenator(recorder: FullPipelineRecorder()),
            audioMuxer: MockFullAudioMuxer(recorder: FullPipelineRecorder()),
            outputPromoter: MockFullPromoter(recorder: FullPipelineRecorder())
        )
        let task = Task { await pipeline.run(fixture.request) }

        await chunks.waitUntilStarted()
        await pipeline.cancel()
        let result = await task.value

        #expect(result == .cancelled(partialOutput: nil))
        #expect(await chunks.wasCancelled)
        #expect(!FileManager.default.fileExists(atPath: fixture.workspaceURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.finalOutputURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.sourceURL.path))
    }

    @Test func refusesDestinationConflictBeforeStartingChunks() async throws {
        let fixture = try FullPipelineFixture()
        defer { fixture.remove() }
        try Data("existing".utf8).write(to: fixture.finalOutputURL)
        let recorder = FullPipelineRecorder()
        let pipeline = FullVideoRestorationPipeline(
            chunkCoordinator: MockFullChunkCoordinator(recorder: recorder),
            segmentConcatenator: MockFullConcatenator(recorder: recorder),
            audioMuxer: MockFullAudioMuxer(recorder: recorder),
            outputPromoter: MockFullPromoter(recorder: recorder)
        )

        let result = await pipeline.run(fixture.request)

        guard case .failed(let message, partialOutput: nil) = result else {
            Issue.record("Expected destination conflict")
            return
        }
        #expect(message.contains("already exists"))
        #expect(await recorder.stages.isEmpty)
        #expect(try String(contentsOf: fixture.finalOutputURL, encoding: .utf8) == "existing")
    }

    @Test func refusesExistingWorkspaceWithoutDeletingItsContents() async throws {
        let fixture = try FullPipelineFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.workspaceURL, withIntermediateDirectories: false)
        let marker = fixture.workspaceURL.appendingPathComponent("unrelated.txt")
        try Data("preserve".utf8).write(to: marker)
        let recorder = FullPipelineRecorder()
        let pipeline = FullVideoRestorationPipeline(
            chunkCoordinator: MockFullChunkCoordinator(recorder: recorder),
            segmentConcatenator: MockFullConcatenator(recorder: recorder),
            audioMuxer: MockFullAudioMuxer(recorder: recorder),
            outputPromoter: MockFullPromoter(recorder: recorder)
        )
        guard case .failed = await pipeline.run(fixture.request) else {
            Issue.record("Expected existing workspace refusal")
            return
        }
        #expect(try String(contentsOf: marker, encoding: .utf8) == "preserve")
        #expect(await recorder.stages.isEmpty)
    }

    @Test func completedPromotionWinsOverLateCancellation() async throws {
        let fixture = try FullPipelineFixture()
        defer { fixture.remove() }
        let promoter = PausingFullPromoter()
        let pipeline = FullVideoRestorationPipeline(
            chunkCoordinator: MockFullChunkCoordinator(recorder: FullPipelineRecorder()),
            segmentConcatenator: MockFullConcatenator(recorder: FullPipelineRecorder()),
            audioMuxer: MockFullAudioMuxer(recorder: FullPipelineRecorder()),
            outputPromoter: promoter
        )
        let task = Task { await pipeline.run(fixture.request) }

        await promoter.waitUntilPromotionStarts()
        await pipeline.cancel()
        await promoter.finishPromotion()
        let result = await task.value

        #expect(result == .completed(output: fixture.finalOutputURL))
        #expect(FileManager.default.fileExists(atPath: fixture.finalOutputURL.path))
    }
}

private struct FullPipelineFixture {
    let rootURL: URL
    let sourceURL: URL
    let workspaceURL: URL
    let finalOutputURL: URL
    let request: FullVideoRestorationRequest

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftyTranscoder-FullPipelineTests-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        sourceURL = rootURL.appendingPathComponent("source.m4v")
        workspaceURL = rootURL.appendingPathComponent("SwiftyTranscoder-Restoration-Full")
        finalOutputURL = rootURL.appendingPathComponent("restored.mp4")
        try Data("source".utf8).write(to: sourceURL)
        request = try FullVideoRestorationRequest(
            sourceURL: sourceURL,
            workspaceURL: workspaceURL,
            finalOutputURL: finalOutputURL,
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
            totalFrameCount: 3,
            durationSeconds: 0.125125,
            sourceAudio: mediaStream(
                index: 1,
                codecName: "aac",
                codecType: "audio",
                channels: 2,
                channelLayout: "stereo",
                sampleRate: "48000",
                tags: ["language": "eng"]
            ),
            gainEnabled: true,
            aacStereoEnabled: true,
            expectedChapterCount: 0,
            expectedContainerTitle: "Episode"
        )
    }

    func remove() { try? FileManager.default.removeItem(at: rootURL) }
}

private actor FullPipelineRecorder {
    private(set) var stages: [FullVideoRestorationStage] = []
    func append(_ stage: FullVideoRestorationStage) { stages.append(stage) }
}

private actor MockFullChunkCoordinator: RestorationChunkCoordinating {
    let recorder: FullPipelineRecorder
    init(recorder: FullPipelineRecorder) { self.recorder = recorder }

    func run(_ plan: RestorationChunkPlan) async throws -> [URL] {
        await recorder.append(.processingChunks)
        let directory = plan.chunks[0].workspaceURL.deletingLastPathComponent()
            .appendingPathComponent("segments")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try plan.chunks.map { chunk in
            let url = directory.appendingPathComponent(
                String(format: "segment-%06d.partial.mp4", chunk.index)
            )
            try Data("segment".utf8).write(to: url)
            return url
        }
    }

    func cancel() async {}
    func currentProgress() async -> Double { 1 }
}

private actor MockFullConcatenator: RestorationSegmentConcatenating {
    let recorder: FullPipelineRecorder
    init(recorder: FullPipelineRecorder) { self.recorder = recorder }

    func concatenate(_ request: RestorationSegmentConcatenation) async throws -> URL {
        await recorder.append(.assemblingSilentVideo)
        try Data("silent video".utf8).write(to: request.outputURL)
        return request.outputURL
    }

    func cancel() async {}
    func currentProgress() async -> Double { 1 }
}

private actor MockFullAudioMuxer: RestorationAudioMuxing {
    let recorder: FullPipelineRecorder
    init(recorder: FullPipelineRecorder) { self.recorder = recorder }

    func mux(_ request: RestorationAudioMux) async throws -> URL {
        await recorder.append(.muxingAudioAndMetadata)
        try Data("validated output".utf8).write(to: request.outputURL)
        return request.outputURL
    }

    func cancel() async {}
    func currentProgress() async -> Double { 1 }
}

private actor MockFullPromoter: RestorationOutputPromoting {
    let recorder: FullPipelineRecorder
    init(recorder: FullPipelineRecorder) { self.recorder = recorder }

    func stage(_ request: RestorationOutputPromotion) async throws -> URL {
        await recorder.append(.stagingDestination)
        try FileManager.default.copyItem(
            at: request.validatedOutputURL,
            to: request.partialOutputURL
        )
        return request.partialOutputURL
    }

    func promote(_ request: RestorationOutputPromotion) async throws -> URL {
        await recorder.append(.promotingDestination)
        try FileManager.default.moveItem(
            at: request.partialOutputURL,
            to: request.finalOutputURL
        )
        return request.finalOutputURL
    }
}

private actor CancellableFullChunkCoordinator: RestorationChunkCoordinating {
    private var continuation: CheckedContinuation<[URL], any Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var started = false
    private(set) var wasCancelled = false

    func run(_ plan: RestorationChunkPlan) async throws -> [URL] {
        started = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() async {
        wasCancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func currentProgress() async -> Double { 0.5 }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor PausingFullPromoter: RestorationOutputPromoting {
    private var promotionContinuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var promotionStarted = false

    func stage(_ request: RestorationOutputPromotion) async throws -> URL {
        try FileManager.default.copyItem(
            at: request.validatedOutputURL,
            to: request.partialOutputURL
        )
        return request.partialOutputURL
    }

    func promote(_ request: RestorationOutputPromotion) async throws -> URL {
        promotionStarted = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
        await withCheckedContinuation { promotionContinuation = $0 }
        try FileManager.default.moveItem(
            at: request.partialOutputURL,
            to: request.finalOutputURL
        )
        return request.finalOutputURL
    }

    func waitUntilPromotionStarts() async {
        if promotionStarted { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finishPromotion() {
        promotionContinuation?.resume()
        promotionContinuation = nil
    }
}
