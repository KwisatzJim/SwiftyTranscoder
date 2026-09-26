import Testing
@testable import SwiftyTranscoderCore

struct VideoSummaryTests {
    @Test(arguments: [(String?, String)]([
        ("bt709", "SDR"), ("smpte2084", "HDR (PQ)"),
        ("arib-std-b67", "HDR (HLG)"), (nil, "Not identified")
    ]))
    func classifiesDynamicRange(transfer: String?, expected: String) {
        let summary = VideoSummary(stream: mediaStream(codecType: "video", colorTransfer: transfer))
        #expect(summary.dynamicRange == expected)
    }

    @Test func formatsFractionalFrameRateAndResolution() {
        let summary = VideoSummary(stream: mediaStream(
            codecName: "h264", codecType: "video", width: 1920, height: 1080,
            colorTransfer: "bt709", averageFrameRate: "24000/1001"
        ))
        #expect(summary.codec == "H.264")
        #expect(summary.resolution == "1920 × 1080")
        #expect(summary.frameRate == "23.976 fps")
    }
}
