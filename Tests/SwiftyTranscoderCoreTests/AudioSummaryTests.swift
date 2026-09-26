import Testing
@testable import SwiftyTranscoderCore

struct AudioSummaryTests {
    @Test func describesFivePointOneAndAtmosMetadata() {
        let summary = AudioSummary(stream: mediaStream(
            codecName: "eac3", codecType: "audio", channels: 6,
            channelLayout: "5.1(side)", tags: ["language": "eng", "title": "Dolby Atmos"]
        ))
        #expect(summary.codec == "Dolby Digital Plus")
        #expect(summary.layout == "5.1 surround")
        #expect(summary.language == "eng")
        #expect(summary.advancedFormat == "Atmos indicated by metadata")
    }

    @Test func doesNotInventAtmosWhenMetadataIsSilent() {
        let summary = AudioSummary(stream: mediaStream(
            codecName: "dts", codecType: "audio", channels: 6, channelLayout: "5.1"
        ))
        #expect(summary.codec == "DTS")
        #expect(summary.advancedFormat == nil)
    }
}
