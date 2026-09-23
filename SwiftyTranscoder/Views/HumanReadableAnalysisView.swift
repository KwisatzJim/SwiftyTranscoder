import SwiftUI

struct HumanReadableAnalysisView: View {
    let inspection: MediaInspection

    private var summary: MediaSummary {
        MediaSummary(inspection: inspection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source overview")
                .font(.title2.bold())

            HStack(alignment: .top, spacing: 12) {
                if let video = summary.video {
                    summaryCard(title: "Video", systemImage: "film") {
                        fact("Resolution", video.resolution)
                        fact("Video format", video.codec)
                        fact("Frame rate", video.frameRate)
                        fact("Picture range", video.dynamicRange)
                    }
                } else {
                    missingCard(title: "Video", systemImage: "film")
                }

                if let audio = summary.audio {
                    summaryCard(title: "Primary audio", systemImage: "speaker.wave.2") {
                        fact("Layout", audio.layout)
                        fact("Audio format", audio.codec)
                        fact("Language", audio.language)
                        if let advancedFormat = audio.advancedFormat {
                            fact("Additional information", advancedFormat)
                        }
                    }
                } else {
                    missingCard(title: "Primary audio", systemImage: "speaker.wave.2")
                }

                summaryCard(title: "Subtitles", systemImage: "captions.bubble") {
                    fact("Tracks found", "\(summary.subtitleCount)")
                    fact("Recommendation", summary.subtitleRecommendation.status)
                    subtitleReason(summary.subtitleRecommendation)
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private func summaryCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }

    private func missingCard(title: String, systemImage: String) -> some View {
        summaryCard(title: title, systemImage: systemImage) {
            Text("Not found")
                .foregroundStyle(.secondary)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
            .font(.callout)
    }

    @ViewBuilder
    private func subtitleReason(_ recommendation: SubtitleRecommendation) -> some View {
        switch recommendation {
        case .forcedEnglishFound(let stream, let reason):
            Text("Stream \(stream.index): \(stream.tags?["title"] ?? "Untitled English track")")
                .font(.caption.weight(.medium))
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)

        case .ambiguousForcedEnglish(let candidates):
            Text("Candidates: \(candidates.map { "stream \($0.index)" }.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .fullEnglishFound(let stream, let reason):
            Text("Stream \(stream.index): \(stream.tags?["title"] ?? "Untitled English track")")
                .font(.caption.weight(.medium))
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)

        case .ambiguousFullEnglish(let candidates):
            Text("Full-English candidates: \(candidates.map { "stream \($0.index)" }.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .noFullEnglish(let audioLanguage):
            Text("Primary audio is \(audioLanguage), but no complete English subtitle track was identified.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .noForcedEnglish:
            Text("No English track has a forced flag or a clearly forced title.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
