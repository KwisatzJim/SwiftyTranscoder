import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct FullRestorationChunkProcessorTests {
    @Test func processesChunkAndPlacesSubtitleAwareDurableSegment() async throws {
        let fixture = try ChunkProcessorFixture()
        defer { fixture.remove() }
        let recorder = ChunkProcessorRecorder()
        let processor = try FullRestorationChunkProcessor(
            sourceURL: fixture.sourceURL,
            workspaceURL: fixture.workspaceURL,
            plan: fixture.plan,
            subtitleStreamOrdinal: 1,
            extractor: MockChunkExtractor(recorder: recorder),
            sequenceProcessor: MockChunkRestorer(recorder: recorder),
            assembler: MockChunkAssembler(recorder: recorder)
        )

        let segment = try await processor.process(fixture.chunk)

        #expect(segment.lastPathComponent == "segment-000002.partial.mp4")
        #expect(segment.deletingLastPathComponent().lastPathComponent == "segments")
        #expect(FileManager.default.fileExists(atPath: segment.path))
        #expect(await recorder.stages == [.extracting, .restoring, .encoding])
        let subtitle = try #require(await recorder.subtitleBurn)
        #expect(subtitle.subtitleStreamOrdinal == 1)
        #expect(abs(subtitle.chunkStartSeconds - fixture.chunk.startSeconds) < 0.000_001)
        #expect(await processor.progress == 1)
    }

    @Test func cancellationRoutesToActiveExtractor() async throws {
        let fixture = try ChunkProcessorFixture()
        defer { fixture.remove() }
        let extractor = CancellableChunkExtractor()
        let processor = try FullRestorationChunkProcessor(
            sourceURL: fixture.sourceURL,
            workspaceURL: fixture.workspaceURL,
            plan: fixture.plan,
            subtitleStreamOrdinal: nil,
            extractor: extractor,
            sequenceProcessor: MockChunkRestorer(recorder: ChunkProcessorRecorder()),
            assembler: MockChunkAssembler(recorder: ChunkProcessorRecorder())
        )
        let task = Task { try await processor.process(fixture.chunk) }

        await extractor.waitUntilStarted()
        await processor.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await extractor.wasCancelled)
        #expect(await processor.stage == .idle)
    }

    @Test func refusesChunkOutsideApprovedRoot() async throws {
        let fixture = try ChunkProcessorFixture()
        defer { fixture.remove() }
        let processor = try FullRestorationChunkProcessor(
            sourceURL: fixture.sourceURL,
            workspaceURL: fixture.workspaceURL,
            plan: fixture.plan,
            subtitleStreamOrdinal: nil,
            extractor: MockChunkExtractor(recorder: ChunkProcessorRecorder()),
            sequenceProcessor: MockChunkRestorer(recorder: ChunkProcessorRecorder()),
            assembler: MockChunkAssembler(recorder: ChunkProcessorRecorder())
        )
        let unsafe = RestorationChunk(
            index: 2,
            startFrame: fixture.chunk.startFrame,
            frameCount: fixture.chunk.frameCount,
            startSeconds: fixture.chunk.startSeconds,
            workspaceURL: fixture.rootURL.appendingPathComponent("chunk-000002")
        )

        await #expect(throws: FullRestorationChunkProcessorError.unapprovedChunk) {
            try await processor.process(unsafe)
        }
    }

    @Test func processesRepresentativeChunkWhenResearchAssetsAreAvailable() async throws {
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

        let workspaceURL = URL(
            fileURLWithPath: "/private/tmp/SwiftyTranscoder-Restoration-Milestone85"
        )
        try? FileManager.default.removeItem(at: workspaceURL)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let plan = RestorationPlan(
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
        let chunk = try #require(RestorationChunkPlan(
            totalFrameCount: 4,
            frameRate: plan.frameRate,
            workspaceURL: workspaceURL
        ).chunks.first)
        let tileProcessor = try CoreMLRestorationTileProcessor(modelURL: modelURL)
        let frameProcessor = RestorationFrameProcessor(tileProcessor: tileProcessor)
        let processor = try FullRestorationChunkProcessor(
            sourceURL: sourceURL,
            workspaceURL: workspaceURL,
            plan: plan,
            subtitleStreamOrdinal: nil,
            extractor: RestorationFrameExtractor(executableURL: ffmpeg),
            sequenceProcessor: RestorationFrameSequenceProcessor(
                frameProcessor: frameProcessor
            ),
            assembler: RestorationVideoAssembler(
                ffmpegURL: ffmpeg,
                ffprobeURL: ffprobe
            )
        )

        let segment = try await processor.process(chunk)

        #expect(segment.lastPathComponent == "segment-000001.partial.mp4")
        #expect(FileManager.default.fileExists(atPath: segment.path))
        #expect(await processor.progress == 1)
    }
}

