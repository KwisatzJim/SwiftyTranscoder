import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct ColorSamplePlanTests {
    @Test func samplesStartMiddleAndNearEnd() {
        let plan = ColorSamplePlan(duration: "120")
        #expect(plan.readIntervals == "0%+#48,60.000%+#48,108.000%+#48")
        #expect(plan.description.contains("50%"))
        #expect(plan.description.contains("90%"))
    }

    @Test func safelyHandlesUnknownOrShortDuration() {
        for duration in [nil, "N/A", "nan", "inf", "-1", "0", "2", "4"] as [String?] {
            #expect(ColorSamplePlan(duration: duration).readIntervals == "%+#48")
        }
    }

    @Test func conflictingEvidenceAcrossSamplesCannotBecomeSDR() throws {
        let data = Data(#"{"frames":[{"color_transfer":"bt709","color_space":"bt709"},{"color_transfer":"bt709","color_space":"smpte170m"}]}"#.utf8)
        let evidence = try JSONDecoder().decode(FrameColorEvidence.self, from: data)
        let result = evidence.applying(to: mediaStream(codecType: "video"), sampleDescription: ColorSamplePlan(duration: "120").description)
        #expect(VideoSummary(stream: result).dynamicRange == "Not identified")
        #expect(result.colorInspectionNote?.contains("Conflicting") == true)
    }
}
