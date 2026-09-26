import Testing
@testable import SwiftyTranscoderCore

struct DestinationStorageRequirementTests {
    @Test func smallSourceReceivesOneGiBMinimumReserve() {
        #expect(DestinationStorageRequirement.requiredBytes(forSourceBytes: 100) == 1_073_741_924)
    }

    @Test func largeSourceReceivesFiftyPercentReserve() {
        #expect(DestinationStorageRequirement.requiredBytes(forSourceBytes: 10_000_000_000) == 15_000_000_000)
    }

    @Test func negativeAndOverflowingSizesAreRejected() {
        #expect(DestinationStorageRequirement.requiredBytes(forSourceBytes: -1) == nil)
        #expect(DestinationStorageRequirement.requiredBytes(forSourceBytes: .max) == nil)
    }
}
