import Foundation

struct ColorSamplePlan: Sendable {
    let readIntervals: String
    let description: String

    init(duration: String?) {
        guard let duration, let seconds = Double(duration), seconds.isFinite, seconds > 4 else {
            readIntervals = "%+#48"
            description = "near the start (short video or duration unavailable)"
            return
        }
        // Absolute seeks can land on earlier keyframes. Packet counts bound
        // decoding work even for variable frame rates or long videos.
        let middle = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds * 0.5)
        let end = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds * 0.9)
        readIntervals = "0%+#48,\(middle)%+#48,\(end)%+#48"
        description = "using seek points at the start, 50%, and 90% of the video (keyframe seeking may land earlier)"
    }
}
