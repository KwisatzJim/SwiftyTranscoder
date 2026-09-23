import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var conversionController = VideoConversionController()
    @State private var isChoosingSource = false
    @State private var selectedSource: URL?
    @State private var inspection: MediaInspection?
    @State private var isInspecting = false
    @State private var selectionError: String?
    @State private var gainEnabled = true
    @State private var colorSelection = ColorSelection.needsConfirmation
    @State private var subtitleSelection = SubtitleSelection.needsChoice
    @State private var outputURL: URL?
    @AppStorage("savedOutputFolderPath") private var savedOutputFolderPath = ""

    private static let sourceTypes: [UTType] = [
        UTType(filenameExtension: "mkv") ?? .data,
        .mpeg4Movie
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("SwiftyTranscoder")
                    .font(.largeTitle.bold())

                Text("A simpler path from MKV to Plex-friendly MP4.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            if let selectedSource {
                selectedFileView(selectedSource)
            } else {
                Text("Choose one MKV or MP4 file to begin. The source will only be read.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

                Button("Choose Video…", systemImage: "folder") {
                    isChoosingSource = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInspecting || conversionController.isActive)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 560, minHeight: 360)
        .fileImporter(
            isPresented: $isChoosingSource,
            allowedContentTypes: Self.sourceTypes,
            allowsMultipleSelection: false
        ) { result in
            handleSelection(result)
        }
        .alert(
            "Couldn’t Select Video",
            isPresented: Binding(
                get: { selectionError != nil },
                set: { if !$0 { selectionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(selectionError ?? "The file could not be selected.")
        }
    }

    private func selectedFileView(_ url: URL) -> some View {
        VStack(spacing: 6) {
            Label("Selected source", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)

            Text(url.lastPathComponent)
                .font(.body.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(url.deletingLastPathComponent().path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if isInspecting {
                ProgressView("Reading media information…")
                    .padding(.top, 10)
            } else if let inspection {
                inspectionSummary(inspection, sourceURL: url)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: 780)
    }

    private func inspectionSummary(_ inspection: MediaInspection, sourceURL: URL) -> some View {
        VStack(spacing: 14) {
            HumanReadableAnalysisView(inspection: inspection)

            ConversionPlanView(
                plan: ConversionPlan(
                    inspection: inspection,
                    gainEnabled: gainEnabled,
                    colorSelection: colorSelection,
                    subtitleSelection: subtitleSelection,
                    outputURL: outputURL,
                    completedOutputURL: conversionController.completedOutputURL,
                    managedPartialOutputURL: conversionController.managedPartialOutputURL
                ),
                sourceURL: sourceURL,
                subtitleStreams: inspection.subtitleStreams,
                sourceDynamicRange: MediaSummary(inspection: inspection).video?.dynamicRange,
                gainEnabled: $gainEnabled,
                colorSelection: $colorSelection,
                subtitleSelection: $subtitleSelection,
                outputURL: $outputURL,
                savedOutputFolderPath: $savedOutputFolderPath
            )

            VideoConversionControlsView(
                controller: conversionController,
                canStart: canStartVideoConversion(inspection: inspection),
                existingPartialOutput: existingPartialOutput,
                start: { startVideoConversion(sourceURL: sourceURL, inspection: inspection) }
            )

            TechnicalInspectionView(inspection: inspection)

            Text("Inspected read-only with ffprobe")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func handleSelection(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let source = urls.first else {
                selectionError = "No file was returned by the file picker."
                return
            }

            let sourceExtension = source.pathExtension.lowercased()
            guard ["mkv", "mp4", "m4v"].contains(sourceExtension) else {
                selectionError = "\(source.lastPathComponent) is not an MKV or MP4 file."
                return
            }

            conversionController.reset()
            selectedSource = source
            inspection = nil
            gainEnabled = true
            colorSelection = .needsConfirmation
            subtitleSelection = .needsChoice
            outputURL = nil
            if let savedFolder = validSavedOutputFolder {
                outputURL = OutputNaming.proposedURL(
                    sourceURL: source,
                    folderURL: savedFolder
                )
            }
            selectionError = nil
            inspect(source)

        case .failure(let error):
            selectionError = error.localizedDescription
        }
    }

    private var validSavedOutputFolder: URL? {
        guard !savedOutputFolderPath.isEmpty else { return nil }
        let folderURL = URL(fileURLWithPath: savedOutputFolderPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: folderURL.path(percentEncoded: false),
            isDirectory: &isDirectory
        ), isDirectory.boolValue else { return nil }
        return folderURL
    }

    private func inspect(_ source: URL) {
        isInspecting = true

        Task {
            defer { isInspecting = false }

            do {
                let probe = try MediaProbe()
                let result = try await probe.inspect(source)
                inspection = result
                colorSelection = ColorSelection(video: result.videoStreams.first)
                subtitleSelection = SubtitleSelection(
                    recommendation: SubtitleRecommendationEngine().recommend(
                        from: result.subtitleStreams,
                        primaryAudio: result.audioStreams.first
                    )
                )
            } catch {
                inspection = nil
                selectionError = error.localizedDescription
            }
        }
    }

    private func canStartVideoConversion(inspection: MediaInspection) -> Bool {
        guard !conversionController.isActive else { return false }
        return (try? VideoConversionCommand(
            sourceURL: selectedSource ?? URL(fileURLWithPath: "/"),
            outputURL: outputURL,
            inspection: inspection,
            gainEnabled: gainEnabled,
            colorSelection: colorSelection,
            subtitleSelection: subtitleSelection
        )) != nil
    }

    private var existingPartialOutput: URL? {
        guard let outputURL else { return nil }
        let partialURL = VideoConversionCommand.partialOutputURL(for: outputURL)
        return FileManager.default.fileExists(atPath: partialURL.path(percentEncoded: false))
            ? partialURL
            : nil
    }

    private func startVideoConversion(sourceURL: URL, inspection: MediaInspection) {
        do {
            let command = try VideoConversionCommand(
                sourceURL: sourceURL,
                outputURL: outputURL,
                inspection: inspection,
                gainEnabled: gainEnabled,
                colorSelection: colorSelection,
                subtitleSelection: subtitleSelection
            )
            guard let expectedVideo = inspection.videoStreams.first,
                  let expectedAudio = inspection.audioStreams.first,
                  let duration = inspection.format.duration.flatMap(Double.init) else {
                throw VideoConversionCommandError.noVideo(file: sourceURL.lastPathComponent)
            }
            try conversionController.start(
                command: command,
                expectedVideo: expectedVideo,
                expectedAudio: expectedAudio,
                videoMode: command.videoMode,
                colorSelection: colorSelection,
                durationSeconds: duration
            )
        } catch {
            selectionError = error.localizedDescription
        }
    }
}
