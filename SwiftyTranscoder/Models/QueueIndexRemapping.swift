import Foundation

enum QueueIndexRemapping {
    static func remap<Value>(_ values: [Int: Value], removing removedIndex: Int) -> [Int: Value] {
        Dictionary(uniqueKeysWithValues: values.compactMap { index, value in
            guard index != removedIndex else { return nil }
            return (index > removedIndex ? index - 1 : index, value)
        })
    }

    static func remap(_ indexes: Set<Int>, removing removedIndex: Int) -> Set<Int> {
        Set(indexes.compactMap { index in
            guard index != removedIndex else { return nil }
            return index > removedIndex ? index - 1 : index
        })
    }

    static func currentIndex(_ currentIndex: Int, removing removedIndex: Int, remainingCount: Int) -> Int {
        guard remainingCount > 0 else { return 0 }
        if currentIndex > removedIndex { return currentIndex - 1 }
        if currentIndex == removedIndex { return min(removedIndex, remainingCount - 1) }
        return currentIndex
    }
}
