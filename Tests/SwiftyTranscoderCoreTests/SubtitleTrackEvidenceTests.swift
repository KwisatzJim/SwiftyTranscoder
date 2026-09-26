import Testing
@testable import SwiftyTranscoderCore

struct SubtitleTrackEvidenceTests {
    @Test func readsMatroskaStatisticsWithoutChangingRecommendationData() throws {
        let stream = mediaStream(
            index: 2,
            codecName: "subrip",
            codecType: "subtitle",
            tags: [
                "language": "eng",
                "NUMBER_OF_FRAMES": "17",
                "DURATION": "00:14:50.473000000"
            ]
        )

        let evidence = try #require(stream.subtitleEvidence)
        #expect(evidence.eventCount == 17)
        #expect(evidence.trackSpanSeconds == 890.473)
    }

    @Test func acceptsCaseInsensitiveTagNames() throws {
        let stream = mediaStream(
            codecType: "subtitle",
            tags: ["number_of_frames": "814", "duration": "00:55:20.275"]
        )

        let evidence = try #require(stream.subtitleEvidence)
        #expect(evidence.eventCount == 814)
        #expect(evidence.trackSpanSeconds == 3_320.275)
    }

    @Test func ignoresMissingMalformedAndNonSubtitleEvidence() {
        let missing = mediaStream(codecType: "subtitle", tags: ["language": "eng"])
        let malformed = mediaStream(
            codecType: "subtitle",
            tags: ["NUMBER_OF_FRAMES": "unknown", "DURATION": "not-a-time"]
        )
        let audio = mediaStream(
            codecType: "audio",
            tags: ["NUMBER_OF_FRAMES": "17", "DURATION": "00:14:50.473"]
        )

        #expect(missing.subtitleEvidence == nil)
        #expect(malformed.subtitleEvidence == nil)
        #expect(audio.subtitleEvidence == nil)
    }
}
