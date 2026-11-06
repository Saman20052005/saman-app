# SAMAN JOURNEY & GAMIFICATION LOOP — IMPLEMENTATION DECISION

**Document Version**: 2.0.0 (Production Architecture, Approved Stitch Design & Verified Business Logic)  
**Author**: Senior Flutter + FastAPI Tech Lead & Systems Architect  
**Scope**: Gamification, Streak Rules, Journey Lifecycle, Points Wallet, AI Turn Exchange, and In-App Feedback Patterns  
**Status**: Approved & Implemented  

---

## 1. ARCHITECTURAL BASELINE & EVIDENCE AUDIT

| Component | Source File / Symbol Evidence | Verified Current State | Architectural Decision for Journey |
| :--- | :--- | :--- | :--- |
| **App Routing & Entry** | `frontend/lib/main.dart`, `frontend/lib/config/routes.dart` | `AppRoutes.splash` checks token -> `AppRoutes.main` -> `ProfileGate`. | Journey is **NOT** a gate requirement for app entry. Entry to `MainScreen` remains purely based on confirmed profile. |
| **Profile & Onboarding Gate** | `frontend/lib/features/profile/presentation/profile_gate.dart` (`ProfileGateState`) | `isCompleteAndConfirmed` admits `MainScreen`; `isIncompleteAndConfirmed` renders `OnboardingFlowScreen`. | Create Journey invitation is offered post-onboarding once via `just_finished_onboarding_$userId` flag with "Để sau", setting `has_dismissed_journey_prompt_$userId`. Never blocks app entry or repeatedly pesters. |
| **Home Screen Structure** | `frontend/lib/screens/home_screen.dart` (`HomeScreenState.build()`) | Sliver order: Header -> CompanionBar -> WorkoutRecommendationCarousel -> DailyTargetsCard -> QuickActionDock -> WeeklyConsistencyCard -> Picks. | Placed **immediately after QuickActionDock and before WeeklyConsistencyCard** as `SamanJourneyCard` (Summary/Hero status). |
| **Nutrition Completion** | `backend/routers/nutrition.py` (`POST /api/nutrition/logs`), `frontend/lib/providers/nutrition_provider.dart` (`addMeal`), `daily_story_provider.dart` | Saves real meal log with MongoDB `_id` in `nutrition_plans`. Photo analysis `/api/food/analyze` is read-only inference. | Nutrition task is completed **ONLY** when verified against a real meal log in `nutrition_plans` owned by authenticated user. Network failure during journey sync does NOT fail meal save. |
| **Workout Completion** | `backend/routers/workout.py` (`POST /api/workouts/sessions`), `ActiveWorkoutScreen` | Real session saved in `workout_history` with `_id`. CV runs on-device MediaPipe Android. | Workout task is completed **ONLY** when session log succeeds with matching owner and date. Unverified camera reps do NOT count. |
| **Membership & Quotas** | `frontend/lib/features/membership/domain/models/membership_plan.dart` | Free, Plus, Pro, Ultra tiers. Dual-currency wallet maintains points and AI analysis credits. | Saman Points wallet maintains points and exchange catalog. AI credit redemption grants real `ai_credits` to the user profile atomically. Unavailable perks have `is_available: false` and are rejected before touching balance. |
| **Timezone & Date** | `backend/routers/journey.py` (`VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")`) | Canonical business timezone is `Asia/Ho_Chi_Minh` (UTC+7). | All streak boundaries, day resets, and task eligibility are computed in UTC+7 (YYYY-MM-DD). |
| **Database Topology** | `backend/app/database.py` | Local development MongoDB operates in **Standalone** mode. | **Atomic single-document mutation with embedded claim receipt** on `users.applied_claims.{claim_key}` (`find_one_and_update`, `$inc`, `$exists: False`) guarantees complete idempotency, zero lost points on crash, and race-condition safety without requiring multi-document replica-set transactions. |

---

## 2. BUSINESS LOGIC RECONCILIATION & RESOLUTIONS (STEP 2 AUDIT)

