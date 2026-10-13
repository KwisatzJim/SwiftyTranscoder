import Foundation

enum FrameRateCompatibility {
    // Container time bases round timestamps differently. Permit only 0.01%
    // variation in the measured average, not a change to a nearby frame rate.
    static func matches(source: String?, output: String?) -> Bool {
        guard let sourceRate = rate(source), let outputRate = rate(output) else { return false }
        return abs(sourceRate - outputRate) <= sourceRate * 0.0001
    }

    private static func rate(_ text: String?) -> Double? {
        guard let text else { return nil }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let numerator = Double(parts[0]), let denominator = Double(parts[1]),
              numerator.isFinite, denominator.isFinite,
              numerator > 0, denominator > 0 else { return nil }
        let value = numerator / denominator
        return value.isFinite && value > 0 ? value : nil
    }
}
