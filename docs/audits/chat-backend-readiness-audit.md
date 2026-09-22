# Technical Audit Report: Saman Chat Backend Integration & Readiness

**Audit Date:** May 2024
**Audit Target:** Saman Chat End-to-End Data Path, Backend Architecture, and Deployment Configuration
**Scope:** Technical Audit Only (Read-Only Inspection). No production or test code modified.
**Report Location:** `docs/audits/chat-backend-readiness-audit.md`

---

## Executive Summary

This technical audit evaluates the backend integration readiness for **Saman Chat**, assessing the complete data pipeline from Flutter UI and Riverpod controllers through authentication, FastAPI routing, user profile resolution, AI model execution, response parsing, and error handling.

While the frontend implementation provides a polished, approved user experience across ten visual states, the existing backend chat route (`POST /api/chat`) is a primitive prototype. It exhibits critical structural deficiencies, security risks, concurrency bottlenecks, and API contract mismatches that prevent production readiness.

### Key Audit Findings & Severity Summary

| Severity | Count | Primary Impact Areas | Key Issues Summary |
|---|---|---|---|
| **P0 (Critical)** | 3 | Concurrency & Security | Event-loop blocking synchronous AI calls; Client-controlled prompt injection via `system_instruction`; Deployment code drift across duplicate code trees. |
| **P1 (High)** | 4 | API Contract & Error Handling | Silent request payload dropping (`context` and `history` ignored); Application errors masked under HTTP 200; Token verification mismatch and exception leaks; History turn duplication risk. |
| **P2 (Medium)** | 3 | Data Integrity & Resilience | Dual source-of-truth conflict (SharedPreferences vs. MongoDB); Unhandled null/malformed JSON responses; Lack of request timeout, retry, or cancellation handling. |
| **P3 (Low)** | 2 | Test Coverage & Debt | Zero backend integration/contract tests; Hardcoded model parameters and unconfigurable fallbacks. |

---

## 1. End-to-End Chat Data Flow Mapping

The complete execution path for a user chat query in the current architecture is mapped below:

```
[User Input in UI]
       │
       ▼
[ChatScreen (`_handleSend`)]
       │ (reads _textController.text)
       ▼
[ChatController (`sendMessage` / `_sendRequest`)]
       │ 1. Appends ChatMessage(role: 'user') to ChatState.messages
       │ 2. Sets ChatState.isLoading = true
       │ 3. Assembles `userContext` from SharedPreferences (`_buildUserContext`)
       │ 4. Extracts last 5 messages via `_getLastMessages(5)`
       ▼
[ApiClient (Dio HTTP Client)]
       │ Interceptor attaches Header: `Authorization: Bearer <JWT>`
       │ Timeout set to 30000ms
       ▼
[HTTP POST /api/chat] Payload: { message, context, history }
       │
       ▼
[FastAPI Router (`backend/routers/chat.py`)]
       │
       ├─► [Auth Dependency (`verify_token` in `backend/auth_utils.py`)]
       │     └─ Decodes JWT using `JWT_SECRET` -> Extracts `email`
       │
       ├─► [User Repository (`UserRepository` in `backend/app/repositories/user_repository.py`)]
       │     └─ MongoDB query: `users_collection.find_one({"email": email})`
       │
       ├─► [Prompt Construction]
       │     └─ Reads DB profile/stats -> Formats `user_context_str`
       │     └─ Combines: `f"{user_context_str}\nUSER HỎI: {request.message}\nTRẢ LỜI NGẮN GỌN & THÂN THIỆN:"`
       │     └─ ⚠️ NOTE: Backend IGNORES client `context` and `history`!
       │
       ├─► [AI Provider Call (`get_ai_reply`)]
       │     ├─ Try Gemini (`google.generativeai`): Synchronous call `model.generate_content(prompt)`
       │     └─ Fallback OpenAI (`openai.OpenAI`): Synchronous call `client.chat.completions.create(...)`
       │
       ▼
[HTTP Response] Status 200 OK -> Body: {"reply": "<string>", "status": "success"|"error"}
       │
       ▼
[ApiClient / ChatController Response Handling]
       │ 1. Dio receives status 200 OK
       │ 2. Controller reads `data['reply']`
       │ 3. Appends ChatMessage(role: 'assistant', content: aiReply)
       │ 4. Sets ChatState.isLoading = false
       ▼
[UI Renders Response in ChatScreen]
```

