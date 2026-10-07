import Foundation

struct OutputVideoDimensions: Equatable, Sendable {
    let width: Int
    let height: Int
}

enum OutputResolution: String, CaseIterable, Sendable {
    case original, p720 = "720p", p480 = "480p"

    var label: String { self == .original ? "Original size" : rawValue }

    func dimensions(width: Int, height: Int) -> OutputVideoDimensions? {
        guard width > 0, height > 0 else { return nil }
        guard self != .original else { return .init(width: width, height: height) }
        let landscapeWidth = self == .p720 ? 1280 : 854
        let landscapeHeight = self == .p720 ? 720 : 480
        let maxWidth = width >= height ? landscapeWidth : landscapeHeight
        let maxHeight = width >= height ? landscapeHeight : landscapeWidth
        let factor = min(1, Double(maxWidth) / Double(width), Double(maxHeight) / Double(height))
        guard factor < 1 else { return .init(width: width, height: height) }
        // Chroma-subsampled encoding needs even dimensions. FFmpeg's scale
        // filter preserves the display aspect ratio through sample aspect ratio.
        return .init(width: max(2, Int(Double(width) * factor) / 2 * 2),
                     height: max(2, Int(Double(height) * factor) / 2 * 2))
    }
}
