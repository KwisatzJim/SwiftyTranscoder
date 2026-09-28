import Foundation
import Testing
@testable import SwiftyTranscoderCore

@MainActor
struct FullVideoRestorationControllerTests {
    @Test func buildsApprovedRequestAndPublishesCompletion() async throws {
        let pipeline = ControllerPipeline(mode: .complete)
        let builder = RecordingRestorationBuilder(pipeline: pipeline)
        let controller = FullVideoRestorationController(
            pipelineBuilder: builder,
            temporaryDirectory: URL(fileURLWithPath: "/private/tmp")
        )
        let sourceURL = URL(fileURLWithPath: "/private/tmp/source.m4v")
        let outputURL = URL(fileURLWithPath: "/private/tmp/restored.mp4")

        controller.start(
            sourceURL: sourceURL,
            inspection: inspection(),
            outputURL: outputURL,
            plan: restorationPlan,
            gainEnabled: true,
            aacStereoEnabled: true,
            subtitleSelection: .burnIn(streamIndex: 7)
        )
        try await waitUntil { !controller.isActive }

        #expect(controller.phase == .completed(outputURL))
        #expect(controller.progress == 1)
        let request = try #require(builder.request)
        #expect(request.sourceURL == sourceURL)
        #expect(request.finalOutputURL == outputURL)
        #expect(request.totalFrameCount == 240)
        #expect(request.subtitleStreamOrdinal == 1)
        #expect(request.expectedChapterCount == 1)
        #expect(request.expectedContainerTitle == "Example Episode")
        #expect(request.workspaceURL.lastPathComponent.hasPrefix(
            "SwiftyTranscoder-Restoration-Full-"
        ))
    }

    @Test func forwardsCancellationAndReportsPartialOutput() async throws {
        let partialURL = URL(fileURLWithPath: "/private/tmp/restored.partial.mp4")
        let pipeline = ControllerPipeline(mode: .waitForCancellation(partialURL))
        let controller = FullVideoRestorationController(
            pipelineBuilder: RecordingRestorationBuilder(pipeline: pipeline),
            temporaryDirectory: URL(fileURLWithPath: "/private/tmp")
        )

        controller.start(
            sourceURL: URL(fileURLWithPath: "/private/tmp/source.m4v"),
            inspection: inspection(),
            outputURL: URL(fileURLWithPath: "/private/tmp/restored.mp4"),
            plan: restorationPlan,
            gainEnabled: false,
            aacStereoEnabled: false,
            subtitleSelection: .omit
        )
        try await waitUntil {
            if case .running = controller.phase { return true }
            return false
        }
        #expect(controller.progress == 0.42)

        controller.cancel()
        try await waitUntil { !controller.isActive }

        #expect(controller.phase == .cancelled(partialOutput: partialURL))
        #expect(await pipeline.wasCancelled)
    }

    @Test func reportsFactoryFailureWithoutStartingPipeline() async throws {
        let builder = FailingRestorationBuilder()
        let controller = FullVideoRestorationController(
            pipelineBuilder: builder,
            temporaryDirectory: URL(fileURLWithPath: "/private/tmp")
        )

        controller.start(
            sourceURL: URL(fileURLWithPath: "/private/tmp/source.m4v"),
            inspection: inspection(),
            outputURL: URL(fileURLWithPath: "/private/tmp/restored.mp4"),
            plan: restorationPlan,
            gainEnabled: false,
            aacStereoEnabled: false,
            subtitleSelection: .omit
        )
        try await waitUntil { !controller.isActive }

        guard case .failed(let message, partialOutput: nil) = controller.phase else {
            Issue.record("Expected resource construction failure")
            return
        }
        #expect(message.contains("test resource failure"))
    }

    @Test func refusesUnresolvedSubtitleBeforeCallingFactory() async {
        let builder = RecordingRestorationBuilder(pipeline: ControllerPipeline(mode: .complete))
        let controller = FullVideoRestorationController(
            pipelineBuilder: builder,
            temporaryDirectory: URL(fileURLWithPath: "/private/tmp")
        )

        controller.start(
            sourceURL: URL(fileURLWithPath: "/private/tmp/source.m4v"),
            inspection: inspection(),
            outputURL: URL(fileURLWithPath: "/private/tmp/restored.mp4"),
            plan: restorationPlan,
            gainEnabled: false,
            aacStereoEnabled: false,
            subtitleSelection: .needsChoice
        )

        guard case .failed(let message, partialOutput: nil) = controller.phase else {
            Issue.record("Expected unresolved subtitle failure")
            return
        }
        #expect(message.contains("Choose a subtitle track"))
        #expect(builder.request == nil)
    }

    private var restorationPlan: RestorationPlan {
        RestorationPlan(
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
    }

    private func inspection() -> MediaInspection {
        MediaInspection(
            streams: [
                mediaStream(
                    index: 0, codecName: "h264", codecType: "video",
                    width: 624, height: 352, pixelFormat: "yuv420p",
                    colorRange: "tv", colorSpace: "smpte170m",
                    colorTransfer: "bt709", colorPrimaries: "smpte170m",
                    averageFrameRate: "24000/1001"
                ),
                mediaStream(
                    index: 1, codecName: "aac", codecType: "audio",
                    channels: 2, channelLayout: "stereo", sampleRate: "48000"
                ),
                mediaStream(index: 4, codecName: "subrip", codecType: "subtitle"),
                mediaStream(index: 7, codecName: "subrip", codecType: "subtitle"),
            ],
            chapters: [MediaChapter(id: 0, startTime: "0", endTime: "10", tags: nil)],
            format: MediaFormat(
                filename: "source.m4v",
                streamCount: 4,
                formatName: "mov,mp4,m4a,3gp,3g2,mj2",
                formatLongName: nil,
                duration: "10.0",
                size: "1000000",
                bitRate: nil,
                tags: ["TITLE": "Example Episode"]
            )
        )
    }

    private func waitUntil(
        timeoutIterations: Int = 100,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for controller state")
    }
}

