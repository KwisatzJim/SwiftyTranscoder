import Foundation

enum DestinationStorageRequirement {
    static let minimumReserveBytes: Int64 = 1_073_741_824

    static func requiredBytes(forSourceBytes sourceBytes: Int64) -> Int64? {
        guard sourceBytes >= 0 else { return nil }
        let reserve = max(sourceBytes / 2, minimumReserveBytes)
        let total = sourceBytes.addingReportingOverflow(reserve)
        return total.overflow ? nil : total.partialValue
    }
}
