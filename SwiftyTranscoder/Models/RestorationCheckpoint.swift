import CryptoKit
import Foundation

struct RestorationCheckpointIdentity: Codable, Equatable, Sendable {
    let sourceSHA256: String
    let settingsSHA256: String

    /// The caller must supply a signature covering the model and processing version.
    static func make(for request: FullVideoRestorationRequest, engineSignature: String) throws -> Self {
        guard !engineSignature.isEmpty else { throw RestorationCheckpointError.invalidRecord }
        let plan = request.plan
        let audio = request.sourceAudio
        let settings: [String: Any] = [
            "engine": engineSignature,
            "source": CanonicalOutputPath.key(for: request.sourceURL.resolvingSymlinksInPath()),
            "output": CanonicalOutputPath.key(for: request.finalOutputURL.resolvingSymlinksInPath()),
            "method": plan.method.rawValue,
            "sourceWidth": plan.sourceWidth, "sourceHeight": plan.sourceHeight,
            "outputWidth": plan.outputWidth, "outputHeight": plan.outputHeight,
            "frameRate": plan.frameRate, "frames": request.totalFrameCount,
            "duration": request.durationSeconds,
            "colorRange": plan.colorRange, "colorSpace": plan.colorSpace,
            "colorTransfer": plan.colorTransfer, "colorPrimaries": plan.colorPrimaries,
            "chunkLimit": RestorationChunkPlan.defaultFrameLimit,
            "gain": request.gainEnabled, "aacStereo": request.aacStereoEnabled,
            "subtitle": request.subtitleStreamOrdinal.map { $0 as Any } ?? NSNull(),
            "chapters": request.expectedChapterCount,
            "title": request.expectedContainerTitle.map { $0 as Any } ?? NSNull(),
            "audioIndex": audio.index, "audioCodec": audio.codecName ?? "",
            "audioChannels": audio.channels ?? 0, "audioLayout": audio.channelLayout ?? "",
            "audioSampleRate": audio.sampleRate ?? "", "audioBitRate": audio.bitRate ?? ""
        ]
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
        return Self(sourceSHA256: try fileSHA256(request.sourceURL), settingsSHA256: digest(data))
    }

    static func fileSHA256(_ url: URL) throws -> String {
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw RestorationCheckpointError.invalidRecord
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct RestorationSavedSegment: Codable, Equatable, Sendable {
    let index: Int
    let startFrame: Int64
    let frameCount: Int
    let bytes: Int
    let sha256: String
}

struct RestorationCheckpoint: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let identity: RestorationCheckpointIdentity
    var segments: [RestorationSavedSegment]
}

/// Completed-segment ledger used by explicit resumable restoration sessions.
actor RestorationCheckpointStore {
    private let workspace: URL
    private let plan: RestorationChunkPlan
    private var recordURL: URL { workspace.appendingPathComponent("restoration-checkpoint.json") }

    init(workspace: URL, plan: RestorationChunkPlan) throws {
        guard workspace.lastPathComponent.hasPrefix("SwiftyTranscoder-Restoration-"),
              plan.chunks.allSatisfy({ $0.workspaceURL.deletingLastPathComponent().standardizedFileURL.path == workspace.standardizedFileURL.path }) else {
            throw RestorationCheckpointError.invalidRecord
        }
        self.workspace = workspace
        self.plan = plan
    }

    func create(identity: RestorationCheckpointIdentity) throws {
        try checkWorkspace()
        guard !FileManager.default.fileExists(atPath: recordURL.path) else {
            throw RestorationCheckpointError.recordExists
        }
        let record = RestorationCheckpoint(schemaVersion: 1, identity: identity, segments: [])
        try validate(record, identity: identity)
        let staged = workspace.appendingPathComponent(".restoration-checkpoint-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: staged) }
        try encode(record).write(to: staged, options: .withoutOverwriting)
        try FileManager.default.moveItem(at: staged, to: recordURL)
    }

    /// Call only after the segment has passed the normal media validation.
    func recordValidatedSegment(_ chunk: RestorationChunk, identity: RestorationCheckpointIdentity) throws {
        var record = try read(identity: identity)
        guard record.segments.count < plan.chunks.count,
              plan.chunks[record.segments.count] == chunk else {
            throw RestorationCheckpointError.invalidRecord
        }
        let file = segmentURL(chunk.index)
        try checkSegment(file)
        let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes > 0 else { throw RestorationCheckpointError.invalidRecord }
        record.segments.append(RestorationSavedSegment(
            index: chunk.index, startFrame: chunk.startFrame, frameCount: chunk.frameCount,
            bytes: bytes, sha256: try RestorationCheckpointIdentity.fileSHA256(file)
        ))
        // Replacement is limited to a previously validated, matching record.
        try encode(record).write(to: recordURL, options: .atomic)
    }

    /// Rehash all saved segments before any future caller reuses them.
    func load(identity: RestorationCheckpointIdentity) throws -> RestorationCheckpoint {
        let record = try read(identity: identity)
        for segment in record.segments {
            let file = segmentURL(segment.index)
            try checkSegment(file)
            guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == segment.bytes,
                  try RestorationCheckpointIdentity.fileSHA256(file) == segment.sha256 else {
                throw RestorationCheckpointError.segmentChanged
            }
        }
        return record
    }

    private func read(identity: RestorationCheckpointIdentity) throws -> RestorationCheckpoint {
        try checkWorkspace()
        let values = try recordURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 4_194_304 else { throw RestorationCheckpointError.invalidRecord }
        let record = try JSONDecoder().decode(RestorationCheckpoint.self, from: Data(contentsOf: recordURL))
        try validate(record, identity: identity)
        return record
    }

    private func validate(_ record: RestorationCheckpoint, identity: RestorationCheckpointIdentity) throws {
        guard record.schemaVersion == 1, record.identity == identity else {
            throw RestorationCheckpointError.identityMismatch
        }
        func validHash(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        guard validHash(identity.sourceSHA256), validHash(identity.settingsSHA256),
              record.segments.count <= plan.chunks.count else { throw RestorationCheckpointError.invalidRecord }
        for (offset, segment) in record.segments.enumerated() {
            let chunk = plan.chunks[offset]
            guard segment.index == chunk.index, segment.startFrame == chunk.startFrame,
                  segment.frameCount == chunk.frameCount, segment.bytes > 0,
                  validHash(segment.sha256) else { throw RestorationCheckpointError.invalidRecord }
        }
    }

    private func checkWorkspace() throws {
        let values = try workspace.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw RestorationCheckpointError.invalidRecord
        }
    }

    private func checkSegment(_ url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let file = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              file.isRegularFile == true, file.isSymbolicLink != true else {
            throw RestorationCheckpointError.invalidRecord
        }
    }

    private func segmentURL(_ index: Int) -> URL {
        workspace.appendingPathComponent("segments").appendingPathComponent(String(format: "segment-%06d.partial.mp4", index))
    }

    private func encode(_ record: RestorationCheckpoint) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard data.count <= 4_194_304 else { throw RestorationCheckpointError.invalidRecord }
        return data
    }
}

enum RestorationCheckpointError: LocalizedError, Equatable {
    case invalidRecord, recordExists, identityMismatch, segmentChanged
    var errorDescription: String? {
        switch self {
        case .invalidRecord: "The saved restoration progress is invalid."
        case .recordExists: "Saved restoration progress already exists and will not be replaced."
        case .identityMismatch: "The source, settings, or processing version differs from the saved restoration."
        case .segmentChanged: "A completed restoration segment has changed."
        }
    }
}
