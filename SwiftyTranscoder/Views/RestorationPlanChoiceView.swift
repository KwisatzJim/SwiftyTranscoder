import SwiftUI

struct RestorationPlanChoiceView: View {
    let inspection: MediaInspection
    let plan: RestorationPlan
    @Binding var isEnabled: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use AI restoration for the full video", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .font(.callout.weight(.medium))

                Text("Off by default. The ordinary non-restored conversion remains available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isEnabled {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        planRow("Method", plan.method.rawValue)
                        planRow(
                            "Dimensions",
                            "\(plan.sourceWidth)×\(plan.sourceHeight) → \(plan.outputWidth)×\(plan.outputHeight) (\(plan.scaleDescription))"
                        )
                        planRow("Frame rate", "Preserve source")
                        planRow("Bounded workspace", temporaryStorageDescription)
                    }

                    if let estimate = storageEstimate,
                       let available = temporaryVolumeAvailableBytes,
                       available < estimate.temporaryBytes {
                        Label(
                            "The current temporary volume does not have enough free space for the bounded workspace.",
                            systemImage: "externaldrive.fill.badge.exclamationmark"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }

                    Label(
                        "Planning review only. Full-file execution remains disabled while final audio, subtitle, and destination validation are added.",
                        systemImage: "info.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Full-video AI restoration", systemImage: "sparkles.rectangle.stack")
                .font(.headline)
        }
        .frame(maxWidth: 760)
    }

    private var temporaryStorageDescription: String {
        guard let estimate = storageEstimate else {
            return "Could not calculate — restoration remains blocked"
        }
        let required = DestinationSpaceCheck.format(estimate.temporaryBytes)
        let chunks = estimate.chunkCount.formatted()
        let residentFrames = estimate.maximumResidentFrameCount.formatted()
        guard let available = temporaryVolumeAvailableBytes else {
            return "About \(required) required; up to \(residentFrames) frames across \(chunks) chunks; free space unavailable"
        }
        return "\(DestinationSpaceCheck.format(available)) available; about \(required) required, up to \(residentFrames) frames at once across \(chunks) chunks"
    }

    private var storageEstimate: RestorationStorageRequirement? {
        guard let size = inspection.format.size.flatMap(Int64.init),
              let duration = inspection.format.duration.flatMap(Double.init) else { return nil }
        return RestorationStorageRequirement.estimate(
            sourceBytes: size,
            durationSeconds: duration,
            frameRate: plan.frameRate,
            plan: plan
        )
    }

    private var temporaryVolumeAvailableBytes: Int64? {
        try? FileManager.default.temporaryDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage
    }

    private func planRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).gridColumnAlignment(.leading).textSelection(.enabled)
        }
        .font(.callout)
    }
}
