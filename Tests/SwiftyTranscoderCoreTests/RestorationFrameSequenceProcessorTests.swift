import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationFrameSequenceProcessorTests {
    @Test func processesFramesSequentiallyAndPreservesNames() async throws {
        let fixture = try SequenceFixture(frameCount: 3)
        defer { fixture.remove() }
        let worker = RecordingFrameProcessor()
        let processor = RestorationFrameSequenceProcessor(frameProcessor: worker)

        let outputs = try await processor.process(fixture.sequence)

        #expect(outputs.map(\.lastPathComponent) == fixture.sourceURLs.map(\.lastPathComponent))
        #expect(await worker.processedNames == fixture.sourceURLs.map(\.lastPathComponent))
        #expect(await processor.completedFrameCount == 3)
        #expect(await processor.progress == 1)
        #expect(outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func rejectsOutOfOrderInputBeforeCreatingOutput() throws {
        let fixture = try SequenceFixture(frameCount: 2)
        defer { fixture.remove() }

        #expect(throws: RestorationFrameSequenceError.framesOutOfOrder) {
            try RestorationFrameSequence(
                sourceURLs: Array(fixture.sourceURLs.reversed()),
                workspaceURL: fixture.workspaceURL,
                expectedWidth: 624,
                expectedHeight: 352
            )
        }
    }

    @Test func refusesExistingOutputDirectory() async throws {
        let fixture = try SequenceFixture(frameCount: 1)
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.sequence.outputDirectoryURL,
            withIntermediateDirectories: false
        )
        let processor = RestorationFrameSequenceProcessor(frameProcessor: RecordingFrameProcessor())

        await #expect(throws: RestorationFrameSequenceError.outputDirectoryExists) {
            try await processor.process(fixture.sequence)
        }
    }

    @Test func cancellationRemovesOnlyTheOwnedDerivedSequence() async throws {
        let fixture = try SequenceFixture(frameCount: 3)
        defer { fixture.remove() }
        let worker = CancellableFrameProcessor()
        let processor = RestorationFrameSequenceProcessor(frameProcessor: worker)
        let task = Task { try await processor.process(fixture.sequence) }

        await worker.waitUntilFirstFrameStarts()
        await processor.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: fixture.sequence.outputDirectoryURL.path))
        #expect(fixture.sourceURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func restoresRepresentativeSequenceWhenResearchModelIsAvailable() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let modelURL = root.appendingPathComponent(
            ".build/restoration-evaluation/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage"
        )
        let sourceDirectoryURL = root.appendingPathComponent(
            ".build/restoration-evaluation/comparisons/Alphas - s01e11 - Original Sin/source-frames"
        )
        let sourceURLs = (1...4).map {
            sourceDirectoryURL.appendingPathComponent(String(format: "frame-%02d.png", $0))
        }
        guard FileManager.default.fileExists(atPath: modelURL.path),
              sourceURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }

        let workspaceURL = URL(
            fileURLWithPath: "/private/tmp/SwiftyTranscoder-Milestone71-native-sequence"
        )
        try? FileManager.default.removeItem(at: workspaceURL)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let sequence = try RestorationFrameSequence(
            sourceURLs: sourceURLs,
            workspaceURL: workspaceURL,
            expectedWidth: 624,
            expectedHeight: 352
        )
        let tiles = try CoreMLRestorationTileProcessor(modelURL: modelURL)
        let frames = RestorationFrameProcessor(tileProcessor: tiles)
        let processor = RestorationFrameSequenceProcessor(frameProcessor: frames)

        let outputs = try await processor.process(sequence)

        #expect(outputs.count == 4)
        #expect(await processor.completedFrameCount == 4)
        #expect(await processor.progress == 1)
        #expect(outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}

private struct SequenceFixture {
    let rootURL: URL
    let workspaceURL: URL
    let sourceURLs: [URL]
    let sequence: RestorationFrameSequence

    init(frameCount: Int) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftyTranscoder-FrameSequenceTests-\(UUID().uuidString)")
        workspaceURL = rootURL.appendingPathComponent("workspace")
        let sourceDirectoryURL = workspaceURL.appendingPathComponent("source-frames")
        try FileManager.default.createDirectory(
            at: sourceDirectoryURL,
            withIntermediateDirectories: true
        )
        sourceURLs = try (1...frameCount).map { index in
            let url = sourceDirectoryURL.appendingPathComponent(
                String(format: "frame-%08d.png", index)
            )
            try Data("source \(index)".utf8).write(to: url)
            return url
        }
        sequence = try RestorationFrameSequence(
            sourceURLs: sourceURLs,
            workspaceURL: workspaceURL,
            expectedWidth: 624,
            expectedHeight: 352
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private actor RecordingFrameProcessor: RestorationFrameProcessing {
    private(set) var processedNames: [String] = []

    func process(
        sourceURL: URL,
        outputURL: URL,
        expectedWidth: Int,
        expectedHeight: Int
    ) async throws -> URL {
        processedNames.append(sourceURL.lastPathComponent)
        try Data("restored".utf8).write(to: outputURL, options: .withoutOverwriting)
        return outputURL
    }

    func cancel() async {}
}

private actor CancellableFrameProcessor: RestorationFrameProcessing {
    private var continuation: CheckedContinuation<URL, any Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var started = false

    func process(
        sourceURL: URL,
        outputURL: URL,
        expectedWidth: Int,
        expectedHeight: Int
    ) async throws -> URL {
        started = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() async {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func waitUntilFirstFrameStarts() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}
