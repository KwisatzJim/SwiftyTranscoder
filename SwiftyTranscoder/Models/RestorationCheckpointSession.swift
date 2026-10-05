import Darwin
import Foundation

/// Explicit opt-in: a fresh saved job or reuse of a matching saved job.
enum RestorationCheckpointMode: Sendable { case create, resume }

actor RestorationCheckpointSession {
    private let workspace: URL
    private let mode: RestorationCheckpointMode
    private let identity: RestorationCheckpointIdentity
    private let plan: RestorationChunkPlan
    private let store: RestorationCheckpointStore
    private var descriptor: Int32 = -1
    private var initialSavedFrames: Int64 = 0
    private var savedCount = 0
    private var prepared = false

    init(request: FullVideoRestorationRequest, identity: RestorationCheckpointIdentity, mode: RestorationCheckpointMode) throws {
        workspace = request.workspaceURL
        self.mode = mode
        self.identity = identity
        plan = try RestorationChunkPlan(totalFrameCount: request.totalFrameCount, frameRate: request.plan.frameRate, workspaceURL: request.workspaceURL)
        store = try RestorationCheckpointStore(workspace: request.workspaceURL, plan: plan)
    }

    deinit { if descriptor >= 0 { close(descriptor) } }

    func prepare() async throws {
        guard !prepared, descriptor < 0 else { throw RestorationCheckpointError.invalidRecord }
        if mode == .create {
            // No reuse or replacement, even when an existing folder happens to be empty.
            guard mkdir(workspace.path, S_IRWXU) == 0 else { throw FullVideoRestorationError.workspaceExists }
        }
        let values = try workspace.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw RestorationCheckpointError.invalidRecord }
        let lock = workspace.appendingPathComponent("restoration.lock")
        let fd = open(lock.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw RestorationCheckpointSessionError.alreadyActive
        }
        descriptor = fd
        do {
            switch mode {
            case .create: try await store.create(identity: identity)
            case .resume:
                let record = try await store.load(identity: identity)
                savedCount = record.segments.count
                initialSavedFrames = record.segments.reduce(0) { $0 + Int64($1.frameCount) }
                try discardInterruptedWork()
            }
            prepared = true
        } catch {
            close(fd)
            descriptor = -1
            throw error
        }
    }

    func savedFrameCountAtStart() -> Int64 { initialSavedFrames }

    func savedSegmentURLs() -> [URL] {
        guard prepared else { return [] }
        return plan.chunks.prefix(savedCount).map { segmentURL($0.index) }
    }

    func record(_ chunk: RestorationChunk) async throws {
        guard prepared, descriptor >= 0 else { throw RestorationCheckpointError.invalidRecord }
        try await store.recordValidatedSegment(chunk, identity: identity)
        savedCount += 1
    }

    func finish(success: Bool) {
        guard descriptor >= 0 else { return }
        // Hold ownership until cleanup finishes. Interrupted jobs keep their ledger and segments.
        if success, prepared { try? FileManager.default.removeItem(at: workspace) }
        close(descriptor)
        descriptor = -1
        prepared = false
    }

    private func segmentURL(_ index: Int) -> URL {
        workspace.appendingPathComponent("segments").appendingPathComponent(String(format: "segment-%06d.partial.mp4", index))
    }

    private func discardInterruptedWork() throws {
        // First validate every candidate. Unknown files are refused, never removed.
        let manager = FileManager.default
        var disposable: [URL] = []
        let chunks = Set(plan.chunks.map { $0.workspaceURL.lastPathComponent })
        for entry in try manager.contentsOfDirectory(at: workspace, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            guard try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw RestorationCheckpointError.invalidRecord }
            let name = entry.lastPathComponent
            if ["restoration-checkpoint.json", "restoration.lock"].contains(name) { continue }
            if name == "segments" {
                guard try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw RestorationCheckpointError.invalidRecord }
                let expected = Dictionary(uniqueKeysWithValues: plan.chunks.map { (segmentURL($0.index).lastPathComponent, $0.index) })
                for segment in try manager.contentsOfDirectory(at: entry, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
                    let values = try segment.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard let index = expected[segment.lastPathComponent], values.isRegularFile == true, values.isSymbolicLink != true else { throw RestorationCheckpointError.invalidRecord }
                    if index > savedCount { disposable.append(segment) }
                }
            } else if chunks.contains(name) || ["restoration-segments.ffconcat", "restored-silent.partial.mp4", "restored-audio.partial.mp4"].contains(name) {
                disposable.append(entry)
            } else if name.hasPrefix(".restoration-checkpoint-"), name.hasSuffix(".tmp"),
                      UUID(uuidString: String(name.dropFirst(".restoration-checkpoint-".count).dropLast(4))) != nil {
                disposable.append(entry)
            } else { throw RestorationCheckpointError.invalidRecord }
        }
        for entry in disposable { try manager.removeItem(at: entry) }
    }

    /// Changes to the model, helper executable, or frame-processing contract invalidate reuse.
    static func engineSignature(model: URL, ffmpeg: URL) throws -> String {
        let manager = FileManager.default
        guard let iterator = manager.enumerator(at: model, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw RestorationCheckpointError.invalidRecord }
        var files: [URL] = []
        for case let file as URL in iterator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw RestorationCheckpointError.invalidRecord }
            if values.isRegularFile == true { files.append(file) }
        }
        guard !files.isEmpty else { throw RestorationCheckpointError.invalidRecord }
        var signature = "restoration-contract-v1;tiling-v1;png-rgba-srgb-v1;chunks-120;"
        for file in files.sorted(by: { $0.path < $1.path }) {
            signature += String(file.path.dropFirst(model.path.count)) + ":" + (try RestorationCheckpointIdentity.fileSHA256(file)) + ";"
        }
        signature += try RestorationCheckpointIdentity.fileSHA256(ffmpeg)
        return signature
    }
}

enum RestorationCheckpointSessionError: LocalizedError {
    case alreadyActive
    var errorDescription: String? { "Another restoration is already using this saved job. Stop that run before resuming." }
}