---

## 2. Deployment Runtime Entry Points & Duplicate-Tree Risk Analysis

### Confirmed Evidence

The repository contains **67 duplicate Python source files** mirrored identically between the repository root directory and the `backend/` directory.

1. **Hugging Face Deployment Entry Point:**
   - **File:** `Dockerfile` (line 12)
   - **Command:** `CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "7860"]`
   - **Effective Entry Point:** Loads `backend.main:app`. This imports routers from `backend.routers` (e.g., `backend.routers.chat`).

2. **Render Deployment Entry Point:**
   - **File:** `Procfile` (line 1)
   - **Command:** `web: uvicorn main:app --host 0.0.0.0 --port $PORT`
   - **File:** `render.yaml` (line 7)
   - **Command:** `startCommand: uvicorn main:app --host 0.0.0.0 --port $PORT`
   - **Effective Entry Point:** Loads root `main.py:app`. This imports routers from `backend.routers` because `backend/routers` is in Python path or imported via `from backend.routers import ...`.

### Risk & Vulnerability Analysis

- **Tree Divergence Risk:** Currently, `cmp backend/main.py main.py` and `cmp backend/routers/chat.py routers/chat.py` confirm the files are byte-for-byte identical. However, having dual file trees (`backend/main.py` vs `main.py`, `backend/routers/chat.py` vs `routers/chat.py`) creates an extreme risk: a developer updating `backend/routers/chat.py` will update Hugging Face deployments while leaving Render deployments running outdated code from `routers/chat.py` if python resolution shifts.
- **Root Cause:** Incomplete architectural migration toward Clean Architecture directory structure (`backend/app`).

---

## 3. Request & Response Contract Analysis

### Request Schema vs. Actual Usage Mismatch

#### Frontend Payload Sent (`frontend/lib/controllers/chat_controller.dart`, lines 143–152)

```json
{
  "message": "User query string",
  "context": {
    "profile": { "name": "...", "biometrics": "...", "tdee": 2200.0, "goal": "..." },
    "daily_stats": { "eaten": 500.0, "remaining": 1700.0 },
    "system_instruction": "YOU ARE: You are Saman AI Coach..."
  },
  "history": [
    { "role": "user", "content": "Previous question" },
    { "role": "assistant", "content": "Previous answer" },
    { "role": "user", "content": "User query string" }
  ]
}
```

#### Backend Pydantic Schema (`backend/routers/chat.py`, lines 40–43)

```python
class ChatRequest(BaseModel):
    message: str
    context: Optional[Dict] = None
    history: Optional[List] = None
```

#### Backend Actual Handler Logic (`backend/routers/chat.py`, lines 45–66)

```python
@router.post("")
async def chat_with_ai(request: ChatRequest, email: str = Depends(verify_token)):
    user = user_repo.get_by_email(email)
    ...
    # Xây dựng prompt
    full_prompt = f"{user_context_str}\nUSER HỎI: {request.message}\nTRẢ LỜI NGẮN GỌN & THÂN THIỆN:"
    reply = get_ai_reply(full_prompt)
```

#### Assessment & Findings

