# Milestone 127 — Local 1.6.0 release

After the user confirmed audio removal, corrected movie duration, and full conversion/playback of the delayed-layout E-AC-3 source, version 1.6.0 (16) was packaged.

The release includes per-file Remove all audio and CLI `--audio omit` for ordinary conversion, omission of malformed chapter lists that extend beyond the movie, and expanded bounded media inspection to identify delayed speaker layouts. AI restoration continues to require audio; valid chapters retain their existing behavior.

Artifact: `dist/SwiftyTranscoder_1.6.0_arm64.dmg`.

SHA-256: `fcf254cb9ef2cb7b13a4b352d1287d9d18397a9f4f9cc0bd7ccd169680f9abb3`.

All 172 regression tests in 42 suites passed. The release process rebuilt the bundled tools, validated pinned models, checked app/helper signatures and required resources, verified DMG integrity, and independently checked the read-only mounted installer and launcher.

Packaged-app checks passed for ordinary MKV/MP4 conversion, gain/AC-3/AAC, cancellation, video-only output, identical MP4 compressed-video hash, reduced size, silent input, longer audio tails, collision refusal, and rejection of deliberately retained audio before promotion. A short malformed-chapter fixture produced the expected duration with no chapters; the reported E-AC-3 source passed packaged CLI dry-run approval. Earlier installer checksums remain valid. Evidence is in `.build/milestone127-evidence/` and the release log.

The user confirmed installed 1.6.0 acceptance. GitHub publication is authorized.
