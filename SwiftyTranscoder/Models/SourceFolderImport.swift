import Foundation

enum SourceFolderImport {
    static func videos(fromDroppedURLs urls: [URL], fileManager: FileManager = .default) throws -> [URL] {
        var candidates: [URL] = []
        for url in urls where url.isFileURL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                candidates += try videos(in: url, fileManager: fileManager)
            } else if values.isRegularFile == true,
                      ["mkv", "mp4", "m4v"].contains(url.pathExtension.lowercased()) {
                candidates.append(url)
            }
        }
        var seen = Set<URL>()
        return candidates.filter {
            seen.insert($0.standardizedFileURL.resolvingSymlinksInPath()).inserted
        }.sorted {
            let comparison = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
            return comparison == .orderedSame ? $0.path < $1.path : comparison == .orderedAscending
        }
    }

    static func videos(in folder: URL, fileManager: FileManager = .default) throws -> [URL] {
        let entries = try fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        var seen = Set<URL>()
        return try entries.filter { url in
            guard ["mkv", "mp4", "m4v"].contains(url.pathExtension.lowercased()) else { return false }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { return false }
            return seen.insert(url.standardizedFileURL.resolvingSymlinksInPath()).inserted
        }.sorted {
            let comparison = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
            return comparison == .orderedSame ? $0.path < $1.path : comparison == .orderedAscending
        }
    }
}
