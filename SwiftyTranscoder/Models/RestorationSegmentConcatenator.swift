import Foundation

protocol RestorationSegmentConcatenating: Sendable {
    func concatenate(_ request: RestorationSegmentConcatenation) async throws -> URL
    func cancel() async
    func currentProgress() async -> Double
}

struct RestorationSegmentConcatenation: Equatable, Sendable {
    let segmentURLs: [URL]
    let manifestURL: URL
    let outputURL: URL
    let plan: RestorationPlan
    let totalFrameCount: Int64

    init(
        segmentURLs: [URL],
        workspaceURL: URL,
        plan: RestorationPlan,
        totalFrameCount: Int64
    ) throws {
        guard !segmentURLs.isEmpty, totalFrameCount > 0 else {
            throw RestorationSegmentConcatenatorError.invalidSegmentCount
        }
        guard RestorationVideoAssembly.frameRateValue(plan.frameRate) != nil else {
            throw RestorationSegmentConcatenatorError.invalidFrameRate
        }
        guard plan.outputWidth > 0, plan.outputHeight > 0,
              plan.outputWidth.isMultiple(of: 2), plan.outputHeight.isMultiple(of: 2) else {
            throw RestorationSegmentConcatenatorError.invalidDimensions
        }
        guard plan.colorRange == "tv", !plan.colorSpace.isEmpty,
              !plan.colorTransfer.isEmpty, !plan.colorPrimaries.isEmpty else {
            throw RestorationSegmentConcatenatorError.invalidColorMetadata
        }

        let parsed = try segmentURLs.map(Self.parseSegmentName)
        guard Set(segmentURLs.map { $0.deletingLastPathComponent() }).count == 1,
              parsed == Array(1...segmentURLs.count) else {
            throw RestorationSegmentConcatenatorError.invalidSegmentSequence
        }

        self.segmentURLs = segmentURLs
        manifestURL = workspaceURL.appendingPathComponent("restoration-segments.ffconcat")
        outputURL = workspaceURL.appendingPathComponent("restored-silent.partial.mp4")
        self.plan = plan
        self.totalFrameCount = totalFrameCount
    }

    var expectedDuration: Double {
        Double(totalFrameCount) / (RestorationVideoAssembly.frameRateValue(plan.frameRate) ?? 1)
    }

    var manifestContents: String {
        "ffconcat version 1.0\n" + segmentURLs.map {
            "file '\(Self.escapeForConcat($0.path(percentEncoded: false)))'\n"
        }.joined()
    }

    var ffmpegArguments: [String] {
        [
            "-hide_banner", "-nostdin", "-n", "-loglevel", "error",
            "-f", "concat", "-safe", "0",
            "-i", manifestURL.path(percentEncoded: false),
            "-map", "0:v:0", "-an", "-sn", "-dn",
            "-c:v", "copy", "-tag:v", "hvc1",
            "-movflags", "+faststart",
            "-progress", "pipe:1", "-nostats",
            outputURL.path(percentEncoded: false),
        ]
    }

    private static func parseSegmentName(_ url: URL) throws -> Int {
        let name = url.lastPathComponent
        guard name.hasPrefix("segment-"), name.hasSuffix(".partial.mp4") else {
            throw RestorationSegmentConcatenatorError.invalidSegmentSequence
        }
        let digits = name.dropFirst(8).dropLast(12)
        guard digits.count == 6, digits.allSatisfy(\.isNumber), let number = Int(digits) else {
            throw RestorationSegmentConcatenatorError.invalidSegmentSequence
        }
        return number
    }

    private static func escapeForConcat(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }
}

