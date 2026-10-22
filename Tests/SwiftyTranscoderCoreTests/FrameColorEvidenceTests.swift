import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct FrameColorEvidenceTests {
    private func evidence(_ json: String) throws -> FrameColorEvidence {
        try JSONDecoder().decode(FrameColorEvidence.self, from: Data(json.utf8))
    }

    @Test func recoversExplicitSDRFromFrames() throws {
        let result = try evidence(#"{"frames":[{"color_transfer":"bt709","color_primaries":"bt709","color_space":"bt709"},{"color_transfer":"bt709","color_primaries":"bt709","color_space":"bt709"}]}"#)
            .applying(to: mediaStream(codecType: "video"))
        #expect(result.colorTransfer == "bt709")
        #expect(result.colorPrimaries == "bt709")
        #expect(VideoSummary(stream: result).dynamicRange == "SDR")
    }

    @Test func missingAndIncompleteTagsNeverImplySDR() throws {
        for json in [#"{"frames":[]}"#, #"{"frames":[{}]}"#,
                     #"{"frames":[{"color_transfer":"bt709"},{}]}"#,
                     #"{"frames":[{"color_transfer":"unknown"}]}"#] {
            let result = try evidence(json).applying(to: mediaStream(codecType: "video"))
            #expect(VideoSummary(stream: result).dynamicRange == "Not identified")
        }
    }

    @Test func conflictsDoNotUnlockSDR() throws {
        let result = try evidence(#"{"frames":[{"color_transfer":"bt709"},{"color_transfer":"smpte2084"}]}"#)
            .applying(to: mediaStream(codecType: "video"))
        #expect(VideoSummary(stream: result).dynamicRange != "SDR")
        let conflictingStream = try evidence(#"{"frames":[{"color_transfer":"smpte2084"}]}"#)
            .applying(to: mediaStream(codecType: "video", colorTransfer: "bt709"))
        #expect(VideoSummary(stream: conflictingStream).dynamicRange != "SDR")
    }

    @Test func detectsHDRSideDataDespiteSDRTag() throws {
        let result = try evidence(#"{"frames":[{"color_transfer":"bt709","side_data_list":[{"side_data_type":"Mastering display metadata"}]}]}"#)
            .applying(to: mediaStream(codecType: "video"))
        #expect(VideoSummary(stream: result).dynamicRange == "HDR (metadata)")
    }

    @Test func recoversPQAndHLGWithoutAssumingSDR() throws {
        for transfer in ["smpte2084", "arib-std-b67"] {
            let result = try evidence("{\"frames\":[{\"color_transfer\":\"\(transfer)\"}]}")
                .applying(to: mediaStream(codecType: "video"))
            #expect(VideoSummary(stream: result).dynamicRange.hasPrefix("HDR"))
        }
    }
}
