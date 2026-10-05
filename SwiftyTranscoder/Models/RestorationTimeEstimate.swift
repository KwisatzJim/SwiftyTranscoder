import Foundation

/// Estimate only the current video: different source sizes can run at very different speeds.
struct RestorationTimeEstimate {
    private var startedAt: Double?
    private var initialProgress = 0.0

    mutating func update(progress: Double, now: Double) -> Double? {
        guard progress.isFinite, now.isFinite, (0..<1).contains(progress) else { return nil }
        guard let startedAt else {
            self.startedAt = now
            initialProgress = progress
            return nil
        }
        let elapsed = now - startedAt
        let advanced = progress - initialProgress
        guard elapsed >= 20, advanced > 0.000001 else { return nil }
        let remaining = elapsed * (1 - progress) / advanced
        return remaining.isFinite && remaining >= 0 ? remaining : nil
    }
}
