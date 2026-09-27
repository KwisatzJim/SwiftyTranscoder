import Foundation

struct RestorationAudioMux: Sendable {
    enum Scope: Equatable, Sendable {
        case preview
        case fullDuration
    }

    let sourceURL: URL
    let silentVideoURL: URL
    let outputURL: URL
    let startSeconds: Double
    let durationSeconds: Double
    let sourceAudio: MediaStream
    let audioSettings: CompatibilityAudioSettings
    let gainEnabled: Bool
    let aacStereoEnabled: Bool
    let scope: Scope

    init(
        sourceURL: URL,
        silentVideoURL: URL,
        workspaceURL: URL,
        startSeconds: Double,
        durationSeconds: Double,
        sourceAudio: MediaStream,
        gainEnabled: Bool,
        aacStereoEnabled: Bool
    ) throws {
        guard silentVideoURL.lastPathComponent == "restored-video.partial.mp4",
              silentVideoURL.deletingLastPathComponent().standardizedFileURL.path
                == workspaceURL.standardizedFileURL.path else {
            throw RestorationAudioMuxerError.invalidSilentVideoLocation
        }
        guard startSeconds >= 0, durationSeconds > 0, durationSeconds <= 30 else {
            throw RestorationAudioMuxerError.invalidTimeRange
        }
        guard let audioSettings = CompatibilityAudioSettings(source: sourceAudio) else {
            throw RestorationAudioMuxerError.unsupportedAudioLayout
        }
        self.sourceURL = sourceURL
        self.silentVideoURL = silentVideoURL
        outputURL = workspaceURL.appendingPathComponent("restored-preview.partial.mp4")
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.sourceAudio = sourceAudio
        self.audioSettings = audioSettings
        self.gainEnabled = gainEnabled
        self.aacStereoEnabled = aacStereoEnabled
        scope = .preview
    }

    init(
        fullDurationSourceURL sourceURL: URL,
        silentVideoURL: URL,
        workspaceURL: URL,
        durationSeconds: Double,
        sourceAudio: MediaStream,
        gainEnabled: Bool,
        aacStereoEnabled: Bool
    ) throws {
        guard silentVideoURL.lastPathComponent == "restored-silent.partial.mp4",
              silentVideoURL.deletingLastPathComponent().standardizedFileURL.path
                == workspaceURL.standardizedFileURL.path else {
            throw RestorationAudioMuxerError.invalidSilentVideoLocation
        }
        guard durationSeconds > 0, durationSeconds.isFinite else {
            throw RestorationAudioMuxerError.invalidTimeRange
        }
        guard let audioSettings = CompatibilityAudioSettings(source: sourceAudio) else {
            throw RestorationAudioMuxerError.unsupportedAudioLayout
        }
        self.sourceURL = sourceURL
        self.silentVideoURL = silentVideoURL
        outputURL = workspaceURL.appendingPathComponent("restored-audio.partial.mp4")
        startSeconds = 0
        self.durationSeconds = durationSeconds
        self.sourceAudio = sourceAudio
        self.audioSettings = audioSettings
        self.gainEnabled = gainEnabled
        self.aacStereoEnabled = aacStereoEnabled
        scope = .fullDuration
    }

    var audioLanguage: String {
        sourceAudio.tags?["language"]?.lowercased() ?? "und"
    }

    var ffmpegArguments: [String] {
        var arguments = [
            "-hide_banner", "-nostdin", "-n", "-loglevel", "error",
            "-i", silentVideoURL.path(percentEncoded: false),
            "-ss", String(format: "%.6f", startSeconds),
            "-t", String(format: "%.6f", durationSeconds),
            "-i", sourceURL.path(percentEncoded: false),
            "-map", "0:v:0", "-map", "1:\(sourceAudio.index)",
        ]
        if aacStereoEnabled { arguments += ["-map", "1:\(sourceAudio.index)"] }
        arguments += ["-c:v", "copy", "-sn", "-dn"]

        let gainFilter = "volume=6dB,alimiter=limit=0.630957:level=false:latency=true"
        if gainEnabled { arguments += ["-filter:a:0", gainFilter] }
        arguments += [
            "-c:a:0", "ac3", "-b:a:0", audioSettings.bitRate,
            "-ar:a:0", "48000", "-ac:a:0", String(audioSettings.channels),
            "-metadata:s:a:0", "language=\(audioLanguage)",
            "-metadata:s:a:0", gainEnabled
                ? "title=Primary Audio AC-3 \(audioSettings.description) Compatibility +6 dB Limited"
                : "title=Primary Audio AC-3 \(audioSettings.description) Compatibility",
            "-disposition:a:0", "default",
        ]
        if aacStereoEnabled {
            let filter = gainEnabled
                ? "aformat=channel_layouts=stereo,\(gainFilter)"
                : "aformat=channel_layouts=stereo"
            arguments += [
                "-filter:a:1", filter,
                "-c:a:1", "aac", "-b:a:1", "192000",
                "-ar:a:1", "48000", "-ac:a:1", "2",
                "-metadata:s:a:1", "language=\(audioLanguage)",
                "-metadata:s:a:1", gainEnabled
                    ? "title=Secondary Audio AAC stereo at 192 kb/s Compatibility +6 dB Limited"
                    : "title=Secondary Audio AAC stereo at 192 kb/s Compatibility",
                "-disposition:a:1", "0",
            ]
        }
        arguments += [
            "-map_metadata", "1", "-map_chapters", "-1",
            "-shortest", "-avoid_negative_ts", "make_zero",
            "-movflags", "+faststart", "-progress", "pipe:1", "-nostats",
            outputURL.path(percentEncoded: false),
        ]
        return arguments
    }
}

