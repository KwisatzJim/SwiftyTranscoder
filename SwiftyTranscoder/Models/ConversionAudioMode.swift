import Foundation

/// Audio removal is explicit and independent of the gain/AAC preferences.
enum ConversionAudioMode: String, Sendable, Equatable {
    case convert
    case omit

    /// Removing audio must not compare video length against a longer audio track.
    func expectedDuration(in inspection: MediaInspection) -> Double? {
        func positive(_ text: String?) -> Double? {
            guard let value = text.flatMap(Double.init), value.isFinite, value > 0 else { return nil }
            return value
        }
        if self == .omit, let video = inspection.videoStreams.first {
            if let duration = positive(video.duration) { return duration }
            if let text = video.tags?.first(where: { $0.key.caseInsensitiveCompare("DURATION") == .orderedSame })?.value {
                let parts = text.split(separator: ":").compactMap { Double($0) }
                if parts.count == 3, parts.allSatisfy({ $0.isFinite && $0 >= 0 }) {
                    let duration = parts[0] * 3600 + parts[1] * 60 + parts[2]
                    if duration > 0 { return duration }
                }
            }
            if let frames = positive(video.numberOfFrames), let rateText = video.averageFrameRate {
                let parts = rateText.split(separator: "/").compactMap { Double($0) }
                if parts.count == 2, parts.allSatisfy({ $0.isFinite && $0 > 0 }) {
                    let duration = frames * parts[1] / parts[0]
                    if duration.isFinite && duration > 0 { return duration }
                }
            }
        }
        return positive(inspection.format.duration)
    }
}
