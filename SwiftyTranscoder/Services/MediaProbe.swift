import Foundation
import Darwin

struct MediaProbe: Sendable {
    private let executableURL: URL

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) throws {
        guard let executableURL = MediaToolLocator.executableURL(
            for: .ffprobe,
            bundleURL: bundleURL,
            fileManager: fileManager
        ) else {
            throw MediaProbeError.executableNotFound
        }
        self.executableURL = executableURL
    }

    func inspect(_ sourceURL: URL) async throws -> MediaInspection {
        let executableURL = self.executableURL

        return try await Task.detached(priority: .userInitiated) {
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()

            process.executableURL = executableURL
            process.arguments = [
                "-v", "error",
                // Some E-AC-3 sources need more packets before the decoder
                // identifies their speaker layout. Keep inspection bounded.
                "-analyzeduration", "20000000",
                "-probesize", "20000000",
                "-print_format", "json",
                "-show_format",
                "-show_streams",
                "-show_chapters",
                sourceURL.path(percentEncoded: false)
            ]
            process.standardOutput = standardOutput
            process.standardError = standardError

            do {
                try process.run()
            } catch {
                throw MediaProbeError.couldNotLaunch(
                    file: sourceURL.lastPathComponent,
                    reason: error.localizedDescription
                )
            }

            let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let detail = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw MediaProbeError.probeFailed(
                    file: sourceURL.lastPathComponent,
                    exitCode: process.terminationStatus,
                    reason: detail?.isEmpty == false ? detail! : "ffprobe did not provide a reason."
                )
            }

            do {
                var inspection = try JSONDecoder().decode(MediaInspection.self, from: outputData)
                if let index = inspection.streams.firstIndex(where: { $0.codecType == "video" }) {
                    let video = inspection.streams[index]
                    if [video.colorTransfer, video.colorPrimaries, video.colorSpace].contains(where: { FrameColorEvidence.known($0) == nil }) {
                        inspection.streams[index] = Self.inspectFrameColors(video, duration: inspection.format.duration ?? video.duration, sourceURL: sourceURL, executableURL: executableURL)
                    }
                }
                return inspection
            } catch {
                throw MediaProbeError.invalidResponse(
                    file: sourceURL.lastPathComponent,
                    reason: error.localizedDescription
                )
            }
        }.value
    }

    private static func inspectFrameColors(_ video: MediaStream, duration: String?, sourceURL: URL, executableURL: URL) -> MediaStream {
        var fallback = video
        fallback.colorInspectionNote = "Deeper color check was unavailable; original metadata and confirmation requirements are unchanged."
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent("colors.json")
            guard FileManager.default.createFile(atPath: output.path, contents: nil) else { return fallback }
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = executableURL
            let samplePlan = ColorSamplePlan(duration: duration)
            // Packet bounds across all seeks and one overall deadline keep this check short.
            process.arguments = ["-v", "error", "-threads", "1", "-select_streams", String(video.index),
                "-read_intervals", samplePlan.readIntervals, "-show_frames",
                "-show_entries", "frame=color_range,color_space,color_transfer,color_primaries:frame_side_data=side_data_type",
                "-of", "json", sourceURL.path(percentEncoded: false)]
            process.standardOutput = handle
            process.standardError = FileHandle.nullDevice
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            if finished.wait(timeout: .now() + 12) == .timedOut {
                process.terminate()
                if finished.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                fallback.colorInspectionNote = "Deeper color check reached its time limit; no color assumptions were made."
                return fallback
            }
            guard process.terminationStatus == 0 else { return fallback }
            let data = try Data(contentsOf: output)
            guard data.count < 2_000_000 else { return fallback }
            return try JSONDecoder().decode(FrameColorEvidence.self, from: data).applying(to: video, sampleDescription: samplePlan.description)
        } catch {
            return fallback
        }
    }
}

enum MediaProbeError: LocalizedError {
    case executableNotFound
    case couldNotLaunch(file: String, reason: String)
    case probeFailed(file: String, exitCode: Int32, reason: String)
    case invalidResponse(file: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "The bundled ffprobe helper is unavailable, and no Homebrew development fallback was found. Reinstall SwiftyTranscoder."
        case .couldNotLaunch(let file, let reason):
            "Could not start ffprobe for \(file): \(reason)"
        case .probeFailed(let file, let exitCode, let reason):
            "ffprobe could not inspect \(file) (exit code \(exitCode)): \(reason)"
        case .invalidResponse(let file, let reason):
            "ffprobe returned unreadable metadata for \(file): \(reason)"
        }
    }
}
