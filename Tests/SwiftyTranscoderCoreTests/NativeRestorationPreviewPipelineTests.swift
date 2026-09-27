import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct NativeRestorationPreviewPipelineTests {
    @Test func runsFourNativeStagesInOrderWithoutFinalPromotion() async throws {
        let fixture = try PreviewPipelineFixture()
        defer { fixture.remove() }
        let recorder = PipelineRecorder()
        let extractor = MockPreviewExtractor(recorder: recorder)
        let restorer = MockPreviewRestorer(recorder: recorder)
        let assembler = MockPreviewAssembler(recorder: recorder)
        let audioMuxer = MockPreviewAudioMuxer(recorder: recorder)
        let pipeline = NativeRestorationPreviewPipeline(
            extractor: extractor,
            sequenceProcessor: restorer,
            assembler: assembler,
            audioMuxer: audioMuxer
        )

        let result = await pipeline.run(fixture.request)

        let expectedOutput = fixture.workspaceURL.appendingPathComponent("restored-preview.partial.mp4")
        #expect(result == .completed(previewPartialOutput: expectedOutput))
        #expect(await recorder.stages == [
            .extractingFrames, .restoringFrames, .assemblingSilentVideo, .muxingAudio,
        ])
        #expect(await pipeline.progress == 1)
        #expect(FileManager.default.fileExists(atPath: expectedOutput.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.finalOutputURL.path))
    }

    @Test func cancellationRoutesToActiveStageAndRemovesOwnedWorkspace() async throws {
        let fixture = try PreviewPipelineFixture()
        defer { fixture.remove() }
        let extractor = CancellablePreviewExtractor()
        let pipeline = NativeRestorationPreviewPipeline(
            extractor: extractor,
            sequenceProcessor: MockPreviewRestorer(recorder: PipelineRecorder()),
            assembler: MockPreviewAssembler(recorder: PipelineRecorder()),
            audioMuxer: MockPreviewAudioMuxer(recorder: PipelineRecorder())
        )
        let task = Task { await pipeline.run(fixture.request) }

        await extractor.waitUntilStarted()
        await pipeline.cancel()
        let result = await task.value

        #expect(result == .cancelled)
        #expect(await extractor.wasCancelled)
        #expect(!FileManager.default.fileExists(atPath: fixture.workspaceURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.sourceURL.path))
    }

    @Test func refusesExistingWorkspaceBeforeStartingAnyStage() async throws {
        let fixture = try PreviewPipelineFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.workspaceURL, withIntermediateDirectories: true)
        let recorder = PipelineRecorder()
        let pipeline = NativeRestorationPreviewPipeline(
            extractor: MockPreviewExtractor(recorder: recorder),
            sequenceProcessor: MockPreviewRestorer(recorder: recorder),
            assembler: MockPreviewAssembler(recorder: recorder),
            audioMuxer: MockPreviewAudioMuxer(recorder: recorder)
        )

        let result = await pipeline.run(fixture.request)

        guard case .failed(let message) = result else {
            Issue.record("Expected existing-workspace failure")
            return
        }
        #expect(message.contains("already exists"))
        #expect(await recorder.stages.isEmpty)
    }

    @Test func runsRepresentativeNativePipelineWhenResearchAssetsAreAvailable() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = root.appendingPathComponent("Alphas - s01e11 - Original Sin.m4v")
        let modelURL = root.appendingPathComponent(
            ".build/restoration-evaluation/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage"
        )
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              FileManager.default.fileExists(atPath: modelURL.path),
              let ffmpeg = MediaToolLocator.executableURL(for: .ffmpeg, bundleURL: root),
              let ffprobe = MediaToolLocator.executableURL(for: .ffprobe, bundleURL: root) else { return }
        let workspaceURL = URL(
            fileURLWithPath: "/private/tmp/SwiftyTranscoder-Restoration-Milestone73"
        )
        try? FileManager.default.removeItem(at: workspaceURL)
        let request = try NativeRestorationPreviewRequest(
            sourceURL: sourceURL,
            workspaceURL: workspaceURL,
            startSeconds: 540,
            frameCount: 4,
            plan: PreviewPipelineFixture.plan,
            sourceAudio: PreviewPipelineFixture.sourceAudio,
            gainEnabled: true,
            aacStereoEnabled: true
        )
        let tiles = try CoreMLRestorationTileProcessor(modelURL: modelURL)
        let frames = RestorationFrameProcessor(tileProcessor: tiles)
        let pipeline = NativeRestorationPreviewPipeline(
            extractor: RestorationFrameExtractor(executableURL: ffmpeg),
            sequenceProcessor: RestorationFrameSequenceProcessor(frameProcessor: frames),
            assembler: RestorationVideoAssembler(ffmpegURL: ffmpeg, ffprobeURL: ffprobe),
            audioMuxer: RestorationAudioMuxer(ffmpegURL: ffmpeg, ffprobeURL: ffprobe)
        )

        let result = await pipeline.run(request)

        let output = workspaceURL.appendingPathComponent("restored-preview.partial.mp4")
        #expect(result == .completed(previewPartialOutput: output))
        #expect(await pipeline.progress == 1)
        #expect(FileManager.default.fileExists(atPath: output.path))
    }
}

