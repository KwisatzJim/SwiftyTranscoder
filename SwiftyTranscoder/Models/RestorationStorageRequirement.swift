import Foundation

struct RestorationStorageRequirement: Equatable, Sendable {
    static let reserveBytes: Int64 = 1_073_741_824

    let frameCount: Int64
    let temporaryBytes: Int64

    static func estimate(
        sourceBytes: Int64,
        durationSeconds: Double,
        frameRate: String,
        plan: RestorationPlan
    ) -> RestorationStorageRequirement? {
        guard sourceBytes >= 0, durationSeconds > 0,
              plan.sourceWidth > 0, plan.sourceHeight > 0,
              plan.outputWidth > 0, plan.outputHeight > 0,
              let framesPerSecond = frameRateValue(frameRate) else { return nil }
        let frameCountValue = (durationSeconds * framesPerSecond).rounded(.up)
        guard frameCountValue.isFinite, frameCountValue > 0,
              frameCountValue <= Double(Int64.max) else { return nil }
        let frameCount = Int64(frameCountValue)

        guard let sourcePixels = multiplied(Int64(plan.sourceWidth), Int64(plan.sourceHeight)),
              let outputPixels = multiplied(Int64(plan.outputWidth), Int64(plan.outputHeight)),
              let pixelsPerFrame = added(sourcePixels, outputPixels),
              let frameBytes = multiplied(pixelsPerFrame, 4),
              let sequenceBytes = multiplied(frameBytes, frameCount),
              let encodedWorkingBytes = multiplied(sourceBytes, 2),
              let withEncodedFiles = added(sequenceBytes, encodedWorkingBytes),
              let total = added(withEncodedFiles, reserveBytes) else { return nil }

        return RestorationStorageRequirement(
            frameCount: frameCount,
            temporaryBytes: total
        )
    }

    private static func frameRateValue(_ value: String) -> Double? {
        let parts = value.split(separator: "/", maxSplits: 1).compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return parts[0] / parts[1]
    }

    private static func multiplied(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? nil : result.partialValue
    }

    private static func added(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }
}
