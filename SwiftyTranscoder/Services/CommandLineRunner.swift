import Darwin
import Foundation

@MainActor
enum CommandLineRunner {
    static func run(_ arguments: [String]) async -> Int32 {
        do {
            let options = try CLIArguments(arguments)
            if options.help { print(CLIArguments.usage); return 0 }
            let source = URL(fileURLWithPath: options.input!).standardizedFileURL
            let output = URL(fileURLWithPath: options.output!).standardizedFileURL
            let controller = VideoConversionController()
            let restorationController = FullVideoRestorationController()
            let interruption = CLIInterruption()
            let signals = [SIGINT, SIGTERM].map { number in
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
                source.setEventHandler {
                    Task { @MainActor in
                        interruption.requested = true
                        controller.cancel()
                        restorationController.cancel()
                    }
                }
                source.resume()
                return source
            }
            defer { signals.forEach { $0.cancel() } }
            print("Inspecting: \(source.path)")
            let inspection = try await MediaProbe().inspect(source)
            guard !interruption.requested else { return 130 }
            guard let video = inspection.videoStreams.first,
                  let duration = options.audioMode.expectedDuration(in: inspection),
                  duration.isFinite, duration > 0 else {
                throw CLIUsageError("Input requires video and a valid duration.")
            }
            let audio = inspection.audioStreams.first
            var color = ColorSelection(video: video)
            if options.assumeBT709 {
                guard source.pathExtension.lowercased() == "mkv", color == .needsConfirmation else {
                    throw CLIUsageError("--assume-bt709 applies only to untagged MKV SDR video.")
                }
                color = .confirmUntaggedAsBT709
            }
            guard color == .preserveConfirmedSDR || color == .confirmUntaggedAsBT709 else {
                throw CLIUsageError("HDR is unsupported. Untagged MKV needs explicit --assume-bt709 confirmation; untagged MP4 cannot be processed.")
            }
            guard options.subtitles != nil || inspection.subtitleStreams.isEmpty else {
                let tracks = inspection.subtitleStreams.map { "\($0.index): \($0.codecName ?? "unknown")" }.joined(separator: ", ")
                throw CLIUsageError("Choose --subtitles omit or a SubRip stream index. Available: \(tracks)")
            }
            let subtitles: SubtitleSelection = options.subtitles.flatMap(Int.init).map {
                .burnIn(streamIndex: $0)
            } ?? .omit
            let command = try VideoConversionCommand(
                sourceURL: source, outputURL: output, inspection: inspection,
                gainEnabled: options.gainDB == 6, aacStereoEnabled: options.aacStereo,
                colorSelection: color, subtitleSelection: subtitles, audioMode: options.audioMode
            )
            let restorationPlan: RestorationPlan?
            if let method = options.restorationMethod {
                switch RestorationPlanner().plan(for: inspection, method: method) {
                case .eligible(let plan): restorationPlan = plan
                case .unavailable(let reason): throw CLIUsageError(reason)
                }
                let plan = restorationPlan!
                let request = try FullVideoRestorationController.makeRequest(
                    sourceURL: source, inspection: inspection, outputURL: output, plan: plan,
                    gainEnabled: options.gainDB == 6, aacStereoEnabled: options.aacStereo,
                    subtitleSelection: subtitles,
                    checkpointDirectory: options.checkpointDirectory.map { URL(fileURLWithPath: $0).standardizedFileURL },
                    checkpointMode: options.checkpointDirectory == nil ? nil : (options.resume ? .resume : .create)
                )
                if options.resume {
                    guard FileManager.default.fileExists(atPath: request.workspaceURL.path) else { throw CLIUsageError("Saved job folder is missing.") }
                }
                try RestorationBatchPreflight().check(request)
                if options.resume, options.dryRun {
                    let identity = try await Task.detached {
                        try FullVideoRestorationResources.locate().checkpointIdentity(for: request)
                    }.value
                    let chunks = try RestorationChunkPlan(totalFrameCount: request.totalFrameCount, frameRate: request.plan.frameRate, workspaceURL: request.workspaceURL)
                    let store = try RestorationCheckpointStore(workspace: request.workspaceURL, plan: chunks)
                    let record = try await store.load(identity: identity)
                    print("Verified saved frames: \(record.segments.reduce(0) { $0 + $1.frameCount }) of \(request.totalFrameCount)")
                }
                if let directory = options.checkpointDirectory { print("Saved job: \(directory) · \(options.resume ? "resume (verified before reuse)" : "new")") }
                print("Video: AI restoration · \(plan.method.rawValue) · Apple hardware HEVC")
                print("Dimensions: \(plan.sourceWidth)×\(plan.sourceHeight) → \(plan.outputWidth)×\(plan.outputHeight)")
            } else {
                restorationPlan = nil
                print("Video: \(command.videoMode == .copyVideo ? "copy unchanged" : "Apple hardware HEVC")")
            }
            if options.audioMode == .omit { print("Audio: omit all tracks (video only; gain and AAC disabled)") }
            else { print("Audio: primary AC-3; protected gain \(options.gainDB) dB; AAC stereo \(options.aacStereo ? "on" : "off")") }
            print("Subtitles: \(options.subtitles ?? "omit (no subtitle streams)")")
            print("Output: \(output.path)")
            if options.dryRun { print("Dry run complete; no output written."); return 0 }
            guard !interruption.requested else { return 130 }
            if let restorationPlan {
                return await restore(
                    options: options, source: source, output: output, inspection: inspection,
                    plan: restorationPlan, subtitles: subtitles, controller: restorationController
                )
            }
            try controller.start(
                command: command, expectedVideo: video, expectedAudio: audio,
                videoMode: command.videoMode, colorSelection: color, durationSeconds: duration
            )
            var lastPercent = -1
            while controller.isActive {
                let percent = Int(controller.progress * 100)
                if percent != lastPercent {
                    print("Progress: \(percent)%")
                    lastPercent = percent
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            switch controller.phase {
            case .completed(let url): print("Completed and validated: \(url.path)"); return 0
            case .cancelled(let partial):
                reportPartial(partial)
                return 130
            case .failed(let message, let partial):
                writeError(message)
                reportPartial(partial)
                return 1
            default: writeError("Conversion ended in an unexpected state."); return 1
            }
        } catch {
            writeError(error.localizedDescription)
            return error is CLIUsageError ? 2 : 1
        }
    }

    private static func restore(
        options: CLIArguments, source: URL, output: URL, inspection: MediaInspection,
        plan: RestorationPlan, subtitles: SubtitleSelection,
        controller: FullVideoRestorationController
    ) async -> Int32 {
        controller.start(
            sourceURL: source, inspection: inspection, outputURL: output, plan: plan,
            gainEnabled: options.gainDB == 6, aacStereoEnabled: options.aacStereo,
            subtitleSelection: subtitles,
            checkpointDirectory: options.checkpointDirectory.map { URL(fileURLWithPath: $0).standardizedFileURL },
            checkpointMode: options.checkpointDirectory == nil ? nil : (options.resume ? .resume : .create)
        )
        var lastPercent = -1
        var lastPhase: FullVideoRestorationController.Phase?
        var estimate = RestorationTimeEstimate()
        while controller.isActive {
            if controller.phase != lastPhase {
                switch controller.phase {
                case .preparing: print("Preparing AI model…")
                case .running(let stage):
                    switch stage {
                    case .processingChunks: print("Restoring video frames…")
                    case .assemblingSilentVideo: print("Joining restored video…")
                    case .muxingAudioAndMetadata: print("Adding audio and metadata…")
                    case .stagingDestination: print("Copying validated output…")
                    case .promotingDestination: print("Finalizing output…")
                    }
                case .cancelling: print("Stopping restoration safely…")
                default: break
                }
                lastPhase = controller.phase
            }
            if case .running = controller.phase {
                let remaining = estimate.update(progress: controller.progress, now: ProcessInfo.processInfo.systemUptime)
                let percent = Int(controller.progress * 100)
                if percent != lastPercent {
                    let suffix = remaining.map { " · about \(max(1, Int(ceil($0 / 60))))m remaining" } ?? ""
                    print("Progress: \(percent)%\(suffix)")
                    lastPercent = percent
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        switch controller.phase {
        case .completed(let url):
            print("Completed and validated: \(url.path)")
            if controller.completionSummary == nil, let seconds = controller.completionElapsedSeconds { print("Elapsed: \(RestorationCompletionSummary.elapsedDescription(seconds))") }
            if controller.reusedFrameCount > 0 { print("Reused: \(controller.reusedFrameCount) verified restored frames") }
            if let summary = controller.completionSummary {
                print("Elapsed: \(RestorationCompletionSummary.elapsedDescription(summary.elapsedSeconds))")
                print("Average: \(summary.averageFramesPerSecond.formatted(.number.precision(.fractionLength(1)))) new frames/s (including preparation, audio, and saving)")
                print("AI model: \(summary.method.rawValue)")
            }
            return 0
        case .cancelled(let partial): reportSavedJob(options); reportPartial(partial); return 130
        case .failed(let message, let partial): writeError(message); reportSavedJob(options); reportPartial(partial); return 1
        default: writeError("Restoration ended in an unexpected state."); return 1
        }
    }

    private static func reportSavedJob(_ options: CLIArguments) {
        if let directory = options.checkpointDirectory, FileManager.default.fileExists(atPath: directory) {
            writeError("Saved job retained: \(directory). Run the same command with --resume to continue.")
        }
    }

    private static func reportPartial(_ url: URL?) {
        if let url { writeError("Partial output retained: \(url.path)") }
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

@MainActor
private final class CLIInterruption {
    var requested = false
}
