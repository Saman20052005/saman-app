# CP-AI-08 — Offline workout recommendation evaluation

## Status

**PASS — offline contract evaluation completed.** All predeclared synthetic
behavior checks passed, and the production ranker ran against the generated
catalog. **Recommendation quality on real users remains UNVERIFIED.**
Human-labeled relevance / NDCG@5 is **MISSING**; the only Hit@5 result is from
one deliberately synthetic temporal holdout.

## Context and workspace

- **Project Context File:** MISSING in the workspace.
- **Workspace root:** `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840`
- **Branch / HEAD:** `agent/nutrition-active-localhost-f02` /
  `10be1ab1971214acd2487ef893df3fcc80212fc9`
- **Git status:** 3,759 existing porcelain entries before CP-AI-08 docs were
  added; 3,761 after adding these two docs. The CP-AI-05 recommendation
  service, resolver, generated catalog, and relevant tests were already
  untracked WIP; preserved read-only. The CP-AI-08 documentation path was
  clean before this task.
- **Handoff:** CP-AI-07 local Flutter Web acceptance was PASS per its report;
  that validates the E2E flow, not ranking quality. CP-AI-05 defines this as
  a deterministic rule-based baseline, not a trained model.
- **Git operations:** No commit, push, merge, reset, clean, stash, or checkout.
- **Runtime/app changes:** None. No production service, database, or AI
  provider was accessed.

## Files written

- `docs/ai_coach/CP-AI-08/EVALUATION_PROTOCOL.md`
- `docs/ai_coach/CP-AI-08/REPORT.md`
- `D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\run-20261103T115621Z\offline_evaluation.py`
- `D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\run-20261103T115621Z\synthetic_fixture.json`
- `D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\run-20261103T115621Z\results.json`
- `D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\run-20261103T115621Z\run.log`
- `D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\run-20261103T115621Z\baseline-tests.log`

## Execution and fingerprints

| Item | Result |
|---|---|
| Interpreter | `D:\SamanDev\runtime\saman-cp7-python\Scripts\python.exe`, Python 3.11.9 |
| Seed | None; deterministic fixture and fixed canonical-ID tie-break |
| Catalog | 49 resolved records |
| Final harness exit | 0 |
| Cases | 6 total: 5 behavior cases plus 1 synthetic temporal holdout |
| Failures | 0 |
| Network / DB / provider | Socket connect/send and database/provider imports blocked; no forbidden module loaded |

Source and catalog SHA-256 fingerprints:

| Source | SHA-256 |
|---|---|
| `backend/app/services/workout_recommendation.py` | `090c18ea166d745034f6041475d3a0d0ce08566d472212940c95af2c4cfb04f7` |
| `backend/app/services/exercise_catalog_resolver.py` | `92107f79cdd92fa1b2ce71a5336a315173cb3a18755ea0783e0eb0e5c8df6075` |
| `backend/app/data/ai_exercise_catalog.generated.json` | `fb955cb9f2dfe962952c6fa9fbca0e2de65d19480584bbd2a715fdeca0221c33` |
| `backend/routers/chat.py` (normalizer source) | `2ab7dbf23e2b0dac0ad89970087bde5a20682c68469b1538f38c272530488f36` |
| `backend/tests/test_ai03_workout_history_context.py` (helper loader) | `64d131d8ec3523faec5d4ba6e7d4d1fe526798c2b333ca28a276ccb7db7efe64` |
| Fixture | `dd8c85d8ad8cd7f0dbf43f5fb8d65e455b00c467382d398a71e357e0a8523086` |
| Final harness | `a13973db8d46d099a6a90e5e7366a544dea448824c1db68d3e5296a772eb85be` |

The first harness attempt exited 1 because its initial import guard treated
the interpreter's preloaded generic `google` namespace as an AI provider.
Inspection showed no `google.generativeai` or `google.genai` module was
loaded. The guard was narrowed to the actual provider modules and the final
run passed; no source or catalog file was changed.

## Results

All expected cases and output invariants passed: at most five unique IDs,
every returned canonical ID/slug resolves in the catalog, and reason codes
match the actual muscle, equipment, history, and tie signals.

