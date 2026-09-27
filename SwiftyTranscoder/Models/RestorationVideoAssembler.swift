import Foundation

struct RestorationVideoAssembly: Equatable, Sendable {
    let frameURLs: [URL]
    let inputPatternURL: URL
    let outputURL: URL
    let plan: RestorationPlan

    init(frameURLs: [URL], workspaceURL: URL, plan: RestorationPlan) throws {
        guard (1...240).contains(frameURLs.count) else {
            throw RestorationVideoAssemblerError.invalidFrameCount
        }
        guard let rate = Self.frameRateValue(plan.frameRate), rate > 0 else {
            throw RestorationVideoAssemblerError.invalidFrameRate
        }
        guard plan.outputWidth > 0, plan.outputHeight > 0,
              plan.outputWidth.isMultiple(of: 2), plan.outputHeight.isMultiple(of: 2) else {
            throw RestorationVideoAssemblerError.invalidDimensions
        }
        guard plan.colorRange == "tv",
              !plan.colorSpace.isEmpty,
              !plan.colorTransfer.isEmpty,
              !plan.colorPrimaries.isEmpty else {
            throw RestorationVideoAssemblerError.invalidColorMetadata
        }

        let parsed = try frameURLs.map(Self.parseFrameName)
        guard Set(frameURLs.map { $0.deletingLastPathComponent() }).count == 1,
              Set(parsed.map(\.width)).count == 1 else {
            throw RestorationVideoAssemblerError.invalidFrameSequence
        }
        guard parsed.map(\.number) == Array(1...frameURLs.count) else {
            throw RestorationVideoAssemblerError.invalidFrameSequence
        }

        self.frameURLs = frameURLs
        let width = parsed[0].width
        inputPatternURL = frameURLs[0].deletingLastPathComponent()
            .appendingPathComponent("frame-%0\(width)d.png")
        outputURL = workspaceURL.appendingPathComponent("restored-video.partial.mp4")
        self.plan = plan
    }

    var expectedDuration: Double {
        Double(frameURLs.count) / (Self.frameRateValue(plan.frameRate) ?? 1)
    }

    var ffmpegArguments: [String] {
        [
            "-hide_banner", "-nostdin", "-n", "-loglevel", "error",
            "-framerate", plan.frameRate,
            "-start_number", "1",
            "-i", inputPatternURL.path(percentEncoded: false),
            "-frames:v", String(frameURLs.count),
            "-an", "-sn", "-dn",
            "-vf", "setparams=range=limited:color_primaries=\(plan.colorPrimaries):color_trc=\(plan.colorTransfer):colorspace=\(plan.colorSpace)",
            "-c:v", "hevc_videotoolbox",
            "-allow_sw", "0",
            "-profile:v", "main",
            "-pix_fmt", "yuv420p",
            "-q:v", "60",
            "-tag:v", "hvc1",
            "-color_range", plan.colorRange,
            "-colorspace", plan.colorSpace,
            "-color_trc", plan.colorTransfer,
            "-color_primaries", plan.colorPrimaries,
            "-fps_mode", "cfr",
            "-movflags", "+faststart",
            "-progress", "pipe:1", "-nostats",
            outputURL.path(percentEncoded: false),
        ]
    }

    private static func parseFrameName(_ url: URL) throws -> (number: Int, width: Int) {
        let name = url.lastPathComponent
        guard name.hasPrefix("frame-"), name.hasSuffix(".png") else {
            throw RestorationVideoAssemblerError.invalidFrameSequence
        }
        let digits = name.dropFirst(6).dropLast(4)
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let number = Int(digits) else {
            throw RestorationVideoAssemblerError.invalidFrameSequence
        }
        return (number, digits.count)
    }

    fileprivate static func frameRateValue(_ value: String) -> Double? {
        let parts = value.split(separator: "/", maxSplits: 1).compactMap { Double($0) }
        guard parts.count == 2, parts[1] > 0 else { return nil }
        return parts[0] / parts[1]
    }
}

