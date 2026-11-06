# CP-AI-04 Proposal — Canonical Exercise Catalog & ID Resolution

## Objective and boundary

Create one verified catalog identity path for Chat/history without changing
the Library's current offline behavior. Use the existing Flutter
`curatedExerciseLibrary` as the maintained source and generate a backend
artifact with the already-installed Dart analyzer tooling.

This checkpoint must not add recommendations, call an AI provider, switch the
Library to an API, change public API/JSON contracts, seed or synchronize
Mongo, or alter auth. Recommendation readiness must be assessed separately;
a passing resolver test alone does not make recommendations safe.

## Proposed allowed paths

Write only:

- `frontend/tool/generate_exercise_catalog.dart`
- `backend/app/data/exercises/curated_catalog.generated.py`
- `backend/app/data/exercises/catalog.py`
- `backend/routers/chat.py`
- `backend/tests/test_ai04_catalog_contract.py`
- `frontend/test/workout_exercise_catalog_test.dart`

Treat the existing Flutter list, exercise model/repository, backend
`BACK_EXERCISES` list, and seed script as read-only compatibility inputs.
Do not modify dependency manifests or lockfiles; `analyzer` is already
declared in the frontend dev dependencies.

## Minimal implementation sequence

1. Parse the Dart AST for the `curatedExerciseLibrary` initializer. Reject
   unknown expressions or unsupported fields; do not regex-extract partial
   Dart or silently omit metadata.
2. Generate a stable Python artifact from the exact records, preserving IDs,
   slugs, names, muscle/equipment fields, bundled asset references, workout
   prescriptions, and CV metadata. Include a digest of the parsed source.
3. Add a deterministic `--check` mode that reports stale generated output
   without writing files. Never hand-edit the generated artifact.
4. Add an exact canonical resolver keyed by ID and unique slug. Accept a
   stored ID/slug pair only when both agree with one generated record.
   Missing/removed IDs, `plan_ex_*`, and mismatches remain unresolved; no
   name matching or fuzzy fallback.
5. Wire only Chat's exercise identity resolution to the generated catalog.
   Keep the existing Library provider/repository and detail resolution local
   and exact-ID based. Keep the Mongo exercise API and seed behavior unchanged.

The current `BACK_EXERCISES` list remains a legacy seed input, not a second
canonical source or a recommendation resolver. Do not run its seed script.
Any removal or migration of that compatibility data requires explicit scope
and deployed-data evidence.

## Compatibility requirements

- Library stays usable offline and retains its current detail/session flow.
- Existing exercise IDs, slugs, bundled thumbnail paths, and CV metadata are
  preserved byte-for-byte in meaning; do not infer IDs from names.
- Existing Mongo records, endpoints, authentication, and response schemas
  remain unchanged.
- Exact slug lookup is allowed only when it uniquely identifies a generated
  record and does not conflict with a stored ID.
- Unknown historical values can be displayed only as values recorded in
  history, labelled unresolved; they are not candidate recommendations.

## Acceptance criteria

- [ ] Generator parses all 49 current Flutter records through the Dart
  analyzer AST and fails on unsupported syntax/fields.
- [ ] Generated backend data has a stable source digest and passes `--check`
  when current; a stale artifact causes a nonzero result.
- [ ] Tests verify exact record count, unique nonempty IDs/slugs, complete
  field preservation, and ID/slug pairs that intentionally differ.
- [ ] Resolver tests cover exact match, valid distinct ID/slug pairs,
  missing/removed IDs, `plan_ex_*`, duplicate/unknown slugs, and conflicting
  pairs without Mongo or provider access.
- [ ] Existing Library offline/detail behavior and asset references remain
  unchanged under Flutter 3.22.0 / Dart 3.4.0.
- [ ] No Mongo seed, DB sync, API/auth/schema/dependency/config change, or
  recommendation logic is included.
- [ ] Recommendation readiness is recorded independently and remains
  blocked until ownership, history, profile provenance, and runtime data
  contracts are separately verified.

## Verification

- Run the generator in check mode using the existing frontend package
  configuration.
- Run `flutter test test/workout_exercise_catalog_test.dart`.
- Run the focused backend catalog contract test with an in-memory resolver
  fixture; do not import application/database modules or connect to Mongo.
- Record interpreter/SDK versions, exact commands, exit codes, and
  pass/fail/skipped counts. No runtime E2E claim without an authorized
  isolated in-process route and database fake.

**Readiness:** proposal only. No CP-AI-04 implementation or catalog resolver
is started by CP-AI-03.