| Case / group | Candidate count | Production ranker Top IDs | Canonical-ID control Top IDs | Result |
|---|---:|---|---|---|
| Cold start / tie | 49 | `ab-wheel-rollout`, `barbell-back-squat`, `barbell-bench-press`, `barbell-hip-thrust`, `barbell-overhead-press` | Same | PASS; empty history, score ties, canonical-ID tie reasons |
| History + equipment + muscle | 1 | `ab-wheel-rollout` | `ab-wheel-rollout` | PASS; resolved count 1, score 90, reasons `requested_muscle_primary_match`, `available_equipment_filter`, `recent_history_variety` |
| Equipment + muscle without history | 1 | `ab-wheel-rollout` | `ab-wheel-rollout` | PASS; score 100, no history reason |
| Unresolved/conflicting history IDs | 49 | Same canonical first five as cold start | Same | PASS; two history IDs unresolved, no resolved history count/reason |
| Muscle filter with no match | 0 | Empty | Empty | PASS; `no_candidates` |
| Synthetic temporal holdout | 9 | `incline-dumbbell-press`, `machine-chest-press`, `pec-deck-fly`, `push-up`, `barbell-bench-press` | `barbell-bench-press`, `cable-chest-fly`, `db-bench-press`, `incline-barbell-bench-press`, `incline-dumbbell-flyes` | PASS; target `push-up` is eligible and included only by production Top 5 |

The temporal cutoff is `2026-11-01T00:00:00+07:00`; five synthetic history
events strictly precede it, and the synthetic target event is
`2026-11-02T08:00:00+07:00`. Only the five pre-cutoff events were passed to
context construction. The result is **production Hit@5 1/1** versus
**canonical-ID control Hit@5 0/1**. There were zero temporal targets outside
the catalog or filtered out (eligible denominator: 1).

Group assertion rates from `results.json`:

| Group | Passed / checks | Pass rate |
|---|---:|---:|
| Cold start | 26 / 26 | 100% |
| Equipment/muscle filter | 28 / 28 | 100% |
| Filter exclusion | 10 / 10 | 100% |
| History signal | 15 / 15 | 100% |
| Output integrity | 20 / 20 | 100% |
| Temporal holdout | 8 / 8 | 100% |
| Tie-break | 26 / 26 | 100% |
| Under five candidates | 28 / 28 | 100% |
| Unresolved history ID | 28 / 28 | 100% |

Group counts overlap because a scenario belongs to multiple check groups.
The history case where production wins over the control is a constructed
synthetic example, not evidence that the baseline is generally more relevant.
No separately approved user/event dataset or human-judged relevance labels
were available; therefore human NDCG@5 and real-user temporal Hit@5 are
**MISSING**.

## Verification commands

| Command | Exit | Result |
|---|---:|---|
| `D:\SamanDev\runtime\saman-cp7-python\Scripts\python.exe -B -m unittest backend.tests.test_ai05_workout_recommendation backend.tests.test_ai04_catalog_resolver backend.tests.test_ai03_workout_history_context -v` | 0 | 41 passed, 0 failed, 0 skipped; captured before CP-AI-08 documentation changes |
| `D:\SamanDev\runtime\saman-cp7-python\Scripts\python.exe -B D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\run-20261103T115621Z\offline_evaluation.py --workspace D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840 --fixture D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\run-20261103T115621Z\synthetic_fixture.json --output-dir D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\run-20261103T115621Z` | 0 | 6/6 cases PASS; result and log saved in the run folder |
| `git diff --check -- docs/ai_coach/CP-AI-08` | 0 | No tracked CP-AI-08 changes; the new docs were separately checked below |
| Focused Python `-B` read check for UTF-8, final newline, and trailing whitespace on both new docs | 0 | Both valid UTF-8, final newline present, 0 trailing-whitespace lines |

## Findings and follow-up

**No baseline defect was reproduced.** The offline behavior assertions agree
with the CP-AI-05 contract. This is not a claim that the current heuristic is
optimal or a trained model.

**UNVERIFIED:** ranking relevance on human judgments and next-exercise
prediction on real, approved longitudinal data.

**MISSING:** approved human-assessed relevance data and approved, timestamped
workout-selection logs for a real temporal holdout.

Before proposing an ML checkpoint, ask the instructor exactly:

> “Is the requirement to train a learned workout-recommendation model, rather
> than only evaluate the current deterministic baseline? If yes, what
> prediction target, approved dataset, and user/time holdout and metric should
> be used?”

Required before that checkpoint: instructor-approved, privacy-cleared
workout/session records with stable pseudonymous user IDs, canonical exercise
IDs, trustworthy timestamps/timezone, the context and explicit filters
available at each prediction point, and post-cutoff selected-exercise labels.
For ranking suitability, additionally require human-reviewed graded
relevance labels, an assessor protocol, and train/validation/test separation
by user and time. The instructor must choose the target and metric (for
example Hit@5 for next selection versus NDCG@5 for graded relevance). Do not
call this baseline a trained model or tune its weights from these synthetic
results.
