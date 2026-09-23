import Foundation

struct MediaSummary: Sendable {
    let video: VideoSummary?
    let audio: AudioSummary?
    let subtitleCount: Int
    let subtitleRecommendation: SubtitleRecommendation

    init(inspection: MediaInspection) {
        video = inspection.videoStreams.first.map(VideoSummary.init)
        audio = inspection.audioStreams.first.map(AudioSummary.init)
        subtitleCount = inspection.subtitleStreams.count
        subtitleRecommendation = SubtitleRecommendationEngine().recommend(
            from: inspection.subtitleStreams,
            primaryAudio: inspection.audioStreams.first
        )
    }
}

struct VideoSummary: Sendable {
    let resolution: String
    let codec: String
    let frameRate: String
    let dynamicRange: String

    init(stream: MediaStream) {
        if let width = stream.width, let height = stream.height {
            resolution = "\(width) × \(height)"
        } else {
            resolution = "Unknown"
        }

        codec = switch stream.codecName?.lowercased() {
        case "h264": "H.264"
        case "hevc": "HEVC"
        case let codec?: codec.uppercased()
        case nil: "Unknown"
        }

        frameRate = Self.formatFrameRate(stream.averageFrameRate) ?? "Unknown"
        dynamicRange = Self.classifyDynamicRange(stream)
    }

    private static func formatFrameRate(_ value: String?) -> String? {
        guard let value else { return nil }
        let parts = value.split(separator: "/", maxSplits: 1).compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return nil }
        let rate = parts[0] / parts[1]
        return String(format: "%.3f fps", rate)
    }

    private static func classifyDynamicRange(_ stream: MediaStream) -> String {
        switch stream.colorTransfer?.lowercased() {
        case "smpte2084": "HDR (PQ)"
        case "arib-std-b67": "HDR (HLG)"
        case "bt709", "iec61966-2-1", "smpte170m", "gamma22", "gamma28": "SDR"
        case nil: "Not identified"
        default: "Not identified"
        }
    }
}

struct AudioSummary: Sendable {
    let layout: String
    let codec: String
    let language: String
    let advancedFormat: String?

    init(stream: MediaStream) {
        layout = Self.describeLayout(stream)
        codec = switch stream.codecName?.lowercased() {
        case "eac3": "Dolby Digital Plus"
        case "ac3": "Dolby Digital"
        case "dts": "DTS"
        case "aac": "AAC"
        case let codec?: codec.uppercased()
        case nil: "Unknown"
        }

        language = stream.tags?["language"] ?? "Unknown"

        let searchableText = [stream.profile, stream.tags?["title"]]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        advancedFormat = searchableText.contains("atmos") ? "Atmos indicated by metadata" : nil
    }

    private static func describeLayout(_ stream: MediaStream) -> String {
        if let channelLayout = stream.channelLayout {
            if channelLayout.lowercased().hasPrefix("5.1") {
                return "5.1 surround"
            }
            if channelLayout.lowercased() == "stereo" {
                return "Stereo"
            }
            return channelLayout
        }
        if let channels = stream.channels {
            return "\(channels) channels"
        }
        return "Unknown"
    }
}
