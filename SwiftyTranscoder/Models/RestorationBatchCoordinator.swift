import Foundation

enum RestorationBatchItemState: Equatable, Sendable {
    case queued
    case preparing
    case running(FullVideoRestorationStage)
    case completed(URL)
    case failed(String, partialOutput: URL?)
    case cancelled(partialOutput: URL?)
    case notRun
}

struct RestorationBatchSnapshot: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case running
        case cancelling
        case finished
        case cancelled
        case rejected(String)
    }

    var phase: Phase = .idle
    var items: [RestorationBatchItemState] = []
    var activeIndex: Int?
    var progress = 0.0
    var activeProgress = 0.0
    var completionSummaries: [Int: RestorationCompletionSummary] = [:]
    var elapsedSeconds: Double?
}

protocol RestorationBatchPreflighting: Sendable {
    func check(_ request: FullVideoRestorationRequest) throws
}

struct RestorationBatchPreflight: RestorationBatchPreflighting {
    var availableBytes: @Sendable (URL) throws -> Int64 = { directory in
        guard let capacity = try directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage else {
            throw RestorationBatchError.capacityUnavailable
        }
        return capacity
    }

    func check(_ request: FullVideoRestorationRequest) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: request.sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { throw FullVideoRestorationError.sourceMissing }
        guard request.checkpointMode == .resume || !manager.fileExists(atPath: request.workspaceURL.path) else {
            throw FullVideoRestorationError.workspaceExists
        }
        guard !manager.fileExists(atPath: request.finalOutputURL.path) else {
            throw FullVideoRestorationError.outputExists
        }
        guard !manager.fileExists(atPath: request.partialOutputURL.path) else {
            throw FullVideoRestorationError.partialOutputExists
        }
        let destination = request.finalOutputURL.deletingLastPathComponent()
        let temporary = request.workspaceURL.deletingLastPathComponent()
        for directory in [temporary, destination] {
            guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { throw FullVideoRestorationError.destinationFolderMissing }
        }
        guard let bytes = try request.sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              let storage = RestorationStorageRequirement.estimate(
                sourceBytes: Int64(bytes), durationSeconds: request.durationSeconds,
                frameRate: request.plan.frameRate, exactFrameCount: request.totalFrameCount,
                plan: request.plan
              ),
              let destinationBytes = DestinationStorageRequirement.requiredBytes(forSourceBytes: Int64(bytes)) else {
            throw RestorationBatchError.invalidStorageEstimate
        }
        guard try availableBytes(temporary) >= storage.temporaryBytes,
              try availableBytes(destination) >= destinationBytes else {
            throw RestorationBatchError.insufficientCapacity
        }
        // The existing promotion service checks actual output size again before
        // staging; these source-based estimates do not guarantee output size.
    }
}

