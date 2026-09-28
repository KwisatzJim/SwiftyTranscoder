import Foundation

enum SubtitleSelection: Hashable, Sendable {
    case burnIn(streamIndex: Int)
    case omit
    case needsChoice

    init(recommendation: SubtitleRecommendation) {
        switch recommendation {
        case .forcedEnglishFound(let stream, _):
            self = .burnIn(streamIndex: stream.index)
        case .likelyForcedEnglish:
            self = .needsChoice
        case .fullEnglishFound(let stream, _):
            self = .burnIn(streamIndex: stream.index)
        case .ambiguousForcedEnglish, .ambiguousFullEnglish:
            self = .needsChoice
        case .noFullEnglish, .noForcedEnglish:
            self = .omit
        }
    }
}
