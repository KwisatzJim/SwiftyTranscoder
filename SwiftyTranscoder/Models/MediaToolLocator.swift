import Foundation

struct MediaToolLocator: Sendable {
    enum Tool: String, Sendable {
        case ffmpeg
        case ffprobe

        var fallbackPaths: [String] {
            switch self {
            case .ffmpeg:
                [
                    "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg",
                    "/usr/local/opt/ffmpeg-full/bin/ffmpeg",
                ]
            case .ffprobe:
                [
                    "/opt/homebrew/bin/ffprobe",
                    "/usr/local/bin/ffprobe",
                ]
            }
        }
    }

    static func executableURL(
        for tool: Tool,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default,
        fallbackPaths: [String]? = nil
    ) -> URL? {
        let bundledURL = bundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent(tool.rawValue, isDirectory: false)

        let candidates = [bundledURL.path(percentEncoded: false)]
            + (fallbackPaths ?? tool.fallbackPaths)

        guard let path = candidates.first(where: fileManager.isExecutableFile(atPath:)) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}
