import Testing
@testable import SwiftyTranscoderCore

struct QueueIndexRemappingTests {
    @Test func removingMiddleValueDropsItAndShiftsLaterValues() {
        let result = QueueIndexRemapping.remap([0: "first", 1: "remove", 2: "last"], removing: 1)
        #expect(result == [0: "first", 1: "last"])
    }

    @Test func removingMiddleCompletedIndexDropsItAndShiftsLaterIndexes() {
        let result = QueueIndexRemapping.remap(Set([0, 1, 3]), removing: 1)
        #expect(result == Set([0, 2]))
    }

    @Test func currentItemBeforeRemovalKeepsItsIndex() {
        #expect(QueueIndexRemapping.currentIndex(0, removing: 2, remainingCount: 2) == 0)
    }

    @Test func currentItemAfterRemovalShiftsBack() {
        #expect(QueueIndexRemapping.currentIndex(2, removing: 0, remainingCount: 2) == 1)
    }

    @Test func removedFinalCurrentItemSelectsNewFinalItem() {
        #expect(QueueIndexRemapping.currentIndex(2, removing: 2, remainingCount: 2) == 1)
    }
}
