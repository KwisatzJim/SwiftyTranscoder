import Foundation

enum OutputNaming {
    static func proposedURL(sourceURL: URL, folderURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let unsuffixedURL = folderURL.appendingPathComponent(baseName).appendingPathExtension("mp4")
        let keepsOriginalName = sourceExtension == "mkv"
            || (sourceExtension == "mp4"
                && CanonicalOutputPath.key(for: unsuffixedURL) != CanonicalOutputPath.key(for: sourceURL))
        let proposedName = keepsOriginalName
            ? baseName
            : "\(baseName) - SwiftyTranscoder"
        return folderURL
            .appendingPathComponent(proposedName, isDirectory: false)
            .appendingPathExtension("mp4")
    }
}
