import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationCompletionSummaryTests {
    @Test func calculatesWholeJobSpeedAndRetainsSelectedModel() throws {
        let summary = try #require(RestorationCompletionSummary(
            method: .lightweightFSRCNN, frameCount: 240, elapsedSeconds: 18
        ))
        #expect(summary.method == .lightweightFSRCNN)
        #expect(abs(summary.averageFramesPerSecond - 13.3333333333) < 0.000001)
        #expect(RestorationCompletionSummary.elapsedDescription(6420) == "1h 47m 0s")
        #expect(RestorationCompletionSummary.elapsedDescription(18.9) == "18s")
    }

    @Test func doesNotReportMisleadingSpeedForInvalidMeasurements() {
        for elapsed in [0.0, -1, .nan, .infinity, .leastNonzeroMagnitude] {
            #expect(RestorationCompletionSummary(method: .compactGeneral, frameCount: 240, elapsedSeconds: elapsed) == nil)
        }
        #expect(RestorationCompletionSummary(method: .compactGeneral, frameCount: 0, elapsedSeconds: 18) == nil)
    }
}

/// Deterministic monotonic timestamps for controller/coordinator boundary tests.
final class RestorationSummaryTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [Double]
    private var index = 0

    init(_ values: [Double]) { self.values = values }

    func next() -> Double {
        lock.lock()
        defer { lock.unlock() }
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}