### A. Đổi thưởng chưa khả dụng & Kiểm chứng Consumer Lượt AI (Unavailable Rewards & AI Credit Consumer Audit)
- **Problem Diagnosed**:
  1. Previous implementation allowed redeeming rewards labeled "Thử nghiệm / Sắp có hiệu lực", deducting points while granting no real feature.
  2. Báo cáo trước mô tả “Đổi 100 điểm → cộng 1 aiCredits”. Tuy nhiên, qua rà soát toàn bộ backend (`backend/routers/food_analysis.py`, `backend/routers/nutrition.py`, `backend/routers/workout.py`, `backend/routers/chat.py`):
     - Tính năng phân tích ảnh món ăn tại `food_analysis.py` chỉ kiểm tra hàm `is_gemini_allowed(email)` dựa vào biến môi trường `GEMINI_ALLOWED_EMAILS`.
     - **Hoàn toàn KHÔNG có consumer backend** nào kiểm tra, ràng buộc hay trừ trường `ai_credits` khi người dùng gọi AI.
     - Chưa có cơ chế xử lý timeout, retry hoặc refund khi gọi AI thất bại theo quota.
- **Resolution**:
  - **Khóa toàn bộ gói đổi chưa có consumer thật**: Đặt `is_available = False` cho cả `rew_ai_credit_1`, `rew_ai_credit_3` và `rew_champion_badge` ở cả backend (`backend/routers/journey.py`) và frontend (`wallet_rewards_screen.dart`, `fake_journey_repository.dart`).
  - Gắn nhãn trạng thái catalog: `"Chưa khả dụng · Đang kết nối hạ tầng AI quota"`.
  - Endpoint `POST /api/wallet/redeem` từ chối tất cả các yêu cầu đổi này với `HTTP 400 Bad Request` *trước khi chạm vào số dư người dùng*. Không tạo thành công giả, không trừ điểm.
  - Giao diện Ví hiển thị catalog dưới dạng “Sắp có”, làm mờ (opacity 0.45) và vô hiệu hóa nút CTA (“Các gói đổi sắp ra mắt”).
  - Thêm định danh phiên bản catalog thử nghiệm: `REWARDS_CATALOG_VERSION = "2026.10.experimental_v1"` để UI đọc trực tiếp từ contract API thay vì hardcode giá trị.
  - **Past Deduction Remediation**: Nếu trước đó có dữ liệu thử nghiệm bị trừ điểm oan, chạy thủ tục hoàn trả nguyên tử:
    ```python
    # Remediation procedure for pre-existing trial deductions:
    # 1. Query point_transactions with type="reward_redemption" and reference_id in ["rew_champion_badge", "rew_ai_credit_1", "rew_ai_credit_3"]
    # 2. For each transaction, issue an atomic $inc {"saman_points": abs(amount)} to user
    # 3. Insert point_transactions record with type="remediation_refund"
    ```

### B. Hoàn thành nhiệm vụ vs. Nhận thưởng ngày (Task Completion vs. Daily Reward)
- **Problem Diagnosed**: Previous version auto-credited points immediately when individual tasks completed, conflicting with the approved PRD daily reward claim flow.
- **Resolution**:
  - Four distinct states established:
    1. **Hoạt động hợp lệ đã lưu**: Meal log or workout session successfully saved in DB.
    2. **Nhiệm vụ/Điều kiện ngày hoàn thành**: Task `is_completed = true`; when all daily tasks complete, Day `is_completed = true`. **0 points auto-credited**.
    3. **Phần thưởng đủ điều kiện**: Day complete, `is_daily_reward_claimed = false`. Prominent CTA "Nhận 20 điểm" enabled.
    4. **Phần thưởng đã nhận**: User clicked claim, backend atomically credited 20 SP. Confirmation row "Đã nhận 20 điểm hôm nay".
  - Endpoint `POST /api/journey/claim-daily-reward` implemented with unique idempotency locking.

### C. Xác thực hoạt động thật (Completion Evidence Verification)
- **Problem Diagnosed**: Endpoint `/api/journey/complete-task` previously trusted client IDs without verification.
- **Resolution**:
  - Backend queries `db["nutrition_plans"]` (for nutrition) and `db["workout_history"]` (for workout).
  - Verifies:
    1. Document exists with valid `ObjectId`.
    2. Owned by the currently authenticated user (`user_email` or `user_id`).
    3. Date matches task date in `Asia/Ho_Chi_Minh`.
    4. `activity_id` is unique across all tasks in the journey (anti-duplicate claim).
  - Graceful fallback: If client doesn't pass `activity_id` (e.g. background sync recovery), backend reconciles by looking up any valid log for that user and date.
  - Client errors during journey sync do NOT fail the primary meal or workout save flow.

