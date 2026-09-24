# Milestone 21 — Saved Conversion Profiles

## Goal

Reduce repetitive choices across sources and launches without reusing unsafe source-specific decisions.

## Step 1 — Saved gain and subtitle defaults

The conversion plan now offers **Save Gain & Subtitle Defaults**. It stores the current gain state and one safe subtitle policy: use SwiftyTranscoder's automatic recommendation or omit subtitles.

The saved defaults apply when each new source is loaded, including later queue items and future app launches. A specific subtitle stream number is never carried to another source, because stream indexes have meaning only within their own file. Color confirmation is also never saved; untagged sources continue to require explicit confirmation.

The user confirmed the saved gain and omit-subtitles choices applied to a different source, persisted after quitting and relaunching the app, and could be restored to the normal +6 dB with automatic subtitle-recommendation workflow.

One saved default profile is sufficient for the current reusable settings. Named profiles are deferred until the app has additional safe, meaningful settings to distinguish them. Milestone 21 is complete.
