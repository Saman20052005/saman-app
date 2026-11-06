# CP-AI-06 — Workout Recommendations in Saman AI Chat

## Status

**PASS — local read-only recommendation integration and required regression
tests passed.** This is a deterministic CP-AI-05 rule-based baseline, not an
ML evaluation or AI-provider feature.

## Workspace and preservation

| Check | Before | After |
|---|---|---|
| Workspace | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` | Same |
| Branch | `agent/nutrition-active-localhost-f02` | Same |
| HEAD | `10be1ab1971214acd2487ef893df3fcc80212fc9` | Same |
| Git status | 3,756 porcelain entries; `backend/routers/chat.py` was already modified WIP. No CP-AI-06 test/report file existed. | 3,758 entries; only the Chat route, this report, and the new CP-AI-06 test are changes from this task. Existing WIP retained. |

No project Context File was found. Root `AGENTS.md` and the CP-AI-04/05
handoffs and contracts named in the task were read. The CP-AI-05 service and
CP-AI-04 generated catalog resolver were not modified. No commit, push,
merge, reset, clean, stash, or checkout was performed.

## Files changed for CP-AI-06

- `backend/routers/chat.py` — intent, baseline wiring, read-only response,
  existing conversation persistence, and relative-yesterday history routing.
- `backend/tests/test_ai06_chat_workout_recommendation.py` — guarded
  in-process HTTP tests using the real route, baseline, and generated catalog.
- `docs/ai_coach/CP-AI-06/REPORT.md` — this handoff.

The route already had unrelated CP-AI-03/04 WIP before this task; it remains
untouched outside the scoped additions.

## Chat integration

The existing `POST /api/chat` route still authenticates through its existing
`get_current_user` dependency. The recommendation branch runs after
authentication and the existing owner check for a supplied conversation ID,
but before water/meal/plan-action dispatch.

Priority:

1. Authenticate and validate any existing conversation against the principal.
2. Recognize an explicit recommendation request and handle it read-only.
   If it also asks to add/save/modify something, only the recommendation
   response is returned; no pending action is created or dispatched.
3. Otherwise preserve the current water, meal, and workout-plan action flow.
4. Preserve the existing date/history grounding and AI-provider path for
   other requests. Relative “yesterday” questions are now resolved to a
   `SPECIFIC_DATE` query by the existing history parser.

Recommendation intent requires explicit wording such as Vietnamese “gợi ý”
or “đề xuất”, English “recommend”/“suggest”, or “what exercises should I do”.
Accent-insensitive Vietnamese variants are supported. Generic mentions of
“tập”, date/history questions, and exercise-technique questions do not
activate the recommendation path.

Muscle and equipment filters are passed only when mapped to generated
catalog tokens. Ambiguous broad groups (for example “legs”), unsupported
equipment, and injury/rehab constraints do not silently become filters.
Unknown equipment is stated as unknown; the reply asks whether to filter by
equipment and does not claim that unfiltered results fit the user's setup.
Explicit goal, experience, schedule, and location requests are disclosed as
unsupported filters rather than silently ignored.
The baseline does not rank by profile goal or activity level. It does not
infer experience, injuries, schedule, or weight recommendations.

The branch uses only principal-derived identity for profile/history reads.
The baseline additionally validates profile and history ownership. Request
body fields such as `context`, `history`, `user_id`, and `owner_id` do not
override this identity. Recommendation output keeps the baseline order,
verified generated-catalog names, unique canonical IDs, and a maximum of five
items. No provider is called and there is no fallback to AI-generated
exercise lists. Conversation messages are persisted using the existing
owner-scoped conversation collection; no profile, nutrition, plan, or workout
session writes occur.

The response retains the existing Chat keys: `reply`, `status`,
`conversation_id`, and `action`. The Flutter Chat controller consumes
`reply` and `conversation_id` and treats absent/non-map `action` as null; the
response is therefore source-compatible. No Flutter app or UI test was run.

## Sanitized example

Request:

```text
Gợi ý bài tập bụng với Ab Wheel
```

In-process response (conversation ID redacted):

```json
{
  "status": "success",
  "conversation_id": "<redacted>",
  "action": null,
  "reply": "Gợi ý theo thứ hạng của danh mục bài tập đã xác minh:\nLịch sử đọc được không có bản ghi khớp; danh sách chưa được cá nhân hóa theo lịch sử.\nĐã áp dụng bộ lọc thiết bị bạn nêu.\nĐã áp dụng bộ lọc nhóm cơ bạn nêu.\nĐiểm không dùng mục tiêu hoặc mức độ hoạt động trong hồ sơ.\n1. Ab Wheel Rollout — khớp nhóm cơ chính Abs, đã qua lọc thiết bị.\nĐây là gợi ý chỉ đọc; tôi không ghi hồ sơ, dinh dưỡng, kế hoạch hoặc buổi tập, và không đánh giá chấn thương, kinh nghiệm hay mức tạ."
}
```

The result's actual reason codes are `requested_muscle_primary_match` and
`available_equipment_filter`; the displayed name and canonical ID were
resolved from the generated catalog. The history-empty explanation is
distinct from the read-error response.

## Verification

Interpreter: `D:\SamanDev\runtime\saman-cp7-python\Scripts\python.exe`,
Python 3.11.9. No dependencies were installed.

The HTTP tests use FastAPI `TestClient` in-process, override the existing auth
dependency with synthetic principals, block `MongoClient` before app import,
disable dotenv loading, and blank provider-key variables. They use fake
collections for profile/history/conversation/action boundaries. The production
recommendation service and resolver load the real generated catalog artifact.
The Mongo guard was exercised; no live Mongo request was made.

| Command / scope | Exit | Result |
|---|---:|---|
| `python -B -m unittest backend.tests.test_ai06_chat_workout_recommendation -v` | 0 | 10 passed, 0 failed, 0 skipped. |
| Guarded `python -B -` runner loading `test_ai06_chat_workout_recommendation`, `test_chat_workout_grounding`, and `test_chat_actions` | 0 | 57 passed, 0 failed, 0 skipped. Exercises the actual HTTP route and baseline, plus grounding and write-action regressions. |
| `python -B -m unittest backend.tests.test_ai05_workout_recommendation backend.tests.test_ai04_catalog_resolver backend.tests.test_ai03_workout_history_context backend.tests.test_ai01_catalog_history_contract` | 0 | 48 passed, 0 failed, 0 skipped. |
| Focused AST parse of `backend/routers/chat.py` and the CP-AI-06 test | 0 | Both Python files parsed. |
| `git diff --check -- backend/routers/chat.py backend/tests/test_ai06_chat_workout_recommendation.py` | 0 | Passed. |

The tests verify route order/unique IDs and catalog resolution, the five-item
cap and a one-result case, supported muscle/equipment filtering, unsupported
equipment and broad muscle clarification, profile/history isolation despite
spoofed payload fields, empty versus failed history, unavailable catalog,
injury and unsupported goal/experience/schedule/location limitations, no
AI-provider invocation, no domain writes for mixed recommendation/write
requests, and preservation of the yesterday history path. Existing
explicit-date grounding and action tests also passed.

Real bearer-token authentication is **not verified**: the tests use an auth
dependency override. Live Mongo is **not verified**: Mongo client creation
was blocked. Deployment packaging and runtime artifact inclusion are
**unverified**. The baseline applies its 90-day history window after reading;
the existing collection read itself remains unbounded, as noted in CP-AI-05.

Baseline and test output included the existing missing-model/PyTorch,
Pydantic configuration, and shop-router import warnings. The in-process
Mongo-construction warning is expected from the safety guard. The editor's
Pylance environment could not resolve installed runtime packages (including
FastAPI/PyMongo/Pydantic); the selected test interpreter could run the suites.
No new diagnostics were reported on the added recommendation code.

## Acceptance and next step

- [x] Recommendation runs through the authenticated existing Chat route and
  real baseline/catalog resolver.
- [x] Explicit intent is separated from history, technique, and write paths.
- [x] Owner-scoped reads ignore client identity/history overrides.
- [x] Results preserve verified baseline ordering and existing response shape.
- [x] Empty/error history, missing equipment context, unsupported constraints,
  and catalog failure are described without provider fallback.
- [x] Provider calls and non-conversation domain writes are zero for this path.
- [x] Chat grounding and write-action regressions pass.
- [x] Changes remain within the three CP-AI-06 allowed paths; no commit/push/
  merge or WIP cleanup was performed.

Next: verify real token authentication and owner-scoped Mongo reads in an
authorized integration environment; verify the generated JSON is packaged in
the deployment artifact. Bound the database history query once the persisted
timestamp-field/query contract is confirmed. If relevance is an objective,
run the proposed offline ranking evaluation separately. This report does
not claim trained ML quality or provider integration.
