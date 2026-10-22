import Foundation

/// A sizing recommendation derived from actual dimensions, independent of AI output.
enum SmallerOutputAdvice {
    static func recognizes(_ request: String) -> Bool {
        let text = request.lowercased()
        let exceptions = ["don't", "do not", "without resizing", "original resolution", "original dimensions", "keep resolution"]
        guard !exceptions.contains(where: text.contains) else { return false }
        return ["make this smaller", "make it smaller", "smaller file", "reduce file size", "shrink"].contains(where: text.contains)
    }

    static func recommendation(width: Int, height: Int, current: OutputResolution, allowsResizing: Bool) -> String {
        guard allowsResizing else {
            return "No size change proposed. Ordinary resizing is unavailable in the current restoration workflow."
        }
        guard let currentDimensions = current.dimensions(width: width, height: height) else {
            return "No size change proposed. Source dimensions are unavailable."
        }
        for candidate in [OutputResolution.p720, .p480] {
            guard let dimensions = candidate.dimensions(width: width, height: height),
                  dimensions.width < currentDimensions.width || dimensions.height < currentDimensions.height else { continue }
            return "Proposed Output size: \(candidate.label)\n\nThis reduces the current planned dimensions from \(currentDimensions.width)×\(currentDimensions.height) to \(dimensions.width)×\(dimensions.height), preserving the picture’s proportions. Some detail will be lost; a smaller file is not guaranteed. Audio settings stay unchanged."
        }
        return "No smaller output size is available with the current controls. The current plan already fits within the 480p limit. This app has no target file size or bitrate control."
    }
}
