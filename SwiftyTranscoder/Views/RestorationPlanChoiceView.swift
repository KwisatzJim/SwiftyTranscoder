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
                        planRow("Temporary storage", temporaryStorageDescription)
                    }

                    if let estimate = storageEstimate,
                       let available = temporaryVolumeAvailableBytes,
                       available < estimate.temporaryBytes {
                        Label(
                            "The current temporary volume does not have enough free space for this plan.",
                            systemImage: "externaldrive.fill.badge.exclamationmark"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }

                    Label(
                        "Planning review only. Full-file restoration execution is not enabled in this milestone.",
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
        let frames = estimate.frameCount.formatted()
        guard let available = temporaryVolumeAvailableBytes else {
            return "About \(required) required for \(frames) frames; free space unavailable"
        }
        return "\(DestinationSpaceCheck.format(available)) available; about \(required) required for \(frames) frames"
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
