import Foundation

struct NativeRestorationPreviewRequest: Equatable, Sendable {
    let sourceURL: URL
    let workspaceURL: URL
    let startSeconds: Double
    let frameCount: Int
    let plan: RestorationPlan

    init(
        sourceURL: URL,
        workspaceURL: URL,
        startSeconds: Double,
        frameCount: Int,
        plan: RestorationPlan
    ) throws {
        guard workspaceURL.lastPathComponent.hasPrefix("SwiftyTranscoder-Restoration-") else {
            throw NativeRestorationPreviewError.invalidWorkspaceName
        }
        _ = try RestorationFrameExtraction(
            sourceURL: sourceURL,
            workspaceURL: workspaceURL,
            startSeconds: startSeconds,
            frameCount: frameCount
        )
        self.sourceURL = sourceURL
        self.workspaceURL = workspaceURL
        self.startSeconds = startSeconds
        self.frameCount = frameCount
        self.plan = plan
    }
}

enum NativeRestorationPreviewStage: Equatable, Sendable {
    case extractingFrames
    case restoringFrames
    case assemblingSilentVideo
}

enum NativeRestorationPreviewState: Equatable, Sendable {
    case idle
    case running(NativeRestorationPreviewStage)
    case cancelling(NativeRestorationPreviewStage)
    case completed(silentPartialOutput: URL)
    case cancelled
    case failed(String)
}

actor NativeRestorationPreviewPipeline {
    private let extractor: any RestorationFrameExtracting
    private let sequenceProcessor: any RestorationFrameSequenceProcessing
    private let assembler: any RestorationVideoAssembling
    private var cancellationRequested = false
    private(set) var progress = 0.0
    private(set) var state: NativeRestorationPreviewState = .idle

    init(
        extractor: any RestorationFrameExtracting,
        sequenceProcessor: any RestorationFrameSequenceProcessing,
        assembler: any RestorationVideoAssembling
    ) {
        self.extractor = extractor
        self.sequenceProcessor = sequenceProcessor
        self.assembler = assembler
    }

    func run(_ request: NativeRestorationPreviewRequest) async -> NativeRestorationPreviewState {
        guard !isActive else {
            return .failed("A native restoration preview is already running.")
        }
        cancellationRequested = false
        progress = 0

        do {
            try prepare(request)

            state = .running(.extractingFrames)
            let extraction = try RestorationFrameExtraction(
                sourceURL: request.sourceURL,
                workspaceURL: request.workspaceURL,
                startSeconds: request.startSeconds,
                frameCount: request.frameCount
            )
            let extractionMonitor = monitorProgress(base: 0, weight: 0.10) {
                await self.extractor.currentProgress()
            }
            let sourceFrames: [URL]
            do {
                sourceFrames = try await extractor.extract(extraction)
            } catch {
                extractionMonitor.cancel()
                throw error
            }
            extractionMonitor.cancel()
            try checkCancellation()
            progress = 0.10

            state = .running(.restoringFrames)
            let sequence = try RestorationFrameSequence(
                sourceURLs: sourceFrames,
                workspaceURL: request.workspaceURL,
                expectedWidth: request.plan.sourceWidth,
                expectedHeight: request.plan.sourceHeight
            )
            let restorationMonitor = monitorProgress(base: 0.10, weight: 0.85) {
                await self.sequenceProcessor.currentProgress()
            }
            let restoredFrames: [URL]
            do {
                restoredFrames = try await sequenceProcessor.process(sequence)
            } catch {
                restorationMonitor.cancel()
                throw error
            }
            restorationMonitor.cancel()
            try checkCancellation()
            progress = 0.95

            state = .running(.assemblingSilentVideo)
            let assembly = try RestorationVideoAssembly(
                frameURLs: restoredFrames,
                workspaceURL: request.workspaceURL,
                plan: request.plan
            )
            let assemblyMonitor = monitorProgress(base: 0.95, weight: 0.05) {
                await self.assembler.currentProgress()
            }
            let output: URL
            do {
                output = try await assembler.assemble(assembly)
            } catch {
                assemblyMonitor.cancel()
                throw error
            }
            assemblyMonitor.cancel()
            try checkCancellation()
            progress = 1
            state = .completed(silentPartialOutput: output)
        } catch {
            try? removeOwnedWorkspace(request.workspaceURL)
            if cancellationRequested || error is CancellationError {
                state = .cancelled
            } else {
                state = .failed(error.localizedDescription)
            }
        }
        return state
    }

    func cancel() async {
        guard case .running(let stage) = state else { return }
        cancellationRequested = true
        state = .cancelling(stage)
        switch stage {
        case .extractingFrames: await extractor.cancel()
        case .restoringFrames: await sequenceProcessor.cancel()
        case .assemblingSilentVideo: await assembler.cancel()
        }
    }

    private var isActive: Bool {
        switch state {
        case .running, .cancelling: true
        default: false
        }
    }

    private func prepare(_ request: NativeRestorationPreviewRequest) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: request.sourceURL.path) else {
            throw NativeRestorationPreviewError.sourceMissing
        }
        guard !fileManager.fileExists(atPath: request.workspaceURL.path) else {
            throw NativeRestorationPreviewError.workspaceExists
        }
        try fileManager.createDirectory(at: request.workspaceURL, withIntermediateDirectories: true)
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

    private func removeOwnedWorkspace(_ url: URL) throws {
        guard url.lastPathComponent.hasPrefix("SwiftyTranscoder-Restoration-") else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum NativeRestorationPreviewError: LocalizedError, Equatable {
    case sourceMissing
    case workspaceExists
    case invalidWorkspaceName

    var errorDescription: String? {
        switch self {
        case .sourceMissing: "The native restoration preview source is unavailable."
        case .workspaceExists: "The native restoration preview workspace already exists."
        case .invalidWorkspaceName: "The native restoration preview workspace name is not safely recognizable."
        }
    }
}
