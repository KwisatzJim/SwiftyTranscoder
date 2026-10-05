import AppKit
import SwiftUI

struct RestorationBatchControlsView: View {
    @ObservedObject var controller: RestorationBatchController
    let sources: [URL]
    let canStart: Bool
    let disabledReason: String?
    let start: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                switch controller.snapshot.phase {
                case .idle:
                    Text("Restore one video at a time using each approved plan.")
                    Button("Start Approved Restoration Batch", systemImage: "sparkles.rectangle.stack", action: start)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canStart)
                    if !canStart, let disabledReason {
                        Text(disabledReason).font(.caption).foregroundStyle(.orange)
                    }
                case .running:
                    ProgressView(value: controller.snapshot.progress) {
                        Text("\(completedCount) of \(sources.count) completed")
                    }
                    Text("Batch progress: \(controller.snapshot.progress * 100, specifier: "%.1f")%")
                        .monospacedDigit()
                    if let index = controller.snapshot.activeIndex,
                       controller.snapshot.items.indices.contains(index),
                       case .running = controller.snapshot.items[index] {
                        Text("Current video: \(controller.snapshot.activeProgress * 100, specifier: "%.1f")% · \(timeRemaining)")
                            .font(.caption).monospacedDigit()
                    }
                    Button("Cancel Restoration Batch", role: .cancel) { controller.cancel() }
                    Text("A failed file is reported below; remaining jobs continue. Cancelling stops the remaining jobs.")
                        .font(.caption).foregroundStyle(.secondary)
                case .cancelling:
                    ProgressView("Stopping the active job safely…")
                case .finished:
                    Label("Batch finished · \(completedCount) of \(sources.count) completed", systemImage: "checkmark.seal")
                    if completedCount < sources.count {
                        Text("Some files failed. Review their results below.").foregroundStyle(.orange)
                    }
                case .cancelled:
                    Label("Batch cancelled · \(completedCount) completed", systemImage: "stop.circle")
                case .rejected(let message):
                    Text(message).foregroundStyle(.orange)
                }

                if let elapsed = controller.snapshot.elapsedSeconds {
                    Text("Batch elapsed: \(RestorationCompletionSummary.elapsedDescription(elapsed))")
                        .font(.caption).monospacedDigit()
                }
                if !controller.snapshot.completionSummaries.isEmpty {
                    Text("Elapsed time and average speed include model preparation, audio, and saving.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if controller.hasStarted {
                    Divider()
                    ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                        if controller.snapshot.items.indices.contains(index) {
                            resultRow(source: source, state: controller.snapshot.items[index], summary: controller.snapshot.completionSummaries[index])
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("AI restoration batch", systemImage: "sparkles.rectangle.stack")
        }
        .frame(maxWidth: 760)
    }

    private var completedCount: Int {
        controller.snapshot.items.filter { if case .completed = $0 { true } else { false } }.count
    }

    private var timeRemaining: String {
        guard let seconds = controller.estimatedRemainingSeconds else { return "Estimating time remaining…" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        let hours = minutes / 60
        return hours > 0
            ? "About \(hours)h \(minutes % 60)m remaining for this video"
            : "About \(minutes)m remaining for this video"
    }

    private func resultRow(source: URL, state: RestorationBatchItemState, summary: RestorationCompletionSummary?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.lastPathComponent).font(.callout.weight(.medium))
            switch state {
            case .queued: Text("Waiting")
            case .preparing: Text("Preparing AI model…")
            case .running(let stage): Text(stageLabel(stage))
            case .completed(let output):
                Text("Completed").foregroundStyle(.green)
                if let summary { RestorationCompletionSummaryView(summary: summary) }
                Button("Show Output in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
            case .failed(let message, let partial):
                Text(message).foregroundStyle(.orange)
                partialRow(partial)
            case .cancelled(let partial):
                Text("Cancelled")
                partialRow(partial)
            case .notRun: Text("Not run")
            }
        }
        .font(.caption)
        .textSelection(.enabled)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func partialRow(_ partial: URL?) -> some View {
        if let partial {
            Text("Incomplete output: \(partial.path)")
            Button("Show Incomplete Output in Finder") { NSWorkspace.shared.activateFileViewerSelecting([partial]) }
        }
    }

    private func stageLabel(_ stage: FullVideoRestorationStage) -> String {
        switch stage {
        case .processingChunks: "Restoring video frames…"
        case .assemblingSilentVideo: "Joining restored video…"
        case .muxingAudioAndMetadata: "Adding approved audio and metadata…"
        case .stagingDestination: "Copying validated output…"
        case .promotingDestination: "Finalizing restored output…"
        }
    }
}
