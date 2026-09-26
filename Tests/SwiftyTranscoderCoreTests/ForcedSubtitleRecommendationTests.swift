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
}
