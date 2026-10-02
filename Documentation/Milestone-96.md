# Milestone 96 — Saved AAC stereo default

The existing saved-defaults action now includes the optional AAC stereo compatibility track. A new persistent Boolean defaults to false, preserving existing behavior until the user explicitly saves a different choice. Loading a new source uses the saved AAC setting; restoring an already approved queue plan continues to use that plan's own setting.

The button is renamed **Save Conversion Defaults**. Its explanation names gain, AAC stereo, and subtitle policy. Changing AAC stereo clears the saved confirmation, just like changing gain or subtitle policy. Source-specific subtitle tracks and color confirmations are still never saved.

The Release Xcode build and signed-app resource verification passed. Diff whitespace checks passed. Persistence and UI behavior await hands-on confirmation.

Hands-on check: enable AAC stereo, save defaults, load another source, and confirm it remains enabled. Quit and reopen the app and repeat. Then disable AAC stereo and save if that is the desired normal preference. Previously approved batch plans must retain their approved choices.
