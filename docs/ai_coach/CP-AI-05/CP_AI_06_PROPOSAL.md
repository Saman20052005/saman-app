# CP-AI-06 Proposal — Minimal Saman AI Chat Integration

## Goal

Connect the CP-AI-05 read-only rule-based baseline to the existing Saman AI
Chat flow. The backend remains authoritative for candidate IDs, scores, and
ordering. This is a proposal only; CP-AI-06 requires its own authorization and
allowlist.

## Smallest integration boundary

1. In `backend/routers/chat.py`, use the already authenticated
   `get_current_chat_user` principal. Pass its server-derived email/ID and
   existing read dependencies to the recommendation service. Inject the
   existing CP-AI-03/04 history normalizer/date parser; do not make the
   service import the router.
2. Derive only explicit structured muscle/equipment constraints. Do not
   accept owner, profile, or history overrides from the request body. If
   required information is absent, retain the service's limited-context or
   empty-result status rather than inventing a preference.
3. Keep the candidate list and order returned by the backend. If an AI
   provider is later used to phrase an explanation, provide only the minimal
   sanitized candidate names/metadata, reason codes, and explicit request
   constraints. Provider output may not add, remove, reorder, rename, or
   substitute an exercise ID. Preserve backend IDs/ranks outside generated
   prose and validate any structured provider response against that exact
   result set.
4. On provider failure, return the deterministic backend reasons/status.
   Do not make any plan/session/database write. Any future write flow needs a
   separate explicit user confirmation and separate authorization.
5. Preserve existing Chat route and public response schema unless the
   CP-AI-06 issue separately authorizes a schema change.

## Proposed allowed paths for CP-AI-06

- `backend/routers/chat.py` — internal wiring only.
- `backend/app/services/workout_recommendation.py` — only if the CP-AI-05
  service contract requires a targeted integration change.
- `backend/tests/test_chat_workout_recommendation.py`
- `docs/ai_coach/CP-AI-06/REPORT.md`
- `docs/ai_coach/CP-AI-06/CHAT_INTEGRATION_CONTRACT.md`

No frontend, catalog artifact/source, database schema, seed, authentication,
route contract, dependency, Revenue, Nutrition, or Workout-CV changes are
proposed.

## Acceptance criteria

- [ ] Chat uses only the authenticated principal and server-side authorized
  profile/history readers; tests prove User A cannot see User B's data.
- [ ] Chat calls the backend baseline and returns only its verified canonical
  IDs, metadata, scores, and order; no provider-created candidates.
- [ ] Unknown/missing/error context remains explicit; no client defaults,
  guessed experience/equipment, or invented safety claims.
- [ ] If AI phrasing is enabled, it receives minimum necessary context and
  cannot mutate the backend candidate IDs or order; failure falls back to
  deterministic reasons.
- [ ] No database writes occur. A future plan/session write requires separate
  user confirmation and authorization.
- [ ] Guarded in-process tests block Mongo/provider access before import where
  needed and verify the Chat path, owner isolation, failure handling, and
  unchanged public response contract.
- [ ] No live-token, live-Mongo, deployment, or relevance-quality claim is
  made without separate evidence.

**Readiness:** proposal only. No CP-AI-06 production integration is included
in CP-AI-05.
