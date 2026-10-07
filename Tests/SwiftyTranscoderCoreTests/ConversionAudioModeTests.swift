import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct ConversionAudioModeTests {
    @Test func removalUsesVideoDurationWhenAudioRunsLonger() throws {
        let inspection = try decode("\"duration\":\"10.01\",")
        #expect(ConversionAudioMode.omit.expectedDuration(in: inspection) == 10.01)
        #expect(ConversionAudioMode.convert.expectedDuration(in: inspection) == 12)
    }

    @Test func usesMatroskaVideoTagOrFrameCountWithoutCountingAudioTail() throws {
        let tagged = try decode("\"tags\":{\"DURATION\":\"00:00:10.010000000\"},")
        #expect(ConversionAudioMode.omit.expectedDuration(in: tagged) == 10.01)
        let counted = try decode("\"nb_frames\":\"240\",\"avg_frame_rate\":\"24000/1001\",")
        #expect(ConversionAudioMode.omit.expectedDuration(in: counted) == 10.01)
    }

    @Test func rejectsInvalidVideoDurationsAndFallsBackToContainer() throws {
        let inspection = try decode("\"duration\":\"nan\",\"tags\":{\"DURATION\":\"bad\"},")
        #expect(ConversionAudioMode.omit.expectedDuration(in: inspection) == 12)
        #expect(try decode("\"duration\":\"nan\",", container: "nan").format.duration == "nan")
        #expect(ConversionAudioMode.omit.expectedDuration(in: try decode("", container: "nan")) == nil)
    }

    private func decode(_ fields: String, container: String = "12") throws -> MediaInspection {
        let json = """
        {"streams":[{\(fields)"index":0,"codec_type":"video"}],"chapters":[],"format":{"duration":"\(container)","size":"1000"}}
        """
        return try JSONDecoder().decode(MediaInspection.self, from: Data(json.utf8))
    }
}