actor RestorationBatchCoordinator {
    private let now: @Sendable () -> Double
    private let builder: any FullVideoRestorationPipelineBuilding
    private let preflight: any RestorationBatchPreflighting
    private var activePipeline: (any FullVideoRestorationPipelineRunning)?
    private var preparationTask: Task<any FullVideoRestorationPipelineRunning, Error>?
    private var cancellationRequested = false
    private var isActive = false
    private(set) var snapshot = RestorationBatchSnapshot()

    init(
        builder: any FullVideoRestorationPipelineBuilding = BundledFullVideoRestorationPipelineBuilder(),
        preflight: any RestorationBatchPreflighting = RestorationBatchPreflight(),
        now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.now = now
        self.builder = builder
        self.preflight = preflight
    }

    func run(_ requests: [FullVideoRestorationRequest]) async -> RestorationBatchSnapshot {
        guard !isActive else {
            return RestorationBatchSnapshot(phase: .rejected("A restoration batch is already running."))
        }
        do {
            try Self.checkPaths(requests)
        } catch {
            snapshot = RestorationBatchSnapshot(
                phase: .rejected(error.localizedDescription),
                items: requests.map { _ in .notRun }
            )
            return snapshot
        }
        let batchStartedAt = now()
        isActive = true
        cancellationRequested = false
        snapshot = RestorationBatchSnapshot(phase: .running, items: requests.map { _ in .queued })
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "SwiftyTranscoder is restoring a batch"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
            activePipeline = nil
            preparationTask = nil
            snapshot.activeIndex = nil
            isActive = false
        }
        let totalFrames = requests.reduce(0.0) { $0 + Double($1.totalFrameCount) }
        var handledFrames = 0.0
        for (index, request) in requests.enumerated() {
            if cancellationRequested || Task.isCancelled { break }
            let jobStartedAt = now()
            snapshot.activeIndex = index
            snapshot.activeProgress = 0
            snapshot.items[index] = .preparing
            do {
                let builder = self.builder
                let preflight = self.preflight
                let preparation = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    try preflight.check(request)
                    try Task.checkCancellation()
                    let pipeline = try builder.makePipeline(for: request)
                    try Task.checkCancellation()
                    return pipeline
                }
                preparationTask = preparation
                let pipeline = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: {
                    preparation.cancel()
                }
                preparationTask = nil
                guard !cancellationRequested, !Task.isCancelled else {
                    snapshot.items[index] = .cancelled(partialOutput: nil)
                    break
                }
                activePipeline = pipeline
                // Publish a stage before awaiting run so the UI can cancel
                // preparation independently of the child pipeline's startup.
                snapshot.items[index] = .running(.processingChunks)
                let base = handledFrames / totalFrames
                let weight = Double(request.totalFrameCount) / totalFrames
                let monitor = Task {
                    while !Task.isCancelled {
                        let progress = await pipeline.currentProgress()
                        let state = await pipeline.currentState()
                        guard !Task.isCancelled else { return }
                        if self.cancellationRequested { await pipeline.cancel() }
                        self.update(index: index, state: state, progress: base + weight * progress)
                        if progress.isFinite { self.snapshot.activeProgress = min(max(progress, 0), 1) }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
                let result = await withTaskCancellationHandler {
                    await pipeline.run(request)
                } onCancel: {
                    Task { await self.cancel() }
                }
                monitor.cancel()
                await monitor.value
                activePipeline = nil
                switch result {
                case .completed(let output):
                    snapshot.items[index] = .completed(output)
                    snapshot.completionSummaries[index] = RestorationCompletionSummary(
                        method: request.plan.method, frameCount: request.totalFrameCount,
                        elapsedSeconds: now() - jobStartedAt
                    )
                case .failed(let message, let partial): snapshot.items[index] = .failed(message, partialOutput: partial)
                case .cancelled(let partial):
                    snapshot.items[index] = .cancelled(partialOutput: partial)
                    cancellationRequested = true
                case .idle, .running, .cancelling:
                    snapshot.items[index] = .failed("The restoration job returned without finishing.", partialOutput: nil)
                }
            } catch {
                preparationTask = nil
                if cancellationRequested || Task.isCancelled || error is CancellationError {
                    snapshot.items[index] = .cancelled(partialOutput: nil)
                    cancellationRequested = true
                } else {
                    snapshot.items[index] = .failed(error.localizedDescription, partialOutput: nil)
                }
            }
            if cancellationRequested || Task.isCancelled { break }
            handledFrames += Double(request.totalFrameCount)
            snapshot.progress = handledFrames / totalFrames
        }
        if cancellationRequested || Task.isCancelled {
            snapshot.phase = .cancelled
            for index in snapshot.items.indices where snapshot.items[index] == .queued {
                snapshot.items[index] = .notRun
            }
        } else {
            snapshot.phase = .finished
            snapshot.progress = 1
        }
        snapshot.activeIndex = nil
        let elapsed = now() - batchStartedAt
        snapshot.elapsedSeconds = elapsed.isFinite && elapsed >= 0 ? elapsed : nil
        return snapshot
    }

    func cancel() async {
        guard isActive else { return }
        cancellationRequested = true
        snapshot.phase = .cancelling
        preparationTask?.cancel()
        await activePipeline?.cancel()
    }

    private func update(index: Int, state: FullVideoRestorationState, progress: Double) {
        if progress.isFinite { snapshot.progress = max(snapshot.progress, min(max(progress, 0), 1)) }
        guard !cancellationRequested else { return }
        if case .running(let stage) = state { snapshot.items[index] = .running(stage) }
    }

    private static func checkPaths(_ requests: [FullVideoRestorationRequest]) throws {
        guard !requests.isEmpty else { throw RestorationBatchError.emptyBatch }
        func key(_ url: URL) -> String { CanonicalOutputPath.key(for: url.resolvingSymlinksInPath()) }
        let sources = Set(requests.map { key($0.sourceURL) })
        var outputs = Set<String>()
        var workspaces: [String] = []
        for request in requests {
            guard request.finalOutputURL.pathExtension.lowercased() == "mp4" else {
                throw RestorationBatchError.invalidOutputExtension
            }
            for url in [request.finalOutputURL, request.partialOutputURL] {
                let path = key(url)
                guard !sources.contains(path), outputs.insert(path).inserted else {
                    throw RestorationBatchError.pathConflict
                }
            }
            let workspace = key(request.workspaceURL)
            guard !workspaces.contains(where: {
                $0 == workspace || $0.hasPrefix(workspace + "/") || workspace.hasPrefix($0 + "/")
            }) else { throw RestorationBatchError.pathConflict }
            workspaces.append(workspace)
        }
        for workspace in workspaces {
            guard !sources.union(outputs).contains(where: {
                $0 == workspace || $0.hasPrefix(workspace + "/") || workspace.hasPrefix($0 + "/")
            }) else { throw RestorationBatchError.pathConflict }
        }
    }
}

enum RestorationBatchError: LocalizedError {
    case emptyBatch, pathConflict, invalidOutputExtension
    case capacityUnavailable, invalidStorageEstimate, insufficientCapacity

    var errorDescription: String? {
        switch self {
        case .emptyBatch: "Select at least one reviewed restoration job."
        case .pathConflict: "Restoration jobs have conflicting source, output, partial, or workspace paths."
        case .invalidOutputExtension: "Every restoration destination must use the .mp4 extension."
        case .capacityUnavailable: "Available restoration storage could not be checked."
        case .invalidStorageEstimate: "Restoration storage requirements could not be estimated."
        case .insufficientCapacity: "Temporary or destination storage is insufficient for the next restoration job."
        }
    }
}
