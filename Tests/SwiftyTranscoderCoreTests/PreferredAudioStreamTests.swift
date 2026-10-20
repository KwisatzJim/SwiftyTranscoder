import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct PreferredAudioStreamTests {
    private func inspection(_ streams: String) throws -> MediaInspection {
        try JSONDecoder().decode(MediaInspection.self, from: Data("""
        {"streams": [\(streams)], "chapters": [], "format": {}}
        """.utf8))
    }

    @Test(arguments: ["eng", "en", " EN-us "])
    func prefersEnglishOverFirstDefaultFrenchTrack(language: String) throws {
        let source = try inspection("""
        {"index": 1, "codec_type": "audio", "tags": {"language": "fre"}, "disposition": {"default": 1}},
        {"index": 2, "codec_type": "audio", "tags": {"language": "\(language)"}, "disposition": {"default": 0}}
        """)
        #expect(source.preferredAudioStream?.index == 2)
        #expect(source.audioStreams.first?.index == 1)
        #expect(MediaSummary(inspection: source).audio?.language == language)
        if case .noForcedEnglish = MediaSummary(inspection: source).subtitleRecommendation {
        } else {
            Issue.record("English audio should not trigger full foreign-language subtitles")
        }
    }

    @Test func preservesFirstTrackWithoutEnglishAndHandlesNoAudio() throws {
        let source = try inspection("""
        {"index": 0, "codec_type": "video", "tags": {"language": "eng"}},
        {"index": 1, "codec_type": "audio", "tags": {"language": "fre"}},
        {"index": 2, "codec_type": "audio"}
        """)
        #expect(source.preferredAudioStream?.index == 1)
        #expect(try inspection("").preferredAudioStream == nil)
    }

    @Test func preservesOrderAmongEnglishTracks() throws {
        let source = try inspection("""
        {"index": 3, "codec_type": "audio", "tags": {"language": "eng"}},
        {"index": 4, "codec_type": "audio", "tags": {"language": "eng"}}
        """)
        #expect(source.preferredAudioStream?.index == 3)
    }
}
