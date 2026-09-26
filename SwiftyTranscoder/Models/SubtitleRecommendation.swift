import Foundation

enum SubtitleRecommendation: Sendable {
    case forcedEnglishFound(stream: MediaStream, reason: String)
    case likelyForcedEnglish(stream: MediaStream, reason: String)
    case ambiguousForcedEnglish(candidates: [MediaStream])
    case fullEnglishFound(stream: MediaStream, reason: String)
    case ambiguousFullEnglish(candidates: [MediaStream])
    case noFullEnglish(audioLanguage: String)
    case noForcedEnglish

    var status: String {
        switch self {
        case .forcedEnglishFound:
            "Forced English found—burn in"
        case .likelyForcedEnglish:
            "Likely forced—please confirm"
        case .ambiguousForcedEnglish:
            "Multiple forced English tracks—choose one"
        case .fullEnglishFound:
            "Foreign-language audio—burn full English"
        case .ambiguousFullEnglish:
            "Multiple full English tracks—choose one"
        case .noFullEnglish:
            "Foreign-language audio—no full English track identified"
        case .noForcedEnglish:
            "No forced English identified"
        }
    }
}

struct SubtitleRecommendationEngine: Sendable {
    func recommend(
        from streams: [MediaStream],
        primaryAudio: MediaStream?
    ) -> SubtitleRecommendation {
        if let audioLanguage = explicitForeignLanguage(primaryAudio) {
            return recommendFullEnglish(from: streams, audioLanguage: audioLanguage)
        }

        let candidates = streams.compactMap(Candidate.init)
        guard !candidates.isEmpty else {
            return likelyForcedRecommendation(from: streams)
        }

        let strongestEvidence = candidates.map(\.evidence).max() ?? .title
        var preferred = candidates.filter { $0.evidence == strongestEvidence }

        let nonSDHCandidates = preferred.filter { !$0.isSDH }
        if !nonSDHCandidates.isEmpty {
            preferred = nonSDHCandidates
        }

        guard preferred.count == 1, let choice = preferred.first else {
            return .ambiguousForcedEnglish(candidates: preferred.map(\.stream))
        }

        let reason = switch choice.evidence {
        case .disposition:
            "Stream \(choice.stream.index) is English and carries the Matroska forced flag."
        case .title:
            "Stream \(choice.stream.index) is English and its title clearly identifies forced dialogue."
        }

        return .forcedEnglishFound(stream: choice.stream, reason: reason)
    }

