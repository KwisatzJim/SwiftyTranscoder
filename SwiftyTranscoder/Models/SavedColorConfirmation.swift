import Foundation
import CryptoKit

struct ColorConfirmationIdentity: Codable, Equatable, Sendable {
    let path: String
    let size: UInt64
    let modified: Date
    let fileNumber: UInt64
    let sha256: String

    static func read(_ source: URL) async throws -> Self {
        try await Task.detached(priority: .utility) {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let url = source.resolvingSymlinksInPath().standardizedFileURL
            let before = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = before[.size] as? NSNumber,
                  let modified = before[.modificationDate] as? Date,
                  let number = before[.systemFileNumber] as? NSNumber else { throw IdentityError.unavailable }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                hash.update(data: data)
            }
            let after = try FileManager.default.attributesOfItem(atPath: url.path)
            guard size == after[.size] as? NSNumber,
                  modified == after[.modificationDate] as? Date,
                  number == after[.systemFileNumber] as? NSNumber else { throw IdentityError.changed }
            return Self(path: url.path, size: size.uint64Value, modified: modified,
                        fileNumber: number.uint64Value,
                        sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
        }.value
    }

    enum IdentityError: Error { case unavailable, changed }
}

@MainActor
struct SavedColorConfirmation {
    private let defaults: UserDefaults
    private let key = "confirmedSDRFiles.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var records: [String: ColorConfirmationIdentity] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([String: ColorConfirmationIdentity].self, from: data) else { return [:] }
        return records
    }

    func isConfirmed(_ identity: ColorConfirmationIdentity) -> Bool {
        records[identity.path] == identity
    }

    func remember(_ identity: ColorConfirmationIdentity) {
        var updated = records
        updated[identity.path] = identity
        if let data = try? JSONEncoder().encode(updated) { defaults.set(data, forKey: key) }
    }

    func forget(_ identity: ColorConfirmationIdentity) {
        var updated = records
        updated.removeValue(forKey: identity.path)
        if let data = try? JSONEncoder().encode(updated) { defaults.set(data, forKey: key) }
    }
}