protocol RestorationAudioMuxing: Sendable {
    func mux(_ request: RestorationAudioMux) async throws -> URL
    func cancel() async
    func currentProgress() async -> Double
}

actor RestorationAudioMuxer: RestorationAudioMuxing {
    private let ffmpegURL: URL
    private let ffprobeURL: URL
    private var process: Process?
    private var cancellationRequested = false
    private(set) var progress = 0.0

    init(ffmpegURL: URL, ffprobeURL: URL) {
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
    }

    init(bundleURL: URL = Bundle.main.bundleURL, fileManager: FileManager = .default) throws {
        guard let ffmpegURL = MediaToolLocator.executableURL(
            for: .ffmpeg, bundleURL: bundleURL, fileManager: fileManager
        ), let ffprobeURL = MediaToolLocator.executableURL(
            for: .ffprobe, bundleURL: bundleURL, fileManager: fileManager
        ) else { throw RestorationAudioMuxerError.executableNotFound }
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
    }

    func mux(_ request: RestorationAudioMux) async throws -> URL {
        guard process == nil else { throw RestorationAudioMuxerError.alreadyRunning }
        try prepare(request)
        cancellationRequested = false
        progress = 0

        let diagnostics = RestorationAudioLockedBuffer()
        let progressParser = RestorationAudioProgressParser(duration: request.durationSeconds) { value in
            Task { await self.setProgress(value) }
        }
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = ffmpegURL
        process.arguments = request.ffmpegArguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        self.process = process
        outputPipe.fileHandleForReading.readabilityHandler = { progressParser.consume($0.availableData) }
        errorPipe.fileHandleForReading.readabilityHandler = { diagnostics.append($0.availableData) }
        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            throw RestorationAudioMuxerError.couldNotLaunch(reason: error.localizedDescription)
        }
        let status = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: $0.terminationStatus)
                }
            }
        } onCancel: { process.terminate() }
        self.process = nil
        guard !cancellationRequested, !Task.isCancelled else { throw CancellationError() }
        guard status == 0 else {
            throw RestorationAudioMuxerError.muxFailed(exitCode: status, reason: diagnostics.text)
        }
        let inspection = try probe(request.outputURL)
        try validate(inspection, request: request)
        progress = 1
        return request.outputURL
    }

    func cancel() { cancellationRequested = true; process?.terminate() }
    func currentProgress() -> Double { progress }

    private func prepare(_ request: RestorationAudioMux) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: request.sourceURL.path),
              manager.fileExists(atPath: request.silentVideoURL.path) else {
            throw RestorationAudioMuxerError.inputMissing
        }
        guard !manager.fileExists(atPath: request.outputURL.path) else {
            throw RestorationAudioMuxerError.outputExists
        }
    }

    private func probe(_ url: URL) throws -> MediaInspection {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = ffprobeURL
        process.arguments = ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", "-show_chapters", url.path]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        self.process = process
        do { try process.run() } catch {
            self.process = nil
            throw RestorationAudioMuxerError.couldNotLaunch(reason: error.localizedDescription)
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        self.process = nil
        guard !cancellationRequested, !Task.isCancelled else { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            throw RestorationAudioMuxerError.validationProbeFailed(String(data: error, encoding: .utf8) ?? "")
        }
        guard let inspection = try? JSONDecoder().decode(MediaInspection.self, from: output) else {
            throw RestorationAudioMuxerError.invalidProbeResponse
        }
        return inspection
    }

    private func validate(_ inspection: MediaInspection, request: RestorationAudioMux) throws {
        let expectedAudioCount = request.aacStereoEnabled ? 2 : 1
        guard inspection.videoStreams.count == 1,
              inspection.audioStreams.count == expectedAudioCount,
              inspection.subtitleStreams.isEmpty,
              inspection.chapters.isEmpty else {
            throw RestorationAudioMuxerError.invalidStreamLayout
        }
        guard let video = inspection.videoStreams.first,
              video.codecName == "hevc", video.codecTagString == "hvc1" else {
            throw RestorationAudioMuxerError.invalidVideoFormat
        }
        let primary = inspection.audioStreams[0]
        guard primary.codecName == "ac3", primary.sampleRate == "48000",
              primary.channels == request.audioSettings.channels,
              request.audioSettings.acceptedLayouts.contains(primary.channelLayout ?? ""),
              primary.bitRate == request.audioSettings.bitRate,
              primary.tags?["language"]?.lowercased() == request.audioLanguage,
              primary.disposition?.isDefault == 1 else {
            throw RestorationAudioMuxerError.invalidPrimaryAudio
        }
        if request.aacStereoEnabled {
            let secondary = inspection.audioStreams[1]
            guard secondary.codecName == "aac", secondary.sampleRate == "48000",
                  secondary.channels == 2, secondary.channelLayout == "stereo",
                  secondary.tags?["language"]?.lowercased() == request.audioLanguage,
                  secondary.disposition?.isDefault == 0 else {
                throw RestorationAudioMuxerError.invalidSecondaryAudio
            }
        }
        guard let durationText = inspection.format.duration,
              let duration = Double(durationText),
              abs(duration - request.durationSeconds) <= durationTolerance(for: request),
              let sizeText = inspection.format.size, let size = Int64(sizeText), size > 0 else {
            throw RestorationAudioMuxerError.invalidDurationOrSize
        }
    }

    private func setProgress(_ value: Double) { progress = value }

    private func durationTolerance(for request: RestorationAudioMux) -> Double {
        switch request.scope {
        case .preview: max(0.1, request.durationSeconds * 0.05)
        case .fullDuration: max(0.1, request.durationSeconds * 0.001)
        }
    }
}

