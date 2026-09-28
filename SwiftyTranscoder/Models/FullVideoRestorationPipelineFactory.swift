import Foundation

struct FullVideoRestorationResources: Equatable, Sendable {
    static let modelName = "RealESRGAN_x2plus_522_fp16.mlpackage"

    let ffmpegURL: URL
    let ffprobeURL: URL
    let modelURL: URL

    static func locate(
        bundleURL: URL = Bundle.main.bundleURL,
        developmentModelURL: URL? = defaultDevelopmentModelURL,
        ffmpegFallbackPaths: [String]? = nil,
        ffprobeFallbackPaths: [String]? = nil,
        fileManager: FileManager = .default
    ) throws -> Self {
        guard let ffmpegURL = MediaToolLocator.executableURL(
            for: .ffmpeg,
            bundleURL: bundleURL,
            fileManager: fileManager,
            fallbackPaths: ffmpegFallbackPaths
        ) else {
            throw FullVideoRestorationFactoryError.ffmpegUnavailable
        }
        guard let ffprobeURL = MediaToolLocator.executableURL(
            for: .ffprobe,
            bundleURL: bundleURL,
            fileManager: fileManager,
            fallbackPaths: ffprobeFallbackPaths
        ) else {
            throw FullVideoRestorationFactoryError.ffprobeUnavailable
        }

        let bundledModelURL = bundleURL
            .appendingPathComponent("Contents/Resources/Models", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)
        let modelCandidates = [bundledModelURL, developmentModelURL].compactMap { $0 }
        guard let modelURL = modelCandidates.first(where: {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: $0.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }) else {
            throw FullVideoRestorationFactoryError.modelUnavailable
        }

        return Self(ffmpegURL: ffmpegURL, ffprobeURL: ffprobeURL, modelURL: modelURL)
    }

    private static var defaultDevelopmentModelURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".build/restoration-evaluation/converter/weights/\(modelName)",
                isDirectory: true
            )
    }
}

protocol FullVideoRestorationPipelineBuilding: Sendable {
    func makePipeline(
        for request: FullVideoRestorationRequest
    ) throws -> any FullVideoRestorationPipelineRunning
}

struct FullVideoRestorationPipelineFactory: FullVideoRestorationPipelineBuilding, Sendable {
    let resources: FullVideoRestorationResources

    init(resources: FullVideoRestorationResources) {
        self.resources = resources
    }

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) throws {
        resources = try FullVideoRestorationResources.locate(
            bundleURL: bundleURL,
            fileManager: fileManager
        )
    }

    func makePipeline(
        for request: FullVideoRestorationRequest
    ) throws -> any FullVideoRestorationPipelineRunning {
        let tileProcessor = try CoreMLRestorationTileProcessor(modelURL: resources.modelURL)
        let frameProcessor = RestorationFrameProcessor(tileProcessor: tileProcessor)
        let chunkProcessor = try FullRestorationChunkProcessor(
            sourceURL: request.sourceURL,
            workspaceURL: request.workspaceURL,
            plan: request.plan,
            subtitleStreamOrdinal: request.subtitleStreamOrdinal,
            extractor: RestorationFrameExtractor(executableURL: resources.ffmpegURL),
            sequenceProcessor: RestorationFrameSequenceProcessor(
                frameProcessor: frameProcessor
            ),
            assembler: RestorationVideoAssembler(
                ffmpegURL: resources.ffmpegURL,
                ffprobeURL: resources.ffprobeURL
            )
        )

        return FullVideoRestorationPipeline(
            chunkCoordinator: RestorationChunkCoordinator(processor: chunkProcessor),
            segmentConcatenator: RestorationSegmentConcatenator(
                ffmpegURL: resources.ffmpegURL,
                ffprobeURL: resources.ffprobeURL
            ),
            audioMuxer: RestorationAudioMuxer(
                ffmpegURL: resources.ffmpegURL,
                ffprobeURL: resources.ffprobeURL
            ),
            outputPromoter: RestorationOutputPromotionService()
        )
    }
}

enum FullVideoRestorationFactoryError: LocalizedError, Equatable {
    case ffmpegUnavailable
    case ffprobeUnavailable
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .ffmpegUnavailable:
            "The bundled FFmpeg helper required for full-video restoration is unavailable."
        case .ffprobeUnavailable:
            "The bundled FFprobe helper required for full-video restoration is unavailable."
        case .modelUnavailable:
            "The bundled AI restoration model is unavailable. Rebuild SwiftyTranscoder after running Scripts/prepare-restoration-model.sh."
        }
    }
}
