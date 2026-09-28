import Foundation

struct ConversionPlan: Sendable {
    let container = "MP4"
    let videoFormat: String
    let videoDimensions: String
    let frameRate: String
    let colorHandling: String
    let audioFormat: String
    let audioGain: String
    let storageStatus: String
    let subtitleAction: SubtitlePlanAction
    let outputURL: URL?
    let outputConflict: Bool
    let partialOutputURL: URL?
    let partialOutputConflict: Bool
    let warnings: [String]

    init(
        inspection: MediaInspection,
        gainEnabled: Bool = true,
        aacStereoEnabled: Bool = false,
        colorSelection: ColorSelection,
        subtitleSelection: SubtitleSelection,
        restorationPlan: RestorationPlan? = nil,
        outputURL: URL? = nil,
        completedOutputURL: URL? = nil,
        managedPartialOutputURL: URL? = nil
    ) {
        let summary = MediaSummary(inspection: inspection)
        let isMP4Source = inspection.format.formatName?.lowercased().contains("mp4") == true
        videoFormat = restorationPlan.map {
            "\($0.method.rawValue), then HEVC using Apple hardware"
        } ?? (isMP4Source
            ? "Copy source video unchanged (no re-encoding)"
            : "HEVC using Apple hardware")
        videoDimensions = restorationPlan.map {
            "\($0.sourceWidth)×\($0.sourceHeight) → \($0.outputWidth)×\($0.outputHeight)"
        } ?? summary.video.map {
            "Preserve source (\($0.resolution)); never upscale"
        } ?? "Unknown—conversion blocked"
        frameRate = summary.video.map { "Preserve source (\($0.frameRate))" }
            ?? "Unknown—conversion blocked"
        colorHandling = colorSelection.description
        let primaryAudioFormat = inspection.audioStreams.first
            .flatMap(CompatibilityAudioSettings.init(source:))
            .map { "AC-3 \($0.description), 48 kHz; preserve channel layout" }
            ?? "Unsupported audio layout—conversion blocked"
        audioFormat = aacStereoEnabled
            ? "\(primaryAudioFormat); plus AAC stereo at 192 kb/s"
            : primaryAudioFormat
        subtitleAction = SubtitlePlanAction(
            selection: subtitleSelection,
            streams: inspection.subtitleStreams,
            recommendation: summary.subtitleRecommendation
        )
        audioGain = gainEnabled ? "+6 dB with peak protection" : "Off"
        self.outputURL = outputURL
        let spaceCheck = outputURL.flatMap {
            DestinationSpaceCheck.evaluate(inspection: inspection, outputURL: $0)
        }
        if let spaceCheck {
            storageStatus = "\(DestinationSpaceCheck.format(spaceCheck.availableBytes)) available; \(DestinationSpaceCheck.format(spaceCheck.requiredBytes)) required"
        } else if outputURL == nil {
            storageStatus = "Choose an output folder"
        } else {
            storageStatus = "Could not verify available space"
        }
        outputConflict = outputURL.map { proposedOutput in
            let isCompletedByThisSession = completedOutputURL.map {
                $0.standardizedFileURL == proposedOutput.standardizedFileURL
            } ?? false
            return !isCompletedByThisSession && FileManager.default.fileExists(
                atPath: proposedOutput.path(percentEncoded: false)
            )
        } ?? false
        partialOutputURL = outputURL.map(VideoConversionCommand.partialOutputURL(for:))
        partialOutputConflict = partialOutputURL.map { proposedPartial in
            let isManagedByCurrentConversion = managedPartialOutputURL.map {
                $0.standardizedFileURL == proposedPartial.standardizedFileURL
            } ?? false
            return !isManagedByCurrentConversion && FileManager.default.fileExists(
                atPath: proposedPartial.path(percentEncoded: false)
            )
        } ?? false

        var warnings: [String] = []
        if outputURL == nil {
            warnings.append("Choose an output location before conversion.")
        } else if outputConflict {
            warnings.append("The output file already exists. Choose a different folder or move the existing file.")
        } else if partialOutputConflict, let partialOutputURL {
            warnings.append("An incomplete output already exists: \(partialOutputURL.lastPathComponent)")
        }
        if outputURL != nil, spaceCheck == nil {
            warnings.append("Available destination space could not be checked. Conversion is blocked.")
        } else if let spaceCheck, !spaceCheck.isSufficient {
            warnings.append("Not enough destination space. Keep \(DestinationSpaceCheck.format(spaceCheck.requiredBytes)) free before conversion.")
        }
        if summary.video == nil {
            warnings.append("No video stream was found.")
        }
        if colorSelection == .needsConfirmation {
            warnings.append("Color metadata is missing. Confirm that the source is SDR before conversion.")
        }
        if summary.audio == nil {
            warnings.append("No primary audio stream was found.")
        }
        if summary.audio?.advancedFormat != nil {
            warnings.append("The compatibility audio track will not preserve Atmos.")
        }
        if case .chooseBeforeConversion = subtitleAction {
            warnings.append("Choose a subtitle track or omit subtitles before conversion.")
        }
        self.warnings = warnings
    }
}

enum ColorSelection: Hashable, Sendable {
    case preserveConfirmedSDR
    case confirmUntaggedAsBT709
    case needsConfirmation
    case unsupportedHDR

    init(video: MediaStream?) {
        guard let video else {
            self = .needsConfirmation
            return
        }
        switch VideoSummary(stream: video).dynamicRange {
        case "SDR": self = .preserveConfirmedSDR
        case "HDR (PQ)", "HDR (HLG)": self = .unsupportedHDR
        default: self = .needsConfirmation
        }
    }

    var description: String {
        switch self {
        case .preserveConfirmedSDR: "Preserve confirmed source SDR metadata"
        case .confirmUntaggedAsBT709: "User-confirmed SDR; tag output as BT.709"
        case .needsConfirmation: "Missing metadata—confirmation required"
        case .unsupportedHDR: "HDR conversion is not supported"
        }
    }
}

enum SubtitlePlanAction: Sendable {
    case burnIn(streamIndex: Int, title: String)
    case omit(reason: String)
    case chooseBeforeConversion(candidateIndexes: [Int])

    init(
        selection: SubtitleSelection,
        streams: [MediaStream],
        recommendation: SubtitleRecommendation
    ) {
        switch selection {
        case .burnIn(let streamIndex):
            guard let stream = streams.first(where: { $0.index == streamIndex }) else {
                self = .chooseBeforeConversion(candidateIndexes: [])
                return
            }
            self = .burnIn(
                streamIndex: stream.index,
                title: stream.tags?["title"] ?? "Untitled English track"
            )
        case .omit:
            self = .omit(reason: "User choice")
        case .needsChoice:
            if case .likelyForcedEnglish(let stream, _) = recommendation {
                self = .chooseBeforeConversion(candidateIndexes: [stream.index])
            } else if case .ambiguousForcedEnglish(let candidates) = recommendation {
                self = .chooseBeforeConversion(candidateIndexes: candidates.map(\.index))
            } else if case .ambiguousFullEnglish(let candidates) = recommendation {
                self = .chooseBeforeConversion(candidateIndexes: candidates.map(\.index))
            } else {
                self = .chooseBeforeConversion(candidateIndexes: [])
            }
        }
    }

    var description: String {
        switch self {
        case .burnIn(let streamIndex, let title):
            "Burn stream \(streamIndex): \(title)"
        case .omit(let reason):
            "Omit—\(reason)"
        case .chooseBeforeConversion(let candidateIndexes):
            "Choose between streams \(candidateIndexes.map(String.init).joined(separator: ", "))"
        }
    }
}