private struct ChunkProcessorFixture {
    let rootURL: URL
    let sourceURL: URL
    let workspaceURL: URL
    let plan: RestorationPlan
    let chunk: RestorationChunk

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftyTranscoder-ChunkProcessorTests-\(UUID().uuidString)"
        )
        workspaceURL = rootURL.appendingPathComponent("SwiftyTranscoder-Restoration-Full")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        sourceURL = rootURL.appendingPathComponent("source.m4v")
        try Data("source".utf8).write(to: sourceURL)
        plan = RestorationPlan(
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
        let chunkPlan = try RestorationChunkPlan(
            totalFrameCount: 240,
            frameRate: plan.frameRate,
            workspaceURL: workspaceURL
        )
        chunk = chunkPlan.chunks[1]
    }

    func remove() { try? FileManager.default.removeItem(at: rootURL) }
}

private actor ChunkProcessorRecorder {
    private(set) var stages: [FullRestorationChunkStage] = []
    private(set) var subtitleBurn: RestorationSubtitleBurn?
    func append(_ stage: FullRestorationChunkStage) { stages.append(stage) }
    func record(_ subtitleBurn: RestorationSubtitleBurn?) { self.subtitleBurn = subtitleBurn }
}

private actor MockChunkExtractor: RestorationFrameExtracting {
    let recorder: ChunkProcessorRecorder
    init(recorder: ChunkProcessorRecorder) { self.recorder = recorder }

    func extract(_ extraction: RestorationFrameExtraction) async throws -> [URL] {
        await recorder.append(.extracting)
        try FileManager.default.createDirectory(
            at: extraction.outputDirectoryURL,
            withIntermediateDirectories: false
        )
        return try (1...extraction.frameCount).map { index in
            let url = extraction.outputDirectoryURL.appendingPathComponent(
                String(format: "frame-%08d.png", index)
            )
            try Data("source frame".utf8).write(to: url)
            return url
        }
    }

    func cancel() async {}
    func currentProgress() async -> Double { 1 }
}

private actor MockChunkRestorer: RestorationFrameSequenceProcessing {
    let recorder: ChunkProcessorRecorder
    init(recorder: ChunkProcessorRecorder) { self.recorder = recorder }

    func process(_ sequence: RestorationFrameSequence) async throws -> [URL] {
        await recorder.append(.restoring)
        try FileManager.default.createDirectory(
            at: sequence.outputDirectoryURL,
            withIntermediateDirectories: false
        )
        for url in sequence.outputURLs {
            try Data("restored frame".utf8).write(to: url)
        }
        return sequence.outputURLs
    }

    func cancel() async {}
    func currentProgress() async -> Double { 1 }
}

private actor MockChunkAssembler: RestorationVideoAssembling {
    let recorder: ChunkProcessorRecorder
    init(recorder: ChunkProcessorRecorder) { self.recorder = recorder }

    func assemble(_ assembly: RestorationVideoAssembly) async throws -> URL {
        await recorder.append(.encoding)
        await recorder.record(assembly.subtitleBurn)
        try Data("validated segment".utf8).write(to: assembly.outputURL)
        return assembly.outputURL
    }

    func cancel() async {}
    func currentProgress() async -> Double { 1 }
}

private actor CancellableChunkExtractor: RestorationFrameExtracting {
    private var continuation: CheckedContinuation<[URL], any Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var started = false
    private(set) var wasCancelled = false

    func extract(_ extraction: RestorationFrameExtraction) async throws -> [URL] {
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
