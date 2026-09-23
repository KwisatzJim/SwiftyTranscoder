import Foundation

struct MediaProbe: Sendable {
    private let executableURL: URL

    init(fileManager: FileManager = .default) throws {
        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe"
        ]

        guard let path = candidates.first(where: fileManager.isExecutableFile(atPath:)) else {
            throw MediaProbeError.executableNotFound
        }

        executableURL = URL(fileURLWithPath: path)
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
                return try JSONDecoder().decode(MediaInspection.self, from: outputData)
            } catch {
                throw MediaProbeError.invalidResponse(
                    file: sourceURL.lastPathComponent,
                    reason: error.localizedDescription
                )
            }
        }.value
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
            "ffprobe was not found in /opt/homebrew/bin or /usr/local/bin. Install FFmpeg before inspecting a video."
        case .couldNotLaunch(let file, let reason):
            "Could not start ffprobe for \(file): \(reason)"
        case .probeFailed(let file, let exitCode, let reason):
            "ffprobe could not inspect \(file) (exit code \(exitCode)): \(reason)"
        case .invalidResponse(let file, let reason):
            "ffprobe returned unreadable metadata for \(file): \(reason)"
        }
    }
}
