import Foundation

@MainActor
final class VideoConversionController: ObservableObject {
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress = 0.0
    @Published private(set) var estimatedRemainingSeconds: TimeInterval?

    private var process: Process?
    private var activeCommand: VideoConversionCommand?
    private var expectedVideo: MediaStream?
    private var expectedAudio: MediaStream?
    private var expectedVideoMode: VideoConversionMode?
    private var colorSelection: ColorSelection?
    private var expectedDurationSeconds: Double?
    private var conversionStartedAt: Date?
    private var cancellationRequested = false
    private let diagnostics = LockedTextBuffer()

    var isActive: Bool {
        switch phase {
        case .running, .cancelling: true
        default: false
        }
    }

    var completedOutputURL: URL? {
        guard case .completed(let output) = phase else { return nil }
        return output
    }

    var managedPartialOutputURL: URL? {
        guard isActive else { return nil }
        return activeCommand?.partialOutputURL
    }

    func start(
        command: VideoConversionCommand,
        expectedVideo: MediaStream,
        expectedAudio: MediaStream,
        videoMode: VideoConversionMode,
        colorSelection: ColorSelection,
        durationSeconds: Double
    ) throws {
        guard !isActive else { throw VideoConversionControllerError.alreadyRunning }

        let process = Process()
        let progressPipe = Pipe()
        let errorPipe = Pipe()
        let parser = FFmpegProgressParser(durationSeconds: durationSeconds) { [weak self] value in
            Task { @MainActor in
                self?.updateProgress(value)
            }
        }

        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = progressPipe
        process.standardError = errorPipe

        diagnostics.reset()
        cancellationRequested = false
        activeCommand = command
        self.expectedVideo = expectedVideo
        self.expectedAudio = expectedAudio
        self.expectedVideoMode = videoMode
        self.colorSelection = colorSelection
        expectedDurationSeconds = durationSeconds
        self.process = process
        progress = 0
        estimatedRemainingSeconds = nil
        conversionStartedAt = Date()
        phase = .running

        progressPipe.fileHandleForReading.readabilityHandler = { handle in
            parser.consume(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [diagnostics] handle in
            diagnostics.append(handle.availableData)
        }

        process.terminationHandler = { [weak self] finishedProcess in
            progressPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                await self?.finish(exitCode: finishedProcess.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            progressPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            activeCommand = nil
            self.expectedVideo = nil
            self.expectedAudio = nil
            self.expectedVideoMode = nil
            self.colorSelection = nil
            expectedDurationSeconds = nil
            conversionStartedAt = nil
            estimatedRemainingSeconds = nil
            phase = .failed("Could not start FFmpeg: \(error.localizedDescription)", partialOutput: nil)
        }
    }

    func cancel() {
        guard isActive, let process else { return }
        cancellationRequested = true
        phase = .cancelling
        process.terminate()
    }

    func reset() {
        guard !isActive else { return }
        phase = .idle
        progress = 0
        estimatedRemainingSeconds = nil
        conversionStartedAt = nil
    }

    func movePartialOutputToTrash(_ detectedPartialOutputURL: URL? = nil) throws {
        guard !isActive, let partialOutputURL = detectedPartialOutputURL ?? partialOutputURL else {
            throw VideoConversionControllerError.noPartialOutput
        }
        guard partialOutputURL.lastPathComponent.hasSuffix(".partial.mp4") else {
            throw VideoConversionControllerError.unsafePartialOutputName
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
        case .cancelled(let partialOutput), .failed(_, let partialOutput):
            partialOutput
        default:
            nil
        }
    }

    private func finish(exitCode: Int32) async {
        guard let command = activeCommand else { return }
        let expectedVideo = self.expectedVideo
        let expectedAudio = self.expectedAudio
        let expectedVideoMode = self.expectedVideoMode
        let colorSelection = self.colorSelection
        let expectedDurationSeconds = self.expectedDurationSeconds
        process = nil
        activeCommand = nil
        self.expectedVideo = nil
        self.expectedAudio = nil
        self.expectedVideoMode = nil
        self.colorSelection = nil
        self.expectedDurationSeconds = nil
        conversionStartedAt = nil
        estimatedRemainingSeconds = nil

        if cancellationRequested {
            phase = .cancelled(partialOutput: existingPartialURL(command.partialOutputURL))
            return
        }

        guard exitCode == 0 else {
            phase = .failed(
                failureMessage(exitCode: exitCode),
                partialOutput: existingPartialURL(command.partialOutputURL)
            )
            return
        }

        guard let expectedVideo, let expectedAudio, let expectedVideoMode, let colorSelection, let expectedDurationSeconds else {
            phase = .failed("The expected source-media details were unavailable.", partialOutput: command.partialOutputURL)
            return
        }

        do {
            let outputInspection = try await MediaProbe().inspect(command.partialOutputURL)
            try validate(
                outputInspection,
                expectedVideo: expectedVideo,
                expectedAudio: expectedAudio,
                videoMode: expectedVideoMode,
                colorSelection: colorSelection,
                expectedDurationSeconds: expectedDurationSeconds
            )

            guard !FileManager.default.fileExists(
                atPath: command.finalOutputURL.path(percentEncoded: false)
            ) else {
                throw VideoConversionControllerError.destinationAppeared(
                    file: command.finalOutputURL.lastPathComponent
                )
            }

            try FileManager.default.moveItem(
                at: command.partialOutputURL,
                to: command.finalOutputURL
            )
            progress = 1
            phase = .completed(output: command.finalOutputURL)
        } catch {
            phase = .failed(
                "Output validation failed: \(error.localizedDescription)",
                partialOutput: existingPartialURL(command.partialOutputURL)
            )
        }
    }

    private func updateProgress(_ value: Double) {
        progress = value

        guard let conversionStartedAt,
              value >= 0.01,
              value < 1 else {
            estimatedRemainingSeconds = nil
            return
        }

        let elapsed = Date().timeIntervalSince(conversionStartedAt)
        guard elapsed >= 2 else {
            estimatedRemainingSeconds = nil
            return
        }

        let newEstimate = elapsed * (1 - value) / value
        if let currentEstimate = estimatedRemainingSeconds {
            estimatedRemainingSeconds = currentEstimate * 0.75 + newEstimate * 0.25
        } else {
            estimatedRemainingSeconds = newEstimate
        }
    }

    private func validate(
        _ inspection: MediaInspection,
        expectedVideo: MediaStream,
        expectedAudio: MediaStream,
        videoMode: VideoConversionMode,
        colorSelection: ColorSelection,
        expectedDurationSeconds: Double
    ) throws {
        guard inspection.videoStreams.count == 1,
              let outputVideo = inspection.videoStreams.first else {
            throw VideoConversionControllerError.invalidVideoStreamCount(
                count: inspection.videoStreams.count
            )
        }
        let expectedCodec = videoMode == .copyVideo ? expectedVideo.codecName : "hevc"
        let expectedTag = videoMode == .copyVideo ? expectedVideo.codecTagString : "hvc1"
        guard outputVideo.codecName == expectedCodec,
              outputVideo.codecTagString == expectedTag else {
            throw VideoConversionControllerError.invalidCodec(
                codec: outputVideo.codecName ?? "unknown",
                tag: outputVideo.codecTagString ?? "unknown"
            )
        }
        let expectedProfile = videoMode == .copyVideo
            ? expectedVideo.profile ?? "unknown"
            : expectedVideo.pixelFormat == "yuv420p10le" ? "Main 10" : "Main"
        guard outputVideo.profile == expectedProfile,
              outputVideo.pixelFormat == expectedVideo.pixelFormat else {
            throw VideoConversionControllerError.changedVideoFormat(
                expectedProfile: expectedProfile,
                actualProfile: outputVideo.profile ?? "unknown",
                expectedPixelFormat: expectedVideo.pixelFormat ?? "unknown",
                actualPixelFormat: outputVideo.pixelFormat ?? "unknown"
            )
        }
        let expectedColor = colorSelection == .confirmUntaggedAsBT709
            ? ("bt709", "bt709", "bt709")
            : (expectedVideo.colorTransfer, expectedVideo.colorSpace, expectedVideo.colorPrimaries)
        guard outputVideo.colorTransfer == expectedColor.0,
              outputVideo.colorSpace == expectedColor.1,
              outputVideo.colorPrimaries == expectedColor.2 else {
            throw VideoConversionControllerError.changedColorMetadata
        }
        guard outputVideo.width == expectedVideo.width,
              outputVideo.height == expectedVideo.height else {
            throw VideoConversionControllerError.changedDimensions
        }
        guard outputVideo.averageFrameRate == expectedVideo.averageFrameRate else {
            throw VideoConversionControllerError.changedFrameRate(
                expected: expectedVideo.averageFrameRate ?? "unknown",
                actual: outputVideo.averageFrameRate ?? "unknown"
            )
        }
        guard inspection.audioStreams.count == 1,
              let outputAudio = inspection.audioStreams.first else {
            throw VideoConversionControllerError.invalidAudioStreamCount(
                count: inspection.audioStreams.count
            )
        }
        guard let audioSettings = CompatibilityAudioSettings(source: expectedAudio) else {
            throw VideoConversionControllerError.changedAudioChannels
        }
        guard outputAudio.codecName == "ac3",
              outputAudio.codecTagString == "ac-3",
              outputAudio.channels == audioSettings.channels,
              outputAudio.channelLayout.map(audioSettings.acceptedLayouts.contains) == true,
              outputAudio.sampleRate == "48000",
              outputAudio.bitRate == audioSettings.bitRate else {
            throw VideoConversionControllerError.invalidAudio(
                expected: audioSettings.description,
                codec: outputAudio.codecName ?? "unknown",
                layout: outputAudio.channelLayout ?? "unknown",
                sampleRate: outputAudio.sampleRate ?? "unknown",
                bitRate: outputAudio.bitRate ?? "unknown"
            )
        }
        guard inspection.subtitleStreams.isEmpty else {
            throw VideoConversionControllerError.unexpectedSubtitles
        }
        guard let outputDuration = inspection.format.duration.flatMap(Double.init),
              abs(outputDuration - expectedDurationSeconds) <= 0.1 else {
            throw VideoConversionControllerError.changedDuration(
                expected: expectedDurationSeconds,
                actual: inspection.format.duration.flatMap(Double.init)
            )
        }
    }

    private func existingPartialURL(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    private func failureMessage(exitCode: Int32) -> String {
        let detail = diagnostics.text
            .split(separator: "\n")
            .suffix(8)
            .joined(separator: "\n")
        return detail.isEmpty
            ? "FFmpeg failed with exit code \(exitCode)."
            : "FFmpeg failed with exit code \(exitCode):\n\(detail)"
    }

    enum Phase: Equatable {
        case idle
        case running
        case cancelling
        case completed(output: URL)
        case cancelled(partialOutput: URL?)
        case failed(String, partialOutput: URL?)
    }
}

private final class LockedTextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var text: String {
        lock.withLock { String(data: data, encoding: .utf8) ?? "" }
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.withLock { data.append(newData) }
    }

    func reset() {
        lock.withLock { data.removeAll(keepingCapacity: true) }
    }
}

private final class FFmpegProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private let durationMicroseconds: Double
    private let onProgress: @Sendable (Double) -> Void

    init(durationSeconds: Double, onProgress: @escaping @Sendable (Double) -> Void) {
        durationMicroseconds = max(durationSeconds * 1_000_000, 1)
        self.onProgress = onProgress
    }

    func consume(_ data: Data) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
        let completeLines: [String] = lock.withLock {
            pending += chunk
            let pieces = pending.split(separator: "\n", omittingEmptySubsequences: false)
            pending = String(pieces.last ?? "")
            return pieces.dropLast().map(String.init)
        }

        for line in completeLines {
            if line == "progress=end" {
                onProgress(1)
            } else if line.hasPrefix("out_time_us="),
                      let value = Double(line.dropFirst("out_time_us=".count)) {
                onProgress(min(max(value / durationMicroseconds, 0), 1))
            }
        }
    }
}

