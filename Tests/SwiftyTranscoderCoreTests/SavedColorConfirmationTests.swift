import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct SavedColorConfirmationTests {
    @Test @MainActor func remembersAcrossInstancesAndForgets() async throws {
        let suite = "SwiftyTranscoder.ColorConfirmationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = ColorConfirmationIdentity(path: "/tmp/example.mkv", size: 4,
            modified: Date(timeIntervalSince1970: 100), fileNumber: 10, sha256: "abc")
        let store = SavedColorConfirmation(defaults: defaults)
        #expect(!store.isConfirmed(identity))
        store.remember(identity)
        #expect(SavedColorConfirmation(defaults: defaults).isConfirmed(identity))
        store.forget(identity)
        #expect(!SavedColorConfirmation(defaults: defaults).isConfirmed(identity))
    }

    @Test @MainActor func changedContentsInvalidateEvenWithSameSizeAndTimestamp() async throws {
        let suite = "SwiftyTranscoder.ColorConfirmationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("video.mkv")
        try Data("AAAA".utf8).write(to: file)
        let original = try await ColorConfirmationIdentity.read(file)
        let store = SavedColorConfirmation(defaults: defaults)
        store.remember(original)
        #expect(store.isConfirmed(try await ColorConfirmationIdentity.read(file)))
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("BBBB".utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: original.modified], ofItemAtPath: file.path)
        let changed = try await ColorConfirmationIdentity.read(file)
        #expect(changed.size == original.size)
        #expect(changed.sha256 != original.sha256)
        #expect(!store.isConfirmed(changed))
    }

    @Test @MainActor func differentPathAndModificationDoNotReuseConfirmation() {
        let suite = "SwiftyTranscoder.ColorConfirmationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = ColorConfirmationIdentity(path: "/tmp/a.mkv", size: 4, modified: Date(timeIntervalSince1970: 100), fileNumber: 10, sha256: "abc")
        let store = SavedColorConfirmation(defaults: defaults)
        store.remember(original)
        #expect(!store.isConfirmed(ColorConfirmationIdentity(path: "/tmp/b.mkv", size: 4, modified: original.modified, fileNumber: 10, sha256: "abc")))
        #expect(!store.isConfirmed(ColorConfirmationIdentity(path: original.path, size: 4, modified: Date(timeIntervalSince1970: 200), fileNumber: 10, sha256: "abc")))
    }
}
