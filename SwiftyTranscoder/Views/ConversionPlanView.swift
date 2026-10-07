import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConversionPlanView: View {
    let plan: ConversionPlan
    let sourceURL: URL
    let subtitleStreams: [MediaStream]
    let sourceDynamicRange: String?
    let allowsAudioRemoval: Bool
    @Binding var removeAudio: Bool
    @Binding var outputResolution: OutputResolution
    @Binding var gainEnabled: Bool
    @Binding var aacStereoEnabled: Bool
    @Binding var colorSelection: ColorSelection
    @Binding var subtitleSelection: SubtitleSelection
    @Binding var outputURL: URL?
    @Binding var savedOutputFolderPath: String
    let saveDefaults: () -> Void
    @State private var defaultsSaved = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    planRow("Container", plan.container)
                    planRow("Video", plan.videoFormat)
                    GridRow {
                        Text("Output size").foregroundStyle(.secondary)
                        Picker("Output size", selection: $outputResolution) {
                            ForEach(OutputResolution.allCases, id: \.self) { resolution in
                                Text(resolution.label).tag(resolution)
                            }
                        }
                        .labelsHidden()
                        .disabled(!allowsAudioRemoval)
                    }
                    .font(.callout)
                    planRow("Dimensions", plan.videoDimensions)
                    planRow("Frame rate", plan.frameRate)
                    GridRow {
                        Text("Color")
                            .foregroundStyle(.secondary)
                        if sourceDynamicRange == "Not identified" {
                            Picker("Color", selection: $colorSelection) {
                                Text("Choose…")
                                    .tag(ColorSelection.needsConfirmation)
                                Text("I confirmed SDR — tag as BT.709")
                                    .tag(ColorSelection.confirmUntaggedAsBT709)
                            }
                            .labelsHidden()
                            .gridColumnAlignment(.leading)
                        } else {
                            Text(plan.colorHandling)
                                .gridColumnAlignment(.leading)
                        }
                    }
                    .font(.callout)
                    planRow("Audio", plan.audioFormat)
                    GridRow {
                        Text("Video only").foregroundStyle(.secondary)
                        Toggle("Remove all audio", isOn: $removeAudio)
                            .toggleStyle(.switch)
                            .disabled(!allowsAudioRemoval)
                            .gridColumnAlignment(.leading)
                    }
                    .font(.callout)
                    planRow("Output storage", plan.storageStatus)
                    GridRow {
                        Text("Gain")
                            .foregroundStyle(.secondary)
                        Toggle(plan.audioGain, isOn: $gainEnabled)
                            .disabled(removeAudio)
                            .toggleStyle(.switch)
                            .gridColumnAlignment(.leading)
                    }
                    .font(.callout)
                    GridRow {
                        Text("Extra audio")
                            .foregroundStyle(.secondary)
                        Toggle("Add AAC stereo compatibility track", isOn: $aacStereoEnabled)
                            .disabled(removeAudio)
                            .toggleStyle(.switch)
                            .gridColumnAlignment(.leading)
                    }
                    .font(.callout)
                    GridRow {
                        Text("Subtitles")
                            .foregroundStyle(.secondary)
                        Picker("Subtitles", selection: $subtitleSelection) {
                            if subtitleSelection == .needsChoice {
                                Text("Choose a track…")
                                    .tag(SubtitleSelection.needsChoice)
                            }
                            Text("Omit subtitles")
                                .tag(SubtitleSelection.omit)
                            ForEach(subtitleStreams) { stream in
                                Text(subtitleLabel(stream))
                                    .tag(SubtitleSelection.burnIn(streamIndex: stream.index))
                            }
                        }
                        .labelsHidden()
                        .gridColumnAlignment(.leading)
                    }
                    .font(.callout)
                    GridRow {
                        Text("Output")
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(plan.outputURL?.path(percentEncoded: false) ?? "Not selected")
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Button("Choose Folder…") {
                                chooseOutputFolder()
                            }
                        }
                        .gridColumnAlignment(.leading)
                    }
                    .font(.callout)
                }

                if outputResolution != .original {
                    Text("Smaller output keeps the picture’s proportions and never enlarges the source. Actual file size depends on the video and its length.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if removeAudio {
                    Text("The output will have no audio tracks. Gain and AAC settings are ignored for this file; the source remains unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if aacStereoEnabled && !removeAudio {
                    Label(
                        "AC-3 remains the default primary track; AAC stereo will be added as a secondary compatibility track.",
                        systemImage: "info.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Divider()
                HStack {
                    Button("Save Conversion Defaults", systemImage: "square.and.arrow.down") {
                        saveDefaults()
                        defaultsSaved = true
                    }
                    if defaultsSaved {
                        Label("Defaults saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Text("Future sources will reuse the gain and AAC stereo settings, and either automatic subtitle recommendations or Omit subtitles. Specific tracks and color confirmations are never reused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !plan.warnings.isEmpty {
                    Divider()
                    ForEach(plan.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Proposed conversion", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
        }
        .frame(maxWidth: 760)
        .onChange(of: gainEnabled) { _, _ in defaultsSaved = false }
        .onChange(of: aacStereoEnabled) { _, _ in defaultsSaved = false }
        .onChange(of: subtitleSelection) { _, _ in defaultsSaved = false }
    }

    private func planRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .gridColumnAlignment(.leading)
                .textSelection(.enabled)
        }
        .font(.callout)
    }

    private func subtitleLabel(_ stream: MediaStream) -> String {
        let language = stream.tags?["language"] ?? "unknown language"
        let title = stream.tags?["title"] ?? "untitled"
        var traits: [String] = []
        if stream.disposition?.forced == 1 { traits.append("forced") }
        if stream.disposition?.hearingImpaired == 1
            || title.localizedCaseInsensitiveContains("SDH") {
            traits.append("SDH")
        }
        let suffix = traits.isEmpty ? "" : " [\(traits.joined(separator: ", "))]"
        return "Stream \(stream.index) · \(language) · \(title)\(suffix)"
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.prompt = "Choose"
        panel.message = "SwiftyTranscoder will propose an MP4 filename in this folder. No file will be created yet."
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = outputURL?.deletingLastPathComponent()
            ?? sourceURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        savedOutputFolderPath = folderURL.path(percentEncoded: false)
        outputURL = OutputNaming.proposedURL(
            sourceURL: sourceURL,
            folderURL: folderURL
        )
    }
}
