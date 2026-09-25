import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var conversionController = VideoConversionController()
    @State private var isChoosingSource = false
    @State private var sourceQueue: [URL] = []
    @State private var currentQueueIndex = 0
    @State private var approvedPlans: [Int: ApprovedConversion] = [:]
    @State private var completedQueueIndexes: Set<Int> = []
    @State private var isBatchReady = false
    @State private var isBatchRunning = false
    @State private var selectedSource: URL?
    @State private var inspection: MediaInspection?
    @State private var isInspecting = false
    @State private var selectionError: String?
    @State private var notificationError: String?
    @State private var gainEnabled = true
    @State private var aacStereoEnabled = false
    @State private var colorSelection = ColorSelection.needsConfirmation
    @State private var subtitleSelection = SubtitleSelection.needsChoice
    @State private var outputURL: URL?
    @AppStorage("savedOutputFolderPath") private var savedOutputFolderPath = ""
    @AppStorage("defaultGainEnabled") private var defaultGainEnabled = true
    @AppStorage("defaultSubtitleMode") private var defaultSubtitleMode = "recommended"
    @AppStorage("batchNotificationsEnabled") private var batchNotificationsEnabled = false

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

            if sourceQueue.count > 1 {
                sourceQueueView
            }

            if let selectedSource {
                selectedFileView(selectedSource)
            } else {
                Text("Choose one or more MKV or MP4 files to begin. Sources will only be read.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

                Button("Choose Videos…", systemImage: "folder") {
                    isChoosingSource = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInspecting || conversionController.isActive || isBatchRunning)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 560, minHeight: 360)
        .fileImporter(
            isPresented: $isChoosingSource,
            allowedContentTypes: Self.sourceTypes,
            allowsMultipleSelection: true
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
        .alert(
            "Batch Notifications Unavailable",
            isPresented: Binding(
                get: { notificationError != nil },
                set: { if !$0 { notificationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notificationError ?? "Notifications could not be enabled.")
        }
        .onChange(of: conversionController.phase) { _, phase in
            handleConversionPhaseChange(phase)
        }
    }

    private var sourceQueueView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(sourceQueue.enumerated()), id: \.offset) { index, source in
                    HStack(spacing: 8) {
                        Image(systemName: queueIcon(for: index))
                            .foregroundStyle(queueColor(for: index))
                        Text(source.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(queueStatus(for: index))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(index == currentQueueIndex ? .body.weight(.semibold) : .body)
                }
                Divider()
                Toggle(
                    "Notify when this batch finishes or stops",
                    isOn: Binding(
                        get: { batchNotificationsEnabled },
                        set: setBatchNotificationsEnabled
                    )
                )
                .disabled(isBatchRunning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(
                "Source queue · \(completedQueueCount) of \(sourceQueue.count) completed",
                systemImage: "list.number"
            )
                .font(.headline)
        }
        .frame(maxWidth: 760)
    }

    private func queueIcon(for index: Int) -> String {
        if isCompletedQueueItem(index) { return "checkmark.circle.fill" }
        if isBatchRunning && index == currentQueueIndex { return "play.circle.fill" }
        if approvedPlans[index] != nil { return "checkmark.circle" }
        if index == currentQueueIndex { return "play.circle.fill" }
        return "circle"
    }

    private func queueColor(for index: Int) -> Color {
        if isCompletedQueueItem(index) { return .green }
        if isBatchRunning && index == currentQueueIndex { return .accentColor }
        if approvedPlans[index] != nil { return .blue }
        if index == currentQueueIndex { return .accentColor }
        return .secondary
    }

    private func queueStatus(for index: Int) -> String {
        if isCompletedQueueItem(index) { return "Completed" }
        if isBatchRunning && index == currentQueueIndex { return "Converting" }
        if approvedPlans[index] != nil { return "Approved" }
        if index == currentQueueIndex { return "Reviewing" }
        return "Waiting"
    }

    private var completedQueueCount: Int {
        completedQueueIndexes.count
    }

    private func isCompletedQueueItem(_ index: Int) -> Bool {
        completedQueueIndexes.contains(index)
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
                    aacStereoEnabled: aacStereoEnabled,
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
                aacStereoEnabled: $aacStereoEnabled,
                colorSelection: $colorSelection,
                subtitleSelection: $subtitleSelection,
                outputURL: $outputURL,
                savedOutputFolderPath: $savedOutputFolderPath,
                saveDefaults: saveCurrentDefaults
            )
            .disabled(isBatchRunning || isBatchReady)

            if isBatchReady {
                batchReadyView
            }

            VideoConversionControlsView(
                controller: conversionController,
                canStart: canStartVideoConversion(inspection: inspection),
                startButtonTitle: startButtonTitle,
                batchItemNumber: isBatchRunning ? currentQueueIndex + 1 : nil,
                batchItemCount: sourceQueue.count,
                completedBatchCount: completedQueueIndexes.count,
                existingPartialOutput: existingPartialOutput,
                start: { performPrimaryAction(sourceURL: sourceURL, inspection: inspection) }
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
            guard !urls.isEmpty else {
                selectionError = "No file was returned by the file picker."
                return
            }

            let supportedSources = urls.filter {
                ["mkv", "mp4", "m4v"].contains($0.pathExtension.lowercased())
            }
            guard supportedSources.count == urls.count else {
                selectionError = "Every selected source must be an MKV or MP4 file."
                return
            }

            sourceQueue = supportedSources
            currentQueueIndex = 0
            approvedPlans = [:]
            completedQueueIndexes = []
            isBatchReady = false
            isBatchRunning = false
            guard let source = sourceQueue.first else { return }
            loadSource(source)

        case .failure(let error):
            selectionError = error.localizedDescription
        }
    }

    private var startButtonTitle: String {
        guard sourceQueue.count > 1 else { return "Convert Approved Plan" }
        if isBatchReady { return "Start Approved Batch" }
        return currentQueueIndex + 1 < sourceQueue.count
            ? "Approve Plan & Review Next"
            : "Approve Final Plan"
    }

    private var batchReadyView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("All \(sourceQueue.count) conversion plans are approved. No encoding has started yet.")
                Text("Start the batch when you are ready, or reopen the final plan to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reopen Final Plan", systemImage: "pencil") {
                    approvedPlans.removeValue(forKey: currentQueueIndex)
                    isBatchReady = false
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Batch ready to start", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
        }
        .frame(maxWidth: 760)
    }

    private func loadSource(_ source: URL) {
        conversionController.reset()
        selectedSource = source
        inspection = nil
        gainEnabled = defaultGainEnabled
        aacStereoEnabled = false
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
                let recommendedSelection = SubtitleSelection(
                    recommendation: SubtitleRecommendationEngine().recommend(
                        from: result.subtitleStreams,
                        primaryAudio: result.audioStreams.first
                    )
                )
                subtitleSelection = defaultSubtitleMode == "omit"
                    ? .omit
                    : recommendedSelection
            } catch {
                inspection = nil
                selectionError = error.localizedDescription
            }
        }
    }

    private func saveCurrentDefaults() {
        defaultGainEnabled = gainEnabled
        defaultSubtitleMode = subtitleSelection == .omit ? "omit" : "recommended"
    }

    private func canStartVideoConversion(inspection: MediaInspection) -> Bool {
        guard !conversionController.isActive else { return false }
        return (try? VideoConversionCommand(
            sourceURL: selectedSource ?? URL(fileURLWithPath: "/"),
            outputURL: outputURL,
            inspection: inspection,
            gainEnabled: gainEnabled,
            aacStereoEnabled: aacStereoEnabled,
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
                aacStereoEnabled: aacStereoEnabled,
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

    private func approveOrStart(sourceURL: URL, inspection: MediaInspection) {
        guard sourceQueue.count > 1 else {
            startVideoConversion(sourceURL: sourceURL, inspection: inspection)
            return
        }

        do {
            _ = try VideoConversionCommand(
                sourceURL: sourceURL,
                outputURL: outputURL,
                inspection: inspection,
                gainEnabled: gainEnabled,
                aacStereoEnabled: aacStereoEnabled,
                colorSelection: colorSelection,
                subtitleSelection: subtitleSelection
            )
            guard let outputURL else { return }
            approvedPlans[currentQueueIndex] = ApprovedConversion(
                sourceURL: sourceURL,
                inspection: inspection,
                outputURL: outputURL,
                gainEnabled: gainEnabled,
                aacStereoEnabled: aacStereoEnabled,
                colorSelection: colorSelection,
                subtitleSelection: subtitleSelection
            )

            if currentQueueIndex + 1 < sourceQueue.count {
                currentQueueIndex += 1
                loadSource(sourceQueue[currentQueueIndex])
            } else {
                isBatchReady = true
            }
        } catch {
            selectionError = error.localizedDescription
        }
    }

    private func performPrimaryAction(sourceURL: URL, inspection: MediaInspection) {
        if isBatchReady {
            beginApprovedBatch()
        } else {
            approveOrStart(sourceURL: sourceURL, inspection: inspection)
        }
    }

    private func beginApprovedBatch() {
        guard approvedPlans.count == sourceQueue.count else {
            selectionError = "Every queued video must have an approved plan before the batch can start."
            return
        }
        completedQueueIndexes = []
        isBatchReady = false
        isBatchRunning = true
        startApprovedConversion(at: 0)
    }

    private func startApprovedConversion(at index: Int) {
        guard let approved = approvedPlans[index] else {
            isBatchRunning = false
            selectionError = "The approved plan for video \(index + 1) is unavailable."
            sendBatchNotification(
                title: "SwiftyTranscoder Batch Stopped",
                body: "The approved plan for video \(index + 1) was unavailable."
            )
            return
        }
        currentQueueIndex = index
        selectedSource = approved.sourceURL
        inspection = approved.inspection
        outputURL = approved.outputURL
        gainEnabled = approved.gainEnabled
        aacStereoEnabled = approved.aacStereoEnabled
        colorSelection = approved.colorSelection
        subtitleSelection = approved.subtitleSelection
        conversionController.reset()
        startVideoConversion(sourceURL: approved.sourceURL, inspection: approved.inspection)
        if !conversionController.isActive {
            isBatchRunning = false
            sendBatchNotification(
                title: "SwiftyTranscoder Batch Stopped",
                body: "Conversion could not start for \(approved.sourceURL.lastPathComponent)."
            )
        }
    }

    private func handleConversionPhaseChange(_ phase: VideoConversionController.Phase) {
        guard isBatchRunning else { return }
        switch phase {
        case .completed:
            completedQueueIndexes.insert(currentQueueIndex)
            let nextIndex = currentQueueIndex + 1
            guard nextIndex < sourceQueue.count else {
                isBatchRunning = false
                sendBatchNotification(
                    title: "SwiftyTranscoder Batch Complete",
                    body: "Successfully converted \(sourceQueue.count) videos."
                )
                return
            }
            Task { @MainActor in
                await Task.yield()
                startApprovedConversion(at: nextIndex)
            }
        case .failed:
            isBatchRunning = false
            sendBatchNotification(
                title: "SwiftyTranscoder Batch Stopped",
                body: "Conversion failed for \(sourceQueue[currentQueueIndex].lastPathComponent)."
            )
        case .cancelled:
            isBatchRunning = false
            sendBatchNotification(
                title: "SwiftyTranscoder Batch Cancelled",
                body: "Stopped at \(sourceQueue[currentQueueIndex].lastPathComponent)."
            )
        default:
            break
        }
    }

    private func setBatchNotificationsEnabled(_ enabled: Bool) {
        guard enabled else {
            batchNotificationsEnabled = false
            return
        }
        Task { @MainActor in
            do {
                let granted = try await BatchNotificationService.requestAuthorization()
                batchNotificationsEnabled = granted
                if !granted {
                    notificationError = "Notifications were not allowed. You can change this in System Settings."
                }
            } catch {
                batchNotificationsEnabled = false
                notificationError = error.localizedDescription
            }
        }
    }

    private func sendBatchNotification(title: String, body: String) {
        guard batchNotificationsEnabled else { return }
        Task { @MainActor in
            do {
                try await BatchNotificationService.send(title: title, body: body)
            } catch {
                notificationError = error.localizedDescription
            }
        }
    }
}

private struct ApprovedConversion {
    let sourceURL: URL
    let inspection: MediaInspection
    let outputURL: URL
    let gainEnabled: Bool
    let aacStereoEnabled: Bool
    let colorSelection: ColorSelection
    let subtitleSelection: SubtitleSelection
}
