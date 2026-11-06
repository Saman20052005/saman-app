# JCOM-05-02 SCOPE — JOURNAL REMOTE READ & COMMUNITY ENTRY

- **Dự án:** Saman App — Phân hệ Journal & Community
- **Checkpoint:** JCOM-05-02
- **Thời gian lập:** 02/11/2026 07:25:00 +07:00

---

## 1. Mục Tiêu Checkpoint

1. **Khép đường vào Community từ Journal**:
   - Nhấn `JournalCommunityDoorwayCard` trên R01 sẽ trực tiếp điều hướng sang `AppRoutes.communityFeed` (R03).
   - Thao tác Back từ R03 trở về R01; Back từ R01 trở về Home.
   - Kiểm soát double-tap và back stack an toàn.
   - Community vẫn giữ nguyên Fake Repository với nhãn preview minh bạch.
2. **Triển khai Journal Read-Only Public API**:
   - `GET /api/journal/featured`: Trả về bài viết tiêu điểm.
   - `GET /api/journal/topics`: Trả về danh sách chủ đề khoa học.
   - `GET /api/journal/articles`: Trả về danh sách bài viết phân trang theo topic.
   - `GET /api/journal/articles/{article_id}`: Trả về chi tiết bài viết.
   - `GET /api/journal/search`: Tìm kiếm hợp nhất qua 4 nhóm thực thể: Bài viết (`journal_articles`), Bài tập (`exercises_collection`), Thực phẩm (`foods_collection`), Công thức (`recipes_collection`).
   - Tái sử dụng nguồn catalog Workout & Nutrition hiện hữu; không sao chép catalog; không coi thực phẩm là công thức nếu source không có recipe contract.
3. **Nối Frontend qua Remote Repository**:
   - Xây dựng `JournalRemoteDatasource` và cập nhật `JournalRepositoryImpl` hỗ trợ chế độ Remote.
   - Điều khiển chế độ Fake vs Remote chủ động qua Riverpod DI.
   - Xử lý lỗi trung thực: Khi remote thất bại, hiển thị lỗi và nút Retry trên UI, giữ nguyên query/filter, KHÔNG fallback ngầm sang dữ liệu fake.
4. **Kiểm chứng Độc Lập**:
   - Backend & Database test riêng biệt trên port 18090 / 27035.
   - Kiểm chứng luồng app chính từ Login -> Home -> R01 -> R02 -> Doorway -> R03 -> Back.
   - Kiểm chứng kịch bản lỗi có kiểm soát và phục hồi bằng Retry.

---

## 2. Danh Mục Tập Tin Được Phép Tạo / Chỉnh Sửa

| STT | Đường dẫn tập tin | Thao tác | Mục đích kỹ thuật |
| :---: | :--- | :---: | :--- |
| 1 | `backend/app/models/journal.py` | Tạo mới | Pydantic models cho Journal API (Article, Search, Topic, Advice) |
| 2 | `backend/routers/journal.py` | Tạo mới | FastAPI router `/api/journal` phục vụ read-only public queries |
| 3 | `backend/routers/__init__.py` | Sửa đổi | Export `journal_router` theo convention an toàn |
| 4 | `backend/main.py` | Sửa đổi | Đăng ký `journal_router` vào FastAPI application |
| 5 | `backend/tests/test_journal_api.py` | Tạo mới | Unit/contract tests toàn diện cho Journal API |
| 6 | `frontend/lib/features/journal/data/datasources/journal_remote_datasource.dart` | Tạo mới | Remote datasource đọc API backend qua Dio |
| 7 | `frontend/lib/features/journal/data/repositories/journal_repository_impl.dart` | Sửa đổi | Hỗ trợ RemoteDatasource, xử lý lỗi trung thực |
| 8 | `frontend/lib/features/journal/presentation/providers/journal_providers.dart` | Sửa đổi | Cấu hình DI linh hoạt giữa Fake và Remote |
| 9 | `frontend/lib/features/journal/presentation/widgets/journal_community_doorway_card.dart` | Sửa đổi | Điều hướng sang `AppRoutes.communityFeed` với throttle |
| 10 | `frontend/test/features/journal/journal_remote_and_doorway_test.dart` | Tạo mới | Test remote mapping, honest error, doorway navigation |
| 11 | `docs/jcom0502_journal_remote_acceptance/JCOM0502_SCOPE.md` | Tạo mới | Hồ sơ phạm vi checkpoint |
| 12 | `docs/jcom0502_journal_remote_acceptance/JCOM0502_REPORT.md` | Tạo mới | Báo cáo nghiệm thu hoàn chỉnh |
| 13 | `docs/CONTINUOUS_RUN_STATUS.md` | Sửa đổi | Cập nhật tiến độ dự án |

---

## 3. Các Tập Tin và Vùng Cấm Tuyệt Đối (Strictly Forbidden)

- `backend/routers/user.py`, `backend/routers/auth.py`, `backend/auth_utils.py`: Không can thiệp auth/user profile.
- `backend/routers/workout.py`, `backend/routers/nutrition.py`: Không sửa đổi logic gốc của Workout/Nutrition.
- `frontend/lib/features/community/*` (ngoại trừ nhận navigation từ Journal): Không sửa logic nghiệp vụ Community.
- `AGENTS.md`, dependencies (`pubspec.yaml`, `requirements.txt`).
- Không deploy remote, không can thiệp database production/live dùng chung.
