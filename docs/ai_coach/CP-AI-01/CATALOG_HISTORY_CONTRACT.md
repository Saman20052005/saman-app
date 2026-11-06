# CP-AI-01 — Catalog and History Contract

## Evidence labels

- **VERIFIED—SOURCE:** established by current repository source; not proof of deployed runtime contents.
- **VERIFIED—ISOLATED TEST:** exercised current function bodies with in-memory fixtures; not HTTP or runtime E2E.
- **UNVERIFIED:** requires runtime/deployment evidence or a policy not present in source.
- **MISSING:** no current implementation found.

## Exercise catalog

### Current source inventory

| Source | ID format | Used by | Current resolution | Verification |
|---|---|---|---|---|
| Flutter `curatedExerciseLibrary` in `frontend/lib/presentation/providers/exercise_providers.dart:123` | `Exercise.id` plus a separate `Exercise.slug`; 49 records, no duplicate IDs/slugs in source. Three pairs differ: `db-bench-press` / `dumbbell-bench-press`, `db-shoulder-press` / `dumbbell-shoulder-press`, `db-bicep-curl` / `dumbbell-bicep-curl`. | `exerciseLibraryListProvider` returns this constant; `workoutDemoRepositoryProvider` constructs a repository from the same list. Library detail receives the selected `Exercise`. | `MockExerciseRepository.getExerciseById` compares exact `id`; detail gets the resolved object. `ExerciseDetailScreen` starts a session from that object. | **VERIFIED—SOURCE.** Current provider path; not a live backend catalog fetch. |
| Backend `BACK_EXERCISES` in `backend/app/data/exercises/back.py:5` | 10 unique `slug` strings; no canonical `id` field in the seed records. | Chat's repository fallback map; `backend/scripts/seed_back_exercises.py` can manually insert the records into Mongo `exercises`. | Chat map is keyed by slug. Seed checks/inserts by slug. | **VERIFIED—SOURCE.** Whether these records are seeded or available in the configured database is **UNVERIFIED**; no DB was queried. |
| Backend Mongo `exercises` collection and `GET /api/workouts/exercises` | Seed data supplies slug; Mongo `_id` may exist but is not the Flutter `Exercise.id` contract. | Backend exercise endpoint and Chat name resolver. | Chat tries Mongo slug, `id`, then `_id`; fallback uses the 10 repository slugs. The endpoint returns stored records and does not establish a mapping to the Flutter list. | **VERIFIED—SOURCE** for query code; deployed contents and ID mapping **UNVERIFIED**. |
| Workout session logs | `exercise_id`/`exerciseId` plus `exercise_slug`/`exerciseSlug`. | Flutter save/history, backend workout history, Chat grounding. | Flutter Library/history screens resolve against the curated list by ID/slug in some views; Chat resolves through Mongo or the 10-slug backend map. Unknown UI fallback labels are not authoritative catalog resolution. | **VERIFIED—SOURCE** for writers/readers; historical records **UNVERIFIED**. |
| Plan-generated alternate branch | `plan_ex_<index>` with a plan exercise name and no slug. | `ActiveWorkoutSessionNotifier.startSessionFromPlan`. | No catalog resolver can identify this synthetic ID; current Chat resolver preserves it as unresolved. No in-repository caller passing `workoutPlan` to `ActiveWorkoutScreen` was found, so live use of this branch is **UNVERIFIED**. | **VERIFIED—SOURCE** for construction and unresolved behavior; reachability **UNVERIFIED**. |

The ordinary Library detail path and the current `MyPlansScreen._startPlan` path resolve a complete `Exercise` from the repository before starting the workout. The alternate `startSessionFromPlan` branch instead constructs IDs from an index. The latter must not be treated as an exercise catalog ID.

### Match and metadata checks

- The 10 backend slugs have 5 exact matches in the Flutter slug set: `bent-over-barbell-row`, `lat-pulldown`, `pull-up`, `romanian-deadlift`, and `seated-cable-row`.
- The other 5 backend slugs (`back-extension`, `deadlift`, `face-pull`, `single-arm-dumbbell-row`, `t-bar-row`) are absent from the current Flutter Library. Forty-four Flutter slugs are absent from the backend seed list.
- Every overlapping backend record lacks the Flutter `id`. Backend `equipment` is a scalar string while Flutter expects a list; backend `defaultReps` is an integer while Flutter stores a string/range. Backend thumbnail values are `None`, while the Flutter entries have bundled thumbnail paths.
- Other overlapping metadata differs: bent-over row name capitalization, Vietnamese name and rep target; lat-pulldown Vietnamese name and rep target; pull-up name capitalization, Vietnamese name and rep target; Romanian deadlift muscle group (`back` vs `Hamstrings`), Vietnamese name and rep target; seated cable row difficulty (`beginner` vs `intermediate`) and rep target.
- The Chat resolver's in-repository static fallback contains only these backend records. Its unresolved branch preserves the supplied identifier and labels it unverified; it does not prove a Flutter item exists.

