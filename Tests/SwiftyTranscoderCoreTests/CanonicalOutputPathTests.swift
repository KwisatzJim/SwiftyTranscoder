import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct CanonicalOutputPathTests {
    @Test func filenameCaseDifferencesCollideConservatively() {
        let first = URL(fileURLWithPath: "/tmp/Example Movie.mp4")
        let second = URL(fileURLWithPath: "/tmp/example movie.MP4")
        #expect(CanonicalOutputPath.key(for: first) == CanonicalOutputPath.key(for: second))
    }

    @Test func canonicallyEquivalentUnicodeNamesCollide() {
        let composed = URL(fileURLWithPath: "/tmp/Caf\u{00E9}.mp4")
        let decomposed = URL(fileURLWithPath: "/tmp/Cafe\u{0301}.mp4")
        #expect(CanonicalOutputPath.key(for: composed) == CanonicalOutputPath.key(for: decomposed))
    }

    @Test func differentFilenamesRemainDistinct() {
        let first = URL(fileURLWithPath: "/tmp/First.mp4")
        let second = URL(fileURLWithPath: "/tmp/Second.mp4")
        #expect(CanonicalOutputPath.key(for: first) != CanonicalOutputPath.key(for: second))
    }
}
