# PHẠM VI CHECKPOINT JCOM-05-03 (JCOM-05-03 SCOPE DEFINITION)

## 1. Mục Tiêu Checkpoint
Triển khai API đọc Community và kết nối frontend trên môi trường local/test độc lập:
- Feed R03 (`GET /api/community/feed`).
- Post Detail R05 (`GET /api/community/posts/{post_id}`).
- Question Detail R15 (`GET /api/community/questions/{question_id}/answers` & `GET /api/community/posts/{post_id}/answers`).
- Thực thi chính sách Audience Enforcement nghiêm ngặt (kiểm soát quyền xem phía máy chủ theo danh tính canonical; fail-closed đối với private, deleted, unpublished và quan hệ followers chưa định nghĩa).
- Kết nối frontend qua Riverpod DI (`useRemoteCommunityProvider`).
- Không thực hiện fake mutation trên bài viết remote; hiển thị thông báo giới hạn rõ ràng đối với thao tác chưa có backend.
- Nghiệm thu tự động Playwright trên ứng dụng web chính (release build với `--dart-define=USE_REMOTE_COMMUNITY=true`).

---

## 2. Danh Sách Tệp Được Phép Tạo / Sửa (Allowed Paths)

### A. Backend
1. `backend/app/models/community.py` (Mới: Pydantic request/response models cho Community Read API)
2. `backend/routers/community.py` (Mới: FastAPI router cho Community Feed, Post Detail, Question Answers)
3. `backend/routers/__init__.py` (Sửa: Export `community_router`)
4. `backend/main.py` (Sửa: Đăng ký `community_router`)
5. `backend/tests/test_community_read_api.py` (Mới: Unit & contract test suite cho Community Read & Audience Enforcement)

### B. Frontend
1. `frontend/lib/features/community/data/datasources/community_remote_datasource.dart` (Mới: Remote datasource qua Dio)
2. `frontend/lib/features/community/data/repositories/community_repository_impl.dart` (Sửa: Tích hợp Remote datasource và xử lý unsupported mutations)
3. `frontend/lib/features/community/presentation/providers/community_providers.dart` (Sửa: Khai báo `useRemoteCommunityProvider`, remote DI wiring, error/retry handling)
4. `frontend/lib/features/community/presentation/screens/community_feed_screen.dart` (Sửa: QA card navigation to R15, remote error/retry, unsupported action feedback)
5. `frontend/lib/features/community/presentation/screens/community_post_detail_screen.dart` (Sửa: Remote error/retry, 404 handling, unsupported action feedback)
6. `frontend/lib/features/community/presentation/screens/qa/community_question_detail_screen.dart` (Sửa: Remote error/retry, 404 handling, unsupported action feedback)
7. `frontend/test/features/community/community_remote_read_test.dart` (Mới: Unit & widget tests cho Community Remote Read & Audience)
8. `frontend/test/features/community/*` (Sửa: Cập nhật các assertion liên quan nếu cần)

### C. Tài liệu & Nghiệm thu
1. `docs/jcom0503_community_remote_read_acceptance/JCOM0503_SCOPE.md` (Mới: Tài liệu ranh giới phạm vi)
2. `docs/jcom0503_community_remote_read_acceptance/JCOM0503_REPORT.md` (Mới: Báo cáo nghiệm thu hoàn tất)
3. `docs/jcom0503_community_remote_read_acceptance/screenshots/*` (Mới: Bằng chứng runtime screenshots)
4. `runtime_evidence/jcom0503_community_remote/*` (Mới: Script crawl và dữ liệu nghiệm thu)
5. `docs/CONTINUOUS_RUN_STATUS.md` (Cập nhật tiến độ)

---

## 3. Ranh Giới Nghiêm Ngặt (Prohibited Scope)
- KHÔNG sửa logic hoặc mã nguồn Auth (`backend/routers/auth.py`, `backend/routers/user.py`, trừ khi đọc `get_current_user`).
- KHÔNG sửa logic gốc hoặc catalog của Workout/Nutrition.
- KHÔNG triển khai mutations (publish bài viết, upload media, like, save, follow, comment, answer upvote, draft persistence).
- KHÔNG deploy remote (HuggingFace) hoặc sửa đổi file ngoài phạm vi.
- KHÔNG commit, push hoặc merge vào git repository.

