import Foundation

struct RestorationJob: Equatable, Sendable {
    let sourceURL: URL
    let finalOutputURL: URL
    let workspaceURL: URL
    let plan: RestorationPlan

    var partialOutputURL: URL {
        finalOutputURL
            .deletingPathExtension()
            .appendingPathExtension("partial")
            .appendingPathExtension("mp4")
    }
}

enum RestorationStage: String, CaseIterable, Equatable, Sendable {
    case extractingFrames
    case restoringFrames
    case assemblingPartialOutput
    case validatingPartialOutput
}

enum RestorationJobState: Equatable, Sendable {
    case idle
    case running(RestorationStage)
    case cancelling(RestorationStage)
    case completed(output: URL)
    case cancelled(partialOutput: URL?)
    case failed(String, partialOutput: URL?)
}

protocol RestorationStageExecuting: Sendable {
    func perform(_ stage: RestorationStage, for job: RestorationJob) async throws
    func cancel() async
}

actor RestorationJobRunner {
    private let executor: any RestorationStageExecuting
    private(set) var state: RestorationJobState = .idle
    private var cancellationRequested = false

    init(executor: any RestorationStageExecuting) {
        self.executor = executor
    }

    func run(_ job: RestorationJob) async throws -> RestorationJobState {
        guard !isActive else { throw RestorationJobError.alreadyRunning }

        cancellationRequested = false

        do {
            try prepare(job)

            for stage in RestorationStage.allCases {
                try checkCancellation()
                state = .running(stage)
                try await executor.perform(stage, for: job)
            }

            try checkCancellation()
            try promoteValidatedOutput(for: job)
            state = .completed(output: job.finalOutputURL)
        } catch {
            let partialOutput = existingPartialOutput(for: job)
            if cancellationRequested || error is CancellationError {
                state = .cancelled(partialOutput: partialOutput)
            } else {
                state = .failed(error.localizedDescription, partialOutput: partialOutput)
            }
        }

        return state
    }

    func cancel() async {
        guard case .running(let stage) = state else { return }
        cancellationRequested = true
        state = .cancelling(stage)
        await executor.cancel()
    }

    func reset() {
        guard !isActive else { return }
        state = .idle
        cancellationRequested = false
    }

    private var isActive: Bool {
        switch state {
        case .running, .cancelling: true
        default: false
        }
    }

    private func prepare(_ job: RestorationJob) throws {
        let fileManager = FileManager.default
        let sourcePath = job.sourceURL.path(percentEncoded: false)
        let finalPath = job.finalOutputURL.path(percentEncoded: false)
        let partialPath = job.partialOutputURL.path(percentEncoded: false)
        let workspacePath = job.workspaceURL.path(percentEncoded: false)

        guard fileManager.fileExists(atPath: sourcePath) else {
            throw RestorationJobError.sourceMissing(file: job.sourceURL.lastPathComponent)
        }
        guard job.finalOutputURL.pathExtension.lowercased() == "mp4" else {
            throw RestorationJobError.outputMustBeMP4
        }
        guard sourcePath != finalPath, sourcePath != partialPath else {
            throw RestorationJobError.outputMatchesSource
        }
        guard !fileManager.fileExists(atPath: finalPath) else {
            throw RestorationJobError.outputExists(file: job.finalOutputURL.lastPathComponent)
        }
        guard !fileManager.fileExists(atPath: partialPath) else {
            throw RestorationJobError.partialOutputExists(file: job.partialOutputURL.lastPathComponent)
        }
        guard !fileManager.fileExists(atPath: workspacePath) else {
            throw RestorationJobError.workspaceExists(folder: job.workspaceURL.lastPathComponent)
        }

        try fileManager.createDirectory(
            at: job.workspaceURL,
            withIntermediateDirectories: true
        )
    }

    private func promoteValidatedOutput(for job: RestorationJob) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(
            atPath: job.partialOutputURL.path(percentEncoded: false)
        ) else {
            throw RestorationJobError.partialOutputMissing
        }
        guard !fileManager.fileExists(
            atPath: job.finalOutputURL.path(percentEncoded: false)
        ) else {
            throw RestorationJobError.outputAppeared(file: job.finalOutputURL.lastPathComponent)
        }

        try fileManager.moveItem(at: job.partialOutputURL, to: job.finalOutputURL)
    }

    private func checkCancellation() throws {
        if cancellationRequested || Task.isCancelled {
            throw CancellationError()
        }
    }

    private func existingPartialOutput(for job: RestorationJob) -> URL? {
        FileManager.default.fileExists(
            atPath: job.partialOutputURL.path(percentEncoded: false)
        ) ? job.partialOutputURL : nil
    }
}

enum RestorationJobError: LocalizedError, Equatable {
    case alreadyRunning
    case sourceMissing(file: String)
    case outputMustBeMP4
    case outputMatchesSource
    case outputExists(file: String)
    case partialOutputExists(file: String)
    case workspaceExists(folder: String)
    case partialOutputMissing
    case outputAppeared(file: String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "A restoration job is already running."
        case .sourceMissing(let file):
            "The restoration source \(file) is no longer available."
        case .outputMustBeMP4:
            "The restoration output must use the .mp4 extension."
        case .outputMatchesSource:
            "The restoration output cannot replace its source file."
        case .outputExists(let file):
            "The destination \(file) already exists and will not be overwritten."
        case .partialOutputExists(let file):
            "The incomplete output \(file) already exists. Move or remove it before retrying."
        case .workspaceExists(let folder):
            "The restoration workspace \(folder) already exists and will not be reused."
        case .partialOutputMissing:
            "Restoration validation finished without producing the expected partial MP4."
        case .outputAppeared(let file):
            "The destination \(file) appeared while restoration was running and was not overwritten."
        }
    }
}
