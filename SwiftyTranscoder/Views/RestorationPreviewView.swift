import SwiftUI

struct RestorationPreviewView: View {
    let sourceURL: URL
    let inspection: MediaInspection
    let plan: RestorationPlan
    let gainEnabled: Bool
    let aacStereoEnabled: Bool
    let disabled: Bool
    @Binding var isActive: Bool
    @StateObject private var controller = RestorationPreviewController()
    @State private var startSeconds = 540.0
    @State private var durationSeconds = 5.0

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Create a short, temporary restored clip before running full-file restoration. The source and normal conversion plan are not changed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("Method").foregroundStyle(.secondary)
                        Text("\(plan.method.rawValue) · \(plan.sourceWidth)×\(plan.sourceHeight) → \(plan.outputWidth)×\(plan.outputHeight)")
                    }
                    GridRow {
                        Text("Start").foregroundStyle(.secondary)
                        HStack {
                            TextField("Seconds", value: $startSeconds, format: .number.precision(.fractionLength(0)))
                                .frame(width: 72)
                            Stepper("seconds", value: $startSeconds, in: 0...maximumStart, step: 30)
                                .fixedSize()
                        }
                    }
                    GridRow {
                        Text("Length").foregroundStyle(.secondary)
                        Picker("Length", selection: $durationSeconds) {
                            Text("2 seconds").tag(2.0)
                            Text("5 seconds").tag(5.0)
                            Text("10 seconds").tag(10.0)
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                }
                .font(.callout)
                .disabled(controller.isActive)

                switch controller.phase {
                case .idle:
                    Button("Create Restoration Preview", systemImage: "sparkles.tv") { start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(disabled)
                case .running(let stage):
                    ProgressView(value: controller.progress) {
                        Text(stageLabel(stage))
                    } currentValueLabel: {
                        Text(controller.progress, format: .percent.precision(.fractionLength(0)))
                    }
                    HStack {
                        Button("Cancel Preview", role: .cancel) { controller.cancel() }
                        Text("Restoration runs one frame at a time and may take several minutes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .cancelling:
                    ProgressView("Cancelling preview…")
                case .completed(let url):
                    Label("Temporary restoration preview is ready.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(url.path(percentEncoded: false))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    HStack {
                        Button("Play Preview", systemImage: "play.fill") { controller.playCompletedPreview() }
                            .buttonStyle(.borderedProminent)
                        Button("Show in Finder", systemImage: "folder") { controller.revealCompletedPreview() }
                        Button("Create Another", systemImage: "arrow.clockwise") { controller.reset() }
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button("Try Again", systemImage: "arrow.clockwise") { controller.reset() }
                }

                Text("Review preview only · temporary .partial.mp4 · no final output is created")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("AI restoration preview", systemImage: "sparkles")
                .font(.headline)
        }
        .frame(maxWidth: 760)
        .onChange(of: controller.isActive) { _, active in
            isActive = active
        }
        .onDisappear {
            if controller.isActive { controller.cancel() }
            isActive = false
        }
    }

    private var maximumStart: Double {
        max(0, (inspection.format.duration.flatMap(Double.init) ?? 0) - durationSeconds)
    }

    private func start() {
        startSeconds = min(max(0, startSeconds), maximumStart)
        controller.start(
            sourceURL: sourceURL,
            inspection: inspection,
            plan: plan,
            startSeconds: startSeconds,
            durationSeconds: durationSeconds,
            gainEnabled: gainEnabled,
            aacStereoEnabled: aacStereoEnabled
        )
    }

    private func stageLabel(_ stage: NativeRestorationPreviewStage) -> String {
        switch stage {
        case .extractingFrames: "Extracting preview frames…"
        case .restoringFrames: "Restoring preview frames…"
        case .assemblingSilentVideo: "Assembling restored video…"
        case .muxingAudio: "Adding compatibility audio…"
        }
    }
}
