import Testing
@testable import SwiftyTranscoderCore

struct ForeignSubtitleRecommendationTests {
    @Test func foreignAudioPrefersOrdinaryFullEnglishOverSDH() {
        let audio = mediaStream(codecName: "aac", codecType: "audio", tags: ["language": "rus"])
        let ordinary = mediaStream(index: 2, codecName: "subrip", codecType: "subtitle", tags: ["language": "eng", "title": "English"])
        let sdh = mediaStream(index: 3, codecName: "subrip", codecType: "subtitle", tags: ["language": "eng", "title": "English SDH"], hearingImpaired: 1)
        let result = SubtitleRecommendationEngine().recommend(from: [sdh, ordinary], primaryAudio: audio)
        guard case .fullEnglishFound(let stream, _) = result else {
            Issue.record("Expected a full-English recommendation")
            return
        }
        #expect(stream.index == 2)
    }

    @Test func foreignAudioPrefersSupportedTextOverImageSubtitle() {
        let audio = mediaStream(codecName: "aac", codecType: "audio", tags: ["language": "jpn"])
        let image = mediaStream(index: 2, codecName: "hdmv_pgs_subtitle", codecType: "subtitle", tags: ["language": "eng"])
        let text = mediaStream(index: 3, codecName: "subrip", codecType: "subtitle", tags: ["language": "eng"])
        let result = SubtitleRecommendationEngine().recommend(from: [image, text], primaryAudio: audio)
        guard case .fullEnglishFound(let stream, _) = result else {
            Issue.record("Expected the supported text candidate")
            return
        }
        #expect(stream.index == 3)
    }
}