**Conclusion:** backend code cannot currently prove that a Mongo or static backend exercise is actually available in the current Flutter Library. The UI currently uses its local curated list, not the backend catalog. Runtime Mongo contents were not checked.

### Proposed minimum catalog rule

1. Use the existing Flutter `Exercise.id` as the **canonical exercise ID**. Keep `slug` as descriptive/lookup metadata, not a second canonical identity. Do not infer the ID from a name.
2. Before server recommendations are enabled, make the full existing Library metadata available to both the backend and Flutter from **one authoritative source** (or a generated representation from that source). Do not maintain a second hand-edited backend list or treat Mongo slugs as equivalent without verified mapping.
3. Recommendation output carries a canonical ID only. The client must resolve that ID through its existing exercise repository before opening detail or starting a workout. If it does not resolve, retain it as unknown and do not display a guessed exercise as available.
4. A database `_id`, slug, name, or `plan_ex_<index>` is not a canonical Flutter exercise ID. No production mapping is created in CP-AI-01.

Choosing the physical shared-source file/runtime path is **UNVERIFIED** in this checkpoint: Flutter's current list is a Dart constant while the backend catalog is a Python list/Mongo seed, and no existing shared data artifact was found. CP-AI-02 must not silently add an independent list.

## History sources and current behavior

| Source/path | Stored fields and behavior | Ownership, time, order | Verification |
|---|---|---|---|
| Direct Library workout | `ActiveWorkoutSessionState.fromExercises` keeps `Exercise.id` and `slug`. Save emits `exerciseId`, `exerciseSlug`, set number, reps or seconds, unit, weight, and `isCompleted=true`. | Session ID is generated client-side; start/finish are sent as UTC. | **VERIFIED—SOURCE.** |
| Current saved plan path | `MyPlansScreen._startPlan` resolves every stored plan exercise ID through `getExerciseById`, then starts from the resolved exercises. | Same session save path as a direct selection. | **VERIFIED—SOURCE.** |
| Alternate plan start | `startSessionFromPlan` constructs `plan_ex_<index>`, uses plan exercise name, and has no catalog slug. | The stored workout log gets the synthetic ID and ID-as-slug fallback. | **VERIFIED—SOURCE** for code; active use **UNVERIFIED**. |
| Canonical backend `exercise_logs` | `log_workout_session` stores `exercise_id`, `exercise_slug`, set fields, `is_completed`, `started_at`, `finished_at`, `date`, and `user_id`. It accepts either canonical `exercise_logs` or the legacy `completed_exercises` input. | Authenticated `user_id` is stored. UTC timestamps are written; `date` is derived in `Asia/Ho_Chi_Minh`. | **VERIFIED—SOURCE.** No real records read. |
| Legacy exercise records | Serializer and Chat retain `completed_exercises`; Chat latest also accepts `exercises`. Older records may contain only a name or older field spellings. Missing exercise completion can default to true in current serializers/Chat formatting. | Legacy date/time fields include `start_time`, `end_time`, `created_at`, or `date`; their original timezone/provenance may be absent. | **VERIFIED—SOURCE** for compatibility branches; historic record contents **UNVERIFIED**. |
| Backend `GET /history` and session detail | History filters by `{"user_id": authenticated_user_id}`, sorts by `started_at`, `date`, `created_at` descending, and supports `limit` (default 10, max 100) and `offset`. Detail combines an owner predicate with the session ID predicate. | Owner is the authenticated user ID. | **VERIFIED—SOURCE.** |
| Chat latest-workout helper | `_build_latest_workout_context` queries by email, `user_email`, or `user_id`, tries field-specific fallbacks, reads `completed_exercises` or `exercises`, then selects the latest in memory. It does **not** read `exercise_logs`. | Queries have no limit/pagination. Read exceptions are swallowed and produce the same “no data” text as an empty result. It does not require the session to be completed. | **VERIFIED—SOURCE** and isolated fixtures. |
| Chat history-specific helper | `fetch_user_workout_sessions` filters strictly by `user_id`; `build_workout_grounding_context` filters sessions through `is_session_completed` and sorts in memory. Completion requires a valid finish/end timestamp not earlier than start. | No database sort/limit/pagination in this helper. Date context uses `Asia/Ho_Chi_Minh`. | **VERIFIED—SOURCE**; separate from latest-workout helper. |

