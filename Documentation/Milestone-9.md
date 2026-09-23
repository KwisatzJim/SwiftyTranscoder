# Milestone 9 — Full English subtitles for foreign-language films

## Step 1: Conservative metadata policy

The live 12-file sample inventory contains no confirmed foreign-language primary audio track. Eleven primary tracks are explicitly tagged English. `Lanterns - s01e06 - Bad Optics.mkv` has no primary-audio language tag and must remain unknown rather than being guessed foreign.

The recommendation engine now follows these rules:

- Trigger the foreign-film path only for an explicit, non-English primary-audio language
- Treat missing, empty, `und`, and `unknown` audio language as unknown
- Consider every English subtitle track
- Exclude forced and `Foreign Parts Only` tracks from full-English candidates
- Prefer ordinary full English over English SDH
- Prefer a supported text subtitle over an image-based candidate at the same accessibility level
- Recommend the only remaining best candidate and preselect burn-in
- If multiple equally preferred candidates remain, show them and require a choice
- If none remain, report that no full-English track was identified

The existing picker keeps every decision visible and changeable. No live sample is claimed as a foreign film without supporting metadata.

### Verification

The Debug application build succeeded. A metadata-only harness exercised the production recommendation engine with controlled stream descriptions:

- Spanish audio plus ordinary English, English SDH, and English forced selected the ordinary full-English stream
- Spanish audio plus two ordinary English tracks returned both as ambiguous and selected neither
- Spanish audio plus only an English forced track reported no full-English candidate
- Unknown audio language plus forced and ordinary English remained on the forced-English path rather than being classified foreign

All assertions passed. At that point, the original 12-file inventory contained no explicitly foreign-language sample; two real samples were subsequently added below.

## Step 2: Real foreign-language samples

Two Russian-language MKVs were added after the initial implementation.

### Come and See (1985)

- Primary audio: Russian AAC mono at 48 kHz
- English stream 3: ordinary/default SubRip titled `SRT`
- English stream 4: image-based PGS titled `PGS`

At equal accessibility level, the engine now prefers supported text-based SubRip over image-based PGS. Both remain visible in the picker. The PGS track is not treated as text and cannot enter the current SubRip command path silently.

### Mr. Nobody Against Putin (2025)

- Primary audio: Russian AAC stereo at 44.1 kHz
- English stream 2: SubRip titled `SDH`
- No ordinary English candidate

The only complete English candidate is therefore SDH. The engine recommends it while explicitly identifying it as SDH; the user can still change or omit the choice.

These files also expose later conversion-scope work: the current first audio path accepts only 48 kHz 5.1 input, while these sources use mono 48 kHz and stereo 44.1 kHz. `Come and See` is also 10-bit HEVC. Recommendation testing is safe, but full conversion must remain blocked until those formats are deliberately supported.

### Runtime verification

The user confirmed the real application behavior for both files:

- `Come and See (1985).mkv` was identified as Russian audio, recommended `Foreign-language audio—burn full English`, and preselected ordinary English SubRip stream 3 while leaving PGS stream 4 visible and unselected.
- `Mr. Nobody Against Putin (2025).mkv` was identified as Russian audio, recommended `Foreign-language audio—burn full English`, and preselected English SDH stream 2 because it is the only full-English candidate.
- The subtitle picker remained visible and changeable.
- Conversion remained blocked for the separately identified unsupported media formats.

Milestone 9's detection, recommendation, preference, ambiguity, and user-control requirements are complete. Full conversion of these broader source formats belongs to the compatibility expansion and end-to-end validation work.
