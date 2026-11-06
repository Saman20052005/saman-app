# CP-AI-08 — Offline workout recommendation evaluation protocol

## Objective and limits

This evaluation checks the current CP-AI-05 rule-based ranker against
predeclared synthetic behavior cases and a canonical-ID-only control. It does
not train, tune, or select a model, and synthetic cases are not evidence of
recommendation quality for real users.

The local generated exercise catalog is the only catalog source. No account,
production, or live Mongo data is read. There is no approved human-reviewed
relevance set in the workspace or handoff, so relevance NDCG@5 is **MISSING**.
A separately reported, deliberately synthetic temporal holdout demonstrates
Hit@5 mechanics only; it is not a real-user estimate.

## Source-audited signals

The audit was made from `backend/app/services/workout_recommendation.py`,
`backend/app/services/exercise_catalog_resolver.py`, the generated catalog,
and the CP-AI-03 history normalizer in `backend/routers/chat.py`.

| Input | Actual use |
|---|---|
| `requested_muscle_groups` | Case-insensitive exact token match against `muscleGroup`, then `targetMuscles`, then `secondaryMuscles`. The first matching tier contributes to the score; only candidates with valid matching metadata remain. No synonym or broad-group inference is applied. |
| `available_equipment` | `None` means no equipment filter and yields `limited_context`/equipment clarification. An explicit list is a case-insensitive exact set; all candidate-required equipment tokens must be in it. Missing or malformed candidate equipment metadata fails closed. |
| History | Only owner-matched sessions with a parseable timestamp in the fixed 90-day window through `now` are considered. For a session, each resolved canonical exercise ID is counted at most once. A count is capped at three for the score penalty. Empty, unavailable, and normalization-error history remain distinct. |
| Profile `activity_level`, `goal` | Read for provenance only. `profile_fields_used` is empty; neither field changes candidate filtering or score. |
| Experience, equipment in profile, injuries, schedule | Not persisted/used by this baseline; no suitability or medical inference is made. |

History timestamps are tried in this order: `start_time`, `started_at`,
`created_at`, `date`, `end_time`, `finished_at`. History identity passes
through the existing injected normalizer and generated-catalog resolver.
Unknown canonical IDs and conflicting ID/slug pairs are ignored for scoring;
the resolver can resolve a synthetic `plan_ex_` ID only with an exact catalog
slug. For history ownership, any present `user_id`, `email`, or `user_email`
must match the principal, and at least one such owner field must be present.

Production candidates are validated/re-resolved by canonical ID and slug,
deduplicated, sorted by score descending then canonical ID ascending, and
capped at five. The ranker emits muscle-tier, equipment-filter,
recent-history, general-baseline, and canonical-ID tie-break reason codes
only for the corresponding signals.

## Data and predeclared scenarios

The fixture uses the 49 records in
`backend/app/data/ai_exercise_catalog.generated.json`. It contains no real
identity or workout data. Its synthetic principal uses an `.invalid` email;
the profile and history readers are in-memory fixture readers.

Before the run, `synthetic_fixture.json` declared expected status, candidate
count, history state, top IDs, and the expected temporal result:

| Case | Expected check |
|---|---|
| Cold start / tie | Empty history, no explicit filters, 49 candidates, first five canonical IDs, tie reason present. |
| History + equipment + muscle | One Ab Wheel/Abs candidate with one resolved recent session; all three signal reasons present. |
| Equipment + muscle, no history | Exactly one eligible candidate, no history reason. |
| Unresolved/conflicting history IDs | Two unresolved IDs, no history score/count, general catalog ordering. |
| No matching muscle | Zero eligible candidates and an empty recommendation list. |
| Synthetic temporal holdout | Five chest sessions strictly before cutoff; the target is a separate post-cutoff `push-up` record. Context uses only pre-cutoff events. Expected production Hit@5 is 1/1; expected canonical-ID control Hit@5 is 0/1. |

The holdout target is not passed to context construction or ranking. The
prediction time is one microsecond before the cutoff. The ID control uses the
same case-insensitive exact muscle/equipment filters over the same validated
catalog and then sorts solely by ascending canonical ID; it has no history or
score. Its candidate eligibility helper duplicates only the filter boundary,
not the production score/ranking formula.

## Metrics and denominators

* **Behavior checks:** count assertions and pass rate for each case group.
  Some groups intentionally overlap (for example equipment/muscle and
  under-five-candidate checks); each group rate uses its own listed
  assertions.
* **Temporal prediction:** Hit@5 = eligible held-out targets in Top 5 divided
  by held-out targets that resolve in the catalog and pass filters. Targets
  outside the catalog or removed by filters are counted and named separately,
  not silently included in the denominator.
* **Human relevance:** NDCG@5 requires assessor-judged relevance labels and is
  **MISSING** because no approved labeled set is available. The synthetic
  temporal Hit@5 is a deterministic contract example, not a population
  metric.

No random sampling is used; there is no random seed. Tie order is fixed by
ascending canonical ID.

## Reproducible execution

From the workspace root, using the existing Python 3.11.9 interpreter:

```powershell
D:\SamanDev\runtime\saman-cp7-python\Scripts\python.exe -B D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\run-20261103T115621Z\offline_evaluation.py --workspace D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840 --fixture D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\run-20261103T115621Z\synthetic_fixture.json --output-dir D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\run-20261103T115621Z
```

The harness imports the production ranker/resolver and the existing
normalizer. Socket connect/send operations and database/provider imports are
blocked. It uses no database, network, provider, random seed, or additional
dependency. It writes `results.json` and `run.log` next to the harness and
fixture; source and catalog SHA-256 values are included in the result.
