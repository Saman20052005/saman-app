# CP-AI-03 — Catalog Decision

## Decision

**Do not switch the Library source or treat the current backend catalog as
canonical.** Prefer the existing Flutter `curatedExerciseLibrary` as the
single maintained catalog source and generate a backend artifact from its
Dart AST in a later checkpoint. Keep the current Library local/offline and
leave Mongo seed/runtime data untouched until that generator and exact
resolver are implemented and verified.

The backend catalog is not proven equivalent to the Library, so this
checkpoint leaves every history ID unresolved. No resolver is claimed ready.

## Source inventory and counts

| Source | Count / uniqueness | Use and evidence |
|---|---|---|
| `frontend/lib/presentation/providers/exercise_providers.dart` — `curatedExerciseLibrary` | 49 records; 49 unique `Exercise.id` values and 49 unique slugs | The existing provider and demo repository use this list. `flutter test test\workout_exercise_catalog_test.dart` passed its length and uniqueness assertions. **VERIFIED—SOURCE / ISOLATED TEST.** |
| `backend/app/data/exercises/back.py` — `BACK_EXERCISES` | 10 records; 10 unique slugs; zero `id` fields | Python AST literal parsing and the CP-AI-03 contract test. Used by the Chat fallback map and a seed script. **VERIFIED—SOURCE.** |
| Mongo `exercises` / `GET /api/workouts/exercises` | Runtime record count and uniqueness not established | Endpoint reads the database; no DB or deployment was queried. **UNVERIFIED.** |

The CP-AI-01 source comparison found five exact slug overlaps between the two
source lists and 44 Flutter slugs absent from the backend seed list. Three
Flutter ID/slug pairs intentionally differ:

- `db-bench-press` / `dumbbell-bench-press`
- `db-shoulder-press` / `dumbbell-shoulder-press`
- `db-bicep-curl` / `dumbbell-bicep-curl`

This is a source comparison, not proof of Mongo contents or deployed behavior.

## Schema and metadata mismatch

The Flutter `Exercise` model includes a stable `id`, `slug`, localized and
English names, muscle groups, list-valued equipment, difficulty, bundled
thumbnail path, video/cues/mistakes, prescriptions, rest, rep type, and CV
support/module metadata.

The ten backend seed records have slugs but no Flutter IDs. Their `equipment`
is a scalar string, `defaultReps` is an integer rather than the Flutter
string/range, and thumbnails are null rather than bundled asset paths. The
five overlapping records also have observed name/localization, prescription,
muscle-group, or difficulty differences. The backend `ExerciseOut` model
requires an `id`, but that does not make the static seed records or Mongo
documents equivalent to Flutter IDs.

The UI currently uses its bundled curated source, not a live backend catalog
request. `MockExerciseRepository.getExerciseById` resolves exact IDs; the
`ExerciseDetailScreen` receives the selected `Exercise`. The alternate
`ExerciseRepositoryImpl` API method does not prove that the Library provider
uses the API. Existing asset paths and CV metadata belong to the Flutter
catalog and must not be reconstructed from backend slugs.

## Preferred implementation for a future checkpoint

Keep the current Dart list as the maintained source and add a deterministic
generator that uses the already-declared `analyzer` dev dependency
(`frontend/pubspec.yaml`, `analyzer: ^6.4.1`) to parse
`curatedExerciseLibrary` as Dart AST. It should fail closed on non-literal or
unsupported fields and emit one generated Python artifact for backend
resolution. Do not copy the catalog into a manually maintained backend list
or use broad regular expressions as a parser.

The generated artifact must preserve each `id`, slug, asset path, CV field,
and every current model field without title/name-based reconstruction. Emit a
source digest and stable ordering. Add a `--check` mode that exits nonzero if
the committed artifact is stale; tests should verify exact record count,
unique IDs/slugs, field parity, and generator drift.

Backend resolution should use the generated catalog's exact ID/slug pairs.
Unknown/removed IDs, `plan_ex_*`, and conflicting pairs remain unresolved;
never fuzzy-match names. A saved history name may be shown only as a recorded
label, not as verified catalog metadata or a recommendation candidate.

Keep the Library backed by its current local list so it remains offline and
asset-compatible. Do not switch it to the API until offline behavior, bundled
assets, and runtime availability have an approved separate contract. Do not
seed/sync Mongo as part of catalog generation. Keep the existing ten-item
`BACK_EXERCISES` seed behavior separate from the canonical resolver until a
checkpoint explicitly addresses seed compatibility.

## Proposed CP-AI-04 write paths

These are proposed paths only; CP-AI-03 does not create or modify them.

- `frontend/tool/generate_exercise_catalog.dart` — AST-based generator using
  the existing analyzer package.
- `backend/app/data/exercises/curated_catalog.generated.py` — generated
  backend artifact; never hand-edit.
- `backend/app/data/exercises/catalog.py` — exact-pair loader/resolver.
- `backend/routers/chat.py` — switch only catalog identity resolution to the
  generated canonical data.
- `backend/tests/test_ai04_catalog_contract.py` — generator drift and exact
  resolution tests using fixtures, no Mongo.
- `frontend/test/workout_exercise_catalog_test.dart` — verify the existing
  Library remains offline and IDs/assets remain unchanged.

Read-only compatibility surfaces for that scope include
`frontend/lib/presentation/providers/exercise_providers.dart` (the maintained
source), `frontend/lib/data/models/exercise.dart`,
`frontend/lib/features/workout/data/repositories/mock_exercise_repository.dart`,
`backend/app/data/exercises/back.py`, and
`backend/scripts/seed_back_exercises.py`. No `pubspec.yaml`, API schema, seed
execution, Mongo data, or deployment configuration change is proposed.

## Verification status

- **VERIFIED—SOURCE:** current Flutter and backend source shapes and their
  in-repository consumers.
- **VERIFIED—ISOLATED TEST:** Flutter 49-entry/unique-ID/slug assertions and
  backend AST-derived count/slug uniqueness.
- **UNVERIFIED:** Mongo contents, deployed artifact packaging, and any mapping
  between legacy database IDs/slugs and Flutter records.
- **MISSING:** a shared/generated catalog artifact and a canonical resolver.
