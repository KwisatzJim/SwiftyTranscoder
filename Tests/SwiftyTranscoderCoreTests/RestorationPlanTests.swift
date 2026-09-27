import Testing
@testable import SwiftyTranscoderCore

struct RestorationPlanTests {
    @Test func plansProvenSDSourceAtExactTwoTimesScale() {
        let result = RestorationPlanner().plan(for: inspection(video: eligibleVideo(width: 624, height: 352)))
        guard case .eligible(let plan) = result else {
            Issue.record("Expected the proven SD source to be eligible")
            return
        }
        #expect(plan.method == .realESRGANX2Plus)
        #expect(plan.outputWidth == 1248)
        #expect(plan.outputHeight == 704)
        #expect(plan.scaleDescription == "2.00×")
        #expect(plan.colorSpace == "smpte170m")
    }

    @Test func caps720pSourceAt1080pWithoutChangingAspectRatio() {
        let result = RestorationPlanner().plan(for: inspection(video: eligibleVideo(width: 1280, height: 720)))
        guard case .eligible(let plan) = result else {
            Issue.record("Expected 720p SDR to be eligible")
            return
        }
        #expect(plan.outputWidth == 1920)
        #expect(plan.outputHeight == 1080)
        #expect(plan.scaleDescription == "1.50×")
    }

    @Test(arguments: [
        (eligibleVideo(width: 1920, height: 1080), "already at or above"),
        (eligibleVideo(pixelFormat: "yuv420p10le"), "8-bit 4:2:0"),
        (eligibleVideo(colorTransfer: "smpte2084"), "limited-range SDR color metadata"),
        (eligibleVideo(colorPrimaries: nil), "limited-range SDR color metadata"),
        (eligibleVideo(averageFrameRate: "0/0"), "known, valid frame rate"),
        (eligibleVideo(codecName: "mpeg2video"), "H.264 or HEVC")
    ])
    func rejectsUnsafeSource(video: MediaStream, expectedReason: String) {
        let result = RestorationPlanner().plan(for: inspection(video: video))
        guard case .unavailable(let reason) = result else {
            Issue.record("Expected source to be unavailable")
            return
        }
        #expect(reason.contains(expectedReason))
    }

    private static func eligibleVideo(
        codecName: String = "h264",
        width: Int = 624,
        height: Int = 352,
        pixelFormat: String = "yuv420p",
        colorTransfer: String = "bt709",
        colorPrimaries: String? = "smpte170m",
        averageFrameRate: String = "24000/1001"
    ) -> MediaStream {
        mediaStream(
            codecName: codecName,
            codecType: "video",
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            colorRange: "tv",
            colorSpace: "smpte170m",
            colorTransfer: colorTransfer,
            colorPrimaries: colorPrimaries,
            averageFrameRate: averageFrameRate
        )
    }

    private func eligibleVideo(
        codecName: String = "h264",
        width: Int = 624,
        height: Int = 352,
        pixelFormat: String = "yuv420p",
        colorTransfer: String = "bt709",
        colorPrimaries: String? = "smpte170m",
        averageFrameRate: String = "24000/1001"
    ) -> MediaStream {
        Self.eligibleVideo(
            codecName: codecName,
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            colorTransfer: colorTransfer,
            colorPrimaries: colorPrimaries,
            averageFrameRate: averageFrameRate
        )
    }

    private func inspection(video: MediaStream) -> MediaInspection {
        MediaInspection(
            streams: [video],
            chapters: [],
            format: MediaFormat(
                filename: nil, streamCount: 1, formatName: nil, formatLongName: nil,
                duration: "60", size: nil, bitRate: nil, tags: nil
            )
        )
    }
}
