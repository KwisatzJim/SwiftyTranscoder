import Foundation

struct DestinationSpaceCheck: Sendable {
    let availableBytes: Int64
    let requiredBytes: Int64

    var isSufficient: Bool { availableBytes >= requiredBytes }

    static func evaluate(inspection: MediaInspection, outputURL: URL) -> DestinationSpaceCheck? {
        guard let sizeText = inspection.format.size,
              let sourceBytes = Int64(sizeText) else { return nil }
        guard let requiredBytes = DestinationStorageRequirement.requiredBytes(forSourceBytes: sourceBytes),
              let availableBytes = try? outputURL.deletingLastPathComponent()
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage else { return nil }
        return DestinationSpaceCheck(
            availableBytes: availableBytes,
            requiredBytes: requiredBytes
        )
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum VideoConversionMode: Sendable, Equatable {
    case transcodeToHEVC
    case copyVideo
}

struct VideoConversionCommand: Sendable {
    let executableURL: URL
    let arguments: [String]
    let sourceURL: URL
    let partialOutputURL: URL
    let finalOutputURL: URL
    let burnedSubtitleStreamIndex: Int?
    let videoMode: VideoConversionMode
    let includesAACStereoTrack: Bool

    static func partialOutputURL(for finalOutputURL: URL) -> URL {
        finalOutputURL
            .deletingPathExtension()
            .appendingPathExtension("partial")
            .appendingPathExtension("mp4")
    }

    init(
        sourceURL: URL,
        outputURL: URL?,
        inspection: MediaInspection,
        gainEnabled: Bool,
        aacStereoEnabled: Bool,
        colorSelection: ColorSelection,
        subtitleSelection: SubtitleSelection,
        fileManager: FileManager = .default
    ) throws {
        let isMP4Source = ["mp4", "m4v"].contains(sourceURL.pathExtension.lowercased())
        videoMode = isMP4Source ? .copyVideo : .transcodeToHEVC
        guard let video = inspection.videoStreams.first else {
            throw VideoConversionCommandError.noVideo(file: sourceURL.lastPathComponent)
        }

        guard ["h264", "hevc"].contains(video.codecName?.lowercased()) else {
            throw VideoConversionCommandError.unsupportedCodec(
                file: sourceURL.lastPathComponent,
                codec: video.codecName ?? "unknown"
            )
        }

        guard ["yuv420p", "yuv420p10le"].contains(video.pixelFormat) else {
            throw VideoConversionCommandError.unsupportedPixelFormat(
                file: sourceURL.lastPathComponent,
                pixelFormat: video.pixelFormat ?? "unknown"
            )
        }

        let sourceDynamicRange = VideoSummary(stream: video).dynamicRange
        guard colorSelection == .preserveConfirmedSDR && sourceDynamicRange == "SDR"
                || !isMP4Source && colorSelection == .confirmUntaggedAsBT709 && sourceDynamicRange == "Not identified" else {
            throw VideoConversionCommandError.unconfirmedColor(
                file: sourceURL.lastPathComponent
            )
        }

        guard let audio = inspection.audioStreams.first else {
            throw VideoConversionCommandError.noAudio(file: sourceURL.lastPathComponent)
        }
        guard let audioSettings = CompatibilityAudioSettings(source: audio) else {
            throw VideoConversionCommandError.unsupportedAudio(
                file: sourceURL.lastPathComponent,
                layout: audio.channelLayout ?? "unknown",
                sampleRate: audio.sampleRate ?? "unknown"
            )
        }
        guard let outputURL else {
            throw VideoConversionCommandError.outputNotSelected
        }
        guard !fileManager.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
            throw VideoConversionCommandError.outputExists(file: outputURL.lastPathComponent)
        }
        guard let spaceCheck = DestinationSpaceCheck.evaluate(
            inspection: inspection,
            outputURL: outputURL
        ) else {
            throw VideoConversionCommandError.cannotCheckDiskSpace
        }
        guard spaceCheck.isSufficient else {
            throw VideoConversionCommandError.insufficientDiskSpace(
                available: spaceCheck.availableBytes,
                required: spaceCheck.requiredBytes
            )
        }

        let partialOutputURL = Self.partialOutputURL(for: outputURL)
        guard !fileManager.fileExists(atPath: partialOutputURL.path(percentEncoded: false)) else {
            throw VideoConversionCommandError.partialOutputExists(
                file: partialOutputURL.lastPathComponent
            )
        }

        let candidates = [
            "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg",
            "/usr/local/opt/ffmpeg-full/bin/ffmpeg"
        ]
        guard let executablePath = candidates.first(where: fileManager.isExecutableFile(atPath:)) else {
            throw VideoConversionCommandError.ffmpegFullNotFound
        }

        var videoFilters: [String] = []
        switch subtitleSelection {
        case .burnIn(let streamIndex):
            guard !isMP4Source else {
                throw VideoConversionCommandError.mp4SubtitleBurnInRequiresTranscode
            }
            guard let subtitleOrdinal = inspection.subtitleStreams.firstIndex(where: {
                $0.index == streamIndex
            }), let stream = inspection.subtitleStreams[safe: subtitleOrdinal] else {
                throw VideoConversionCommandError.subtitleNotFound(streamIndex: streamIndex)
            }
            guard stream.codecName == "subrip" else {
                throw VideoConversionCommandError.unsupportedSubtitle(
                    streamIndex: streamIndex,
                    codec: stream.codecName ?? "unknown"
                )
            }
            let escapedSource = Self.escapeFilterValue(
                sourceURL.path(percentEncoded: false)
            )
            videoFilters.append("subtitles=filename='\(escapedSource)':stream_index=\(subtitleOrdinal):force_style='FontName=Helvetica,FontSize=22,Outline=2,Shadow=0,MarginV=36'")
            burnedSubtitleStreamIndex = streamIndex
        case .omit:
            burnedSubtitleStreamIndex = nil
        case .needsChoice:
            throw VideoConversionCommandError.subtitleChoiceRequired
        }
        if !isMP4Source && colorSelection == .confirmUntaggedAsBT709 {
            videoFilters.append("setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709")
        }

        let quality = (video.height ?? 0) > 1_080 ? "50" : "60"
        let isTenBit = video.pixelFormat == "yuv420p10le"
        let outputProfile = isTenBit ? "main10" : "main"
        let outputPixelFormat = isTenBit ? "p010le" : "yuv420p"
        let audioLanguage = audio.tags?["language"]?.isEmpty == false
            ? audio.tags?["language"] ?? "und"
            : "und"

        self.executableURL = URL(fileURLWithPath: executablePath)
        self.sourceURL = sourceURL
        self.partialOutputURL = partialOutputURL
        self.finalOutputURL = outputURL
        includesAACStereoTrack = aacStereoEnabled
        var arguments = [
            "-hide_banner",
            "-nostdin",
            "-n",
            "-i", sourceURL.path(percentEncoded: false),
            "-map", "0:v:0",
            "-map", "0:a:0",
            "-sn",
            "-dn",
        ]
        if aacStereoEnabled {
            arguments += ["-map", "0:a:0"]
        }
        if !videoFilters.isEmpty {
            arguments += ["-vf", videoFilters.joined(separator: ",")]
        }
        if isMP4Source {
            arguments += ["-c:v", "copy"]
        } else {
            arguments += [
                "-c:v", "hevc_videotoolbox",
                "-allow_sw", "0",
                "-profile:v", outputProfile,
                "-pix_fmt", outputPixelFormat,
                "-q:v", quality,
                "-tag:v", "hvc1",
                "-fps_mode", "passthrough",
            ]
        }
        let gainFilter = "volume=6dB,alimiter=limit=0.630957:level=false:latency=true"
        if gainEnabled {
            arguments += ["-filter:a:0", gainFilter]
        }
        arguments += [
            "-c:a:0", "ac3",
            "-b:a:0", audioSettings.bitRate,
            "-ar:a:0", "48000",
            "-ac:a:0", String(audioSettings.channels),
            "-metadata:s:a:0", "language=\(audioLanguage)",
            "-metadata:s:a:0", gainEnabled
                ? "title=Primary Audio AC-3 \(audioSettings.description) Compatibility +6 dB Limited"
                : "title=Primary Audio AC-3 \(audioSettings.description) Compatibility",
            "-disposition:a:0", "default",
        ]
        if aacStereoEnabled {
            let stereoFilter = gainEnabled
                ? "aformat=channel_layouts=stereo,\(gainFilter)"
                : "aformat=channel_layouts=stereo"
            arguments += [
                "-filter:a:1", stereoFilter,
                "-c:a:1", "aac",
                "-b:a:1", "192000",
                "-ar:a:1", "48000",
                "-ac:a:1", "2",
                "-metadata:s:a:1", "language=\(audioLanguage)",
                "-metadata:s:a:1", gainEnabled
                    ? "title=Secondary Audio AAC stereo at 192 kb/s Compatibility +6 dB Limited"
                    : "title=Secondary Audio AAC stereo at 192 kb/s Compatibility",
                "-disposition:a:1", "0",
            ]
        }
        arguments += [
            "-map_metadata", "0",
            "-map_chapters", "0",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            partialOutputURL.path(percentEncoded: false)
        ]
        self.arguments = arguments
    }

    private static func escapeFilterValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: ":", with: "\\:")
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum VideoConversionCommandError: LocalizedError {
    case mp4SubtitleBurnInRequiresTranscode
    case noVideo(file: String)
    case noAudio(file: String)
    case unsupportedAudio(file: String, layout: String, sampleRate: String)
    case unsupportedCodec(file: String, codec: String)
    case unsupportedPixelFormat(file: String, pixelFormat: String)
    case unconfirmedColor(file: String)
    case outputNotSelected
    case outputExists(file: String)
    case cannotCheckDiskSpace
    case insufficientDiskSpace(available: Int64, required: Int64)
    case partialOutputExists(file: String)
    case ffmpegFullNotFound
    case subtitleNotFound(streamIndex: Int)
    case unsupportedSubtitle(streamIndex: Int, codec: String)
    case subtitleChoiceRequired

    var errorDescription: String? {
        switch self {
        case .mp4SubtitleBurnInRequiresTranscode:
            "MP4 audio-gain conversion copies video unchanged. Choose Omit subtitles; burning subtitles would require re-encoding the video."
        case .noVideo(let file):
            "\(file) has no video stream to convert."
        case .noAudio(let file):
            "\(file) has no primary audio stream to convert."
        case .unsupportedAudio(let file, let layout, let sampleRate):
            "\(file) uses unsupported \(layout) audio at \(sampleRate) Hz. Conversion currently supports mono, stereo, and 5.1 layouts; sample rate is safely normalized to 48000 Hz."
        case .unsupportedCodec(let file, let codec):
            "\(file) uses unsupported video codec \(codec). The first conversion path supports H.264 and HEVC only."
        case .unsupportedPixelFormat(let file, let pixelFormat):
            "\(file) uses \(pixelFormat). Conversion supports confirmed SDR yuv420p and yuv420p10le sources only."
        case .unconfirmedColor(let file):
            "\(file) is not explicitly identified as SDR. Conversion is blocked to avoid losing or changing important color information."
        case .outputNotSelected:
            "Choose an output folder before conversion."
        case .outputExists(let file):
            "The destination \(file) already exists and will not be overwritten."
        case .cannotCheckDiskSpace:
            "Available space at the destination could not be checked, so conversion was not started."
        case .insufficientDiskSpace(let available, let required):
            "The destination has \(DestinationSpaceCheck.format(available)) available. Keep at least \(DestinationSpaceCheck.format(required)) free for this conversion and its safety reserve."
        case .partialOutputExists(let file):
            "The incomplete output \(file) already exists. Move or remove it before retrying."
        case .ffmpegFullNotFound:
            "The libass-capable ffmpeg-full executable was not found. Install ffmpeg-full before converting subtitles."
        case .subtitleNotFound(let streamIndex):
            "Selected subtitle stream \(streamIndex) is no longer present in the inspected source."
        case .unsupportedSubtitle(let streamIndex, let codec):
            "Selected subtitle stream \(streamIndex) uses unsupported codec \(codec). This burn-in path currently supports SubRip."
        case .subtitleChoiceRequired:
            "Choose a subtitle track or select Omit subtitles before conversion."
        }
    }
}
