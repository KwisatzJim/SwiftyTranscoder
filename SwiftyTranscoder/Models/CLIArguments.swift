import Foundation

struct CLIArguments: Equatable, Sendable {
    var input: String?
    var output: String?
    var audioMode: ConversionAudioMode = .convert
    var gainDB = 6
    var aacStereo = true
    var subtitles: String?
    var assumeBT709 = false
    var restorationMethod: RestorationMethod?
    var checkpointDirectory: String?
    var resume = false
    var dryRun = false
    var help = false

    init(_ arguments: [String]) throws {
        var index = 0
        var seen = Set<String>()
        var positionalOnly = false
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if argument == "--", !positionalOnly {
                positionalOnly = true
                continue
            }
            if !positionalOnly, argument.hasPrefix("-") {
                let key = argument == "-h" ? "--help" : argument
                guard seen.insert(key).inserted else { throw CLIUsageError("Repeated option: \(argument)") }
                func value() throws -> String {
                    guard index < arguments.count else { throw CLIUsageError("Missing value for \(argument)") }
                    let result = arguments[index]
                    index += 1
                    return result
                }
                switch key {
                case "--checkpoint-dir": checkpointDirectory = try value()
                case "--resume": resume = true
                case "--help": help = true
                case "--dry-run": dryRun = true
                case "--assume-bt709": assumeBT709 = true
                case "--restore":
                    guard try value() == "lightweight" else {
                        throw CLIUsageError("--restore currently supports lightweight only.")
                    }
                    restorationMethod = .lightweightFSRCNN
                case "--audio":
                    guard let mode = ConversionAudioMode(rawValue: try value()) else { throw CLIUsageError("--audio requires convert or omit.") }
                    audioMode = mode
                case "--output": output = try value()
                case "--preset":
                    guard try value() == "plex" else { throw CLIUsageError("Only --preset plex is supported.") }
                case "--gain-db":
                    guard let gain = Int(try value()), [0, 6].contains(gain) else {
                        throw CLIUsageError("--gain-db supports 0 or 6.")
                    }
                    gainDB = gain
                case "--aac-stereo":
                    let selection = try value()
                    guard ["on", "off"].contains(selection) else { throw CLIUsageError("--aac-stereo requires on or off.") }
                    aacStereo = selection == "on"
                case "--subtitles":
                    let selection = try value()
                    guard selection == "omit" || (Int(selection).map { $0 >= 0 } == true) else {
                        throw CLIUsageError("--subtitles requires omit or a nonnegative source stream index.")
                    }
                    subtitles = selection
                default: throw CLIUsageError("Unknown option: \(argument)")
                }
            } else {
                guard input == nil else { throw CLIUsageError("Supply exactly one input file.") }
                input = argument
            }
        }
        guard !help else { return }
        guard audioMode != .omit || restorationMethod == nil else { throw CLIUsageError("--audio omit currently applies to ordinary conversion. Remove --restore to create video-only output.") }
        guard !resume || checkpointDirectory != nil else { throw CLIUsageError("--resume requires --checkpoint-dir.") }
        guard checkpointDirectory == nil || restorationMethod != nil else { throw CLIUsageError("--checkpoint-dir requires --restore lightweight.") }
        if let checkpointDirectory {
            guard URL(fileURLWithPath: checkpointDirectory).lastPathComponent.hasPrefix("SwiftyTranscoder-Restoration-") else { throw CLIUsageError("Saved job folder must be named SwiftyTranscoder-Restoration- followed by a job name.") }
        }
        guard let input, !input.isEmpty, let output, !output.isEmpty else {
            throw CLIUsageError("An input file and --output are required. Use --help for usage.")
        }
        guard ["mkv", "mp4", "m4v"].contains(URL(fileURLWithPath: input).pathExtension.lowercased()) else {
            throw CLIUsageError("Input must be MKV, MP4, or M4V.")
        }
        guard URL(fileURLWithPath: output).pathExtension.lowercased() == "mp4" else {
            throw CLIUsageError("Output must have the .mp4 extension.")
        }
        let source = URL(fileURLWithPath: input).resolvingSymlinksInPath()
        let destination = URL(fileURLWithPath: output).resolvingSymlinksInPath()
        guard CanonicalOutputPath.key(for: source) != CanonicalOutputPath.key(for: destination) else {
            throw CLIUsageError("Input and output must be different files.")
        }
    }

    static let usage = """
    Usage: swiftytranscoder INPUT --preset plex --output OUTPUT.mp4 [options]
    Input: MKV, or compatible SDR H.264/HEVC MP4/M4V.
    Plex defaults: protected +6 dB gain, primary AC-3, optional AAC stereo on.
    By default, MP4/M4V video is copied; MKV video uses hardware HEVC.
    --restore lightweight enables explicit AI restoration with hardware HEVC output.

      --restore lightweight   Restore eligible tagged SDR video using FSRCNN
      --checkpoint-dir PATH    Save completed blocks in a new persistent job folder
      --resume                 Reuse that folder with exactly the same input/settings
      --audio convert|omit     Convert audio (default) or remove all audio tracks
      --gain-db 0|6            Audio gain (default: 6, peak protected)
      --aac-stereo on|off      Secondary AAC stereo (default: on)
      --subtitles omit|INDEX   Omit or burn a source SubRip stream index
                              Required when subtitle streams are present
      --assume-bt709           Confirm untagged MKV video as SDR BT.709
      --dry-run               Inspect and print the plan without converting
      --help, -h              Show this help
      --                      Treat remaining arguments as positional paths

    Existing destinations and partial files are never overwritten.
    Ctrl-C cancels conversion and retains a labeled partial output if present.
    Exit codes: 0 success, 1 processing failure, 2 usage error, 130 cancelled.
    Restoration uses the same eligibility checks, 1080p cap, and settings as the GUI.
    """
}

struct CLIUsageError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
