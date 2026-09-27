import Foundation

struct RestorationFrameExtraction: Equatable, Sendable {
    let sourceURL: URL
    let outputDirectoryURL: URL
    let startSeconds: Double
    let frameCount: Int

    init(
        sourceURL: URL,
        workspaceURL: URL,
        startSeconds: Double,
        frameCount: Int
    ) throws {
        guard startSeconds >= 0, startSeconds.isFinite else {
            throw RestorationFrameExtractorError.invalidStartTime
        }
        guard (1...240).contains(frameCount) else {
            throw RestorationFrameExtractorError.invalidFrameCount
        }

        self.sourceURL = sourceURL
        outputDirectoryURL = workspaceURL.appendingPathComponent(
            "source-frames",
            isDirectory: true
        )
        self.startSeconds = startSeconds
        self.frameCount = frameCount
    }

    var outputPatternURL: URL {
        outputDirectoryURL.appendingPathComponent("frame-%08d.png")
    }

    var ffmpegArguments: [String] {
        [
            "-hide_banner",
            "-nostdin",
            "-n",
            "-loglevel", "error",
            "-ss", String(format: "%.3f", startSeconds),
            "-i", sourceURL.path(percentEncoded: false),
            "-map", "0:v:0",
            "-frames:v", String(frameCount),
            "-fps_mode", "passthrough",
            "-pix_fmt", "rgb24",
            "-progress", "pipe:1",
            "-nostats",
            outputPatternURL.path(percentEncoded: false),
        ]
    }
}

protocol RestorationFrameExtracting: Sendable {
    func extract(_ extraction: RestorationFrameExtraction) async throws -> [URL]
    func cancel() async
    func currentProgress() async -> Double
}

actor RestorationFrameExtractor: RestorationFrameExtracting {
    private let executableURL: URL
    private var process: Process?
    private var cancellationRequested = false
    private(set) var progress = 0.0

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) throws {
        guard let executableURL = MediaToolLocator.executableURL(
            for: .ffmpeg,
            bundleURL: bundleURL,
            fileManager: fileManager
        ) else {
            throw RestorationFrameExtractorError.executableNotFound
        }
        self.executableURL = executableURL
    }

    func extract(_ extraction: RestorationFrameExtraction) async throws -> [URL] {
        guard process == nil else {
            throw RestorationFrameExtractorError.alreadyRunning
        }

        try prepare(extraction)

        let process = Process()
        let progressPipe = Pipe()
        let errorPipe = Pipe()
        let parser = RestorationFrameProgressParser(frameCount: extraction.frameCount) { value in
            Task { await self.setProgress(value) }
        }
        let diagnostics = RestorationLockedTextBuffer()

        process.executableURL = executableURL
        process.arguments = extraction.ffmpegArguments
        process.standardOutput = progressPipe
        process.standardError = errorPipe
        self.process = process
        cancellationRequested = false
        progress = 0

        progressPipe.fileHandleForReading.readabilityHandler = { handle in
            parser.consume(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            diagnostics.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            progressPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            throw RestorationFrameExtractorError.couldNotLaunch(
                reason: error.localizedDescription
            )
        }

        let status = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { finishedProcess in
                    progressPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: finishedProcess.terminationStatus)
                }
            }
        } onCancel: {
            process.terminate()
        }
        self.process = nil

        guard !cancellationRequested, !Task.isCancelled else { throw CancellationError() }
        guard status == 0 else {
            throw RestorationFrameExtractorError.extractionFailed(
                exitCode: status,
                reason: diagnostics.text
            )
        }

        let frames = try validate(extraction)
        progress = 1
        return frames
    }

    func cancel() {
        cancellationRequested = true
        process?.terminate()
    }

    func currentProgress() -> Double { progress }

    private func prepare(_ extraction: RestorationFrameExtraction) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(
            atPath: extraction.sourceURL.path(percentEncoded: false)
        ) else {
            throw RestorationFrameExtractorError.sourceMissing
        }
        guard !fileManager.fileExists(
            atPath: extraction.outputDirectoryURL.path(percentEncoded: false)
        ) else {
            throw RestorationFrameExtractorError.outputDirectoryExists
        }
        try fileManager.createDirectory(
            at: extraction.outputDirectoryURL,
            withIntermediateDirectories: false
        )
    }

    private func validate(_ extraction: RestorationFrameExtraction) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: extraction.outputDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let frames = contents
            .filter { $0.lastPathComponent.hasPrefix("frame-") && $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard frames.count == extraction.frameCount else {
            throw RestorationFrameExtractorError.unexpectedFrameCount(
                expected: extraction.frameCount,
                actual: frames.count
            )
        }
        for frame in frames {
            let values = try frame.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) > 0 else {
                throw RestorationFrameExtractorError.emptyFrame(file: frame.lastPathComponent)
            }
        }
        return frames
    }

    private func setProgress(_ value: Double) {
        progress = value
    }
}

enum RestorationFrameExtractorError: LocalizedError, Equatable {
    case executableNotFound
    case alreadyRunning
    case invalidStartTime
    case invalidFrameCount
    case sourceMissing
    case outputDirectoryExists
    case couldNotLaunch(reason: String)
    case extractionFailed(exitCode: Int32, reason: String)
    case unexpectedFrameCount(expected: Int, actual: Int)
    case emptyFrame(file: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "The bundled FFmpeg helper is unavailable."
        case .alreadyRunning:
            return "Frame extraction is already running."
        case .invalidStartTime:
            return "The frame-extraction start time must be zero or later."
        case .invalidFrameCount:
            return "A restoration extraction must contain between 1 and 240 frames."
        case .sourceMissing:
            return "The frame-extraction source is no longer available."
        case .outputDirectoryExists:
            return "The source-frames folder already exists and will not be overwritten."
        case .couldNotLaunch(let reason):
            return "Could not start FFmpeg frame extraction: \(reason)"
        case .extractionFailed(let exitCode, let reason):
            let detail = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "FFmpeg frame extraction failed with exit code \(exitCode)."
                : "FFmpeg frame extraction failed with exit code \(exitCode): \(detail)"
        case .unexpectedFrameCount(let expected, let actual):
            return "Expected \(expected) restoration frames but found \(actual)."
        case .emptyFrame(let file):
            return "The extracted frame \(file) is empty."
        }
    }
}

private final class RestorationLockedTextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var text: String {
        lock.withLock { String(data: data, encoding: .utf8) ?? "" }
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.withLock { data.append(newData) }
    }
}

private final class RestorationFrameProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private let frameCount: Double
    private let onProgress: @Sendable (Double) -> Void

    init(frameCount: Int, onProgress: @escaping @Sendable (Double) -> Void) {
        self.frameCount = Double(frameCount)
        self.onProgress = onProgress
    }

    func consume(_ data: Data) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
        let lines: [String] = lock.withLock {
            pending += chunk
            let pieces = pending.split(separator: "\n", omittingEmptySubsequences: false)
            pending = String(pieces.last ?? "")
            return pieces.dropLast().map(String.init)
        }

        for line in lines where line.hasPrefix("frame=") {
            if let frame = Double(line.dropFirst("frame=".count)) {
                onProgress(min(max(frame / frameCount, 0), 1))
            }
        }
    }
}
