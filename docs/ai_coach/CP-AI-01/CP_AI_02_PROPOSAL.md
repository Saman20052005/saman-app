# CP-AI-02 Proposal — Ownership First, Data Contract Gate

## Objective and sequence

1. Fix and verify the reproduced private-plan ownership/filter defect first.
2. Preserve the current unknown shared/system/public plan policy; do not broaden visibility without an explicit product/security contract.
3. After the ownership regression is green, make the catalog/history source decision from `CATALOG_HISTORY_CONTRACT.md`. Do not implement recommendation UI, endpoints, or model calls until the data source and normalization contract are accepted.

The current audit cannot safely name a production catalog/history source file: Flutter's 49-item catalog is a Dart constant, backend records are a separate Python/Mongo slug list, and no shared artifact or verified deployment path exists. Creating a second list or assuming Mongo equivalence would defeat the acceptance criteria. If CP-AI-02 is expected to modify catalog/history production code in the same checkpoint, first update its allowed paths after choosing the single-source design.

## Proposed allowed paths for CP-AI-02

Only these paths should be writable for the immediate ownership repair:

- `backend/routers/workout.py`
- `backend/tests/test_ai01_plan_query_ownership.py`
- `docs/ai_coach/CP-AI-02/REPORT.md`
- `docs/ai_coach/CP-AI-02/CATALOG_HISTORY_DECISION.md`

All other paths remain read-only. In particular, do not change frontend UI, auth, database/seed data, dependencies, `backend/routers/chat.py`, or any recommendation endpoint in this ownership repair.

## Minimal ownership change

Keep the existing owner alternatives grouped together and require that group independently of filters:

```text
owner = OR(email == authenticated email, user_id == authenticated user ID)
muscle = OR(target_muscles == requested muscle, muscle_groups == requested muscle)
query = owner AND muscle, with difficulty as another AND condition when provided
```

When no muscle is supplied, omit the muscle predicate. Preserve the response schema and existing email/user-ID ownership compatibility. Do not add a public/system/shared branch until its visibility rules are approved.

## Acceptance criteria

- [ ] User A can list A's private plans, with and without filters.
- [ ] User A cannot list B's private plan without a filter.
- [ ] User A cannot list B's private plan when B's plan matches A's muscle filter.
- [ ] A muscle filter returns only matching plans owned by A; it does not make all A plans visible.
- [ ] Difficulty and muscle filters combine with ownership as ANDed conditions.
- [ ] The existing isolated collection fake continues to evaluate the actual generated query; the two currently failing tests become green without changing their expectations.
- [ ] Query behavior is unchanged for the endpoint response shape and private-plan creation contract.
- [ ] Shared/system/public plan policy remains explicitly **UNVERIFIED** unless separately authorized; tests do not invent visibility expectations.
- [ ] `REPORT.md` records exact command and pass/fail/skipped counts; no database or external service is used.
- [ ] No recommendation UI, service, provider call, or catalog duplicate is added.

## Catalog/history gate after ownership

`CATALOG_HISTORY_DECISION.md` should record the selected single authoritative catalog source, stable-ID resolution rule, and data provenance. The decision must explain how both Flutter detail/session flows and the backend validate the same metadata without two manually maintained lists. If the chosen design requires paths beyond the four listed above, stop and request an explicit allowed-path update rather than expanding scope.

Before any later recommendation implementation:

- canonical `Exercise.id` must resolve in the existing Library/detail path;
- `plan_ex_*` and unknown/removed IDs must remain unknown;
- history must distinguish no records from read failure and preserve owner, completion, timestamp, and per-set provenance;
- missing profile values must remain missing; `activity_level` must not stand in for training experience;
- recommendations must not infer equipment, injury, or schedule facts.

No recommendation may be shown until these data gates are verified. No merge or deployment is part of this proposal.
