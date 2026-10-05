import Testing
@testable import SwiftyTranscoderCore

struct RestorationTimeEstimateTests {
    @Test func waitsForMeasuredProgressAndEstimatesCurrentVideo() {
        var estimate = RestorationTimeEstimate()
        #expect(estimate.update(progress: 0.1, now: 100) == nil)
        #expect(estimate.update(progress: 0.2, now: 110) == nil)
        let remaining = estimate.update(progress: 0.3, now: 140) ?? -1
        #expect(abs(remaining - 140) < 0.001)
        #expect(estimate.update(progress: 1, now: 200) == nil)
    }
    @Test func refusesStalledAndInvalidMeasurements() {
        var estimate = RestorationTimeEstimate()
        #expect(estimate.update(progress: .nan, now: 0) == nil)
        #expect(estimate.update(progress: 0.2, now: 100) == nil)
        #expect(estimate.update(progress: 0.2, now: 200) == nil)
        #expect(estimate.update(progress: 0.1, now: 200) == nil)
    }
}