private struct PreviewPipelineFixture {
    let rootURL: URL
    let sourceURL: URL
    let workspaceURL: URL
    let finalOutputURL: URL
    let request: NativeRestorationPreviewRequest

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftyTranscoder-PreviewPipelineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        sourceURL = rootURL.appendingPathComponent("source.m4v")
        try Data("source".utf8).write(to: sourceURL)
        workspaceURL = rootURL.appendingPathComponent("SwiftyTranscoder-Restoration-Test")
        finalOutputURL = rootURL.appendingPathComponent("finished.mp4")
        request = try NativeRestorationPreviewRequest(
            sourceURL: sourceURL,
            workspaceURL: workspaceURL,
            startSeconds: 9,
            frameCount: 3,
            plan: Self.plan,
            sourceAudio: Self.sourceAudio,
            gainEnabled: true,
            aacStereoEnabled: true
        )
    }

    static let plan = RestorationPlan(
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

    static let sourceAudio = mediaStream(
        index: 1, codecName: "aac", codecType: "audio", channels: 2,
        channelLayout: "stereo", sampleRate: "48000", tags: ["language": "und"]
    )

    func remove() { try? FileManager.default.removeItem(at: rootURL) }
}

private actor PipelineRecorder {
    private(set) var stages: [NativeRestorationPreviewStage] = []
    func append(_ stage: NativeRestorationPreviewStage) { stages.append(stage) }
}

private actor MockPreviewExtractor: RestorationFrameExtracting {
    let recorder: PipelineRecorder
    init(recorder: PipelineRecorder) { self.recorder = recorder }

    func extract(_ extraction: RestorationFrameExtraction) async throws -> [URL] {
        await recorder.append(.extractingFrames)
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

private actor MockPreviewRestorer: RestorationFrameSequenceProcessing {
    let recorder: PipelineRecorder
    init(recorder: PipelineRecorder) { self.recorder = recorder }

    func process(_ sequence: RestorationFrameSequence) async throws -> [URL] {
        await recorder.append(.restoringFrames)
        try FileManager.default.createDirectory(
            at: sequence.outputDirectoryURL,
            withIntermediateDirectories: false
        )
        for output in sequence.outputURLs {
            try Data("restored frame".utf8).write(to: output)
        }
        return sequence.outputURLs
    }
    func cancel() async {}
    func currentProgress() async -> Double { 1 }
}

private actor MockPreviewAssembler: RestorationVideoAssembling {
    let recorder: PipelineRecorder
    init(recorder: PipelineRecorder) { self.recorder = recorder }

    func assemble(_ assembly: RestorationVideoAssembly) async throws -> URL {
        await recorder.append(.assemblingSilentVideo)
        try Data("silent partial".utf8).write(to: assembly.outputURL)
        return assembly.outputURL
    }
    func cancel() async {}
    func currentProgress() async -> Double { 1 }
}

private actor MockPreviewAudioMuxer: RestorationAudioMuxing {
    let recorder: PipelineRecorder
    init(recorder: PipelineRecorder) { self.recorder = recorder }

    func mux(_ request: RestorationAudioMux) async throws -> URL {
        await recorder.append(.muxingAudio)
        try Data("preview partial".utf8).write(to: request.outputURL)
        return request.outputURL
    }
    func cancel() async {}
    func currentProgress() async -> Double { 1 }
}

private actor CancellablePreviewExtractor: RestorationFrameExtracting {
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
