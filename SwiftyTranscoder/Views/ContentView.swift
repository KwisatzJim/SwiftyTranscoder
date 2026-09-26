import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum WizardStep: Int, CaseIterable {
        case choose
        case review
        case plan
        case convert

        var title: String {
            switch self {
            case .choose: "Choose"
            case .review: "Review"
            case .plan: "Plan"
            case .convert: "Convert"
            }
        }
    }

    @StateObject private var conversionController = VideoConversionController()
    @State private var wizardStep = WizardStep.choose
    @State private var technicalDetailsExpanded = false
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
    @State private var queueIndexPendingRemoval: Int?
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
                wizardHeader

                switch wizardStep {
                case .choose:
                    chooseStep
                case .review:
                    reviewStep
                case .plan:
                    planStep
                case .convert:
                    convertStep
                }
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
        .confirmationDialog(
            "Remove this video from the batch?",
            isPresented: Binding(
                get: { queueIndexPendingRemoval != nil },
                set: { if !$0 { queueIndexPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from Batch", role: .destructive) {
                if let index = queueIndexPendingRemoval {
                    removeQueueItem(at: index)
                }
                queueIndexPendingRemoval = nil
            }
            Button("Keep Video", role: .cancel) {
                queueIndexPendingRemoval = nil
            }
        } message: {
            Text(queueRemovalMessage)
        }
        .onChange(of: conversionController.phase) { _, phase in
            handleConversionPhaseChange(phase)
        }
    }

    private var wizardHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tint)

                Text("SwiftyTranscoder")
                    .font(.largeTitle.bold())
            }

            HStack(spacing: 8) {
                ForEach(WizardStep.allCases, id: \.rawValue) { step in
                    Label(step.title, systemImage: wizardIcon(for: step))
                        .font(.callout.weight(step == wizardStep ? .semibold : .regular))
                        .foregroundStyle(step.rawValue <= wizardStep.rawValue ? Color.accentColor : Color.secondary)

                    if step != WizardStep.allCases.last {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
    }

    private func wizardIcon(for step: WizardStep) -> String {
        if step.rawValue < wizardStep.rawValue { return "checkmark.circle.fill" }
        if step == wizardStep { return "circle.inset.filled" }
        return "circle"
    }

    private var chooseStep: some View {
        VStack(spacing: 18) {
            Text("Choose one or more MKV or MP4 files to begin. Sources will only be read.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button("Choose Videos…", systemImage: "folder") {
                isChoosingSource = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 28)
    }

    @ViewBuilder
    private var reviewStep: some View {
        if let selectedSource {
            VStack(spacing: 14) {
                if sourceQueue.count > 1 {
                    sourceQueueView
                }
                selectedSourceHeader(selectedSource)

                if isInspecting {
                    ProgressView("Reading media information…")
                        .padding(.vertical, 24)
                } else if let inspection {
                    HumanReadableAnalysisView(inspection: inspection)

                    DisclosureGroup("Technical details", isExpanded: $technicalDetailsExpanded) {
                        TechnicalInspectionView(inspection: inspection)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: 760)

                    Text("Inspected read-only with ffprobe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Choose Different Videos") {
                        wizardStep = .choose
                    }
                    Spacer()
                    Button("Continue to Plan", systemImage: "arrow.right") {
                        wizardStep = .plan
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inspection == nil || isInspecting)
                }
                .frame(maxWidth: 760)
            }
        }
    }

    @ViewBuilder
    private var planStep: some View {
        if let selectedSource, let inspection {
            VStack(spacing: 14) {
                if sourceQueue.count > 1 {
                    sourceQueueView
                }
                selectedSourceHeader(selectedSource)
                conversionPlan(inspection, sourceURL: selectedSource)

                HStack {
                    Button("Back to Review", systemImage: "arrow.left") {
                        wizardStep = .review
                    }
                    Spacer()
                }
                .frame(maxWidth: 760)
            }
        }
    }

    @ViewBuilder
    private var convertStep: some View {
        if let selectedSource, let inspection {
            let blockingReason = conversionBlockingReason(inspection: inspection)

            VStack(spacing: 14) {
                if sourceQueue.count > 1 {
                    sourceQueueView
                }
                selectedSourceHeader(selectedSource)

                if isBatchReady {
                    batchReadyView
                }

                VideoConversionControlsView(
                    controller: conversionController,
                    canStart: blockingReason == nil
                        && (!isBatchReady || batchHasSufficientSpace && duplicateBatchOutputURLs.isEmpty),
                    disabledReason: blockingReason,
                    startButtonTitle: startButtonTitle,
                    batchItemNumber: isBatchRunning ? currentQueueIndex + 1 : nil,
                    batchItemCount: sourceQueue.count,
                    completedBatchCount: completedQueueIndexes.count,
                    existingPartialOutput: existingPartialOutput,
                    start: { performPrimaryAction(sourceURL: selectedSource, inspection: inspection) }
                )

                if !conversionController.isActive && !isBatchRunning {
                    Button("Choose More Videos…", systemImage: "folder") {
                        isChoosingSource = true
                    }
                }
            }
        }
    }

    private var sourceQueueView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(sourceQueue.enumerated()), id: \.offset) { index, source in
                    HStack(spacing: 8) {
                        if isBatchReady {
                            Button {
                                selectApprovedPlan(at: index)
                            } label: {
                                queueRow(index: index, source: source)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "Review \(source.lastPathComponent), \(queueStatus(for: index))"
                            )
                            .accessibilityHint("Shows this approved conversion plan")
                        } else {
                            queueRow(index: index, source: source)
                        }
                        Button(role: .destructive) {
                            queueIndexPendingRemoval = index
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(source.lastPathComponent) from this batch")
                        .accessibilityLabel("Remove \(source.lastPathComponent) from batch")
                        .accessibilityHint("Asks for confirmation and does not delete the source file")
                        .disabled(isBatchRunning || conversionController.isActive)
                    }
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

    private func queueRow(index: Int, source: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: queueIcon(for: index))
                .foregroundStyle(queueColor(for: index))
                .accessibilityHidden(true)
            Text(source.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(queueStatus(for: index))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .font(index == currentQueueIndex ? .body.weight(.semibold) : .body)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.lastPathComponent), \(queueStatus(for: index))")
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

    private var queueRemovalMessage: String {
        guard let index = queueIndexPendingRemoval, sourceQueue.indices.contains(index) else {
            return "The source file will not be changed or deleted."
        }
        return "\(sourceQueue[index].lastPathComponent) will leave this batch. The source file will not be changed or deleted."
    }

    private func removeQueueItem(at index: Int) {
        guard !isBatchRunning, !conversionController.isActive,
              sourceQueue.count > 1, sourceQueue.indices.contains(index) else { return }

        sourceQueue.remove(at: index)
        approvedPlans = QueueIndexRemapping.remap(approvedPlans, removing: index)
        completedQueueIndexes = QueueIndexRemapping.remap(completedQueueIndexes, removing: index)

        if sourceQueue.count == 1 {
            let remainingPlan = approvedPlans[0]
            approvedPlans = [:]
            isBatchReady = false
            currentQueueIndex = 0
            if let remainingPlan {
                restoreApprovedPlan(remainingPlan)
            } else {
                loadSource(sourceQueue[0])
            }
            return
        }

        currentQueueIndex = QueueIndexRemapping.currentIndex(
            currentQueueIndex,
            removing: index,
            remainingCount: sourceQueue.count
        )

        isBatchReady = approvedPlans.count == sourceQueue.count
        if isBatchReady, let plan = approvedPlans[currentQueueIndex] {
            restoreApprovedPlan(plan)
        } else if selectedSource.map({ !sourceQueue.contains($0) }) ?? true {
            loadSource(sourceQueue[currentQueueIndex])
        }
    }

    private func selectedSourceHeader(_ url: URL) -> some View {
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
        }
        .frame(maxWidth: 780)
    }

    private func conversionPlan(_ inspection: MediaInspection, sourceURL: URL) -> some View {
        let conversionBlockingReason = conversionBlockingReason(inspection: inspection)

        return VStack(spacing: 14) {
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

            VideoConversionControlsView(
                controller: conversionController,
                canStart: conversionBlockingReason == nil,
                disabledReason: conversionBlockingReason,
                startButtonTitle: startButtonTitle,
                batchItemNumber: nil,
                batchItemCount: sourceQueue.count,
                completedBatchCount: completedQueueIndexes.count,
                existingPartialOutput: existingPartialOutput,
                start: { performPrimaryAction(sourceURL: sourceURL, inspection: inspection) }
            )
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
            technicalDetailsExpanded = false
            wizardStep = .review

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
                Text("Select any queue row to review it. Start the batch when you are ready, or reopen the selected plan to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                if let checks = batchDestinationSpaceChecks {
                    ForEach(checks) { check in
                        Label(
                            "\(check.volumeName): \(DestinationSpaceCheck.format(check.availableBytes)) available; \(DestinationSpaceCheck.format(check.requiredBytes)) required for this batch",
                            systemImage: check.isSufficient ? "externaldrive.fill.badge.checkmark" : "externaldrive.fill.badge.exclamationmark"
                        )
                        .font(.caption)
                        .foregroundStyle(check.isSufficient ? Color.secondary : Color.orange)
                    }
                } else {
                    Label(
                        "Batch destination space could not be verified. Batch start is blocked.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if duplicateBatchOutputURLs.isEmpty {
                    Label("Every approved output filename is unique.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(duplicateBatchOutputURLs, id: \.self) { output in
                        Label(
                            "Duplicate batch destination: \(output.path(percentEncoded: false))",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                Button("Reopen Selected Plan", systemImage: "pencil") {
                    approvedPlans.removeValue(forKey: currentQueueIndex)
                    isBatchReady = false
                    wizardStep = .plan
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

    private func conversionBlockingReason(inspection: MediaInspection) -> String? {
        guard !conversionController.isActive else { return nil }
        do {
            _ = try VideoConversionCommand(
                sourceURL: selectedSource ?? URL(fileURLWithPath: "/"),
                outputURL: outputURL,
                inspection: inspection,
                gainEnabled: gainEnabled,
                aacStereoEnabled: aacStereoEnabled,
                colorSelection: colorSelection,
                subtitleSelection: subtitleSelection
            )
            return nil
        } catch {
            return error.localizedDescription
        }
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
            wizardStep = .convert
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

            if approvedPlans.count == sourceQueue.count {
                isBatchReady = true
                wizardStep = .convert
            } else if let nextIndex = nextUnapprovedIndex {
                currentQueueIndex = nextIndex
                loadSource(sourceQueue[nextIndex])
                technicalDetailsExpanded = false
                wizardStep = .review
            } else {
                selectionError = "A waiting video could not be found in the queue."
            }
        } catch {
            selectionError = error.localizedDescription
        }
    }

    private var nextUnapprovedIndex: Int? {
        let laterIndexes = sourceQueue.indices.filter {
            $0 > currentQueueIndex && approvedPlans[$0] == nil
        }
        return laterIndexes.first ?? sourceQueue.indices.first {
            approvedPlans[$0] == nil
        }
    }

    private func selectApprovedPlan(at index: Int) {
        guard isBatchReady, let approved = approvedPlans[index] else { return }
        currentQueueIndex = index
        restoreApprovedPlan(approved)
    }

    private func restoreApprovedPlan(_ approved: ApprovedConversion) {
        selectedSource = approved.sourceURL
        inspection = approved.inspection
        outputURL = approved.outputURL
        gainEnabled = approved.gainEnabled
        aacStereoEnabled = approved.aacStereoEnabled
        colorSelection = approved.colorSelection
        subtitleSelection = approved.subtitleSelection
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
        guard batchHasSufficientSpace else {
            selectionError = "The approved batch requires more destination space than is currently available."
            return
        }
        guard duplicateBatchOutputURLs.isEmpty else {
            selectionError = "Two or more approved plans use the same output filename. Reopen a plan and choose a different destination folder."
            return
        }
        completedQueueIndexes = []
        isBatchReady = false
        isBatchRunning = true
        startApprovedConversion(at: 0)
    }

    private var batchHasSufficientSpace: Bool {
        batchDestinationSpaceChecks?.allSatisfy(\.isSufficient) == true
    }

    private var batchDestinationSpaceChecks: [BatchDestinationSpaceCheck]? {
        guard approvedPlans.count == sourceQueue.count else { return nil }
        var checksByVolume: [String: BatchDestinationSpaceCheck] = [:]

        for approved in approvedPlans.values {
            guard let itemCheck = DestinationSpaceCheck.evaluate(
                inspection: approved.inspection,
                outputURL: approved.outputURL
            ) else { return nil }
            let folderURL = approved.outputURL.deletingLastPathComponent()
            guard let values = try? folderURL.resourceValues(
                forKeys: [.volumeIdentifierKey, .volumeNameKey]
            ), let identifier = values.volumeIdentifier else { return nil }
            let key = String(describing: identifier)
            let volumeName = values.volumeName ?? folderURL.path(percentEncoded: false)

            if let existing = checksByVolume[key] {
                let total = existing.requiredBytes.addingReportingOverflow(itemCheck.requiredBytes)
                guard !total.overflow else { return nil }
                checksByVolume[key] = BatchDestinationSpaceCheck(
                    id: key,
                    volumeName: volumeName,
                    availableBytes: min(existing.availableBytes, itemCheck.availableBytes),
                    requiredBytes: total.partialValue
                )
            } else {
                checksByVolume[key] = BatchDestinationSpaceCheck(
                    id: key,
                    volumeName: volumeName,
                    availableBytes: itemCheck.availableBytes,
                    requiredBytes: itemCheck.requiredBytes
                )
            }
        }

        return checksByVolume.values.sorted { $0.volumeName < $1.volumeName }
    }

    private var duplicateBatchOutputURLs: [URL] {
        let grouped = Dictionary(grouping: approvedPlans.values) { approved in
            CanonicalOutputPath.key(for: approved.outputURL)
        }
        return grouped.values.compactMap { matches in
            guard matches.count > 1 else { return nil }
            return matches[0].outputURL
        }
        .sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
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

private struct BatchDestinationSpaceCheck: Identifiable {
    let id: String
    let volumeName: String
    let availableBytes: Int64
    let requiredBytes: Int64

    var isSufficient: Bool { availableBytes >= requiredBytes }
}
