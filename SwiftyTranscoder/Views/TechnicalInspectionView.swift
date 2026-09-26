import SwiftUI

struct TechnicalInspectionView: View {
    let inspection: MediaInspection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            containerSection
            streamSection("Video", streams: inspection.videoStreams)
            streamSection("Audio", streams: inspection.audioStreams)
            streamSection("Subtitles", streams: inspection.subtitleStreams)
            chapterSection
            streamSection("Attachments", streams: inspection.attachmentStreams)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var containerSection: some View {
        detailSection("Container") {
            detailRow("Format", inspection.format.formatLongName ?? inspection.format.formatName)
            detailRow("Duration", formattedDuration(inspection.format.duration))
            detailRow("File size", formattedSize(inspection.format.size))
            detailRow("Overall bitrate", formattedBitRate(inspection.format.bitRate))
        }
    }

    private func streamSection(_ title: String, streams: [MediaStream]) -> some View {
        detailSection("\(title) (\(streams.count))") {
            if streams.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(streams) { stream in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Stream \(stream.index): \(streamTitle(stream))")
                            .font(.callout.weight(.medium))

                        Text(streamDetails(stream))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var chapterSection: some View {
        detailSection("Chapters (\(inspection.chapters.count))") {
            if inspection.chapters.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(inspection.chapters) { chapter in
                    let title = chapter.tags?["title"] ?? "Chapter \(chapter.id + 1)"
                    Text("\(title): \(chapter.startTime ?? "unknown")–\(chapter.endTime ?? "unknown")")
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?) -> some View {
        LabeledContent(label, value: value ?? "Unknown")
            .font(.callout)
    }

    private func streamTitle(_ stream: MediaStream) -> String {
        let values = [stream.tags?["language"], stream.tags?["title"], stream.codecName]
            .compactMap { $0 }
        return values.isEmpty ? "Unknown" : values.joined(separator: " · ")
    }

    private func streamDetails(_ stream: MediaStream) -> String {
        var details: [String] = []

        if let width = stream.width, let height = stream.height {
            details.append("\(width) × \(height)")
        }
        if let frameRate = formattedFrameRate(stream.averageFrameRate) {
            details.append("\(frameRate) fps")
        }
        if let pixelFormat = stream.pixelFormat { details.append(pixelFormat) }
        if let colorTransfer = stream.colorTransfer { details.append("transfer \(colorTransfer)") }
        if let colorPrimaries = stream.colorPrimaries { details.append("primaries \(colorPrimaries)") }
        if let channels = stream.channels { details.append("\(channels) channels") }
        if let channelLayout = stream.channelLayout { details.append(channelLayout) }
        if let sampleRate = stream.sampleRate, let rate = Double(sampleRate) {
            details.append(String(format: "%.0f kHz", rate / 1_000))
        }
        if let bitRate = formattedBitRate(stream.bitRate) { details.append(bitRate) }
        if stream.disposition?.forced == 1 { details.append("forced") }
        if stream.disposition?.isDefault == 1 { details.append("default") }
        if stream.disposition?.hearingImpaired == 1 { details.append("hearing impaired") }
        if let evidence = stream.subtitleEvidence {
            if let eventCount = evidence.eventCount {
                details.append("\(eventCount) subtitle events")
            }
            if let trackSpan = formattedTimeInterval(evidence.trackSpanSeconds) {
                details.append("track span \(trackSpan)")
            }
        }

        return details.isEmpty ? "No additional metadata" : details.joined(separator: " · ")
    }

    private func formattedDuration(_ value: String?) -> String? {
        guard let value, let seconds = Double(value) else { return nil }
        return formattedTimeInterval(seconds)
    }

    private func formattedTimeInterval(_ value: TimeInterval?) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        let totalSeconds = Int(value.rounded())
        return String(
            format: "%d:%02d:%02d",
            totalSeconds / 3_600,
            (totalSeconds % 3_600) / 60,
            totalSeconds % 60
        )
    }

    private func formattedSize(_ value: String?) -> String? {
        guard let value, let bytes = Int64(value) else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formattedBitRate(_ value: String?) -> String? {
        guard let value, let bitsPerSecond = Double(value) else { return nil }
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.2f Mb/s", bitsPerSecond / 1_000_000)
        }
        return String(format: "%.0f kb/s", bitsPerSecond / 1_000)
    }

    private func formattedFrameRate(_ value: String?) -> String? {
        guard let value else { return nil }
        let parts = value.split(separator: "/", maxSplits: 1).compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return nil }
        return String(format: "%.3f", parts[0] / parts[1])
    }
}
