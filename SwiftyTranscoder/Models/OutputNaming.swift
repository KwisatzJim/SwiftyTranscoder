import Foundation

enum OutputNaming {
    static func proposedURL(sourceURL: URL, folderURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let proposedName = sourceURL.pathExtension.lowercased() == "mkv"
            ? baseName
            : "\(baseName) - SwiftyTranscoder"
        return folderURL
            .appendingPathComponent(proposedName, isDirectory: false)
            .appendingPathExtension("mp4")
    }
}