protocol RestorationVideoAssembling: Sendable {
    func assemble(_ assembly: RestorationVideoAssembly) async throws -> URL
    func cancel() async
    func currentProgress() async -> Double
}

actor RestorationVideoAssembler: RestorationVideoAssembling {
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
        ) else {
            throw RestorationVideoAssemblerError.executableNotFound
        }
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
    }

    func assemble(_ assembly: RestorationVideoAssembly) async throws -> URL {
        guard process == nil else { throw RestorationVideoAssemblerError.alreadyRunning }
        try prepare(assembly)
        cancellationRequested = false
        progress = 0

        let diagnostics = RestorationVideoLockedBuffer()
        let process = Process()
        let progressPipe = Pipe()
        let errorPipe = Pipe()
        let parser = RestorationVideoProgressParser(frameCount: assembly.frameURLs.count) { value in
            Task { await self.setProgress(value) }
        }
        process.executableURL = ffmpegURL
        process.arguments = assembly.ffmpegArguments
        process.standardOutput = progressPipe
        process.standardError = errorPipe
        self.process = process
        progressPipe.fileHandleForReading.readabilityHandler = { parser.consume($0.availableData) }
        errorPipe.fileHandleForReading.readabilityHandler = { diagnostics.append($0.availableData) }

        do {
            try process.run()
        } catch {
            progressPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            throw RestorationVideoAssemblerError.couldNotLaunch(reason: error.localizedDescription)
        }

        let status = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = {
                    progressPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: $0.terminationStatus)
                }
            }
        } onCancel: {
            process.terminate()
        }
        self.process = nil

        guard !cancellationRequested, !Task.isCancelled else { throw CancellationError() }
        guard status == 0 else {
            throw RestorationVideoAssemblerError.encodingFailed(
                exitCode: status,
                reason: diagnostics.text
            )
        }

        let inspection = try probe(assembly.outputURL)
        try validate(inspection, assembly: assembly)
        progress = 1
        return assembly.outputURL
    }

    func cancel() {
        cancellationRequested = true
        process?.terminate()
    }

    func currentProgress() -> Double { progress }

    private func prepare(_ assembly: RestorationVideoAssembly) throws {
        let fileManager = FileManager.default
        guard assembly.frameURLs.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw RestorationVideoAssemblerError.sourceFrameMissing
        }
        guard !fileManager.fileExists(atPath: assembly.outputURL.path) else {
            throw RestorationVideoAssemblerError.outputExists
        }
    }

    private func probe(_ url: URL) throws -> MediaInspection {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = ffprobeURL
        process.arguments = [
            "-v", "error", "-print_format", "json",
            "-show_format", "-show_streams", "-show_chapters", url.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        self.process = process
        do {
            try process.run()
        } catch {
            self.process = nil
            throw RestorationVideoAssemblerError.couldNotLaunch(reason: error.localizedDescription)
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        self.process = nil
        guard !cancellationRequested, !Task.isCancelled else { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            throw RestorationVideoAssemblerError.validationProbeFailed(
                String(data: error, encoding: .utf8) ?? ""
            )
        }
        do {
            return try JSONDecoder().decode(MediaInspection.self, from: output)
        } catch {
            throw RestorationVideoAssemblerError.invalidProbeResponse
        }
    }

    private func validate(_ inspection: MediaInspection, assembly: RestorationVideoAssembly) throws {
        guard inspection.videoStreams.count == 1,
              inspection.audioStreams.isEmpty,
              inspection.subtitleStreams.isEmpty,
              let video = inspection.videoStreams.first else {
            throw RestorationVideoAssemblerError.invalidStreamLayout
        }
        guard video.codecName == "hevc", video.codecTagString == "hvc1",
              video.profile == "Main", video.pixelFormat == "yuv420p" else {
            throw RestorationVideoAssemblerError.invalidVideoFormat
        }
        guard video.width == assembly.plan.outputWidth,
              video.height == assembly.plan.outputHeight else {
            throw RestorationVideoAssemblerError.changedDimensions
        }
        guard let actualFrameRate = video.averageFrameRate,
              Self.frameRatesMatch(actualFrameRate, assembly.plan.frameRate) else {
            throw RestorationVideoAssemblerError.changedFrameRate
        }
        guard video.colorRange == assembly.plan.colorRange,
              video.colorSpace == assembly.plan.colorSpace,
              video.colorTransfer == assembly.plan.colorTransfer,
              video.colorPrimaries == assembly.plan.colorPrimaries else {
            throw RestorationVideoAssemblerError.changedColorMetadata
        }
        guard let durationText = inspection.format.duration,
              let duration = Double(durationText),
              abs(duration - assembly.expectedDuration) <= max(0.05, assembly.expectedDuration * 0.05),
              let sizeText = inspection.format.size,
              let size = Int64(sizeText), size > 0 else {
            throw RestorationVideoAssemblerError.invalidDurationOrSize
        }
    }

    private func setProgress(_ value: Double) { progress = value }

    static func frameRatesMatch(_ actual: String, _ expected: String) -> Bool {
        guard let actualValue = RestorationVideoAssembly.frameRateValue(actual),
              let expectedValue = RestorationVideoAssembly.frameRateValue(expected) else {
            return false
        }
        let permittedDifference = max(actualValue, expectedValue) * 0.0001
        return abs(actualValue - expectedValue) <= permittedDifference
    }
}

enum RestorationVideoAssemblerError: LocalizedError, Equatable {
    case executableNotFound, alreadyRunning, invalidFrameCount, invalidFrameRate
    case invalidDimensions, invalidColorMetadata, invalidFrameSequence
    case sourceFrameMissing, outputExists, couldNotLaunch(reason: String)
    case encodingFailed(exitCode: Int32, reason: String)
    case validationProbeFailed(String), invalidProbeResponse, invalidStreamLayout
    case invalidVideoFormat, changedDimensions, changedFrameRate
    case changedColorMetadata, invalidDurationOrSize

    var errorDescription: String? {
        switch self {
        case .executableNotFound: "The bundled FFmpeg or ffprobe helper is unavailable."
        case .alreadyRunning: "Restored video assembly is already running."
        case .invalidFrameCount: "A restored video segment must contain between 1 and 240 frames."
        case .invalidFrameRate: "The restored video frame rate is invalid."
        case .invalidDimensions: "The restored video dimensions must be positive even numbers."
        case .invalidColorMetadata: "The restored video requires explicit limited-range SDR color metadata."
        case .invalidFrameSequence: "The restored frames are not one complete ordered numeric sequence."
        case .sourceFrameMissing: "A restored source frame is unavailable."
        case .outputExists: "The restored-video partial output already exists and will not be overwritten."
        case .couldNotLaunch(let reason): "Could not start a media helper: \(reason)"
        case .encodingFailed(let exitCode, let reason):
            "Hardware HEVC assembly failed with exit code \(exitCode): \(reason)"
        case .validationProbeFailed(let reason): "The restored video could not be inspected: \(reason)"
        case .invalidProbeResponse: "ffprobe returned unreadable restored-video metadata."
        case .invalidStreamLayout: "The restored video must contain exactly one video stream and no audio or subtitles."
        case .invalidVideoFormat: "The restored video is not HEVC Main, hvc1, and yuv420p."
        case .changedDimensions: "The restored video dimensions do not match the approved plan."
        case .changedFrameRate: "The restored video frame rate does not match the approved plan."
        case .changedColorMetadata: "The restored video color metadata does not match the approved plan."
        case .invalidDurationOrSize: "The restored video duration or file size is invalid."
        }
    }
}

private final class RestorationVideoLockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    var text: String { lock.withLock { String(data: data, encoding: .utf8) ?? "" } }
    func append(_ value: Data) { if !value.isEmpty { lock.withLock { data.append(value) } } }
}

private final class RestorationVideoProgressParser: @unchecked Sendable {
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
            if let frame = Double(line.dropFirst(6)) {
                onProgress(min(max(frame / frameCount, 0), 1))
            }
        }
    }
}
