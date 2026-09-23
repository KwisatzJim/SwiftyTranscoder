import Foundation

struct MediaInspection: Decodable, Sendable {
    let streams: [MediaStream]
    let chapters: [MediaChapter]
    let format: MediaFormat

    var videoStreams: [MediaStream] { streams.filter { $0.codecType == "video" } }
    var audioStreams: [MediaStream] { streams.filter { $0.codecType == "audio" } }
    var subtitleStreams: [MediaStream] { streams.filter { $0.codecType == "subtitle" } }
    var attachmentStreams: [MediaStream] { streams.filter { $0.codecType == "attachment" } }
}

struct MediaStream: Decodable, Identifiable, Sendable {
    let index: Int
    let codecName: String?
    let codecLongName: String?
    let codecTagString: String?
    let profile: String?
    let codecType: String
    let width: Int?
    let height: Int?
    let pixelFormat: String?
    let colorRange: String?
    let colorSpace: String?
    let colorTransfer: String?
    let colorPrimaries: String?
    let averageFrameRate: String?
    let channels: Int?
    let channelLayout: String?
    let sampleRate: String?
    let bitRate: String?
    let tags: [String: String]?
    let disposition: StreamDisposition?

    var id: Int { index }

    enum CodingKeys: String, CodingKey {
        case index, profile, width, height, channels, tags, disposition
        case codecName = "codec_name"
        case codecLongName = "codec_long_name"
        case codecTagString = "codec_tag_string"
        case codecType = "codec_type"
        case pixelFormat = "pix_fmt"
        case colorRange = "color_range"
        case colorSpace = "color_space"
        case colorTransfer = "color_transfer"
        case colorPrimaries = "color_primaries"
        case averageFrameRate = "avg_frame_rate"
        case channelLayout = "channel_layout"
        case sampleRate = "sample_rate"
        case bitRate = "bit_rate"
    }
}

struct StreamDisposition: Decodable, Sendable {
    let isDefault: Int?
    let forced: Int?
    let hearingImpaired: Int?
    let attachedPicture: Int?

    enum CodingKeys: String, CodingKey {
        case isDefault = "default"
        case forced
        case hearingImpaired = "hearing_impaired"
        case attachedPicture = "attached_pic"
    }
}

struct MediaChapter: Decodable, Identifiable, Sendable {
    let id: Int
    let startTime: String?
    let endTime: String?
    let tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, tags
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

struct MediaFormat: Decodable, Sendable {
    let filename: String?
    let streamCount: Int?
    let formatName: String?
    let formatLongName: String?
    let duration: String?
    let size: String?
    let bitRate: String?
    let tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case filename, duration, size, tags
        case streamCount = "nb_streams"
        case formatName = "format_name"
        case formatLongName = "format_long_name"
        case bitRate = "bit_rate"
    }
}
