# CP-AI-05 — Rule-Based Workout Recommendation Baseline

## Scope and trust boundary

This is an internal, read-only **rule-based baseline**, not a trained model.
It has no route, UI, Chat, or AI-provider integration.

`load_workout_recommendation_context()` receives:

- The authenticated principal from a trusted backend caller.
- A profile reader accepting the principal-derived email.
- A history reader accepting the principal-derived owner ID.
- The caller-injected CP-AI-03/04 exercise-history normalizer and date parser.
- The existing generated-catalog resolver.

It accepts no client-provided profile, history, or owner identifier. The
profile record must match the authenticated email and, when present, owner ID.
Each history row must contain a matching owner ID or email; conflicting or
foreign-owner records are excluded. The profile/history readers are trusted
dependencies and must query by the supplied principal identity.

No database, router, provider, or write dependency is imported by the service.
The history normalizer remains the CP-AI-03/04 helper, passed in by the
caller/test rather than imported from the router.

## Context schema

The context is an internal dictionary containing:

| Field | Meaning |
|---|---|
| `profile_status` | `available`, `missing`, or `unavailable`; read errors and ownership mismatch include a reason code. |
| `profile_fields.activity_level`, `profile_fields.goal` | Persisted values, each with `known`/`unknown` status and source (`profile.<field>` or root mirror). |
| `profile_fields_used` | Empty. These fields are retained for provenance but are not baseline score signals. |
| `unknown_profile_fields` | `training_experience`, `available_equipment`, `injuries`, and `schedule` are `not_persisted`. |
| `history_status` | `empty`, `available`, or `unavailable`; an empty read is distinct from a failed read/normalization. |
| `history_records_read` | Owner-matched records returned by the injected reader. |
| `history_sessions_in_window` | Owner-matched sessions with a valid timestamp inside the window. |
| `unresolved_history_exercises` | Unknown, conflicting, malformed, or otherwise unresolved exercise identities ignored for scoring. |
| `recent_exercise_session_counts` | Resolved canonical IDs counted once per session in the history window. |
| `recent_exercise_provenance` | Resolver provenance kinds for the canonical history IDs used. |
| `history_window_days` | Fixed 90-day lookback; future and older sessions do not score. |

The date parser is injected from the existing Chat history helper. Reads
outside the window do not contribute to personalization. Profile activity
level is not converted into workout experience or candidate difficulty;
profile goal is not mapped to catalog metadata without a verified mapping.

## Catalog and candidates

`ExerciseCatalogResolver.list_exercises()` exposes defensive copies of the
records already validated from
`backend/app/data/ai_exercise_catalog.generated.json`. It returns an empty
list when the resolver is unavailable. It does not read another source,
fall back to Mongo/seeds, or create a second catalog.

Every listed candidate is re-resolved by canonical ID and slug before use.
Candidates must have unique, nonempty canonical IDs and valid catalog
metadata. An unavailable catalog, empty list, or zero valid/filter-matching
candidates returns an explicit status and an empty recommendation list.

## Explicit filtering

- Muscle groups are case-insensitive exact tokens. When requested, the
  candidate must match `muscleGroup`, `targetMuscles`, or
  `secondaryMuscles`; the corresponding metadata must be present and valid.
- An explicit `available_equipment` list is treated as an exact set of
  available catalog equipment tokens. A candidate passes only when every
  required equipment token is in that set. Missing or malformed candidate
  equipment metadata fails closed. `None` means no equipment constraint was
  supplied; an empty list means no equipment items were declared available.
- No synonym/fuzzy matching, difficulty inference, injury screening, medical
  safety judgment, or ability/weight prescription is performed.

## Deterministic ranking

For each candidate:

```text
score =
    primary muscleGroup match                 +100
    else targetMuscles match                    +60
    else secondaryMuscles match                 +30
    recent resolved sessions in 90 days      -10 each, capped at 3
```

Only the highest matching muscle tier contributes. The history penalty is
used only when history is available; empty or failed history contributes
zero and remains distinguishable in the result. Persisted profile fields do
not change the score.

Candidates sort by descending score, then ascending canonical ID. Identical
inputs therefore produce identical ordering. The result has zero to five
items, each with canonical ID, slug, rank, integer score, score components,
catalog metadata, and reason codes. Reasons include the exact matching
muscle tier, `available_equipment_filter` when an explicit equipment
constraint filtered candidates, `recent_history_variety` when resolved
history affected the score, `general_catalog_baseline` when no personalization
signal applied, and `canonical_id_tiebreak` when IDs break an equal-score tie.

## Fallbacks and limitations

- History empty/read-error/normalization-error are explicit; only successfully
  resolved canonical exercise IDs are history signals.
- Profile missing/read-error/owner-mismatch does not synthesize defaults.
- Missing constraints are not represented as negative preferences. When the
  caller provides no explicit constraints and history is unavailable/empty,
  results are a general catalog baseline, not a claim of personal suitability.
  Unknown equipment sets `limited_context` and requests equipment
  clarification; up to five verified candidates may still be returned as
  general candidates, not as confirmed suitable exercises.
- No eligible candidate returns an empty list with `no_candidates`; catalog
  failure returns `catalog_unavailable`.
- A live caller must provide trusted, owner-scoped readers and the existing
  router normalization helpers. This checkpoint does not wire them into a
  route.
- Current CP-AI-03 history reads may be unbounded. This service applies a
  90-day scoring window after the injected read; a future integration should
  bound the database query as well.

## Offline evaluation proposal

For relevance evaluation, construct a versioned set of user scenarios with
explicit equipment/muscle constraints and human-reviewed relevant/excluded
catalog IDs. Use held-out scenarios and report Recall@5, Precision@5, and
NDCG@5, with disagreements adjudicated and results separated by cold-start
versus available-history cases.

If the future objective is predicting a user's next selected exercise, use a
per-user temporal holdout: rank from history before a cutoff and evaluate
against selections after that cutoff. Treat the next selection only as a
behavioral prediction label, not as ground truth for exercise suitability.
No experiment or quality result is claimed in CP-AI-05.
