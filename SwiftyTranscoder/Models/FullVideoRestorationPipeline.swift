import Foundation

struct FullVideoRestorationRequest: Sendable {
    let checkpointMode: RestorationCheckpointMode?
    let sourceURL: URL
    let workspaceURL: URL
    let finalOutputURL: URL
    let plan: RestorationPlan
    let totalFrameCount: Int64
    let durationSeconds: Double
    let sourceAudio: MediaStream
    let gainEnabled: Bool
    let aacStereoEnabled: Bool
    let subtitleStreamOrdinal: Int?
    let expectedChapterCount: Int
    let expectedContainerTitle: String?

    init(
        sourceURL: URL,
        workspaceURL: URL,
        finalOutputURL: URL,
        plan: RestorationPlan,
        totalFrameCount: Int64,
        durationSeconds: Double,
        sourceAudio: MediaStream,
        gainEnabled: Bool,
        aacStereoEnabled: Bool,
        subtitleStreamOrdinal: Int? = nil,
        expectedChapterCount: Int,
        expectedContainerTitle: String?,
        checkpointMode: RestorationCheckpointMode? = nil
    ) throws {
        guard workspaceURL.lastPathComponent.hasPrefix("SwiftyTranscoder-Restoration-") else {
            throw FullVideoRestorationError.invalidWorkspaceName
        }
        guard totalFrameCount > 0, durationSeconds > 0, durationSeconds.isFinite else {
            throw FullVideoRestorationError.invalidDurationOrFrameCount
        }
        guard expectedChapterCount >= 0 else {
            throw FullVideoRestorationError.invalidChapterCount
        }
        if let subtitleStreamOrdinal, subtitleStreamOrdinal < 0 {
            throw FullVideoRestorationError.invalidSubtitleStream
        }
        guard CompatibilityAudioSettings(source: sourceAudio) != nil else {
            throw FullVideoRestorationError.unsupportedAudio
        }
        _ = try RestorationChunkPlan(
            totalFrameCount: totalFrameCount,
            frameRate: plan.frameRate,
            workspaceURL: workspaceURL
        )
        _ = try RestorationOutputPromotion(
            validatedOutputURL: workspaceURL.appendingPathComponent(
                "restored-audio.partial.mp4"
            ),
            workspaceURL: workspaceURL,
            sourceURL: sourceURL,
            finalOutputURL: finalOutputURL
        )

        self.checkpointMode = checkpointMode
        self.sourceURL = sourceURL
        self.workspaceURL = workspaceURL
        self.finalOutputURL = finalOutputURL
        self.plan = plan
        self.totalFrameCount = totalFrameCount
        self.durationSeconds = durationSeconds
        self.sourceAudio = sourceAudio
        self.gainEnabled = gainEnabled
        self.aacStereoEnabled = aacStereoEnabled
        self.subtitleStreamOrdinal = subtitleStreamOrdinal
        self.expectedChapterCount = expectedChapterCount
        self.expectedContainerTitle = expectedContainerTitle
    }

    var partialOutputURL: URL {
        finalOutputURL
            .deletingPathExtension()
            .appendingPathExtension("partial")
            .appendingPathExtension("mp4")
    }
}

enum FullVideoRestorationStage: Equatable, Sendable {
    case processingChunks
    case assemblingSilentVideo
    case muxingAudioAndMetadata
    case stagingDestination
    case promotingDestination
}

enum FullVideoRestorationState: Equatable, Sendable {
    case idle
    case running(FullVideoRestorationStage)
    case cancelling(FullVideoRestorationStage)
    case completed(output: URL)
    case cancelled(partialOutput: URL?)
    case failed(String, partialOutput: URL?)
}

protocol FullVideoRestorationPipelineRunning: Sendable {
    func run(_ request: FullVideoRestorationRequest) async -> FullVideoRestorationState
    func cancel() async
    func currentProgress() async -> Double
    func currentState() async -> FullVideoRestorationState
    func savedFrameCountAtStart() async -> Int64
}

extension FullVideoRestorationPipelineRunning {
    func savedFrameCountAtStart() async -> Int64 { 0 }
}