### D. Thứ tự ghi, Nguồn dữ liệu có thẩm quyền & Kiểm chứng Fault Injection Claim
- **Lỗ hổng thứ tự ghi cũ được phát hiện & khắc phục**:
  - *Phát hiện*: Trước đó, sequence thực hiện `journey_claims pending -> credited` trước khi `$inc users.saman_points`. Nếu process gặp sự cố giữa 2 thao tác, retry sẽ thấy claim đã mang trạng thái `credited` và bỏ qua `$inc`, dẫn tới mất điểm của người dùng.
  - *Giải pháp*: Áp dụng pattern **Atomic Single-Document Mutation with Embedded Receipt** trên MongoDB Standalone. Cả việc tăng số dư (`$inc: {"saman_points": 20}`) và ghi nhận biên lai nhận thưởng (`$set: {f"applied_claims.{claim_key}": receipt_data}`) được thực thi đồng thời trong **CÙNG một thao tác nguyên tử duy nhất trên CÙNG document người dùng (`users`)** với điều kiện query `f"applied_claims.{claim_key}": {"$exists": False}`.
- **Hệ thống thẩm quyền dữ liệu (Hierarchy of Authority)**:
  1. **Canonical Claim Authority & Balance State (Thẩm quyền cao nhất)**: Trường `users.applied_claims.{claim_key}` cùng `users.saman_points`. Đây là nguồn dữ liệu duy nhất quyết định quyền lợi đã được cộng hay chưa. Do nằm trong cùng 1 document, tính toàn vẹn ACID là tuyệt đối ngay cả trên MongoDB Standalone.
  2. **Audit Ledger**: Collection `point_transactions` với `_id = f"tx_{claim_key}"` (upsert an toàn, idempotent từ metadata biên lai).
  3. **Claim State Sync**: Collection `journey_claims` với `_id = claim_key` mang `status: "credited"`.
  4. **Presentation Cache**: Mảng `journeys.days[...].is_daily_reward_claimed`.
- **Thứ tự ghi chuẩn (Write Sequence)**:
  ```mermaid
  sequenceDiagram
    autonumber
    Client->>Backend: POST /api/journey/claim-daily-reward
    Backend->>journeys: 1. Đọc và kiểm tra hành trình (ngày hợp lệ, chưa claim)
    Backend->>users: 2. find_one_and_update (ATOMIC WALLET UPDATE)
    Note over Backend,users: Query: email == user_email AND applied_claims[claim_key] NOT EXISTS<br/>Update: $inc saman_points += 20 AND $set applied_claims[claim_key] = receipt
    alt Cập nhật thành công (Lần đầu claim)
      Backend->>point_transactions: 3. update_one(_id: tx_claim_key, $setOnInsert, upsert=True)
      Backend->>journey_claims: 4. update_one(_id: claim_key, $set: status="credited", upsert=True)
      Backend->>journeys: 5. update_one(days[...].is_daily_reward_claimed = True)
      Backend-->>Client: 6. Return response {new_balance, message}
    else Cập nhật trả về None (Claim đã tồn tại / Retry)
      Backend->>users: 3b. Đọc lại receipt từ applied_claims[claim_key]
      Backend->>point_transactions: 4b. Reconcile / heal ledger nếu thiếu
      Backend->>journeys: 5b. Reconcile / heal UI flag nếu thiếu
      Backend-->>Client: 6b. Return idempotent response {new_balance: current_balance, message: "..."}
    end
  ```
