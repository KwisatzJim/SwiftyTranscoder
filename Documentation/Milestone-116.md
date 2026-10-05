# Milestone 116 — Remember the selected AI model

After accepting the completion summary, the user authorized the next focused improvement. The AI model picker now writes the selected method to SwiftUI AppStorage under `preferredRestorationMethod`. Loading a new source restores that preference, including after quitting and reopening the app. Absent or unrecognized values use the existing detailed-model default.

The live per-source selection remains separate from the preference. Revisiting an approved batch file restores its reviewed model without overwriting the preference. Only an explicit picker selection writes the preference. Previously approved batch jobs retain their existing plans. AI restoration is still enabled explicitly for each source.

The completion summary from milestone 115 is included in the development build. The installed 1.3.0 app and existing installer are unchanged. No transcoding, model processing, or CLI behavior changed.

Validation: optimized Xcode build, strict deep signature verification, and whitespace checks passed. This is a reversible UI preference change; no implementation-mirroring unit tests were added. The user confirmed the relaunch check; the saved model preference is accepted.

Test app: `.build/Milestone116DerivedData/Build/Products/Release/SwiftyTranscoder.app`. User checkpoint: select Lightweight AI for a source, quit and reopen this same test app, load a source and enable AI restoration, and confirm Lightweight AI is already selected. No restoration run is required for this checkpoint.
