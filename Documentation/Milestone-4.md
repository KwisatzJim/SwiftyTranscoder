# Milestone 4 — Deterministic subtitle recommendation

## Step 1: Forced-English rules

### Goal

Recommend a forced-English subtitle only when deterministic metadata supports the choice. Do not use packet counts, duration, or other statistical guessing yet.

### Rules implemented

1. Consider every English subtitle track.
2. Prefer an explicit Matroska forced disposition over title-only evidence.
3. Recognize the title word `Forced` and the phrase `Foreign Parts Only`.
4. Prefer a non-SDH candidate when multiple candidates have equally strong evidence.
5. Select only when one candidate remains; otherwise require user choice.
6. Do not treat an ordinary English or English SDH track as forced.

### User-facing outcomes

- `Forced English found—burn in`
- `Multiple forced English tracks—choose one`
- `No forced English identified`

The chosen stream number, title, and reason are visible. This milestone recommends a future action but performs no subtitle burn-in or media conversion.

### Verification

The Debug application build succeeded. The recommendation engine was then tested independently with:

- The real `Reacher - s04e08 - Cut.mkv` metadata: selected stream 2, `American English [Forced]`, because it carries the forced disposition. Stream 3, `American English [SDH]`, was not selected.
- A synthetic fixture containing two equally strong forced-English candidates: returned both candidates as ambiguous and selected neither.

Runtime presentation confirmation remains pending.
