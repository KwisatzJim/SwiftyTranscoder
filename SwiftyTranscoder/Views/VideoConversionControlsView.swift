import SwiftUI

struct VideoConversionControlsView: View {
    @ObservedObject var controller: VideoConversionController
    let canStart: Bool
    let startButtonTitle: String
    let existingPartialOutput: URL?
    let start: () -> Void
    @State private var partialPendingTrash: URL?
    @State private var trashError: String?

    var body: some View {
        VStack(spacing: 8) {
            switch controller.phase {
            case .idle:
                Button(startButtonTitle, systemImage: "checkmark.circle", action: start)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart)
                if let existingPartialOutput {
                    VStack(spacing: 5) {
                        Label("Incomplete output found", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(existingPartialOutput.path(percentEncoded: false))
                            .font(.caption)
                            .textSelection(.enabled)
                        Button("Move Incomplete File to Trash", role: .destructive) {
                            partialPendingTrash = existingPartialOutput
                        }
                    }
                }

            case .running:
                VStack(spacing: 4) {
                    HStack {
                        Text("Encoding approved plan… \(controller.progress.formatted(.percent.precision(.fractionLength(0))))")
                        Spacer()
                        Text(progressStatus)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: controller.progress)
                }
                Button("Cancel", role: .cancel) { controller.cancel() }

            case .cancelling:
                ProgressView("Stopping safely…")

            case .completed(let output):
                Label("Approved conversion completed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(output.path(percentEncoded: false))
                    .font(.caption)
                    .textSelection(.enabled)

            case .cancelled(let partialOutput):
                statusMessage(
                    "Conversion cancelled",
                    detail: partialOutput.map {
                        "Incomplete output remains clearly labeled at \($0.path(percentEncoded: false))."
                    } ?? "No incomplete output was created.",
                    partialOutput: partialOutput
                )

            case .failed(let message, let partialOutput):
                statusMessage(
                    "Conversion failed",
                    detail: message + (partialOutput.map {
                        "\nIncomplete output: \($0.path(percentEncoded: false))"
                    } ?? ""),
                    partialOutput: partialOutput
                )
            }
        }
        .frame(maxWidth: 760)
        .confirmationDialog(
            "Move this incomplete output to the Trash?",
            isPresented: Binding(
                get: { partialPendingTrash != nil },
                set: { if !$0 { partialPendingTrash = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                do {
                    try controller.movePartialOutputToTrash(partialPendingTrash)
                } catch {
                    trashError = error.localizedDescription
                }
                partialPendingTrash = nil
            }
            Button("Keep File", role: .cancel) {
                partialPendingTrash = nil
            }
        } message: {
            Text(partialPendingTrash?.path(percentEncoded: false) ?? "")
        }
        .alert("Could Not Move File", isPresented: Binding(
            get: { trashError != nil },
            set: { if !$0 { trashError = nil } }
        )) {
            Button("OK", role: .cancel) { trashError = nil }
        } message: {
            Text(trashError ?? "Unknown error")
        }
    }

    private var progressStatus: String {
        if controller.progress >= 0.999 {
            return "Finalizing…"
        }
        guard let remaining = controller.estimatedRemainingSeconds else {
            return "ETA calculating…"
        }
        return "ETA \(formattedDuration(remaining))"
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 { return "\(hours)h\(minutes)m" }
        if minutes > 0 { return "\(minutes)m\(seconds)s" }
        return "\(seconds)s"
    }

    private func statusMessage(
        _ title: String,
        detail: String,
        partialOutput: URL?
    ) -> some View {
        VStack(spacing: 5) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(detail)
                .font(.caption)
                .textSelection(.enabled)
            HStack {
                if let partialOutput {
                    Button("Move Incomplete File to Trash", role: .destructive) {
                        partialPendingTrash = partialOutput
                    }
                }
                Button("Keep File and Reset") { controller.reset() }
            }
        }
    }
}
