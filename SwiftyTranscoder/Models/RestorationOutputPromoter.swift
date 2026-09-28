import Foundation

struct RestorationOutputPromotion: Equatable, Sendable {
    let validatedOutputURL: URL
    let partialOutputURL: URL
    let finalOutputURL: URL

    init(
        validatedOutputURL: URL,
        workspaceURL: URL,
        sourceURL: URL,
        finalOutputURL: URL
    ) throws {
        let expectedValidatedURL = workspaceURL.appendingPathComponent(
            "restored-audio.partial.mp4"
        )
        guard validatedOutputURL.standardizedFileURL == expectedValidatedURL.standardizedFileURL else {
            throw RestorationOutputPromoterError.unapprovedValidatedOutput
        }
        guard finalOutputURL.pathExtension.lowercased() == "mp4" else {
            throw RestorationOutputPromoterError.outputMustBeMP4
        }

        let partialOutputURL = finalOutputURL
            .deletingPathExtension()
            .appendingPathExtension("partial")
            .appendingPathExtension("mp4")
        let sourceKey = CanonicalOutputPath.key(for: sourceURL)
        let finalKey = CanonicalOutputPath.key(for: finalOutputURL)
        let partialKey = CanonicalOutputPath.key(for: partialOutputURL)
        guard sourceKey != finalKey, sourceKey != partialKey else {
            throw RestorationOutputPromoterError.outputMatchesSource
        }
        guard CanonicalOutputPath.key(for: validatedOutputURL) != finalKey,
              CanonicalOutputPath.key(for: validatedOutputURL) != partialKey else {
            throw RestorationOutputPromoterError.workspaceMatchesDestination
        }

        self.validatedOutputURL = validatedOutputURL
        self.partialOutputURL = partialOutputURL
        self.finalOutputURL = finalOutputURL
    }
}

struct RestorationOutputPromoter {
    static let destinationReserveBytes: Int64 = 1_073_741_824

    private let fileManager: FileManager
    private let availableCapacity: (URL) -> Int64?

    init(
        fileManager: FileManager = .default,
        availableCapacity: @escaping (URL) -> Int64? = { directory in
            try? directory.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
        }
    ) {
        self.fileManager = fileManager
        self.availableCapacity = availableCapacity
    }

    func stage(_ request: RestorationOutputPromotion) throws -> URL {
        let destinationDirectory = request.finalOutputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destinationDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw RestorationOutputPromoterError.destinationFolderMissing
        }
        guard !fileManager.fileExists(atPath: request.finalOutputURL.path) else {
            throw RestorationOutputPromoterError.outputExists(
                file: request.finalOutputURL.lastPathComponent
            )
        }
        guard !fileManager.fileExists(atPath: request.partialOutputURL.path) else {
            throw RestorationOutputPromoterError.partialOutputExists(
                file: request.partialOutputURL.lastPathComponent
            )
        }
        let expectedSize = try regularFileSize(at: request.validatedOutputURL)
        let requiredSpace = expectedSize.addingReportingOverflow(Self.destinationReserveBytes)
        guard !requiredSpace.overflow else {
            throw RestorationOutputPromoterError.invalidDestinationRequirement
        }
        guard let capacity = availableCapacity(destinationDirectory) else {
            throw RestorationOutputPromoterError.cannotCheckDestinationSpace
        }
        guard capacity >= requiredSpace.partialValue else {
            throw RestorationOutputPromoterError.insufficientDestinationSpace(
                available: capacity,
                required: requiredSpace.partialValue
            )
        }

        try fileManager.copyItem(at: request.validatedOutputURL, to: request.partialOutputURL)
        guard (try? regularFileSize(at: request.partialOutputURL)) == expectedSize else {
            throw RestorationOutputPromoterError.stagedCopyInvalid
        }
        return request.partialOutputURL
    }

    func promote(_ request: RestorationOutputPromotion) throws -> URL {
        let validatedSize = try regularFileSize(at: request.validatedOutputURL)
        guard (try? regularFileSize(at: request.partialOutputURL)) == validatedSize else {
            throw RestorationOutputPromoterError.stagedCopyInvalid
        }
        guard !fileManager.fileExists(atPath: request.finalOutputURL.path) else {
            throw RestorationOutputPromoterError.outputAppeared(
                file: request.finalOutputURL.lastPathComponent
            )
        }

        try fileManager.moveItem(at: request.partialOutputURL, to: request.finalOutputURL)
        return request.finalOutputURL
    }

    private func regularFileSize(at url: URL) throws -> Int64 {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw RestorationOutputPromoterError.validatedOutputMissing
        }
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size > 0 else {
            throw RestorationOutputPromoterError.validatedOutputInvalid
        }
        return Int64(size)
    }
}

enum RestorationOutputPromoterError: LocalizedError, Equatable {
    case unapprovedValidatedOutput
    case outputMustBeMP4
    case outputMatchesSource
    case workspaceMatchesDestination
    case destinationFolderMissing
    case validatedOutputMissing
    case validatedOutputInvalid
    case invalidDestinationRequirement
    case cannotCheckDestinationSpace
    case insufficientDestinationSpace(available: Int64, required: Int64)
    case outputExists(file: String)
    case partialOutputExists(file: String)
    case stagedCopyInvalid
    case outputAppeared(file: String)

    var errorDescription: String? {
        switch self {
        case .unapprovedValidatedOutput:
            "Only the validated restoration audio output can be staged."
        case .outputMustBeMP4:
            "The restoration output must use the .mp4 extension."
        case .outputMatchesSource:
            "The restoration output cannot replace its source file."
        case .workspaceMatchesDestination:
            "The restoration workspace output cannot also be the destination output."
        case .destinationFolderMissing:
            "The selected restoration destination folder is no longer available."
        case .validatedOutputMissing:
            "The validated restoration output is no longer available."
        case .validatedOutputInvalid:
            "The validated restoration output is not a nonempty regular file."
        case .invalidDestinationRequirement:
            "The restoration destination space requirement could not be calculated."
        case .cannotCheckDestinationSpace:
            "Available space could not be checked on the restoration destination."
        case .insufficientDestinationSpace(let available, let required):
            "The restoration destination has \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available but requires \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file))."
        case .outputExists(let file):
            "The destination \(file) already exists and will not be overwritten."
        case .partialOutputExists(let file):
            "The incomplete output \(file) already exists. Move or remove it before retrying."
        case .stagedCopyInvalid:
            "The staged restoration copy does not match the validated output size."
        case .outputAppeared(let file):
            "The destination \(file) appeared while restoration was running and was not overwritten."
        }
    }
}
