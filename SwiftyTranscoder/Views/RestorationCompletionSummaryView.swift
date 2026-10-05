import SwiftUI

struct RestorationCompletionSummaryView: View {
    let summary: RestorationCompletionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Elapsed: \(RestorationCompletionSummary.elapsedDescription(summary.elapsedSeconds)) · Average: \(summary.averageFramesPerSecond, specifier: "%.1f") frames/s")
                .monospacedDigit()
            Text("AI model: \(summary.method.rawValue)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
}