enum VideoConversionControllerError: LocalizedError {
    case alreadyRunning
    case noPartialOutput
    case unsafePartialOutputName
    case destinationAppeared(file: String)
    case invalidVideoStreamCount(count: Int)
    case invalidCodec(codec: String, tag: String)
    case changedVideoFormat(
        expectedProfile: String,
        actualProfile: String,
        expectedPixelFormat: String,
        actualPixelFormat: String
    )
    case changedColorMetadata
    case invalidAudioStreamCount(count: Int)
    case invalidAudio(expected: String, codec: String, layout: String, sampleRate: String, bitRate: String)
    case changedAudioChannels
    case changedDuration(expected: Double, actual: Double?)
    case changedDimensions
    case changedFrameRate(expected: String, actual: String)
    case unexpectedSubtitles

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "A conversion is already running."
        case .noPartialOutput:
            "There is no incomplete output to move to the Trash."
        case .unsafePartialOutputName:
            "The incomplete output name was not recognized, so it was left untouched."
        case .destinationAppeared(let file):
            "\(file) appeared while conversion was running and was not overwritten."
        case .invalidVideoStreamCount(let count):
            "Expected one output video stream but found \(count)."
        case .invalidCodec(let codec, let tag):
            "Expected HEVC with the hvc1 tag but found \(codec) with \(tag)."
        case .changedVideoFormat(let expectedProfile, let actualProfile, let expectedPixelFormat, let actualPixelFormat):
            "Expected \(expectedProfile) \(expectedPixelFormat), but found \(actualProfile) \(actualPixelFormat)."
        case .changedColorMetadata:
            "The output color metadata does not match the approved source metadata."
        case .invalidAudioStreamCount(let count):
            "Expected one output audio stream but found \(count)."
        case .invalidAudio(let expected, let codec, let layout, let sampleRate, let bitRate):
            "Expected AC-3 \(expected) at 48000 Hz but found \(codec), \(layout), \(sampleRate) Hz, \(bitRate) b/s."
        case .changedAudioChannels:
            "The approved source uses an unsupported audio channel layout."
        case .changedDuration(let expected, let actual):
            if let actual {
                "The output duration \(String(actual)) does not match the expected \(String(expected)) seconds."
            } else {
                "The output duration is unknown and could not be compared with the expected \(String(expected)) seconds."
            }
        case .changedDimensions:
            "The output dimensions do not match the approved source dimensions."
        case .changedFrameRate(let expected, let actual):
            "The output frame rate is \(actual), but the approved source rate is \(expected)."
        case .unexpectedSubtitles:
            "The output unexpectedly contains subtitle streams."
        }
    }
}