actor FullVideoRestorationPipeline: FullVideoRestorationPipelineRunning {
    private let checkpointSession: RestorationCheckpointSession?
    private var ownsWorkspace = false
    private var hasStarted = false
    private let chunkCoordinator: any RestorationChunkCoordinating
    private let segmentConcatenator: any RestorationSegmentConcatenating
    private let audioMuxer: any RestorationAudioMuxing
    private let outputPromoter: any RestorationOutputPromoting
    private var cancellationRequested = false
    private(set) var progress = 0.0
    private(set) var state: FullVideoRestorationState = .idle

    init(
        chunkCoordinator: any RestorationChunkCoordinating,
        segmentConcatenator: any RestorationSegmentConcatenating,
        audioMuxer: any RestorationAudioMuxing,
        outputPromoter: any RestorationOutputPromoting,
        checkpointSession: RestorationCheckpointSession? = nil
    ) {
        self.checkpointSession = checkpointSession
        self.chunkCoordinator = chunkCoordinator
        self.segmentConcatenator = segmentConcatenator
        self.audioMuxer = audioMuxer
        self.outputPromoter = outputPromoter
    }

    func run(_ request: FullVideoRestorationRequest) async -> FullVideoRestorationState {
        guard !isActive, !hasStarted else {
            return .failed("This full-video restoration pipeline has already started.", partialOutput: nil)
        }
        hasStarted = true
        cancellationRequested = false
        progress = 0
        state = .running(.processingChunks)

        do {
            try prepare(request)
            if let checkpointSession { try await checkpointSession.prepare() }
            try checkCancellation()
            let chunkPlan = try RestorationChunkPlan(
                totalFrameCount: request.totalFrameCount,
                frameRate: request.plan.frameRate,
                workspaceURL: request.workspaceURL
            )

            state = .running(.processingChunks)
            let chunkMonitor = monitorProgress(base: 0, weight: 0.90) {
                await self.chunkCoordinator.currentProgress()
            }
            let segments: [URL]
            do {
                segments = try await chunkCoordinator.run(chunkPlan)
            } catch {
                chunkMonitor.cancel()
                throw error
            }
            chunkMonitor.cancel()
            try checkCancellation()
            progress = 0.90

            state = .running(.assemblingSilentVideo)
            let concatenation = try RestorationSegmentConcatenation(
                segmentURLs: segments,
                workspaceURL: request.workspaceURL,
                plan: request.plan,
                totalFrameCount: request.totalFrameCount
            )
            let assemblyMonitor = monitorProgress(base: 0.90, weight: 0.04) {
                await self.segmentConcatenator.currentProgress()
            }
            let silentVideo: URL
            do {
                silentVideo = try await segmentConcatenator.concatenate(concatenation)
            } catch {
                assemblyMonitor.cancel()
                throw error
            }
            assemblyMonitor.cancel()
            try checkCancellation()
            progress = 0.94

            state = .running(.muxingAudioAndMetadata)
            let audioRequest = try RestorationAudioMux(
                fullDurationSourceURL: request.sourceURL,
                silentVideoURL: silentVideo,
                workspaceURL: request.workspaceURL,
                durationSeconds: request.durationSeconds,
                sourceAudio: request.sourceAudio,
                gainEnabled: request.gainEnabled,
                aacStereoEnabled: request.aacStereoEnabled,
                expectedChapterCount: request.expectedChapterCount,
                expectedContainerTitle: request.expectedContainerTitle
            )
            let audioMonitor = monitorProgress(base: 0.94, weight: 0.04) {
                await self.audioMuxer.currentProgress()
            }
            let validatedOutput: URL
            do {
                validatedOutput = try await audioMuxer.mux(audioRequest)
            } catch {
                audioMonitor.cancel()
                throw error
            }
            audioMonitor.cancel()
            try checkCancellation()
            progress = 0.98

            let promotion = try RestorationOutputPromotion(
                validatedOutputURL: validatedOutput,
                workspaceURL: request.workspaceURL,
                sourceURL: request.sourceURL,
                finalOutputURL: request.finalOutputURL
            )
            state = .running(.stagingDestination)
            _ = try await outputPromoter.stage(promotion)
            try checkCancellation()
            progress = 0.99

            state = .running(.promotingDestination)
            let output = try await outputPromoter.promote(promotion)
            progress = 1
            if let checkpointSession { await checkpointSession.finish(success: true) }
            else if ownsWorkspace { try? removeOwnedWorkspace(request.workspaceURL) }
            state = .completed(output: output)
        } catch {
            if let checkpointSession { await checkpointSession.finish(success: false) }
            else if ownsWorkspace { try? removeOwnedWorkspace(request.workspaceURL) }
            let partial = existingPartialOutput(request.partialOutputURL)
            if cancellationRequested || error is CancellationError {
                state = .cancelled(partialOutput: partial)
            } else {
                state = .failed(error.localizedDescription, partialOutput: partial)
            }
        }
        return state
    }

    func cancel() async {
        guard case .running(let stage) = state else { return }
        cancellationRequested = true
        state = .cancelling(stage)
        switch stage {
        case .processingChunks: await chunkCoordinator.cancel()
        case .assemblingSilentVideo: await segmentConcatenator.cancel()
        case .muxingAudioAndMetadata: await audioMuxer.cancel()
        case .stagingDestination, .promotingDestination: break
        }
    }

    func savedFrameCountAtStart() async -> Int64 { await checkpointSession?.savedFrameCountAtStart() ?? 0 }

    func currentProgress() -> Double { progress }
    func currentState() -> FullVideoRestorationState { state }

    private var isActive: Bool {
        switch state {
        case .running, .cancelling: true
        default: false
        }
    }

    private func prepare(_ request: FullVideoRestorationRequest) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: request.sourceURL.path) else {
            throw FullVideoRestorationError.sourceMissing
        }
        guard checkpointSession != nil || !fileManager.fileExists(atPath: request.workspaceURL.path) else {
            throw FullVideoRestorationError.workspaceExists
        }
        guard !fileManager.fileExists(atPath: request.finalOutputURL.path) else {
            throw FullVideoRestorationError.outputExists
        }
        guard !fileManager.fileExists(atPath: request.partialOutputURL.path) else {
            throw FullVideoRestorationError.partialOutputExists
        }
        var isDirectory: ObjCBool = false
        let destinationDirectory = request.finalOutputURL.deletingLastPathComponent()
        guard fileManager.fileExists(
            atPath: destinationDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw FullVideoRestorationError.destinationFolderMissing
        }
        if checkpointSession == nil {
            try fileManager.createDirectory(at: request.workspaceURL, withIntermediateDirectories: true)
            ownsWorkspace = true
        }
    }

    private func monitorProgress(
        base: Double,
        weight: Double,
        value: @escaping @Sendable () async -> Double
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                let childProgress = await value()
                self.setProgress(base + childProgress * weight)
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
    }

    private func setProgress(_ value: Double) {
        progress = min(max(value, progress), 1)
    }

    private func checkCancellation() throws {
        if cancellationRequested || Task.isCancelled { throw CancellationError() }
    }

    private func existingPartialOutput(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func removeOwnedWorkspace(_ url: URL) throws {
        guard url.lastPathComponent.hasPrefix("SwiftyTranscoder-Restoration-") else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum FullVideoRestorationError: LocalizedError, Equatable {
    case invalidWorkspaceName
    case invalidDurationOrFrameCount
    case invalidChapterCount
    case invalidSubtitleStream
    case unsupportedAudio
    case sourceMissing
    case workspaceExists
    case outputExists
    case partialOutputExists
    case destinationFolderMissing

    var errorDescription: String? {
        switch self {
        case .invalidWorkspaceName: "The full restoration workspace name is not safely recognizable."
        case .invalidDurationOrFrameCount: "The full restoration duration or frame count is invalid."
        case .invalidChapterCount: "The full restoration chapter count is invalid."
        case .invalidSubtitleStream: "The full restoration subtitle stream is invalid."
        case .unsupportedAudio: "The full restoration audio layout is unsupported."
        case .sourceMissing: "The full restoration source is unavailable."
        case .workspaceExists: "The full restoration workspace already exists and will not be reused."
        case .outputExists: "The full restoration destination already exists and will not be overwritten."
        case .partialOutputExists: "The full restoration partial destination already exists and will not be overwritten."
        case .destinationFolderMissing: "The full restoration destination folder is no longer available."
        }
    }
}