enum RestorationAudioMuxerError: LocalizedError, Equatable {
    case executableNotFound, alreadyRunning, invalidSilentVideoLocation, invalidTimeRange
    case unsupportedAudioLayout, inputMissing, outputExists, couldNotLaunch(reason: String)
    case muxFailed(exitCode: Int32, reason: String), validationProbeFailed(String)
    case invalidProbeResponse, invalidStreamLayout, invalidVideoFormat
    case invalidPrimaryAudio, invalidSecondaryAudio, invalidDurationOrSize

    var errorDescription: String? {
        switch self {
        case .executableNotFound: "The bundled FFmpeg or ffprobe helper is unavailable."
        case .alreadyRunning: "Restoration audio muxing is already running."
        case .invalidSilentVideoLocation: "The silent restored video is not in the approved restoration workspace."
        case .invalidTimeRange: "The restoration audio time range is invalid."
        case .unsupportedAudioLayout: "The selected audio layout is not supported by the compatibility output."
        case .inputMissing: "A restoration audio mux input is unavailable."
        case .outputExists: "The restored-audio partial output already exists and will not be overwritten."
        case .couldNotLaunch(let reason): "Could not start a media helper: \(reason)"
        case .muxFailed(let exitCode, let reason): "Restoration audio muxing failed with exit code \(exitCode): \(reason)"
        case .validationProbeFailed(let reason): "The restored audio output could not be inspected: \(reason)"
        case .invalidProbeResponse: "ffprobe returned unreadable restored-audio metadata."
        case .invalidStreamLayout: "The restored audio output does not have the approved video-and-audio layout."
        case .invalidVideoFormat: "The restored audio output did not preserve HEVC with the hvc1 compatibility tag."
        case .invalidPrimaryAudio: "The restored primary AC-3 track is invalid."
        case .invalidSecondaryAudio: "The restored secondary AAC stereo track is invalid."
        case .invalidDurationOrSize: "The restored audio output duration or file size is invalid."
        }
    }
}

private final class RestorationAudioLockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    var text: String { lock.withLock { String(data: data, encoding: .utf8) ?? "" } }
    func append(_ value: Data) { if !value.isEmpty { lock.withLock { data.append(value) } } }
}

private final class RestorationAudioProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private let durationMicroseconds: Double
    private let onProgress: @Sendable (Double) -> Void

    init(duration: Double, onProgress: @escaping @Sendable (Double) -> Void) {
        durationMicroseconds = duration * 1_000_000
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
        for line in lines where line.hasPrefix("out_time_us=") {
            if let time = Double(line.dropFirst(12)) {
                onProgress(min(max(time / durationMicroseconds, 0), 1))
            }
        }
    }
}