- **Xử lý các điểm lỗi thực tế & Bằng chứng kiểm thử (Fault-Injection & Failure Modes)**:
  1. *Lỗi trước atomic wallet update*: Document user chưa thay đổi, `applied_claims.{claim_key}` chưa tồn tại. Khi retry, query `$exists: False` khớp bình thường, cộng đúng 20 SP và lưu receipt (Đã kiểm chứng: `test_claim_failure_before_atomic_wallet_update`).
  2. *Lỗi sau atomic wallet update nhưng trước khi ghi ledger/journey*: Điểm đã cộng, receipt đã lưu. Khi retry, query `$exists: False` không khớp (trả về None), hệ thống đọc receipt gốc, tự động phục hồi (heal) ledger và cờ journey, **tuyệt đối không cộng thêm điểm lần 2** (Đã kiểm chứng: `test_claim_failure_after_atomic_wallet_update_before_ledger`).
  3. *Lỗi trước khi trả response*: Người dùng hoặc app timeout gọi lại; backend trả ngay trạng thái thành công kèm `new_balance` hiện tại và thông báo idempotency mà không thay đổi số dư.
  4. *Hai request gửi đồng thời (Concurrency / Race Condition)*: Khóa document cấp độ MongoDB đảm bảo đúng 1 request khớp `$exists: False` và thực hiện `$inc: 20`. Request thứ 2 lập tức bị từ chối chuyển sang nhánh retry idempotent. Tổng số dư tăng đúng 20 SP (Đã kiểm chứng bằng cả giả lập in-memory `test_claim_concurrent_requests_race_condition` và MongoDB 7.0.14 thật với `asyncio.gather` trong `test_journey_real_mongo.py`).
  5. *Retry khi cấu hình thưởng thay đổi (Policy Change)*: Receipt lưu rõ `points: 20, policy_version: "2026.10.v1"`. Dù hệ thống đổi cấu hình lên 50 SP, retry vẫn phục hồi ledger với đúng 20 SP gốc từ receipt (Đã kiểm chứng: `test_claim_retry_preserves_original_points_on_policy_change`).
  6. *Đối soát dữ liệu cũ (Legacy Credited Records without Receipt)*:
     - Nếu tồn tại bản ghi trong `journey_claims` có `status: "credited"` nhưng không có `applied_claims.{claim_key}` trong `users`: Không tự ý cộng bù trên dữ liệu người dùng thật để tránh sai lệch kế toán.
     - Quy trình đối soát: Chạy script so khớp `journey_claims` và `point_transactions`. Chỉ đối soát hoàn điểm nếu có bản ghi giao dịch trong `point_transactions` tương ứng chứng minh tiền đã được cộng hoặc trừ.

### E. Quy tắc Ngày nghỉ, Chuỗi liên tiếp (Streak) & Phân định chỉ số
- **Cách xác định Ngày nghỉ (Rest Day Determination)**:
  - **Chu kỳ**: Ngày thứ 6 của mỗi chu kỳ 7 ngày tính từ ngày bắt đầu hành trình (`((day_index) % 7) == 6`).
  - **Nội dung nhiệm vụ**:
    - Với hành trình Workout: Thay thế bài tập nặng bằng nhiệm vụ hồi phục nhẹ (`Nghỉ ngơi & phục hồi`: "Thả lỏng cơ thể, giãn cơ nhẹ nhàng hoặc đi bộ").
    - Với hành trình Nutrition hoặc Hybrid: Vẫn duy trì nhiệm vụ ghi nhận bữa ăn (`Ghi nhận bữa ăn`), vì dinh dưỡng cần duy trì liên tục.
  - **Duy trì Streak**: Ngày nghỉ tự động bảo lưu chuỗi liên tiếp (`current_streak`) mà không làm ngắt chuỗi của người dùng, tôn trọng triết lý *Calm Athleticism* không trừng phạt người dùng khi cơ thể cần hồi phục.
  - **Quy tắc nhận thưởng ngày nghỉ**: Để nhận thưởng 20 điểm thưởng ngày của ngày nghỉ, người dùng vẫn phải hoàn thành và xác nhận các nhiệm vụ của ngày nghỉ đó. Nếu không hoàn thành, streak vẫn được giữ nhưng không nhận thưởng 20 điểm của ngày nghỉ.
- **Phân tách ba chỉ số độc lập**:
  - `day_index`: Ngày thứ mấy của lịch trình (1 đến `total_days`).
  - `completed_days_count`: Tổng số ngày trong quá khứ đã hoàn thành 100% nhiệm vụ.
  - `current_streak`: Số ngày liên tiếp hoàn thành tính đến hiện tại. Hành trình mới tạo có `current_streak = 0`. Ngày hôm nay chưa kết thúc không bị coi là bỏ lỡ. Bỏ lỡ ngày trong quá khứ ngắt streak về 0 nhưng giữ nguyên `completed_days_count` và `best_streak`.

### F. Onboarding & Session Invalidation
- ProfileGate remains 100% untouched.
- `just_finished_onboarding_$userId` flag set in SharedPreferences upon onboarding completion; `HomeScreen` presents the invitation once with "Để sau", setting `has_dismissed_journey_prompt_$userId`.
- `AuthHelper.logout` explicitly invalidates `journeyControllerProvider` and `walletControllerProvider`.
- Reminder time is stored purely as a user preference string (HH:mm); UI states "Bạn có thể điều chỉnh giờ nhắc bất kỳ lúc nào" without claiming local notification scheduling.