    private func likelyForcedRecommendation(from streams: [MediaStream]) -> SubtitleRecommendation {
        let englishTracks = streams.filter { stream in
            let language = stream.tags?["language"]?.lowercased()
            let title = stream.tags?["title"]?.lowercased() ?? ""
            return language == "eng"
                || language == "en"
                || language?.hasPrefix("en-") == true
                || title.contains("english")
        }

        let evidenceTracks = englishTracks.compactMap { stream -> (MediaStream, Int)? in
            guard let count = stream.subtitleEvidence?.eventCount, count > 0 else { return nil }
            return (stream, count)
        }

        let likely = evidenceTracks.filter { stream, count in
            let title = stream.tags?["title"]?.lowercased() ?? ""
            let isSDH = stream.disposition?.hearingImpaired == 1
                || title.range(of: #"\bsdh\b"#, options: .regularExpression) != nil
                || title.contains("hearing impaired")
                || title.contains("closed captions")
            guard !isSDH, stream.codecName == "subrip", count <= 200 else { return false }

            return evidenceTracks.contains { otherStream, otherCount in
                otherStream.index != stream.index
                    && otherCount >= 300
                    && otherCount >= count * 3
            }
        }

        guard likely.count == 1, let (stream, count) = likely.first else {
            return .noForcedEnglish
        }
        let comparisonCount = evidenceTracks
            .filter { $0.0.index != stream.index }
            .map(\.1)
            .max() ?? 0
        return .likelyForcedEnglish(
            stream: stream,
            reason: "Stream \(stream.index) has \(count) subtitle events, compared with \(comparisonCount) in a fuller English track. This is statistical evidence only; confirm the track before burn-in."
        )
    }

    private func recommendFullEnglish(
        from streams: [MediaStream],
        audioLanguage: String
    ) -> SubtitleRecommendation {
        let candidates = streams.compactMap(FullEnglishCandidate.init)
        guard !candidates.isEmpty else {
            return .noFullEnglish(audioLanguage: audioLanguage)
        }

        let ordinary = candidates.filter { !$0.isSDH }
        let accessibilityPreferred = ordinary.isEmpty ? candidates : ordinary
        let textBased = accessibilityPreferred.filter(\.isTextBased)
        let preferred = textBased.isEmpty ? accessibilityPreferred : textBased
        guard preferred.count == 1, let choice = preferred.first else {
            return .ambiguousFullEnglish(candidates: preferred.map(\.stream))
        }

        let description = choice.isSDH ? "English SDH" : "ordinary full English"
        let formatReason = choice.isTextBased
            ? " It is a supported text subtitle track."
            : " It is an image-based subtitle track and requires explicit burn-in handling."
        return .fullEnglishFound(
            stream: choice.stream,
            reason: "Primary audio is explicitly \(audioLanguage). Stream \(choice.stream.index) is the preferred \(description) candidate.\(formatReason)"
        )
    }

    private func explicitForeignLanguage(_ audio: MediaStream?) -> String? {
        guard let rawLanguage = audio?.tags?["language"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawLanguage.isEmpty else { return nil }
        let language = rawLanguage.lowercased()
        guard language != "und", language != "unknown" else { return nil }
        let isEnglish = language == "eng"
            || language == "en"
            || language.hasPrefix("en-")
        return isEnglish ? nil : rawLanguage
    }
}

private extension SubtitleRecommendationEngine {
    struct Candidate {
        let stream: MediaStream
        let evidence: Evidence
        let isSDH: Bool

        init?(_ stream: MediaStream) {
            let language = stream.tags?["language"]?.lowercased()
            let title = stream.tags?["title"]?.lowercased() ?? ""

            let isEnglish = language == "eng"
                || language == "en"
                || language?.hasPrefix("en-") == true
                || title.contains("english")
            guard isEnglish else { return nil }

            if stream.disposition?.forced == 1 {
                evidence = .disposition
            } else if title.range(of: #"\bforced\b"#, options: .regularExpression) != nil
                        || title.contains("foreign parts only") {
                evidence = .title
            } else {
                return nil
            }

            self.stream = stream
            isSDH = stream.disposition?.hearingImpaired == 1
                || title.range(of: #"\bsdh\b"#, options: .regularExpression) != nil
                || title.contains("hearing impaired")
                || title.contains("closed captions")
        }
    }

    struct FullEnglishCandidate {
        let stream: MediaStream
        let isSDH: Bool
        let isTextBased: Bool

        init?(_ stream: MediaStream) {
            let language = stream.tags?["language"]?.lowercased()
            let title = stream.tags?["title"]?.lowercased() ?? ""
            let isEnglish = language == "eng"
                || language == "en"
                || language?.hasPrefix("en-") == true
                || title.contains("english")
            guard isEnglish else { return nil }

            let isForced = stream.disposition?.forced == 1
                || title.range(of: #"\bforced\b"#, options: .regularExpression) != nil
                || title.contains("foreign parts only")
            guard !isForced else { return nil }

            self.stream = stream
            isTextBased = stream.codecName == "subrip"
            isSDH = stream.disposition?.hearingImpaired == 1
                || title.range(of: #"\bsdh\b"#, options: .regularExpression) != nil
                || title.contains("hearing impaired")
                || title.contains("closed captions")
        }
    }

    enum Evidence: Int, Comparable {
        case title
        case disposition

        static func < (lhs: Evidence, rhs: Evidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
