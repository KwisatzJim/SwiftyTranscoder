import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct SourceFolderImportTests {
    @Test func mixedDropExpandsFoldersAndDeduplicatesDirectFiles() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let video = folder.appendingPathComponent("Episode 2.mp4")
        try Data().write(to: video)
        try Data().write(to: folder.appendingPathComponent("Episode 10.mkv"))
        let text = folder.appendingPathComponent("notes.txt")
        try Data().write(to: text)
        #expect(try SourceFolderImport.videos(fromDroppedURLs: [folder, video, folder, text, URL(string: "https://example.com/video.mp4")!]).map(\.lastPathComponent)
                == ["Episode 2.mp4", "Episode 10.mkv"])
        #expect(try SourceFolderImport.videos(fromDroppedURLs: [text]).isEmpty)
    }

    @Test func importsOnlyImmediateVisibleRegularVideosInNaturalOrder() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        for name in ["Episode 10.MKV", "Episode 2.mp4", "Episode 1.m4v", ".hidden.mp4", "notes.txt"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let nested = folder.appendingPathComponent("directory.mp4")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("nested.mp4"))
        try fm.createSymbolicLink(at: folder.appendingPathComponent("alias.mp4"),
                                  withDestinationURL: folder.appendingPathComponent("Episode 2.mp4"))
        #expect(try SourceFolderImport.videos(in: folder).map(\.lastPathComponent)
                == ["Episode 1.m4v", "Episode 2.mp4", "Episode 10.MKV"])
    }

    @Test func emptyFolderReturnsNoVideosAndMissingFolderThrows() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        #expect(try SourceFolderImport.videos(in: folder).isEmpty)
        #expect(throws: (any Error).self) {
            try SourceFolderImport.videos(in: folder.appendingPathComponent("missing"))
        }
    }
}