---

## 3. DESIGN ARTIFACT MAPPING (STITCH CALM ATHLETICISM)

| Stitch Approved Design Source | Flutter Target File | Core Visual & Behavioral Directives |
| :--- | :--- | :--- |
| `design/saman-journey/saman_habit_journey/saman_screen_1_t_o_h_nh_tr_nh/` (`screen.png` & `code.html`) | `frontend/lib/features/journey/presentation/screens/create_journey_screen.dart` | Obsidian `#0C0D0E`, Focus options (Workout, Nutrition, Both) with emerald radio, Segmented duration (7, 14, 30 days theo policy; default 14 ngày), Reminder toggle & time picker, Sticky CTA `#F9FAFB` button, thao tác "Để sau". |
| `design/saman-journey/saman_habit_journey/saman_screen_2_h_nh_tr_nh_c_a_t_i/` (`screen.png` & `code.html`) | `frontend/lib/features/journey/presentation/screens/my_journey_screen.dart` | Hero card with streak flame `#FFB95F` & tabular figures, Today's tasks (clean rows, read-only status for completed, tappable to launch logging, NO checkboxes), Daily reward claim button (20 pts), 7-column calendar matrix with legend, Point Wallet entry row. |
| `design/saman-journey/saman_habit_journey/saman_screen_3_v_i_m_i_l_t_ai/` (`screen.png` & `code.html`) | `frontend/lib/features/journey/presentation/screens/wallet_rewards_screen.dart` | Center-aligned accumulated points (48px tabular digits) & AI credits chip, Divided exchange offer rows (toàn bộ gói chưa khả dụng hiển thị "Sắp có", mờ opacity 0.45, nút CTA vô hiệu hóa), Disclaimer note, Recent Activity transaction ledger with empty state, Sticky CTA `#F9FAFB` button, Confirmation Modal Bottom Sheet (Before/After balance preview, Confirm Redeem, Maybe later). |
| `design/saman-journey/saman_habit_journey/saman_in_app_feedback_components_state_variants/` (`screen.png` & `code.html`) | `frontend/lib/features/journey/presentation/widgets/journey_feedback.dart` | Standard meal saved, Meal/Workout saved + Task completed snackbars with "Xem →" action, Daily completion banner ("Nhận thưởng"), Missed day supportive message ("Khởi động lại..."), AI credit redemption success sheet. |
| Prototype Summary Card | `frontend/lib/features/journey/presentation/widgets/saman_journey_card.dart` | Home screen summary module (Obsidian `#16171B`, hairline `#26282F`, emerald `#10B981`). Inactive invitation vs. Active progress hero. |

---

## 4. DIFFERENCE TABLE: STITCH MOCKUPS VS. BUSINESS SPECIFICATION

| Element | Stitch Design Mockup Illustration | Saman Production Implementation | Rationale & Nguồn phê duyệt nghiệp vụ |
| :--- | :--- | :--- | :--- |
| **Duration Options** | Hiển thị 21 ngày làm ví dụ minh họa | **Policy 7, 14, 30 ngày (mặc định 14 ngày)** | Giữ nguyên phạm vi nghiệp vụ đã chốt ban đầu (7/14/30 ngày). 21 ngày chỉ là minh họa trong mẫu Stitch và không được chọn làm mặc định sản phẩm. |
| **Daily Reward Value** | Hiển thị 20 pts trong UI | **20 Saman Points (SP) / ngày hoàn thành** | Phê duyệt từ PRD v2.0; cấu hình động qua contract `daily_reward_points`, không hardcode vào UI. |
| **Exchange Packs** | Gói 1: 1 AI credit = 100 pts<br>Gói 2: 3 AI credits = 280 pts | **Toàn bộ gói đổi AI & Huy hiệu ở trạng thái `is_available: false` (Sắp có)** | **Kiểm chứng thực tế:** Backend hiện tại chưa có consumer kiểm tra và trừ `ai_credits` khi gọi AI. Để đảm bảo không trừ điểm khống của user, toàn bộ gói đổi bị khóa ở cả backend (trả HTTP 400 trước khi trừ tiền) và frontend (dim, disabled button). Thuộc cấu hình thử nghiệm version `2026.10.experimental_v1`. |
| **Task Completion** | Read-only trên mockup | Read-only điều khiển bởi bản ghi thật trong MongoDB (`nutrition_plans`, `workout_history`) | Triệt tiêu checkbox thủ công, chống gian lận claim điểm và chống desync. |
| **Reminder Scheduling** | Toggle và chọn giờ trực quan | Lưu preference dạng chuỗi (HH:mm) trên profile | Tránh mở rộng hạ tầng push notification vượt ngoài phạm vi giao diện task. |
| **Rest Day Policy** | Minh họa biểu tượng mầm cây / chiếc lá | **Ngày thứ 6 trong mỗi chu kỳ 7 ngày** | Bảo lưu streak mà không ép tập luyện nặng; nhiệm vụ nghỉ ngơi hồi phục hoặc dinh dưỡng. Nhận thưởng 20 SP cần hoàn thành nhiệm vụ ngày nghỉ. |

