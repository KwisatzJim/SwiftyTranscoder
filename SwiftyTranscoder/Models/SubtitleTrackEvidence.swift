import Foundation

struct SubtitleTrackEvidence: Equatable, Sendable {
    let eventCount: Int?
    let trackSpanSeconds: TimeInterval?

    init?(stream: MediaStream) {
        guard stream.codecType == "subtitle" else { return nil }

        eventCount = Self.integerTag(named: "NUMBER_OF_FRAMES", in: stream.tags)
        trackSpanSeconds = Self.durationTag(named: "DURATION", in: stream.tags)

        guard eventCount != nil || trackSpanSeconds != nil else { return nil }
    }

    private static func integerTag(named name: String, in tags: [String: String]?) -> Int? {
        guard let value = tag(named: name, in: tags),
              let count = Int(value),
              count >= 0 else { return nil }
        return count
    }

    private static func durationTag(named name: String, in tags: [String: String]?) -> TimeInterval? {
        guard let value = tag(named: name, in: tags) else { return nil }
        let fields = value.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 3,
              let hours = Double(fields[0]),
              let minutes = Double(fields[1]),
              let seconds = Double(fields[2]),
              hours >= 0,
              minutes >= 0, minutes < 60,
              seconds >= 0, seconds < 60 else { return nil }
        return (hours * 3_600) + (minutes * 60) + seconds
    }

    private static func tag(named name: String, in tags: [String: String]?) -> String? {
        tags?.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }
}
