import Foundation

struct RestorationStorageRequirement: Equatable, Sendable {
    static let reserveBytes: Int64 = 1_073_741_824

    let frameCount: Int64
    let chunkCount: Int64
    let maximumResidentFrameCount: Int64
    let temporaryBytes: Int64

    static func estimate(
        sourceBytes: Int64,
        durationSeconds: Double,
        frameRate: String,
        exactFrameCount: Int64? = nil,
        plan: RestorationPlan
    ) -> RestorationStorageRequirement? {
        guard sourceBytes >= 0, durationSeconds > 0,
              plan.sourceWidth > 0, plan.sourceHeight > 0,
              plan.outputWidth > 0, plan.outputHeight > 0,
              let framesPerSecond = frameRateValue(frameRate) else { return nil }
        let estimatedFrameCount = durationSeconds * framesPerSecond
        guard estimatedFrameCount.isFinite, estimatedFrameCount > 0,
              estimatedFrameCount <= Double(Int64.max) else { return nil }
        let frameCount: Int64
        if let exactFrameCount {
            guard exactFrameCount > 0 else { return nil }
            frameCount = exactFrameCount
        } else {
            frameCount = Int64(estimatedFrameCount.rounded(.up))
        }
        let maximumResidentFrameCount = min(
            frameCount,
            Int64(RestorationChunkPlan.defaultFrameLimit)
        )
        let chunkCount = (frameCount + maximumResidentFrameCount - 1) / maximumResidentFrameCount

        // Restored PNGs are always 2× source dimensions; the 1080p cap is applied
        // later during video assembly. Include PNG/zlib overhead for larger files.
        let restoredWidth = plan.sourceWidth.multipliedReportingOverflow(by: RestorationFrameGeometry.scale)
        let restoredHeight = plan.sourceHeight.multipliedReportingOverflow(by: RestorationFrameGeometry.scale)
        guard !restoredWidth.overflow, !restoredHeight.overflow,
              let sourceFrameBytes = RestorationPNGEncoder.maximumFileBytes(width: plan.sourceWidth, height: plan.sourceHeight),
              let restoredFrameBytes = RestorationPNGEncoder.maximumFileBytes(width: restoredWidth.partialValue, height: restoredHeight.partialValue),
              // Allow extra metadata chunks in FFmpeg source PNGs.
              let sourceFrameWithMetadata = added(sourceFrameBytes, 1024),
              let frameBytes = added(sourceFrameWithMetadata, restoredFrameBytes),
              let sequenceBytes = multiplied(frameBytes, maximumResidentFrameCount),
              let encodedWorkingBytes = multiplied(sourceBytes, 2),
              let withEncodedFiles = added(sequenceBytes, encodedWorkingBytes),
              let total = added(withEncodedFiles, reserveBytes) else { return nil }

        return RestorationStorageRequirement(
            frameCount: frameCount,
            chunkCount: chunkCount,
            maximumResidentFrameCount: maximumResidentFrameCount,
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
