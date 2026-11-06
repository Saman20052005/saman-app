# CP-AI-05 Proposal — Authorized Recommendation Context

## Goal and non-goals

Add a read-only, deterministic recommendation context using only canonical
catalog records and explicitly authorized user inputs. Keep the existing
Library and Chat public response contracts unchanged.

This proposal does not add UI, a new endpoint, DB writes, Mongo seeding,
fuzzy identity matching, or an AI-provider call. It does not claim that an AI
API is a self-trained model.

## Proposed context boundary

The next checkpoint should first establish authorization and provenance for
each input. Candidate exercises must come from the generated catalog and be
resolved by canonical ID. Historical records with unknown/conflicting
identity may be summarized as history but must not become recommendation
candidates. A missing catalog, unavailable history, or absent user
preference must be represented explicitly rather than treated as a negative
preference.

Available catalog fields include:

- Canonical ID and slug, localized/English names.
- Primary/secondary muscle fields and equipment list.
- Difficulty, default sets/reps/rest, and rep type.
- Thumbnail/video, cues, common mistakes, and CV support/module metadata.

The CP-AI-05 context contract should admit only existing, permission-checked
profile preferences and history values whose owner and source are verified.
Do not infer medical constraints, goals, equipment access, or preferences
from names, free text, or missing fields.

## Read-only baseline ranking proposal

After an authorized preference schema is verified, use deterministic
filter-then-rank logic over canonical catalog entries:

1. Filter only on explicit user-approved constraints, such as available
   equipment or chosen muscle focus. Missing constraints do not filter.
2. Score exact primary-muscle matches above exact secondary-muscle matches.
3. Use an explicitly selected difficulty preference only when one is present.
4. Break ties by canonical ID for stable output.
5. Keep every score component and explanation attributable to actual
   catalog/context fields. Do not infer safety or medical suitability.

This is a baseline proposal, not an authorized score to ship. The next issue
must choose and test weights only after the user preference contract,
ownership, freshness, and metric meanings are verified. No hidden or
provider-generated ranking should be mixed into this baseline.

## Proposed allowed paths for a future issue

- `backend/app/services/exercise_recommendation_context.py`
- `backend/routers/chat.py` — internal context wiring only, if authorized.
- `backend/tests/test_ai05_recommendation_context.py`
- `docs/ai_coach/CP-AI-05/REPORT.md`
- `docs/ai_coach/CP-AI-05/RECOMMENDATION_CONTRACT.md`

Any profile/auth repository changes, public response changes, frontend work,
or deployment changes require explicit additional allowed paths and approval.

## Proposed acceptance criteria

- [ ] Every candidate resolves to one generated canonical catalog ID; no
  unresolved history value becomes a candidate.
- [ ] Input owner, authorization, source, timestamp/freshness, and
  missing/error semantics are explicit and tested.
- [ ] The feature uses only verified, user-authorized profile/history fields;
  no inferred health constraints or unverified preference defaults.
- [ ] Filtering/ranking is read-only, deterministic for identical inputs,
  stable-tie-broken by canonical ID, and has testable score explanations.
- [ ] Missing catalog/history/profile inputs remain distinguishable and do
  not silently become empty or negative preferences.
- [ ] Catalog defaults are never represented as logged performance.
- [ ] No new endpoint, public response schema, UI, database write, seed, or
  external AI call is introduced unless separately authorized.
- [ ] Targeted tests prove owner isolation, exact candidate identity,
  deterministic ordering, exclusions, and no data mutation.
- [ ] Recommendation quality and safety limitations are documented; no claim
  is made that an AI API is a self-trained model.

**Readiness:** proposal only. CP-AI-05 is not implemented or authorized by
this document. Before implementation, run the explicit-date Chat regression
in an environment with the existing backend test dependencies and retain
this report's deployment-packaging verification caveat.
