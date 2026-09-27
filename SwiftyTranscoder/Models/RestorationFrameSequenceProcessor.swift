import Foundation

struct RestorationFrameSequence: Equatable, Sendable {
    let sourceURLs: [URL]
    let outputDirectoryURL: URL
    let expectedWidth: Int
    let expectedHeight: Int

    init(
        sourceURLs: [URL],
        workspaceURL: URL,
        expectedWidth: Int,
        expectedHeight: Int
    ) throws {
        guard (1...240).contains(sourceURLs.count) else {
            throw RestorationFrameSequenceError.invalidFrameCount
        }
        guard expectedWidth > 0, expectedHeight > 0 else {
            throw RestorationFrameSequenceError.invalidDimensions
        }
        guard sourceURLs.allSatisfy({ $0.pathExtension.lowercased() == "png" }) else {
            throw RestorationFrameSequenceError.sourceMustBePNG
        }
        let names = sourceURLs.map(\.lastPathComponent)
        guard Set(names).count == names.count else {
            throw RestorationFrameSequenceError.duplicateFrameName
        }
        guard names == names.sorted() else {
            throw RestorationFrameSequenceError.framesOutOfOrder
        }

        self.sourceURLs = sourceURLs
        outputDirectoryURL = workspaceURL.appendingPathComponent(
            "restored-frames",
            isDirectory: true
        )
        self.expectedWidth = expectedWidth
        self.expectedHeight = expectedHeight
    }

    var outputURLs: [URL] {
        sourceURLs.map {
            outputDirectoryURL.appendingPathComponent($0.lastPathComponent)
        }
    }
}

actor RestorationFrameSequenceProcessor {
    private let frameProcessor: any RestorationFrameProcessing
    private var cancellationRequested = false
    private(set) var progress = 0.0
    private(set) var completedFrameCount = 0

    init(frameProcessor: any RestorationFrameProcessing) {
        self.frameProcessor = frameProcessor
    }

    func process(_ sequence: RestorationFrameSequence) async throws -> [URL] {
        cancellationRequested = false
        progress = 0
        completedFrameCount = 0
        try prepare(sequence)

        do {
            for (sourceURL, outputURL) in zip(sequence.sourceURLs, sequence.outputURLs) {
                try checkCancellation()
                _ = try await frameProcessor.process(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    expectedWidth: sequence.expectedWidth,
                    expectedHeight: sequence.expectedHeight
                )
                try checkCancellation()
                completedFrameCount += 1
                progress = Double(completedFrameCount) / Double(sequence.sourceURLs.count)
            }
            try validate(sequence)
            return sequence.outputURLs
        } catch {
            try? removeOwnedOutputDirectory(sequence.outputDirectoryURL)
            throw error
        }
    }

    func cancel() async {
        cancellationRequested = true
        await frameProcessor.cancel()
    }

    private func prepare(_ sequence: RestorationFrameSequence) throws {
        let fileManager = FileManager.default
        for sourceURL in sequence.sourceURLs {
            guard fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
                throw RestorationFrameSequenceError.sourceMissing(file: sourceURL.lastPathComponent)
            }
        }
        guard !fileManager.fileExists(
            atPath: sequence.outputDirectoryURL.path(percentEncoded: false)
        ) else {
            throw RestorationFrameSequenceError.outputDirectoryExists
        }
        try fileManager.createDirectory(
            at: sequence.outputDirectoryURL,
            withIntermediateDirectories: false
        )
    }

    private func validate(_ sequence: RestorationFrameSequence) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: sequence.outputDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard contents.map(\.lastPathComponent) == sequence.outputURLs.map(\.lastPathComponent) else {
            throw RestorationFrameSequenceError.unexpectedOutputSequence
        }
        for outputURL in contents {
            let values = try outputURL.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) > 0 else {
                throw RestorationFrameSequenceError.emptyOutput(file: outputURL.lastPathComponent)
            }
        }
    }

    private func removeOwnedOutputDirectory(_ url: URL) throws {
        guard url.lastPathComponent == "restored-frames" else { return }
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func checkCancellation() throws {
        if cancellationRequested || Task.isCancelled { throw CancellationError() }
    }
}

enum RestorationFrameSequenceError: LocalizedError, Equatable {
    case invalidFrameCount
    case invalidDimensions
    case sourceMustBePNG
    case duplicateFrameName
    case framesOutOfOrder
    case sourceMissing(file: String)
    case outputDirectoryExists
    case unexpectedOutputSequence
    case emptyOutput(file: String)

    var errorDescription: String? {
        switch self {
        case .invalidFrameCount:
            "A native restoration sequence must contain between 1 and 240 frames."
        case .invalidDimensions:
            "The expected restoration frame dimensions are invalid."
        case .sourceMustBePNG:
            "Every restoration source frame must be a PNG."
        case .duplicateFrameName:
            "Restoration source frame names must be unique."
        case .framesOutOfOrder:
            "Restoration source frames must be supplied in filename order."
        case .sourceMissing(let file):
            "The restoration source frame \(file) is unavailable."
        case .outputDirectoryExists:
            "The restored-frames folder already exists and will not be overwritten."
        case .unexpectedOutputSequence:
            "The restored frame sequence is incomplete or out of order."
        case .emptyOutput(let file):
            "The restored frame \(file) is empty."
        }
    }
}
