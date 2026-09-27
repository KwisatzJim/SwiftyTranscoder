import Foundation

struct RestorationChunk: Equatable, Sendable {
    let index: Int
    let startFrame: Int64
    let frameCount: Int
    let startSeconds: Double
    let workspaceURL: URL
}

struct RestorationChunkPlan: Equatable, Sendable {
    static let defaultFrameLimit = 120

    let chunks: [RestorationChunk]
    let frameRate: String
    let frameLimit: Int

    init(
        totalFrameCount: Int64,
        frameRate: String,
        workspaceURL: URL,
        frameLimit: Int = defaultFrameLimit
    ) throws {
        guard totalFrameCount > 0, totalFrameCount <= Int64(Int.max) else {
            throw RestorationChunkError.invalidFrameCount
        }
        guard (1...240).contains(frameLimit) else {
            throw RestorationChunkError.invalidFrameLimit
        }
        guard workspaceURL.lastPathComponent.hasPrefix("SwiftyTranscoder-Restoration-") else {
            throw RestorationChunkError.invalidWorkspaceName
        }
        guard let rate = Self.frameRateValue(frameRate) else {
            throw RestorationChunkError.invalidFrameRate
        }

        var planned: [RestorationChunk] = []
        var startFrame: Int64 = 0
        var index = 1
        while startFrame < totalFrameCount {
            let remaining = totalFrameCount - startFrame
            let count = Int(min(Int64(frameLimit), remaining))
            planned.append(RestorationChunk(
                index: index,
                startFrame: startFrame,
                frameCount: count,
                startSeconds: Double(startFrame) / rate,
                workspaceURL: workspaceURL.appendingPathComponent(
                    String(format: "chunk-%06d", index),
                    isDirectory: true
                )
            ))
            startFrame += Int64(count)
            index += 1
        }

        chunks = planned
        self.frameRate = frameRate
        self.frameLimit = frameLimit
    }

    private static func frameRateValue(_ value: String) -> Double? {
        let parts = value.split(separator: "/", maxSplits: 1).compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return parts[0] / parts[1]
    }
}

protocol RestorationChunkProcessing: Sendable {
    func process(_ chunk: RestorationChunk) async throws -> URL
    func cancel() async
}

actor RestorationChunkCoordinator {
    private let processor: any RestorationChunkProcessing
    private var cancellationRequested = false
    private var hasStarted = false
    private(set) var completedChunkCount = 0
    private(set) var progress = 0.0

    init(processor: any RestorationChunkProcessing) {
        self.processor = processor
    }

    func run(_ plan: RestorationChunkPlan) async throws -> [URL] {
        guard !hasStarted else { throw RestorationChunkError.alreadyRun }
        hasStarted = true
        cancellationRequested = false
        progress = 0
        var segments: [URL] = []

        do {
            for chunk in plan.chunks {
                try checkCancellation()
                let segment = try await processor.process(chunk)
                guard !segment.path.hasPrefix(chunk.workspaceURL.path + "/") else {
                    throw RestorationChunkError.segmentInsideDisposableWorkspace
                }
                try checkCancellation()
                try removeChunkWorkspace(chunk.workspaceURL)
                segments.append(segment)
                completedChunkCount += 1
                progress = Double(completedChunkCount) / Double(plan.chunks.count)
            }
            return segments
        } catch {
            if completedChunkCount < plan.chunks.count {
                try? removeChunkWorkspace(plan.chunks[completedChunkCount].workspaceURL)
            }
            throw error
        }
    }

    func cancel() async {
        cancellationRequested = true
        await processor.cancel()
    }

    private func checkCancellation() throws {
        if cancellationRequested || Task.isCancelled { throw CancellationError() }
    }

    private func removeChunkWorkspace(_ url: URL) throws {
        guard url.lastPathComponent.hasPrefix("chunk-") else {
            throw RestorationChunkError.invalidChunkWorkspace
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum RestorationChunkError: LocalizedError, Equatable {
    case invalidFrameCount
    case invalidFrameLimit
    case invalidFrameRate
    case invalidWorkspaceName
    case invalidChunkWorkspace
    case alreadyRun
    case segmentInsideDisposableWorkspace

    var errorDescription: String? {
        switch self {
        case .invalidFrameCount: "A restoration chunk plan requires a positive, representable frame count."
        case .invalidFrameLimit: "A restoration chunk must contain between 1 and 240 frames."
        case .invalidFrameRate: "A restoration chunk plan requires a valid frame rate."
        case .invalidWorkspaceName: "The restoration workspace is not safely recognizable."
        case .invalidChunkWorkspace: "The restoration chunk workspace is not safely recognizable."
        case .alreadyRun: "This restoration chunk coordinator has already run."
        case .segmentInsideDisposableWorkspace: "A restored segment cannot be stored inside its disposable frame workspace."
        }
    }
}
