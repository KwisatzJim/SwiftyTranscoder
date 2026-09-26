import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct OutputNamingTests {
    @Test func mkvUsesOriginalBaseName() {
        let result = OutputNaming.proposedURL(
            sourceURL: URL(fileURLWithPath: "/Source/Movie.mkv"),
            folderURL: URL(fileURLWithPath: "/Output", isDirectory: true)
        )
        #expect(result.path == "/Output/Movie.mp4")
    }

    @Test func mp4AddsSuffixToProtectSourceName() {
        let result = OutputNaming.proposedURL(
            sourceURL: URL(fileURLWithPath: "/Source/Movie.MP4"),
            folderURL: URL(fileURLWithPath: "/Output", isDirectory: true)
        )
        #expect(result.path == "/Output/Movie - SwiftyTranscoder.mp4")
    }

    @Test func m4vAlsoAddsSuffix() {
        let result = OutputNaming.proposedURL(
            sourceURL: URL(fileURLWithPath: "/Source/Movie.m4v"),
            folderURL: URL(fileURLWithPath: "/Output", isDirectory: true)
        )
        #expect(result.path == "/Output/Movie - SwiftyTranscoder.mp4")
    }
}
