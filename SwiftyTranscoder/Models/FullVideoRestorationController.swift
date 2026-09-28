import Combine
import Foundation

@MainActor
final class FullVideoRestorationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case running(FullVideoRestorationStage)
        case cancelling(FullVideoRestorationStage?)
        case completed(URL)
        case cancelled(partialOutput: URL?)
        case failed(String, partialOutput: URL?)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress = 0.0

    private let pipelineBuilder: any FullVideoRestorationPipelineBuilding
    private let temporaryDirectory: URL
    private var pipeline: (any FullVideoRestorationPipelineRunning)?
    private var runTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var systemActivity: NSObjectProtocol?
    private var cancellationRequested = false

    init(
        pipelineBuilder: any FullVideoRestorationPipelineBuilding,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.pipelineBuilder = pipelineBuilder
        self.temporaryDirectory = temporaryDirectory
    }

    convenience init(bundleURL: URL = Bundle.main.bundleURL) {
        self.init(
            pipelineBuilder: BundledFullVideoRestorationPipelineBuilder(bundleURL: bundleURL)
        )
    }

    var isActive: Bool {
        switch phase {
        case .preparing, .running, .cancelling: true
        default: false
        }
    }

    var isPreventingIdleSystemSleep: Bool {
        systemActivity != nil
    }

    func start(
        sourceURL: URL,
        inspection: MediaInspection,
        outputURL: URL,
        plan: RestorationPlan,
        gainEnabled: Bool,
        aacStereoEnabled: Bool,
        subtitleSelection: SubtitleSelection
    ) {
        guard !isActive else { return }

        do {
            let request = try makeRequest(
                sourceURL: sourceURL,
                inspection: inspection,
                outputURL: outputURL,
                plan: plan,
                gainEnabled: gainEnabled,
                aacStereoEnabled: aacStereoEnabled,
                subtitleSelection: subtitleSelection
            )
            phase = .preparing
            progress = 0
            cancellationRequested = false
            beginSystemActivity()
            let pipelineBuilder = self.pipelineBuilder
            runTask = Task { [weak self] in
                do {
                    let pipeline = try await Task.detached(priority: .userInitiated) {
                        try pipelineBuilder.makePipeline(for: request)
                    }.value
                    guard let self else { return }
                    guard !self.cancellationRequested, !Task.isCancelled else {
                        self.finish(with: .cancelled(partialOutput: nil), finalProgress: 0)
                        return
                    }
                    self.pipeline = pipeline
                    self.startMonitoring(pipeline)
                    let result = await pipeline.run(request)
                    let finalProgress = await pipeline.currentProgress()
                    self.finish(with: result, finalProgress: finalProgress)
                } catch {
                    guard let self else { return }
                    let result: FullVideoRestorationState = self.cancellationRequested
                        || error is CancellationError
                        ? .cancelled(partialOutput: nil)
                        : .failed(error.localizedDescription, partialOutput: nil)
                    self.finish(with: result, finalProgress: 0)
                }
            }
        } catch {
            phase = .failed(error.localizedDescription, partialOutput: nil)
        }
    }

    func cancel() {
        guard isActive else { return }
        cancellationRequested = true
        switch phase {
        case .running(let stage): phase = .cancelling(stage)
        case .preparing: phase = .cancelling(nil)
        case .cancelling, .idle, .completed, .cancelled, .failed: break
        }
        if let pipeline {
            Task { await pipeline.cancel() }
        } else {
            runTask?.cancel()
        }
    }

    func reset() {
        guard !isActive else { return }
        phase = .idle
        progress = 0
    }

    func movePartialOutputToTrash(_ detectedPartialOutputURL: URL? = nil) throws {
        guard !isActive,
              let partialOutputURL = detectedPartialOutputURL ?? partialOutputURL else {
            throw FullVideoRestorationControllerError.noPartialOutput
        }
        guard partialOutputURL.lastPathComponent.hasSuffix(".partial.mp4") else {
            throw FullVideoRestorationControllerError.unsafePartialOutputName
        }

        var trashedURL: NSURL?
        try FileManager.default.trashItem(
            at: partialOutputURL,
            resultingItemURL: &trashedURL
        )
        reset()
    }

    private var partialOutputURL: URL? {
        switch phase {
        case .cancelled(let partialOutput), .failed(_, let partialOutput): partialOutput
        default: nil
        }
    }

    private func makeRequest(
        sourceURL: URL,
        inspection: MediaInspection,
        outputURL: URL,
        plan: RestorationPlan,
        gainEnabled: Bool,
        aacStereoEnabled: Bool,
        subtitleSelection: SubtitleSelection
    ) throws -> FullVideoRestorationRequest {
        guard let duration = inspection.format.duration.flatMap(Double.init),
              let sourceBytes = inspection.format.size.flatMap(Int64.init),
              let storage = RestorationStorageRequirement.estimate(
                sourceBytes: sourceBytes,
                durationSeconds: duration,
                frameRate: plan.frameRate,
                plan: plan
              ) else {
            throw FullVideoRestorationControllerError.invalidDurationOrSize
        }
        guard let sourceAudio = inspection.audioStreams.first else {
            throw FullVideoRestorationControllerError.missingAudio
        }
        let subtitleStreamOrdinal: Int?
        switch subtitleSelection {
        case .omit:
            subtitleStreamOrdinal = nil
        case .needsChoice:
            throw FullVideoRestorationControllerError.unresolvedSubtitleChoice
        case .burnIn(let streamIndex):
            guard let ordinal = inspection.subtitleStreams.firstIndex(where: {
                $0.index == streamIndex
            }) else {
                throw FullVideoRestorationControllerError.subtitleMissing(streamIndex)
            }
            guard inspection.subtitleStreams[ordinal].codecName == "subrip" else {
                throw FullVideoRestorationControllerError.unsupportedSubtitle(streamIndex)
            }
            subtitleStreamOrdinal = ordinal
        }

        let workspaceURL = temporaryDirectory.appendingPathComponent(
            "SwiftyTranscoder-Restoration-Full-\(UUID().uuidString)",
            isDirectory: true
        )
        let title = inspection.format.tags?.first(where: {
            $0.key.caseInsensitiveCompare("title") == .orderedSame
        })?.value
        return try FullVideoRestorationRequest(
            sourceURL: sourceURL,
            workspaceURL: workspaceURL,
            finalOutputURL: outputURL,
            plan: plan,
            totalFrameCount: storage.frameCount,
            durationSeconds: duration,
            sourceAudio: sourceAudio,
            gainEnabled: gainEnabled,
            aacStereoEnabled: aacStereoEnabled,
            subtitleStreamOrdinal: subtitleStreamOrdinal,
            expectedChapterCount: inspection.chapters.count,
            expectedContainerTitle: title
        )
    }

    private func startMonitoring(_ pipeline: any FullVideoRestorationPipelineRunning) {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let progress = await pipeline.currentProgress()
                let state = await pipeline.currentState()
                guard !Task.isCancelled else { return }
                self.progress = progress
                self.apply(state)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func finish(
        with state: FullVideoRestorationState,
        finalProgress: Double
    ) {
        monitorTask?.cancel()
        monitorTask = nil
        runTask = nil
        endSystemActivity()
        progress = min(max(finalProgress, 0), 1)
        apply(state)
        pipeline = nil
    }

    private func beginSystemActivity() {
        guard systemActivity == nil else { return }
        systemActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "SwiftyTranscoder is restoring video"
        )
    }

    private func endSystemActivity() {
        guard let systemActivity else { return }
        ProcessInfo.processInfo.endActivity(systemActivity)
        self.systemActivity = nil
    }

    private func apply(_ state: FullVideoRestorationState) {
        switch state {
        case .idle: break
        case .running(let stage):
            if case .cancelling = phase { return }
            phase = .running(stage)
        case .cancelling(let stage): phase = .cancelling(stage)
        case .completed(let output): phase = .completed(output)
        case .cancelled(let partial): phase = .cancelled(partialOutput: partial)
        case .failed(let message, let partial):
            phase = .failed(message, partialOutput: partial)
        }
    }
}

enum FullVideoRestorationControllerError: LocalizedError, Equatable {
    case invalidDurationOrSize
    case missingAudio
    case unresolvedSubtitleChoice
    case subtitleMissing(Int)
    case unsupportedSubtitle(Int)
    case noPartialOutput
    case unsafePartialOutputName

    var errorDescription: String? {
        switch self {
        case .invalidDurationOrSize:
            "AI restoration requires valid source duration and size metadata."
        case .missingAudio:
            "AI restoration requires a primary audio stream."
        case .unresolvedSubtitleChoice:
            "Choose a subtitle track or omit subtitles before starting AI restoration."
        case .subtitleMissing(let index):
            "Subtitle stream \(index) is no longer available."
        case .unsupportedSubtitle(let index):
            "Subtitle stream \(index) is not a supported SubRip text track."
        case .noPartialOutput:
            "There is no incomplete restoration output to move."
        case .unsafePartialOutputName:
            "Only a clearly labeled .partial.mp4 restoration output can be moved to the Trash."
        }
    }
}
