import Foundation

enum FullRestorationChunkStage: Equatable, Sendable {
    case idle
    case extracting
    case restoring
    case encoding
    case placingSegment
}

actor FullRestorationChunkProcessor: RestorationChunkProcessing {
    private let sourceURL: URL
    private let rootWorkspaceURL: URL
    private let segmentDirectoryURL: URL
    private let plan: RestorationPlan
    private let subtitleStreamOrdinal: Int?
    private let extractor: any RestorationFrameExtracting
    private let sequenceProcessor: any RestorationFrameSequenceProcessing
    private let assembler: any RestorationVideoAssembling
    private var cancellationRequested = false
    private(set) var stage: FullRestorationChunkStage = .idle
    private(set) var progress = 0.0

    init(
        sourceURL: URL,
        workspaceURL: URL,
        plan: RestorationPlan,
        subtitleStreamOrdinal: Int?,
        extractor: any RestorationFrameExtracting,
        sequenceProcessor: any RestorationFrameSequenceProcessing,
        assembler: any RestorationVideoAssembling
    ) throws {
        guard workspaceURL.lastPathComponent.hasPrefix("SwiftyTranscoder-Restoration-") else {
            throw FullRestorationChunkProcessorError.invalidWorkspace
        }
        if let subtitleStreamOrdinal, subtitleStreamOrdinal < 0 {
            throw FullRestorationChunkProcessorError.invalidSubtitleStream
        }
        self.sourceURL = sourceURL
        rootWorkspaceURL = workspaceURL
        segmentDirectoryURL = workspaceURL.appendingPathComponent("segments", isDirectory: true)
        self.plan = plan
        self.subtitleStreamOrdinal = subtitleStreamOrdinal
        self.extractor = extractor
        self.sequenceProcessor = sequenceProcessor
        self.assembler = assembler
    }

    func process(_ chunk: RestorationChunk) async throws -> URL {
        guard stage == .idle else {
            throw FullRestorationChunkProcessorError.alreadyRunning
        }
        cancellationRequested = false
        progress = 0

        do {
            try prepare(chunk)

            stage = .extracting
            let extraction = try RestorationFrameExtraction(
                sourceURL: sourceURL,
                workspaceURL: chunk.workspaceURL,
                startSeconds: chunk.startSeconds,
                frameCount: chunk.frameCount
            )
            let extractionMonitor = monitorProgress(base: 0, weight: 0.08) {
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
            progress = 0.08

            stage = .restoring
            let sequence = try RestorationFrameSequence(
                sourceURLs: sourceFrames,
                workspaceURL: chunk.workspaceURL,
                expectedWidth: plan.sourceWidth,
                expectedHeight: plan.sourceHeight
            )
            let restorationMonitor = monitorProgress(base: 0.08, weight: 0.87) {
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

            stage = .encoding
            let subtitleBurn = try subtitleStreamOrdinal.map {
                try RestorationSubtitleBurn(
                    sourceURL: sourceURL,
                    subtitleStreamOrdinal: $0,
                    chunkStartSeconds: chunk.startSeconds
                )
            }
            let assembly = try RestorationVideoAssembly(
                frameURLs: restoredFrames,
                workspaceURL: chunk.workspaceURL,
                plan: plan,
                subtitleBurn: subtitleBurn
            )
            let assemblyMonitor = monitorProgress(base: 0.95, weight: 0.04) {
                await self.assembler.currentProgress()
            }
            let temporarySegment: URL
            do {
                temporarySegment = try await assembler.assemble(assembly)
            } catch {
                assemblyMonitor.cancel()
                throw error
            }
            assemblyMonitor.cancel()
            try checkCancellation()
            progress = 0.99

            stage = .placingSegment
            let durableSegment = segmentDirectoryURL.appendingPathComponent(
                String(format: "segment-%06d.partial.mp4", chunk.index)
            )
            guard !FileManager.default.fileExists(atPath: durableSegment.path) else {
                throw FullRestorationChunkProcessorError.segmentExists(
                    file: durableSegment.lastPathComponent
                )
            }
            try FileManager.default.moveItem(at: temporarySegment, to: durableSegment)
            progress = 1
            stage = .idle
            return durableSegment
        } catch {
            stage = .idle
            throw error
        }
    }

    func cancel() async {
        cancellationRequested = true
        switch stage {
        case .extracting: await extractor.cancel()
        case .restoring: await sequenceProcessor.cancel()
        case .encoding: await assembler.cancel()
        case .idle, .placingSegment: break
        }
    }

    func currentProgress() -> Double { progress }

    private func prepare(_ chunk: RestorationChunk) throws {
        let chunkParentPath = chunk.workspaceURL.deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath().path
        let approvedRootPath = rootWorkspaceURL.standardizedFileURL
            .resolvingSymlinksInPath().path
        guard chunkParentPath == approvedRootPath,
              chunk.workspaceURL.lastPathComponent
                == String(format: "chunk-%06d", chunk.index) else {
            throw FullRestorationChunkProcessorError.unapprovedChunk
        }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw FullRestorationChunkProcessorError.sourceMissing
        }
        guard !fileManager.fileExists(atPath: chunk.workspaceURL.path) else {
            throw FullRestorationChunkProcessorError.chunkWorkspaceExists
        }
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: segmentDirectoryURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw FullRestorationChunkProcessorError.invalidSegmentDirectory
            }
        } else {
            try fileManager.createDirectory(
                at: segmentDirectoryURL,
                withIntermediateDirectories: false
            )
        }
        try fileManager.createDirectory(
            at: chunk.workspaceURL,
            withIntermediateDirectories: false
        )
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
}

enum FullRestorationChunkProcessorError: LocalizedError, Equatable {
    case invalidWorkspace
    case invalidSubtitleStream
    case alreadyRunning
    case unapprovedChunk
    case sourceMissing
    case chunkWorkspaceExists
    case invalidSegmentDirectory
    case segmentExists(file: String)

    var errorDescription: String? {
        switch self {
        case .invalidWorkspace: "The full restoration workspace is not safely recognizable."
        case .invalidSubtitleStream: "The full restoration subtitle stream is invalid."
        case .alreadyRunning: "A restoration chunk is already being processed."
        case .unapprovedChunk: "The restoration chunk is outside the approved workspace sequence."
        case .sourceMissing: "The restoration source is no longer available."
        case .chunkWorkspaceExists: "The restoration chunk workspace already exists and will not be reused."
        case .invalidSegmentDirectory: "The durable restoration segment location is invalid."
        case .segmentExists(let file): "The restoration segment \(file) already exists and will not be overwritten."
        }
    }
}
