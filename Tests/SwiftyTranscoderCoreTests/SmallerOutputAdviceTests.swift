import Testing
@testable import SwiftyTranscoderCore

struct SmallerOutputAdviceTests {
    @Test func commonRequestUses720pForActualSource() {
        #expect(SmallerOutputAdvice.recognizes("Make this smaller for Plex"))
        let advice = SmallerOutputAdvice.recommendation(width: 1920, height: 1078, current: .original, allowsResizing: true)
        #expect(advice.hasPrefix("Proposed Output size: 720p"))
        #expect(advice.contains("Audio settings stay unchanged"))
    }

    @Test func selected720pMovesTo480pAndNeverEnlarges() {
        #expect(SmallerOutputAdvice.recommendation(width: 1920, height: 1080, current: .p720, allowsResizing: true).hasPrefix("Proposed Output size: 480p"))
        #expect(SmallerOutputAdvice.recommendation(width: 640, height: 360, current: .original, allowsResizing: true).hasPrefix("No smaller output size"))
        #expect(SmallerOutputAdvice.recommendation(width: 1920, height: 1080, current: .p480, allowsResizing: true).hasPrefix("No smaller output size"))
    }

    @Test func respectsUnavailableResizingAndExplicitConstraints() {
        #expect(!SmallerOutputAdvice.recognizes("Make this smaller without resizing"))
        #expect(!SmallerOutputAdvice.recognizes("Don't make this smaller"))
        #expect(SmallerOutputAdvice.recommendation(width: 1920, height: 1080, current: .original, allowsResizing: false).hasPrefix("No size change proposed"))
    }
}