private final class RecordingRestorationBuilder: FullVideoRestorationPipelineBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private let pipeline: any FullVideoRestorationPipelineRunning
    private var recordedRequest: FullVideoRestorationRequest?

    init(pipeline: any FullVideoRestorationPipelineRunning) { self.pipeline = pipeline }

    var request: FullVideoRestorationRequest? {
        lock.withLock { recordedRequest }
    }

    func makePipeline(
        for request: FullVideoRestorationRequest
    ) throws -> any FullVideoRestorationPipelineRunning {
        lock.withLock { recordedRequest = request }
        return pipeline
    }
}

private struct FailingRestorationBuilder: FullVideoRestorationPipelineBuilding {
    func makePipeline(
        for request: FullVideoRestorationRequest
    ) throws -> any FullVideoRestorationPipelineRunning {
        throw ControllerTestError.resourceFailure
    }
}

private enum ControllerPipelineMode: Sendable {
    case complete
    case waitForCancellation(URL)
}

private actor ControllerPipeline: FullVideoRestorationPipelineRunning {
    private let mode: ControllerPipelineMode
    private var state: FullVideoRestorationState = .idle
    private var progress = 0.0
    private var continuation: CheckedContinuation<FullVideoRestorationState, Never>?
    private(set) var wasCancelled = false

    init(mode: ControllerPipelineMode) { self.mode = mode }

    func run(_ request: FullVideoRestorationRequest) async -> FullVideoRestorationState {
        state = .running(.processingChunks)
        switch mode {
        case .complete:
            progress = 1
            state = .completed(output: request.finalOutputURL)
            return state
        case .waitForCancellation:
            progress = 0.42
            return await withCheckedContinuation { continuation = $0 }
        }
    }

    func cancel() {
        wasCancelled = true
        guard case .waitForCancellation(let partialURL) = mode else { return }
        state = .cancelled(partialOutput: partialURL)
        continuation?.resume(returning: state)
        continuation = nil
    }

    func currentProgress() -> Double { progress }
    func currentState() -> FullVideoRestorationState { state }
}

private enum ControllerTestError: LocalizedError {
    case resourceFailure
    var errorDescription: String? { "test resource failure" }
}
