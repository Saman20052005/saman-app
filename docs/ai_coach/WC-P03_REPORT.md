# BÁO CÁO TRIỂN KHAI: WC-P03
## XỬ LÝ XUNG ĐỘT PHIÊN TẬP (ACTIVE SESSION CONFLICT RESOLUTION)

- **Thời gian lập**: 2026-11-04 16:05 +07:00
- **Workspace**: `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840`
- **Branch / HEAD**: `agent/nutrition-active-localhost-f02` / `10be1ab1971214acd2487ef893df3fcc80212fc9`
- **Nhiệm vụ**: Kiểm tra và giải quyết an toàn trường hợp người dùng khởi động buổi tập mới từ AI Chat khi đang có một buổi tập khác đang diễn ra dở dang (Active Session Conflict).

---

## 1. Cơ chế Kiểm tra State & Hủy Session từ Provider

Đã đọc và khảo sát file [`frontend/lib/presentation/providers/active_workout_providers.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/presentation/providers/active_workout_providers.dart) và [`active_workout_state.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/presentation/providers/active_workout_state.dart):

### 1.1. Biến & Điều kiện xác định Session đang diễn ra
- **Provider**: `activeWorkoutSessionProvider` (kiểu `ActiveWorkoutSessionState`).
- **Điều kiện kiểm tra**:
  ```dart
  final session = ref.read(activeWorkoutSessionProvider);
  final bool hasActiveSession = !session.isFinished &&
      (session.elapsedSeconds > 0 || session.completedSetsCount > 0);
  ```
  - `session.isFinished == false`: Buổi tập chưa được lưu hoặc kết thúc.
  - `session.elapsedSeconds > 0`: Đồng hồ tập luyện thực tế đã bắt đầu đếm.
  - `session.completedSetsCount > 0`: Đã có ít nhất một set tập được ghi nhận kết quả.

### 1.2. Hàm Hủy / Kết thúc Session cũ an toàn
- **Provider Notifier**: `ref.read(activeWorkoutSessionProvider.notifier)`.
- **Hàm thực thi**:
  - `clearPendingSave()`: Xóa sạch dữ liệu pending snapshot đang chờ lưu.
  - `markSaved()`: Đặt trạng thái `isFinished = true, isPaused = true` để đóng phiên tập hiện tại.
  - Khi phiên tập mới khởi tạo: `ActiveWorkoutScreen.fromExercises` gọi `startSession(exercises, title: ...)` tạo `sessionId` mới, gán `startedAt = DateTime.now()` và reset toàn bộ state cho buổi tập mới.

---

## 2. Luồng Xử lý Xung đột trên Giao diện (`frontend/lib/screens/chat_screen.dart`)

Trong phương thức `_showWorkoutPreviewModal`, sự kiện bấm nút **"Bắt đầu tập ngay"** được ủy quyền cho hàm điều phối `_startWorkoutSession(modalContext, exercises)`:

1. **Trường hợp 1: Không có buổi tập nào đang diễn ra (`hasActiveSession == false`)**:
   - Đóng Modal xem trước: `Navigator.of(modalContext).pop()`.
   - Điều hướng trực tiếp sang màn hình tập luyện:
     ```dart
     Navigator.of(context).push(
       MaterialPageRoute(
         builder: (_) => ActiveWorkoutScreen.fromExercises(
           exercises: exercises,
           title: 'AI Recommended Workout',
         ),
       ),
     );
     ```

2. **Trường hợp 2: Có buổi tập dang dở (`hasActiveSession == true`)**:
   - Giữ nguyên Modal xem trước, hiển thị `AlertDialog` cảnh báo:
     - **Tiêu đề**: *Buổi tập đang diễn ra*
     - **Nội dung**: *"Bạn đang có một buổi tập dang dở. Bắt đầu buổi tập mới sẽ kết thúc buổi tập hiện tại. Bạn có chắc chắn muốn tiếp tục?"*
     - **Nút "Hủy"**: Đóng Dialog với giá trị `false`, giữ nguyên phiên tập cũ đang chạy, không chuyển trang.
     - **Nút "Đồng ý"**:
       - Đóng Dialog với giá trị `true`.
       - Hủy phiên tập cũ:
         ```dart
         ref.read(activeWorkoutSessionProvider.notifier).clearPendingSave();
         ref.read(activeWorkoutSessionProvider.notifier).markSaved();
         ```
       - Đóng Modal xem trước.
       - Khởi động và điều hướng sang `ActiveWorkoutScreen.fromExercises` với danh sách bài tập mới từ Chat.

---

## 3. Kết quả Kiểm tra & Bằng chứng (Verification & Evidence)

### Phân tích tĩnh Flutter (`flutter analyze`)
```bash
cd frontend
flutter analyze lib/screens/chat_screen.dart lib/screens/chat/
```
**Kết quả**:
```text
Analyzing 2 items...
No issues found! (ran in 3.5s)
```
- **0 errors**, **0 warnings**, **0 infos**.
- File [`chat_screen.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/screens/chat_screen.dart) hoàn toàn tương thích và không có lỗi biên dịch.

---

## 4. Acceptance Checklist

| Tiêu chuẩn Nghiệm thu | Trạng thái | Ghi chú |
|---|---|---|
| **Đọc đúng state của Active Session từ Provider** | **PASS** | Sử dụng `activeWorkoutSessionProvider` với các cờ `!isFinished`, `elapsedSeconds > 0`, `completedSetsCount > 0` |
| **Hiển thị Dialog cảnh báo nếu có xung đột** | **PASS** | Hiển thị `AlertDialog` chuẩn style Obsidian với thông báo rõ ràng khi phát hiện buổi tập dang dở |
| **Hủy an toàn session cũ nếu người dùng đồng ý** | **PASS** | Gọi `clearPendingSave()` và `markSaved()`, dọn dẹp state trước khi push session mới |
| **flutter analyze không báo lỗi** | **PASS** | `No issues found!` trên toàn bộ file thay đổi |

---

## 5. Handoff & Tuân thủ Quy tắc Dự án
- **Phạm vi file sửa**: Duy nhất file [frontend/lib/screens/chat_screen.dart](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/screens/chat_screen.dart) và tạo tài liệu [docs/ai_coach/WC-P03_REPORT.md](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/docs/ai_coach/WC-P03_REPORT.md).
- **Git Safety**: Bảo toàn 267 mục WIP chưa commit của người dùng; không tự ý commit, push hay merge nhánh.