- **Silent Payload Dropping:** The backend schema declares `context` and `history`, but the handler function **completely ignores `request.context` and `request.history`**.
- **Context Loss:** Any client-side contextual telemetry (e.g., today's logged meals, specific active workout state, or UI action shortcuts) sent in `context` is discarded without notice.
- **Stateless Chat Memory:** Multi-turn conversation history sent in `history` is completely ignored by the backend. Every user query is treated as a single, isolated turn with zero memory of prior assistant responses.

---

## 4. Response & Error Behavior (HTTP Status Code Semantics)

### Confirmed Evidence

1. **Backend Response Semantics (`backend/routers/chat.py`, lines 68–79):**

```python
    reply = get_ai_reply(full_prompt)
    return {
        "reply": reply,
        "status": "success" if not reply.startswith("Lỗi:") else "error"
    }
except Exception as e:
    logging.error(f"Chat Route Error: {e}")
    return {
        "reply": f"Lỗi hệ thống: {str(e)}",
        "status": "error"
    }
```

2. **Frontend Error Handling (`frontend/lib/controllers/chat_controller.dart`, lines 155–173):**

```python
if (response.statusCode == 200) {
  final data = response.data is String ? jsonDecode(response.data as String) : response.data;
  final aiReply = data['reply'];
  final botMsg = ChatMessage(role: 'assistant', content: aiReply);
  state = state.copyWith(messages: [...state.messages, botMsg], isLoading: false);
} else {
  throw Exception("Server Error: ${response.statusCode}");
}
```

### Risk & Impact

- **HTTP Status Masking (Application Errors inside HTTP 200):** When an AI provider fails (or when AI keys are missing), `get_ai_reply` returns `"Lỗi: Không tìm thấy API Key..."`. The backend route returns this with `HTTP 200 OK` and `status: "error"`.
- **Frontend Misinterpretation:** Because `response.statusCode == 200`, Dio treats the request as successful. `ChatController` reads `data['reply']` and renders `"Lỗi: Không tìm thấy API Key..."` as a regular assistant chat bubble.
- **Failure of Recoverable Error UI:** The frontend's dedicated State 07 Recoverable Error UI (*"I couldn't complete that response."* with `Retry →` / `Edit question`) is **never triggered** for backend AI provider errors because the frontend only enters its `catch` block on HTTP standard errors (>299) or network drops.

---

## 5. Conversation History & Current-Turn Duplication Assessment

### Traced Sequence

1. User types message `"I ate 2 eggs"` in UI and hits send.
2. `ChatController.sendMessage("I ate 2 eggs")` runs:
   - Appends `ChatMessage(role: 'user', content: "I ate 2 eggs")` to `state.messages`. (`state.messages` length = N).
3. `ChatController._sendRequest("I ate 2 eggs")` runs:
   - Calls `_getLastMessages(5)`. Since the current user message was already appended to `state.messages`, `_getLastMessages(5)` includes `"I ate 2 eggs"` as the last item in `history`.
   - Payload sent:
     - `message`: `"I ate 2 eggs"`
     - `history`: `[..., {"role": "user", "content": "I ate 2 eggs"}]`

### Turn Duplication Assessment

- **Confirmed Risk:** The current turn (`message`) is present in both the root `message` field AND as the trailing element of `history`.
- **Backend Combination Risk:** If a future backend implementation constructs the model prompt by naively appending `message` to `history` (e.g., `prompt_messages = history + [message]`), the model will receive the current user turn twice in succession.
- **Recommendation:** Define explicit contract semantics: `history` MUST contain strictly prior turns, excluding the current `message` turn.

---

## 6. Source-of-Truth & Context Trust Boundaries

### Current Dual Source-of-Truth Conflict

| Field | Client Source (`SharedPreferences`) | Backend Source (`MongoDB users_collection`) |
|---|---|---|
| User Name | `prefs.getString('user_name')` | `user.get('full_name')` |
| Weight / Height | `prefs.get('user_weight')`, `user_height` | `user['profile']['weight']`, `height` |
| Goal | `prefs.getString('user_goal')` | `user['profile']['goal']` |
| TDEE | `prefs.get('user_tdee')` | `user['health_stats']['tdee']` |
| Calories Eaten Today | `prefs.get('daily_calories_in')` | Computed from `meal_logs` collection or user document |

### Prompt Injection & Security Boundary Risk

- **Client `system_instruction` Vulnerability:** `ChatController` constructs an extensive system prompt on the client side (`_buildUserContext`, lines 212–264) and transmits it in `request.context['system_instruction']`.
- **Malicious Override Exposure:** If the backend ever executes or trusts `request.context['system_instruction']`, a compromised or modified client app could manipulate system instructions, alter guardrails, instruct the model to leak data, or bypass safety rules.
- **Recommended Source of Truth:**
  1. **Primary Source of Truth:** Backend MongoDB database (`users_collection` & `nutrition_logs`).
  2. **Trust Boundary Rule:** Backend MUST generate all system instructions, guardrails, and user profile summaries directly from verified database records and session authentication. Client-provided context must be strictly limited to transient UI state (e.g., `active_screen`, `selected_food_item_id`).

---

## 7. Authentication & Token Security Boundary Analysis

### Code Evidence

- **Auth Dependency (`backend/auth_utils.py`, lines 24–29):**
  ```python
  def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
      try:
          payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[JWT_ALGORITHM])
          return payload.get("email")
      except Exception:
          raise HTTPException(status_code=401, detail="Token invalid")
  ```
- **Router Dependency (`backend/routers/chat.py`, line 45):**
  ```python
  async def chat_with_ai(request: ChatRequest, email: str = Depends(verify_token)):
  ```

### Assessment across Token States

1. **Valid Token:** Correctly extracts `email` claim from HS256 JWT and passes to handler.
2. **Missing Token:** `security = HTTPBearer()` raises `401 Unauthorized` automatically via FastAPI.
3. **Expired Token / Malformed Signature:** `jwt.decode` throws `ExpiredSignatureError` or `DecodeError`, caught by `except Exception` in `verify_token` and re-raised as `401 Unauthorized (Token invalid)`.
4. **Valid Token but Non-existent User Email:**
   - In `backend/routers/chat.py` (line 48): `user = user_repo.get_by_email(email)`.
   - If `user` is `None`, `user_context_str` defaults to empty string `""`.
   - The request proceeds without failing authentication, but loses user context.

---

## 8. Async Concurrency & Event-Loop Blocking Risks

### Confirmed Code Evidence (`backend/routers/chat.py`, lines 18–38, 45)

```python
def get_ai_reply(prompt: str) -> str:
    if GEMINI_API_KEY:
        ...
        response = model.generate_content(prompt) # ⚠️ SYNCHRONOUS NETWORK I/O
        return response.text
    if OPENAI_API_KEY:
        ...
        response = client.chat.completions.create(...) # ⚠️ SYNCHRONOUS NETWORK I/O
        return response.choices[0].message.content

@router.post("")
async def chat_with_ai(request: ChatRequest, email: str = Depends(verify_token)):
    ...
    reply = get_ai_reply(full_prompt) # ⚠️ CALLED DIRECTLY INSIDE ASYNC DEF
```

### Performance & Architectural Impact

- **Event Loop Starvation:** `chat_with_ai` is declared as an `async def` function. When FastAPI executes an `async def` route, it runs on the main asyncio event loop thread.
- **Blocking Call:** `get_ai_reply` executes blocking HTTP network calls to Google Gemini or OpenAI synchronously on the event loop thread.
- **System Impact:** While one chat request waits 3–10 seconds for an AI model response, **the entire FastAPI process event loop is completely blocked**. All concurrent requests from other users (e.g., authentication, profile fetches, nutrition lookups, health checks) are frozen until the AI network call finishes.
- **Remediation:** Either wrap synchronous provider calls in `asyncio.to_thread(get_ai_reply, full_prompt)` or switch to native async SDK clients (`AsyncOpenAI`, `genai` async methods).

---

## 9. Inventory of Existing Tests & Missing Coverage

### Existing Chat Test Suite (Frontend Only)

| Test File | Focus Area | Backend Realism / Mocks |
|---|---|---|
| `frontend/test/chat_active_conversation_test.dart` | Message list rendering, auto-scroll | Mock / Riverpod Override |
| `frontend/test/chat_drawer_test.dart` | Drawer UI actions & persona dialog | Local Widget State |
| `frontend/test/chat_empty_state_test.dart` | Quick suggestion taps & empty UI | Local Widget State |
| `frontend/test/chat_food_photo_test.dart` | Food photo state, meal log buttons | Mocked `NutritionService` |
| `frontend/test/chat_loading_and_recovery_test.dart` | State 05 (Loading) & State 07 (Recovery) | Local Controller State |
| `frontend/test/chat_long_response_test.dart` | Markdown rendering & table layouts | Static Mock Markdown |
| `frontend/test/chat_reminder_nudge_test.dart` | Nudge banner UI presentation | Local Widget State |

### Identified Test Coverage Gaps

1. **Backend Unit Tests (`backend/tests`):** **ZERO** unit tests exist for `backend/routers/chat.py` or AI provider fallback logic.
2. **API Contract Tests:** No automated tests verify request/response JSON schema compliance between Dio client and FastAPI router.
3. **Auth Integration Tests:** No tests verify behavior under missing, expired, or tampered JWT tokens on the chat route.
4. **Negative & Error Tests:** No backend tests simulate provider timeouts, rate limits, 5xx AI provider errors, or malformed JSON responses.

---

## 10. Classified Findings & Detailed Breakdown

### P0 Findings (Critical - Must Fix Before Production)

#### Finding P0-1: Synchronous AI SDK Calls Block FastAPI Async Event Loop
- **Classification:** Confirmed Bug & Performance Vulnerability
- **Impact:** System-wide latency spikes and total server unresponsiveness under concurrent chat usage.
- **Trigger Condition:** Multiple users calling `POST /api/chat` simultaneously.
- **Evidence:** `backend/routers/chat.py` (lines 24, 34, 65).
- **Remediation:** Execute provider calls in threadpool via `await asyncio.to_thread(...)` or migrate to `AsyncOpenAI` / `genai` async API calls.

#### Finding P0-2: Un-sanitized Client Control of System Prompt & Guardrails
- **Classification:** Confirmed Security Risk
- **Impact:** Prompt injection, safety guardrail bypass, and persona hijacking.
- **Trigger Condition:** Malicious or altered client payload sending modified `context.system_instruction`.
- **Evidence:** `frontend/lib/controllers/chat_controller.dart` (lines 212–264) vs `backend/routers/chat.py` (line 58).
- **Remediation:** Remove client-side prompt generation; assemble system instructions and safety rules exclusively inside the backend router using authenticated database records.

#### Finding P0-3: Deployment Entry Point Divergence across Duplicate Code Trees
- **Classification:** Confirmed Risk
- **Impact:** Production bugs where Render and Hugging Face run different code versions due to `backend/` vs root file duplication.
- **Trigger Condition:** Developer edits `backend/routers/chat.py` without updating root `routers/chat.py`.
- **Evidence:** `Dockerfile` (line 12: `backend.main:app`), `Procfile` (line 1: `main:app`), `render.yaml` (line 7: `main:app`).
- **Remediation:** Consolidate entry points in follow-up task so both deployment environments run `backend.main:app`.

---

### P1 Findings (High - Contract & Error Mismatches)

#### Finding P1-1: Silent Payload Dropping (`context` and `history` Ignored)
- **Classification:** Confirmed Bug
- **Impact:** Total loss of multi-turn conversation context and user telemetry in backend prompt generation.
- **Trigger Condition:** Normal chat conversation where user sends follow-up questions.
- **Evidence:** `backend/routers/chat.py` (lines 40–66).
- **Remediation:** Update backend route to parse `history` array and append prior turns into model prompt messages.

#### Finding P1-2: Application & Provider Errors Masked under HTTP 200 OK
- **Classification:** Confirmed Architectural Defect
- **Impact:** Frontend cannot trigger State 07 Recoverable Error UI; error messages render as valid coach responses.
- **Trigger Condition:** Missing API keys, provider outage, or rate-limiting.
- **Evidence:** `backend/routers/chat.py` (lines 70–78) and `frontend/lib/controllers/chat_controller.dart` (lines 155–163).
- **Remediation:** Return standard HTTP status codes (`HTTP 502 Bad Gateway` or `HTTP 500 Internal Server Error`) when AI providers fail, allowing frontend Dio client to catch errors cleanly.

#### Finding P1-3: History Construction Creates Duplicate Current-Turn Risk
- **Classification:** Confirmed Risk
- **Impact:** Model receives current user query twice in prompt, causing repetitive or confused responses.
- **Trigger Condition:** Frontend sends `message` and `history` where `history` already contains `message`.
- **Evidence:** `frontend/lib/controllers/chat_controller.dart` (lines 111–125, 281–287).
- **Remediation:** Exclude current user message from `history` list when calling `_sendRequest()`.

#### Finding P1-4: Auth Exception Handling Divergence between Auth Utilities
- **Classification:** Confirmed Architectural Risk
- **Impact:** Inconsistent error responses across endpoints when token is expired or invalid (`401` vs `500`).
- **Trigger Condition:** User with expired token accesses `/api/chat` vs `/api/user/profile`.
- **Evidence:** `backend/auth_utils.py` (`verify_token`) vs `backend/auth/dependencies.py` (`get_token_header`).
- **Remediation:** Standardize auth dependencies across all backend routers.

---

### P2 Findings (Medium - Data Integrity & Edge Cases)

#### Finding P2-1: Dual Source-of-Truth Conflict for User Profile Telemetry
- **Classification:** Confirmed Risk
- **Impact:** Inconsistent coaching advice if local `SharedPreferences` stats differ from MongoDB user profile.
- **Trigger Condition:** Profile updated on web or another device.
- **Evidence:** `frontend/lib/controllers/chat_controller.dart` (lines 185–205) vs `backend/routers/chat.py` (lines 48–56).
- **Remediation:** Make backend MongoDB the authoritative source of truth for user health stats.

#### Finding P2-2: Missing Timeout, Cancellation, and Rapid-Submit Handling
- **Classification:** Confirmed Edge Case Risk
- **Impact:** Multiple overlapping HTTP requests when user rapidly taps send button.
- **Trigger Condition:** Rapid user interaction during pending API request.
- **Evidence:** `frontend/lib/controllers/chat_controller.dart` (`sendMessage` lacks active request debouncing or cancellation token).
- **Remediation:** Disable send button and ignore input submission while `isLoading` is true.

#### Finding P2-3: Unhandled Malformed or Null AI Provider Responses
- **Classification:** Confirmed Risk
- **Impact:** Backend crashes with `AttributeError` or `KeyError` if AI response body is null or malformed.
- **Trigger Condition:** Provider returns unexpected JSON structure.
- **Evidence:** `backend/routers/chat.py` (lines 25, 36).
- **Remediation:** Add null-checks and fallback handling around `response.text` and `response.choices[0]`.

---

### P3 Findings (Low - Technical Debt)

#### Finding P3-1: Zero Backend Integration & Contract Unit Tests
- **Classification:** Confirmed Debt
- **Impact:** Regression risk during backend refactoring.
- **Evidence:** Absence of chat tests in `backend/tests/`.
- **Remediation:** Add FastAPI `TestClient` test suite covering `/api/v1/chat`.

#### Finding P3-2: Hardcoded AI Model Parameters
- **Classification:** Intentional Limitation / Debt
- **Impact:** Inability to adjust model temperature or max tokens without code changes.
- **Evidence:** `backend/routers/chat.py` (lines 23, 31: `gemini-1.5-flash`, `gpt-4o-mini`).
- **Remediation:** Move model IDs and temperature parameters to environment variables.

---

## 11. Proposed Stable API Contract (`/api/v1/chat`)

To prepare for tomorrow's backend implementation task without making changes today, the following stable, versioned API contract is proposed:

### Request Contract (`POST /api/v1/chat`)

```json
{
  "message": "What should I eat for dinner to reach my protein goal?",
  "history": [
    { "role": "user", "content": "I had chicken salad for lunch." },
    { "role": "assistant", "content": "Great choice! That provided about 35g of protein." }
  ],
  "context_overrides": {
    "active_screen": "chat_screen",
    "selected_food_id": null
  }
}
```

### Response Contract — Success (`HTTP 200 OK`)

```json
{
  "status": "success",
  "data": {
    "reply": "Based on your remaining 35g protein target, a salmon fillet with quinoa would be ideal.",
    "model_used": "gemini-1.5-flash",
    "usage": {
      "prompt_tokens": 120,
      "completion_tokens": 45
    }
  }
}
```

### Response Contract — Error (`HTTP 502 / 500 / 401`)

```json
{
  "status": "error",
  "error": {
    "code": "PROVIDER_UNAVAILABLE",
    "message": "Unable to communicate with AI coaching service. Please try again later.",
    "details": null
  }
}
```

---

## 12. Recommended Backend Implementation Sequence for Follow-up Task

For the upcoming backend implementation task, the following sequence is recommended:

1. **Phase 1: Entry Point Consolidation & Route Versioning**
   - Direct `Procfile` and `render.yaml` to use `backend.main:app`.
   - Create new versioned route `POST /api/v1/chat` in `backend/routers/chat.py`.
2. **Phase 2: Auth & User Profile Context Integration**
   - Wire `verify_token` authentication.
   - Fetch authoritative user profile and TDEE/nutrition stats from MongoDB `UserRepository`.
3. **Phase 3: Async Provider Integration & Fallback**
   - Implement asynchronous wrapper (`asyncio.to_thread`) for AI provider calls.
   - Implement Gemini -> OpenAI -> Fallback message provider pipeline.
4. **Phase 4: History Construction & Prompt Assembly**
   - Cleanly format `history` array (excluding current turn) into provider prompt messages.
   - Enforce system guardrails on backend.
5. **Phase 5: Error Semantics & Status Codes**
   - Ensure AI provider exceptions raise proper HTTP `502` / `500` status codes.
6. **Phase 6: Frontend Integration & Test Verification**
   - Update `ChatController` to call `/api/v1/chat` and handle HTTP status errors.
   - Run backend `compileall` and frontend widget test suite.

---

## 13. Baseline of Impacted Production Files for Follow-up Task

The following files will likely need modification during the follow-up backend implementation task:

- `backend/routers/chat.py` (and root `routers/chat.py` until duplicate tree is removed)
- `frontend/lib/controllers/chat_controller.dart`
- `Procfile`
- `render.yaml`
- `backend/tests/test_chat_router.py` (new test file to be created)

---

## 14. Verification Commands & Log

The following read-only verification commands were executed to confirm system baseline health:

```bash
# 1. Python Syntax Verification
python3 -m compileall -q backend
# Result: SUCCESS (0 errors)

# 2. Flutter Codebase Analysis
cd frontend
flutter analyze --no-fatal-infos --no-fatal-warnings
# Result: SUCCESS (108 non-fatal info issues found, 0 errors)

# 3. Flutter Chat Widget & State Tests
flutter test test/chat_active_conversation_test.dart
flutter test test/chat_loading_and_recovery_test.dart
flutter test test/chat_food_photo_test.dart
cd ..
# Result: SUCCESS (All tests passed)

# 4. Git Diff & Working Tree Verification
git diff --check
git status --short
# Result: Clean working tree. Single new file created: docs/audits/chat-backend-readiness-audit.md
```

### Tooling & Environment Limitations

- `flutter analyze` reported 108 pre-existing non-fatal informational notices (mostly linter suggestions regarding trailing commas and const constructors in unrelated screens). Per task instructions, these were documented and left unmodified.

---

## 15. Final Scope & Audit Confirmation

- **Production Source Modified:** NONE (0 files)
- **Tests Modified:** NONE (0 files)
- **Configurations / Deployment Files Modified:** NONE (0 files)
- **Secrets / Credentials Exposed:** NONE
- **External Paid APIs Called:** NONE
- **Single Permitted Audit Artifact Created:** `docs/audits/chat-backend-readiness-audit.md`

*Audit completed successfully.*