---

## 5. FILES MODIFIED & CREATED

### Primary Scope Files (Created / Restyled)
1. `backend/routers/journey.py`: FastAPI router with real activity verification, atomic single-document wallet update with embedded receipt on `users.applied_claims`, idempotent retry healing, and unavailable reward guards.
2. `backend/tests/test_journey.py`: Comprehensive test suite (10 unit/fault-injection tests covering streak, verification, idempotency, crash before atomic mutation, crash after atomic mutation before ledger, concurrency race condition, policy version change retry, unavailable reward rejection, AI package lockout, rest days).
3. `backend/tests/test_journey_real_mongo.py`: Real MongoDB integration test suite (2 integration tests against local MongoDB 7.0.14 on port 27028, verifying real concurrent claims and crash recovery).
4. `frontend/lib/features/journey/domain/models/journey_models.dart`: Models for `SamanJourney`, `JourneyDayRecord`, `JourneyTask`, `PointTransaction`, `RewardItem`.
5. `frontend/lib/features/journey/data/repositories/journey_repository.dart`: Interface & implementation with `claimDailyReward` and `WalletBalanceData`.
6. `frontend/lib/features/journey/data/repositories/fake_journey_repository.dart`: Mock repository for isolated widget tests with dynamic item availability toggle.
7. `frontend/lib/features/journey/presentation/providers/journey_providers.dart`: Riverpod state notifiers for journey and wallet.
8. `frontend/lib/features/journey/presentation/screens/create_journey_screen.dart`: Stitch Screen 1 (7/14/30 days, default 14).
9. `frontend/lib/features/journey/presentation/screens/my_journey_screen.dart`: Stitch Screen 2.
10. `frontend/lib/features/journey/presentation/screens/wallet_rewards_screen.dart`: Stitch Screen 3.
11. `frontend/lib/features/journey/presentation/widgets/saman_journey_card.dart`: Home summary hero card.
12. `frontend/lib/features/journey/presentation/widgets/journey_feedback.dart`: Stitch feedback components and snackbars.
13. `frontend/test/features/journey/journey_flow_test.dart`: Complete unit & widget test suite (16 tests).

### Shared Integration Files (Minimal Wiring Only)
1. `backend/main.py`: Route inclusion for `journey_router`.
2. `backend/routers/__init__.py`: Export of `journey_router`.
3. `frontend/lib/config/routes.dart`: Route constants and generators for journey screens.
4. `frontend/lib/screens/home_screen.dart`: Embedded `SamanJourneyCard` and post-onboarding invitation hook.
5. `frontend/lib/screens/profile_screen.dart`: Navigation rows for journey and wallet.
6. `frontend/lib/providers/nutrition_provider.dart`: Event dispatch to journey controller on meal save.
7. `frontend/lib/providers/daily_story_provider.dart`: Event dispatch on daily meal log confirm.
8. `frontend/lib/presentation/screens/active_workout_screen.dart`: Event dispatch on workout session save.
9. `frontend/lib/utils/auth_helper.dart`: Invalidation of journey and wallet state on logout.
10. `frontend/lib/features/profile/presentation/onboarding/onboarding_flow_screen.dart`: Sets `just_finished_onboarding` flag upon completion.

---

## 6. ANALYZER DIAGNOSTIC #87 AUDIT

- **Analyzer Result**: `87 issues found` across the entire Flutter project.
- **Journey Scope Verification**:
  - `frontend/lib/features/journey/**`: Exactly **0 errors, 0 warnings, 0 infos**.
