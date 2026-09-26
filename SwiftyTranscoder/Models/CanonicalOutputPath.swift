import Foundation

enum CanonicalOutputPath {
    static func key(for outputURL: URL) -> String {
        outputURL.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(outputURL.lastPathComponent)
            .standardizedFileURL
            .path(percentEncoded: false)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}