actor RestorationSegmentConcatenator {
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
            throw RestorationSegmentConcatenatorError.executableNotFound
        }
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
    }

    func concatenate(_ request: RestorationSegmentConcatenation) async throws -> URL {
        guard process == nil else { throw RestorationSegmentConcatenatorError.alreadyRunning }
        try prepare(request)
        cancellationRequested = false
        progress = 0
        try request.manifestContents.write(
            to: request.manifestURL,
            atomically: true,
            encoding: .utf8
        )

        defer { try? FileManager.default.removeItem(at: request.manifestURL) }
        let diagnostics = RestorationSegmentLockedBuffer()
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = ffmpegURL
        process.arguments = request.ffmpegArguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        self.process = process
        errorPipe.fileHandleForReading.readabilityHandler = { diagnostics.append($0.availableData) }

        do {
            try process.run()
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            throw RestorationSegmentConcatenatorError.couldNotLaunch(reason: error.localizedDescription)
        }

        let status = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = {
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
            throw RestorationSegmentConcatenatorError.concatenationFailed(
                exitCode: status,
                reason: diagnostics.text
            )
        }

        let inspection = try probe(request.outputURL)
        try validate(inspection, request: request)
        progress = 1
        return request.outputURL
    }

    func cancel() {
        cancellationRequested = true
        process?.terminate()
    }

    func currentProgress() -> Double { progress }

    private func prepare(_ request: RestorationSegmentConcatenation) throws {
        let fileManager = FileManager.default
        guard request.segmentURLs.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw RestorationSegmentConcatenatorError.segmentMissing
        }
        guard !fileManager.fileExists(atPath: request.manifestURL.path),
              !fileManager.fileExists(atPath: request.outputURL.path) else {
            throw RestorationSegmentConcatenatorError.outputExists
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
            throw RestorationSegmentConcatenatorError.couldNotLaunch(reason: error.localizedDescription)
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        self.process = nil
        guard !cancellationRequested, !Task.isCancelled else { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            throw RestorationSegmentConcatenatorError.validationProbeFailed(
                String(data: error, encoding: .utf8) ?? ""
            )
        }
        guard let inspection = try? JSONDecoder().decode(MediaInspection.self, from: output) else {
            throw RestorationSegmentConcatenatorError.invalidProbeResponse
        }
        return inspection
    }

    private func validate(
        _ inspection: MediaInspection,
        request: RestorationSegmentConcatenation
    ) throws {
        guard inspection.videoStreams.count == 1,
              inspection.audioStreams.isEmpty,
              inspection.subtitleStreams.isEmpty,
              let video = inspection.videoStreams.first else {
            throw RestorationSegmentConcatenatorError.invalidStreamLayout
        }
        guard video.codecName == "hevc", video.codecTagString == "hvc1",
              video.profile == "Main", video.pixelFormat == "yuv420p" else {
            throw RestorationSegmentConcatenatorError.invalidVideoFormat
        }
        guard video.width == request.plan.outputWidth,
              video.height == request.plan.outputHeight else {
            throw RestorationSegmentConcatenatorError.changedDimensions
        }
        guard let actualFrameRate = video.averageFrameRate,
              RestorationVideoAssembler.frameRatesMatch(actualFrameRate, request.plan.frameRate) else {
            throw RestorationSegmentConcatenatorError.changedFrameRate
        }
        guard video.colorRange == request.plan.colorRange,
              video.colorSpace == request.plan.colorSpace,
              video.colorTransfer == request.plan.colorTransfer,
              video.colorPrimaries == request.plan.colorPrimaries else {
            throw RestorationSegmentConcatenatorError.changedColorMetadata
        }
        guard let durationText = inspection.format.duration,
              let duration = Double(durationText),
              abs(duration - request.expectedDuration) <= max(0.05, request.expectedDuration * 0.001),
              let sizeText = inspection.format.size,
              let size = Int64(sizeText), size > 0 else {
            throw RestorationSegmentConcatenatorError.invalidDurationOrSize
        }
    }
}

extension RestorationSegmentConcatenator: RestorationSegmentConcatenating {}

enum RestorationSegmentConcatenatorError: LocalizedError, Equatable {
    case executableNotFound, alreadyRunning, invalidSegmentCount, invalidFrameRate
    case invalidDimensions, invalidColorMetadata, invalidSegmentSequence
    case segmentMissing, outputExists, couldNotLaunch(reason: String)
    case concatenationFailed(exitCode: Int32, reason: String)
    case validationProbeFailed(String), invalidProbeResponse, invalidStreamLayout
    case invalidVideoFormat, changedDimensions, changedFrameRate
    case changedColorMetadata, invalidDurationOrSize

    var errorDescription: String? {
        switch self {
        case .executableNotFound: "The bundled FFmpeg or ffprobe helper is unavailable."
        case .alreadyRunning: "Restoration segment assembly is already running."
        case .invalidSegmentCount: "Restoration requires at least one encoded segment and one frame."
        case .invalidFrameRate: "The restoration segment frame rate is invalid."
        case .invalidDimensions: "The restoration segment dimensions are invalid."
        case .invalidColorMetadata: "Restoration segments require explicit limited-range SDR metadata."
        case .invalidSegmentSequence: "Restoration segments are not one complete ordered numeric sequence."
        case .segmentMissing: "A restoration segment is no longer available."
        case .outputExists: "The segment manifest or silent partial output already exists."
        case .couldNotLaunch(let reason): "Could not start a media helper: \(reason)"
        case .concatenationFailed(let exitCode, let reason):
            "Restoration segment assembly failed with exit code \(exitCode): \(reason)"
        case .validationProbeFailed(let reason): "The assembled restoration video could not be inspected: \(reason)"
        case .invalidProbeResponse: "ffprobe returned unreadable assembled-video metadata."
        case .invalidStreamLayout: "The assembled restoration video must contain only one video stream."
        case .invalidVideoFormat: "The assembled restoration video is not HEVC Main, hvc1, and yuv420p."
        case .changedDimensions: "The assembled restoration dimensions do not match the plan."
        case .changedFrameRate: "The assembled restoration frame rate does not match the plan."
        case .changedColorMetadata: "The assembled restoration color metadata does not match the plan."
        case .invalidDurationOrSize: "The assembled restoration duration or file size is invalid."
        }
    }
}

private final class RestorationSegmentLockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    var text: String { lock.withLock { String(data: data, encoding: .utf8) ?? "" } }
    func append(_ value: Data) { if !value.isEmpty { lock.withLock { data.append(value) } } }
}