- **Exact Details of Diagnostic #87**:
  - **File**: `frontend/lib/screens/profile_screen.dart`
  - **Line**: 240, Column: 52
  - **Diagnostic Code**: `use_build_context_synchronously`
  - **Message**: `info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\screens\profile_screen.dart:240:52 - use_build_context_synchronously`
  - **Origin**: Part of pre-existing uncommitted avatar upload logic (`uploadAvatar` / `_showAvatarOptions` in `profile_screen.dart`). Not introduced by the Journey feature.

---

## 7. RUNTIME ISOLATION & VERIFICATION SUMMARY

1. **Shared Runtime Status**:
   - Port 8000: Occupied by pre-existing background process (uvicorn, PID 836, started prior to journey router).
   - Port 3000: Occupied by pre-existing background process (dart/shelf, PID 3272).
   - Shared ports were preserved without interference per safety rules.
2. **Isolated Task Runtime**:
   - Discovered active local MongoDB 7.0.14 instance on port 27028 (PID 9556).
   - Started isolated FastAPI instance on port 8008 connected to test database `saman_journey_isolated_runtime_db`.
3. **Live End-to-End Execution Evidence**:
   - `POST /api/journey`: Status 201 Created (14-day hybrid journey).
   - `GET /api/wallet/rewards`: Status 200 OK (version `2026.10.experimental_v1`, all items `is_available: false`).
   - `POST /api/wallet/redeem`: Status 400 Bad Request ("Gói đổi thưởng hiện chưa khả dụng").
   - Verified real activity logs: Nutrition meal log + Workout session log created in DB.
   - Complete tasks: Both tasks completed, Day completed.
   - Balance check: 0 SP (confirmed NO auto-crediting on task completion).
   - `POST /api/journey/claim-daily-reward`: Status 200 OK (+20 SP credited, `new_balance: 20`).
   - Idempotent Retry: Status 200 OK (+0 SP credited, `new_balance: 20`, message: "Bạn đã nhận thưởng của ngày hôm nay rồi").
   - Concurrency & Crash Recovery: Verified on real MongoDB 7.0.14 with `asyncio.gather` and receipt detection.
4. **Cleanup**:
   - Test databases `saman_journey_isolated_runtime_db`, `saman_journey_live_e2e_db`, and `saman_journey_test_real_db` dropped cleanly from MongoDB 27028.
   - Isolated background processes (port 8008 PID 16476, port 3008 PID 1656) cleanly terminated. Zero lingering background tasks.

---

## 8. HTTP RUNTIME EXIT CODE 1 ROOT CAUSE & REPAIR EXPLANATION

- **Incident Description**: Trong phiên trước, lệnh inline verification trên cổng 8008 gặp lỗi `Exited with code 1`.
- **Root Cause Analysis**:
  - Tại file `backend/routers/journey.py`, hàm `claim_daily_reward` có hai nhánh trả về đối với trường hợp ngày hôm nay đã được claim:
    1. Nhánh phát hiện sớm (Early return): `if target_day.get("is_daily_reward_claimed"): return {"journey": ..., "message": "Phần thưởng ngày hôm nay đã được nhận"}` -> **THIẾU TRƯỜNG `new_balance`**.
    2. Nhánh xung đột atomic (Race/Retry sau atomic update): trả về `{"journey": ..., "new_balance": ..., "message": ...}` -> Có trường `new_balance`.
  - Khi script kiểm thử thực hiện bước 14 (Idempotent Retry assertion `res["new_balance"] == 20`), Python ném ngoại lệ `KeyError: 'new_balance'`, dẫn tới exit code 1.
- **Fix Applied**:
  - Bổ sung `"new_balance": (users_col.find_one({"email": user_email}) or {}).get("saman_points", 0)` vào nhánh early return tại dòng 453 của `backend/routers/journey.py`.
- **Re-Verification Evidence**:
  - Tạo script độc lập `design/saman-journey/evidence/test_live_http_api_flow.py`.
  - Thực thi toàn bộ 16 bước kiểm thử qua giao thức HTTP thực tế trên backend port 8008 và DB riêng `saman_journey_live_e2e_db`.
  - Kết quả: **16/16 bước PASS (100%)**, exit code 0.
  - Toàn bộ request/response đã được làm sạch secret/token và lưu tại `design/saman-journey/evidence/http_api_flow.log` và `design/saman-journey/evidence/http_api_flow_results.json`.

---