### Set metrics and time

- Current Flutter volume is `repsCompleted × weightKg` for repetitions and `0` for timed sets. Save sums completed set volumes and rounds the total to integer kilograms. The backend accepts `total_volume_kg`; it does not recalculate it from logs.
- Timed logs use zero reps plus `seconds_completed`; repetition logs use reps and weight. Missing values are currently defaulted in multiple serialization paths, so the raw field and whether it was explicitly recorded matter.
- Canonical timestamps are sent/stored in UTC and Chat displays Vietnam time. Date-only or legacy naive timestamps may lack enough provenance to recover an exact instant or original timezone.

### Normalized-history contract (proposed; implementation MISSING)

Each normalized record should retain its original source fields and add explicit resolution/completion states. It must not rewrite source history.

- **Identity:** accept a canonical ID only after exact resolution in the authoritative catalog. If ID and slug disagree, mark a conflict/unknown rather than choosing silently. `plan_ex_*`, missing IDs, removed IDs, and unknown IDs remain unknown. Never map by name.
- **Legacy migration:** permit an exact slug-to-ID mapping only when the mapping comes from the authoritative catalog, is unique, and is verified. Record mapping source and mapping version. No name-based fallback.
- **Unknown records:** preserve raw ID, slug, name, and original fields with `exercise_resolution=unknown`; never silently drop or relabel them.
- **Completion:** distinguish session completion from per-set completion. Missing completion flags remain unknown; do not upgrade them to completed merely because an older serializer defaulted them to true.
- **Time:** retain raw timestamp, normalized UTC instant when unambiguous, timezone/provenance, and a distinct date-only state. Do not manufacture an instant from a date-only value.
- **Metrics:** retain raw unit, reps, seconds, and weight. Calculate volume only for valid repetition sets with explicit reps and kg; timed sets contribute zero. A missing submitted aggregate is unknown, not zero. Do not infer missing values.
- **Read result:** distinguish `history_available`, `no_history`, and `history_read_error`. An empty result must not conceal a failed query.
- **Ownership:** query history only by the authenticated server-derived `user_id`; never accept an owner ID from recommendation text or client profile fields.

Normalization currently does not exist as a shared service. These are contract rules, **not** tests for a fabricated implementation. CP-AI-01's tests instead exercise present Chat helper behavior with synthetic canonical, legacy, unknown, plan-generated, missing-history, and other-owner fixtures.

## Authorized recommendation context (proposed)

The server should construct context only after authenticating the request and derive owner identity from the authenticated principal. Suggested fields and provenance:

| Context field | Allowed source and handling |
|---|---|
| `user_id` | Server-derived authenticated identity; never a request-body override. |
| `catalog_version` and allowed exercise records/IDs | The one authoritative catalog source selected above; include only resolvable canonical IDs and trusted catalog metadata. |
| `training_history` | Only sessions belonging to that `user_id`; include completion state, UTC/local-time provenance, normalized sets, and resolution state. Keep unknown records explicitly unknown. |
| Profile attributes | Include only persisted, explicitly present profile values with field provenance/last-updated metadata. Do not substitute frontend defaults for stored facts. |
| Training experience | Include only an explicit verified experience field. Current inspected backend profile schema has `activity_level` but no training-experience field; do not use activity level as a proxy. |
| Equipment, injuries, availability/schedule | Include only explicit, verified user-provided data with source/timestamp. Current inspected profile model does not establish these facts. Absence means unknown, not “none”. |

Do not pass inferred injury/device/schedule constraints, default weights/reps as user profile, or unverified catalog names as facts. Recommendation generation and API wiring remain out of scope.

## Unverified items and risks

- Deployed Mongo `exercises` records and seed state were not inspected.
- No shared/public/system plan visibility contract is established by the current `/plans` route.
- The alternate plan-generated ID path's current runtime reachability is unknown.
- Historical data quality, legacy timezone, missing completion fields, and existing owner consistency were not inspected.
- No normalized history service exists; Chat latest-workout and history-specific helpers read different fields and have different failure behavior.
- Enabling recommendations before ownership, shared catalog, and history contracts are resolved risks private-plan disclosure, unavailable recommendations, and false statements about training history.
