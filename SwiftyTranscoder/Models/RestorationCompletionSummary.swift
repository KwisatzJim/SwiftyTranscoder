import Foundation

struct RestorationCompletionSummary: Equatable, Sendable {
    let method: RestorationMethod
    let frameCount: Int64
    let elapsedSeconds: Double
    let averageFramesPerSecond: Double

    init?(method: RestorationMethod, frameCount: Int64, elapsedSeconds: Double) {
        guard frameCount > 0, elapsedSeconds.isFinite, elapsedSeconds > 0,
              elapsedSeconds < Double(Int.max) else { return nil }
        let speed = Double(frameCount) / elapsedSeconds
        guard speed.isFinite else { return nil }
        self.method = method
        self.frameCount = frameCount
        self.elapsedSeconds = elapsedSeconds
        self.averageFramesPerSecond = speed
    }

    static func elapsedDescription(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "Unavailable" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = total / 60 % 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m \(seconds)s" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}
