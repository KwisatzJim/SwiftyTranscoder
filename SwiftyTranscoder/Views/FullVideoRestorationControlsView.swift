import AppKit
import SwiftUI

struct FullVideoRestorationControlsView: View {
    @ObservedObject var controller: FullVideoRestorationController
    let canStart: Bool
    let disabledReason: String?
    let existingPartialOutput: URL?
    var startButtonTitle = "Restore and Convert Approved Plan"
    var supportsSavedProgress = true
    @Binding var keepProgress: Bool
    let savedJobDirectory: URL?
    let start: () -> Void
    @State private var partialPendingTrash: URL?
    @State private var trashError: String?

    var body: some View {
        VStack(spacing: 8) {
            switch controller.phase {
            case .idle:
                if supportsSavedProgress { savedProgressControls }
                Button(supportsSavedProgress && hasSavedJob && keepProgress ? "Resume Saved Restoration" : startButtonTitle, systemImage: "sparkles.rectangle.stack", action: start)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
                if !canStart, let disabledReason {
                    Label(disabledReason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let existingPartialOutput {
                    incompleteOutput(existingPartialOutput)
                }

            case .preparing:
                activeProgress(label: "Preparing AI restoration…")

            case .running(let stage):
                activeProgress(label: stageLabel(stage))

            case .cancelling:
                ProgressView("Stopping restoration safely…")

            case .completed(let output):
                Label("Restored conversion completed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(output.path(percentEncoded: false))
                    .font(.caption)
                    .textSelection(.enabled)
                if controller.reusedFrameCount > 0 {
                    Text("Reused \(controller.reusedFrameCount) verified restored frames.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let summary = controller.completionSummary {
                    RestorationCompletionSummaryView(summary: summary)
                    Text("Elapsed time and speed for newly restored frames include model preparation, audio, and saving.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if controller.completionSummary == nil, let seconds = controller.completionElapsedSeconds {
                    Text("Elapsed: " + RestorationCompletionSummary.elapsedDescription(seconds))
                        .font(.caption)
                }
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                }

            case .cancelled(let partialOutput):
                terminalStatus(
                    title: "Restoration cancelled",
                    detail: partialOutput.map {
                        "Incomplete output remains clearly labeled at \($0.path(percentEncoded: false))."
                    } ?? "No incomplete output was created.",
                    partialOutput: partialOutput
                )

            case .failed(let message, let partialOutput):
                terminalStatus(
                    title: "Restoration failed",
                    detail: message + (partialOutput.map {
                        "\nIncomplete output: \($0.path(percentEncoded: false))"
                    } ?? ""),
                    partialOutput: partialOutput
                )
            }
        }
        .frame(maxWidth: 760)
        .confirmationDialog(
            "Move this incomplete restoration output to the Trash?",
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
            Button("Keep File", role: .cancel) { partialPendingTrash = nil }
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

    private var hasSavedJob: Bool {
        savedJobDirectory.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    private var savedProgressControls: some View {
        VStack(spacing: 5) {
            Toggle("Keep progress so this restoration can be resumed", isOn: $keepProgress)
                .toggleStyle(.checkbox)
            if keepProgress {
                Text("Completed blocks are saved beside the output. Resume requires the same source, output, model, and settings. Saved blocks are removed after success.")
                    .font(.caption).foregroundStyle(.secondary)
                if hasSavedJob {
                    Label("Saved restoration found", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
            }
        }
    }

    private func activeProgress(label: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(label)
                Spacer()
                Text(controller.progress.formatted(.percent.precision(.fractionLength(0))))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: controller.progress)
            if let seconds = controller.estimatedRemainingSeconds {
                Text("About \(max(1, Int(ceil(seconds / 60))))m remaining")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Cancel", role: .cancel) { controller.cancel() }
            if controller.isPreventingIdleSystemSleep {
                Label("Keeping this Mac awake until restoration stops", systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private func incompleteOutput(_ url: URL) -> some View {
        VStack(spacing: 5) {
            Label("Incomplete restoration output found", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(url.path(percentEncoded: false))
                .font(.caption)
                .textSelection(.enabled)
            Button("Move Incomplete File to Trash", role: .destructive) {
                partialPendingTrash = url
            }
        }
    }

    private func terminalStatus(
        title: String,
        detail: String,
        partialOutput: URL?
    ) -> some View {
        VStack(spacing: 5) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(detail)
                .font(.caption)
                .textSelection(.enabled)
            if supportsSavedProgress, keepProgress, hasSavedJob, let savedJobDirectory {
                Text("Completed blocks retained: \(savedJobDirectory.path)")
                    .font(.caption).textSelection(.enabled)
                Button("Resume Saved Restoration", systemImage: "arrow.clockwise", action: start)
                    .disabled(!canStart || partialOutput != nil)
                Button("Show Saved Job in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([savedJobDirectory])
                }
            }
            if let partialOutput {
                Button("Move Incomplete File to Trash", role: .destructive) {
                    partialPendingTrash = partialOutput
                }
            }
        }
    }
}
