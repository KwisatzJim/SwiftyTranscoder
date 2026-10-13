import Testing
@testable import SwiftyTranscoderCore

struct FrameRateCompatibilityTests {
    @Test func acceptsContainerRoundingAndEquivalentFractions() {
        #expect(FrameRateCompatibility.matches(source: "68500/4633", output: "2055/139"))
        #expect(FrameRateCompatibility.matches(source: "30000/1001", output: "60000/2002"))
    }

    @Test func rejectsChangedFrameRates() {
        #expect(!FrameRateCompatibility.matches(source: "30000/1001", output: "30/1"))
        #expect(!FrameRateCompatibility.matches(source: "24/1", output: "25/1"))
        #expect(!FrameRateCompatibility.matches(source: "68500/4633", output: "15/1"))
    }

    @Test(arguments: [nil, "", "0/0", "1/0", "-24/1", "24/-1", "nan/1", "inf/1", "24", "24/1/2"])
    func rejectsUnknownOrInvalidRates(_ invalid: String?) {
        #expect(!FrameRateCompatibility.matches(source: invalid, output: "24/1"))
        #expect(!FrameRateCompatibility.matches(source: "24/1", output: invalid))
    }
}
