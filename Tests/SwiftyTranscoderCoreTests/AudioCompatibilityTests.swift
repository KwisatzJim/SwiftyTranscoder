import Testing
@testable import SwiftyTranscoderCore

struct AudioCompatibilityTests {
    @Test(arguments: [(Int, String, String)]([
        (1, "mono", "96000"), (2, "stereo", "192000"),
        (6, "5.1", "224000"), (6, "5.1(side)", "224000")
    ]))
    func acceptsSupportedLayouts(channels: Int, layout: String, bitRate: String) {
        let source = mediaStream(codecType: "audio", channels: channels, channelLayout: layout)
        #expect(CompatibilityAudioSettings(source: source)?.bitRate == bitRate)
    }

    @Test func rejectsUnsupportedSevenPointOne() {
        let source = mediaStream(codecType: "audio", channels: 8, channelLayout: "7.1")
        #expect(CompatibilityAudioSettings(source: source) == nil)
    }
}