## 9. FRONTEND RUNTIME & VISUAL EVIDENCE AUDIT

- **Isolated Web Server**:
  - Build Flutter Web `frontend/build/web` với `--no-pub`.
  - Phục vụ ứng dụng tại cổng độc lập 3008 (`http://localhost:3008`), không ảnh hưởng cổng 3000 của phiên khác.
- **RenderFlex Layout Bug Fixing**:
  - Trong quá trình kiểm tra màn hình nhỏ (360x640) và render font tiếng Việt, phát hiện các thành phần `Row` trong `frontend/lib/features/journey/presentation/screens/my_journey_screen.dart` bị lỗi `RenderFlex overflowed by ... pixels`.
  - Đã khắc phục triệt để bằng cách:
    1. Bọc tiêu đề header bằng `Expanded`.
    2. Bọc Hero card title và subtitle bằng `Expanded` kèm spacing chuẩn.
    3. Bọc văn bản số ngày hoàn thành bằng `Expanded` kèm `TextOverflow.ellipsis`.
    4. Bọc các nhãn phần thưởng bằng `Expanded`.
    5. Bọc các tiêu đề nhiệm vụ bằng `Expanded`.
    6. Chuyển legend hàng ngang cố định của ma trận lịch sang `Wrap(spacing: 12, runSpacing: 8, children: ...)`.
    7. Bọc văn bản dòng truy cập Ví bằng `Expanded` và `Flexible`.
- **Visual Evidence Screenshots**:
  - Đã xuất 6 file ảnh độ phân giải cao tại `design/saman-journey/evidence/screenshots/`:
    1. `saman_screen_1_t_o_h_nh_tr_nh.png`: Màn hình Tạo Hành Trình (theme Obsidian `#0C0D0E`, 3 tùy chọn Focus, Segmented 7/14/30 ngày với mặc định 14 ngày, Reminder time picker, CTA nổi "Bắt đầu hành trình", hành động "Để sau").
    2. `saman_screen_2_h_nh_tr_nh_chua_hoan_thanh.png`: Màn hình Hành Trình Khi Chưa Hoàn Thành Nhiệm Vụ (Streak flame 0, hai thẻ nhiệm vụ Dinh dưỡng và Luyện tập dạng hàng trạng thái không có checkbox, nút nhận thưởng ở trạng thái vô hiệu hóa).
    3. `saman_screen_2_h_nh_tr_nh_du_dieu_kien_nhan_thuong.png`: Màn hình Hành Trình Đủ Điều Kiện Nhận Thưởng (Cả hai nhiệm vụ đã hoàn thành từ hoạt động thật, nút CTA nổi màu trắng viền ngọc lục bảo "Nhận 20 điểm" được kích hoạt).
    4. `saman_screen_2_h_nh_tr_nh_da_nhan_thuong.png`: Màn hình Hành Trình Đã Nhận Thưởng (Dòng trạng thái "Đã nhận 20 điểm hôm nay" kèm biểu tượng check, Streak tăng lên 1 ngày).
    5. `saman_screen_3_v_i_m_i_l_t_ai_chua_kha_dung.png`: Màn hình Ví Điểm (Số dư kép 20 Saman Points & 0 Lượt AI, catalog các gói đổi điểm bị mờ kèm nhãn "Sắp có", nút CTA vô hiệu hóa "Các gói đổi sắp ra mắt", danh sách lịch sử biến động số dư).
    6. `saman_screen_small_compact_360x640.png`: Màn hình điện thoại nhỏ (360x640dp) đạt chuẩn 0 lỗi RenderFlex và an toàn viền màn hình (Safe Area).

---

## 10. EVIDENCE ARTIFACT REPOSITORY

Tất cả script, log và ảnh bằng chứng phục vụ nghiệm thu được lưu trữ tại:
`design/saman-journey/evidence/`
- `test_live_http_api_flow.py`: Script kiểm thử API HTTP live (16 bước) độc lập.
- `http_api_flow.log`: Nhật ký chi tiết từng request, response status, headers và payload (đã lọc token/secret).
- `http_api_flow_results.json`: Báo cáo kết quả kiểm thử dạng máy đọc (JSON).
- `generate_evidence_screenshots.dart`: Bộ sinh ảnh kiểm chứng giao diện Flutter tự động.
- `screenshots/`: Thư mục chứa 6 ảnh nghiệm thu giao diện đạt chuẩn Stitch.
