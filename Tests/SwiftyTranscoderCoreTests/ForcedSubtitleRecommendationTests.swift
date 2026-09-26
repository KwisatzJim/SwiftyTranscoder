import Testing
@testable import SwiftyTranscoderCore

struct ForcedSubtitleRecommendationTests {
    @Test func forcedDispositionBeatsTitleOnlyEvidence() {
        let titled = mediaStream(index: 2, codecName: "subrip", codecType: "subtitle", tags: ["language": "eng", "title": "English Forced"])
        let flagged = mediaStream(index: 3, codecName: "subrip", codecType: "subtitle", tags: ["language": "eng"], forced: 1)
        let result = SubtitleRecommendationEngine().recommend(from: [titled, flagged], primaryAudio: nil)
        guard case .forcedEnglishFound(let stream, _) = result else {
            Issue.record("Expected a forced-English recommendation")
            return
        }
        #expect(stream.index == 3)
    }

    @Test func nonSDHIsPreferredAmongEqualForcedCandidates() {
        let ordinary = mediaStream(index: 2, codecName: "subrip", codecType: "subtitle", tags: ["language": "eng"], forced: 1)
        let sdh = mediaStream(index: 3, codecName: "subrip", codecType: "subtitle", tags: ["language": "eng", "title": "English SDH"], forced: 1, hearingImpaired: 1)
        let result = SubtitleRecommendationEngine().recommend(from: [sdh, ordinary], primaryAudio: nil)
        guard case .forcedEnglishFound(let stream, _) = result else {
            Issue.record("Expected one preferred forced-English track")
            return
        }
        #expect(stream.index == 2)
    }

    @Test func sparseEnglishTrackIsPresentedForConfirmation() {
        let sparse = mediaStream(
            index: 2,
            codecName: "subrip",
            codecType: "subtitle",
            tags: ["language": "eng", "NUMBER_OF_FRAMES": "17"]
        )
        let full = mediaStream(
            index: 3,
            codecName: "subrip",
            codecType: "subtitle",
            tags: ["language": "eng", "title": "English SDH", "NUMBER_OF_FRAMES": "814"],
            hearingImpaired: 1
        )

        let result = SubtitleRecommendationEngine().recommend(from: [sparse, full], primaryAudio: nil)
        guard case .likelyForcedEnglish(let stream, let reason) = result else {
            Issue.record("Expected a confirmation-only likely-forced result")
            return
        }
        #expect(stream.index == 2)
        #expect(reason.contains("17 subtitle events"))
    }

    @Test func sparseTrackWithoutFullEnglishComparisonIsNotGuessed() {
        let sparse = mediaStream(
            index: 2,
            codecName: "subrip",
            codecType: "subtitle",
            tags: ["language": "eng", "NUMBER_OF_FRAMES": "17"]
        )

        let result = SubtitleRecommendationEngine().recommend(from: [sparse], primaryAudio: nil)
        guard case .noForcedEnglish = result else {
            Issue.record("A sparse track alone must not be treated as likely forced")
            return
        }
    }

    @Test func multipleSparseCandidatesRemainUnselected() {
        let first = mediaStream(
            index: 2,
            codecName: "subrip",
            codecType: "subtitle",
            tags: ["language": "eng", "NUMBER_OF_FRAMES": "17"]
        )
        let second = mediaStream(
            index: 3,
            codecName: "subrip",
            codecType: "subtitle",
            tags: ["language": "eng", "NUMBER_OF_FRAMES": "22"]
        )
        let full = mediaStream(
            index: 4,
            codecName: "subrip",
            codecType: "subtitle",
            tags: ["language": "eng", "NUMBER_OF_FRAMES": "800"]
        )

        let result = SubtitleRecommendationEngine().recommend(
            from: [first, second, full],
            primaryAudio: nil
        )
        guard case .noForcedEnglish = result else {
            Issue.record("Multiple statistical candidates must not produce a recommendation")
            return
        }
    }
}
