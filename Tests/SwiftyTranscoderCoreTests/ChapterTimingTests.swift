import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct ChapterTimingTests {
    @Test func preservesValidChapters() throws {
        #expect(try inspection([[0, 50], [50, 100]]).chaptersAreSafeToCopy)
    }

    @Test func rejectsMovieChaptersExtendingToTwentyOneHours() throws {
        #expect(try !inspection([[0, 8700.672], [10000, 10000], [44000, 44000], [78000, 78000]], duration: 8700.672).chaptersAreSafeToCopy)
    }

    @Test func rejectsNegativeReversedAndMissingTiming() throws {
        #expect(try !inspection([[-1, 50]]).chaptersAreSafeToCopy)
        #expect(try !inspection([[50, 20]]).chaptersAreSafeToCopy)
        #expect(try !inspection([[100, 100]]).chaptersAreSafeToCopy)
        let missing = try JSONDecoder().decode(MediaInspection.self, from: Data(#"{"streams":[],"chapters":[{"id":0}],"format":{"duration":"100"}}"#.utf8))
        #expect(!missing.chaptersAreSafeToCopy)
    }

    private func inspection(_ times: [[Double]], duration: Double = 100) throws -> MediaInspection {
        let chapters = times.enumerated().map { index, times in
            ["id": index, "start_time": String(times[0]), "end_time": String(times[1])] as [String: Any]
        }
        let json = try JSONSerialization.data(withJSONObject: ["streams": [], "chapters": chapters, "format": ["duration": String(duration)]])
        return try JSONDecoder().decode(MediaInspection.self, from: json)
    }
}
