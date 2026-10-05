import AppKit
import Foundation

@MainActor
final class RestorationPreviewController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case running(NativeRestorationPreviewStage)
        case cancelling
        case completed(URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress = 0.0

    private var pipeline: NativeRestorationPreviewPipeline?
    private var runTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?

    var isActive: Bool {
        switch phase {
        case .preparing, .running, .cancelling: true
        default: false
        }
    }

    func start(
        sourceURL: URL,
        inspection: MediaInspection,
        plan: RestorationPlan,
        startSeconds: Double,
        durationSeconds: Double,
        gainEnabled: Bool,
        aacStereoEnabled: Bool
    ) {
        guard !isActive else { return }
        guard let sourceAudio = inspection.audioStreams.first else {
            phase = .failed("AI restoration preview requires a primary audio stream.")
            return
        }
        guard let frameRate = Self.frameRate(plan.frameRate) else {
            phase = .failed("AI restoration preview requires a valid frame rate.")
            return
        }
        let frameCount = min(240, max(1, Int((durationSeconds * frameRate).rounded())))

        progress = 0
        phase = .preparing
        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                let preparation = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let resources = try FullVideoRestorationResources.locate()
                    let frames = try resources.makeFrameProcessor(for: plan)
                    try Task.checkCancellation()
                    return frames
                }
                let frames = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: {
                    preparation.cancel()
                }
                try Task.checkCancellation()
                let extractor = try RestorationFrameExtractor()
                let assembler = try RestorationVideoAssembler()
                let audioMuxer = try RestorationAudioMuxer()
                let pipeline = NativeRestorationPreviewPipeline(
                    extractor: extractor,
                    sequenceProcessor: RestorationFrameSequenceProcessor(frameProcessor: frames),
                    assembler: assembler,
                    audioMuxer: audioMuxer
                )
                let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "SwiftyTranscoder-Restoration-Preview-\(UUID().uuidString)",
                    isDirectory: true
                )
                let request = try NativeRestorationPreviewRequest(
                    sourceURL: sourceURL,
                    workspaceURL: workspaceURL,
                    startSeconds: startSeconds,
                    frameCount: frameCount,
                    plan: plan,
                    sourceAudio: sourceAudio,
                    gainEnabled: gainEnabled,
                    aacStereoEnabled: aacStereoEnabled
                )
                self.pipeline = pipeline
                progress = 0
                phase = .running(.extractingFrames)
                monitorTask = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let self, let pipeline = self.pipeline else { return }
                        self.progress = await pipeline.progress
                        if case .running(let stage) = await pipeline.state, self.phase != .cancelling {
                            self.phase = .running(stage)
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
                let result = await pipeline.run(request)
                self.monitorTask?.cancel()
                self.monitorTask = nil
                self.progress = await pipeline.progress
                self.pipeline = nil
                self.runTask = nil
                switch result {
                case .completed(let output): self.phase = .completed(output)
                case .cancelled: self.phase = .idle
                case .failed(let message): self.phase = .failed(message)
                case .idle, .running, .cancelling:
                    self.phase = .failed("The restoration preview stopped in an unexpected state.")
                }
            } catch {
                self.pipeline = nil
                self.runTask = nil
                self.phase = Task.isCancelled ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        guard isActive else { return }
        phase = .cancelling
        runTask?.cancel()
        if let pipeline {
            Task { await pipeline.cancel() }
        }
    }

    func revealCompletedPreview() {
        guard case .completed(let url) = phase else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func playCompletedPreview() {
        guard case .completed(let url) = phase else { return }
        NSWorkspace.shared.open(url)
    }

    func reset() {
        guard !isActive else { return }
        phase = .idle
        progress = 0
    }

    private static func frameRate(_ value: String) -> Double? {
        let parts = value.split(separator: "/", maxSplits: 1).compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return parts[0] / parts[1]
    }
}
