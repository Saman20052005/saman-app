import copy
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Dict, Any
import unittest
from unittest.mock import patch, MagicMock
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.auth_utils import get_current_user
import backend.routers.chat as chat_module


class _InsertResult:
    def __init__(self, obj_id):
        self.inserted_id = obj_id

class _UpdateResult:
    matched_count = 1
    modified_count = 1

class MemoryWorkoutCollection:
    def __init__(self):
        self.documents: List[dict] = []
        self.simulate_error = False

    def insert_one(self, document: dict):
        stored = copy.deepcopy(document)
        if "_id" not in stored:
            stored["_id"] = ObjectId()
        self.documents.append(stored)
        return _InsertResult(stored["_id"])

    def find_one(self, query: dict) -> Optional[dict]:
        res = self.find(query)
        return res[0] if res else None

    def update_one(self, query: dict, update: dict):
        return _UpdateResult()

    def find(self, query: dict):
        if self.simulate_error:
            raise RuntimeError("Database connection failure in find()")

        def _match(doc):
            for k, v in query.items():
                if k == "$and":
                    if not all(self._match_subquery(doc, item) for item in v):
                        return False
                elif k == "$or":
                    if not any(self._match_subquery(doc, item) for item in v):
                        return False
                else:
                    if doc.get(k) != v:
                        return False
            return True

        results = [copy.deepcopy(doc) for doc in self.documents if _match(doc)]
        return results

    def _match_subquery(self, doc, sub):
        for k, v in sub.items():
            if doc.get(k) != v:
                return False
        return True


class MemoryExercisesCollection:
    def __init__(self):
        self.documents: List[dict] = []

    def insert_one(self, doc: dict):
        stored = copy.deepcopy(doc)
        if "_id" not in stored:
            stored["_id"] = ObjectId()
        self.documents.append(stored)
        return stored

    def find_one(self, query: dict) -> Optional[dict]:
        for doc in self.documents:
            match = True
            for k, v in query.items():
                if doc.get(k) != v:
                    match = False
                    break
            if match:
                return copy.deepcopy(doc)
        return None


class TestChatWorkoutGrounding(unittest.TestCase):
    def setUp(self):
        self.orig_workout_col = chat_module.workout_history_collection
        self.orig_exercises_col = chat_module.exercises_collection
        self.orig_conversations_col = getattr(chat_module, "conversations_col", None)

        self.memory_workout_col = MemoryWorkoutCollection()
        self.memory_exercises_col = MemoryExercisesCollection()
        self.memory_conversations_col = MemoryWorkoutCollection()

        chat_module.workout_history_collection = self.memory_workout_col
        chat_module.exercises_collection = self.memory_exercises_col
        chat_module.conversations_col = self.memory_conversations_col

        self.app = FastAPI()
        self.app.include_router(chat_module.router)

        self.user_a = {
            "_id": ObjectId("650000000000000000000001"),
            "email": "user_a@saman.test",
            "full_name": "Nguyen Van A",
            "profile": {"weight": 70, "goal": "tang co"},
            "health_stats": {"tdee": 2200},
        }
        self.user_b = {
            "_id": ObjectId("650000000000000000000002"),
            "email": "user_b@saman.test",
            "full_name": "Tran Van B",
            "profile": {"weight": 65, "goal": "giam mo"},
            "health_stats": {"tdee": 1900},
        }

        self.active_user = self.user_a
        self.app.dependency_overrides[get_current_user] = lambda: self.active_user
        self.client = TestClient(self.app)

        self.captured_prompts: List[str] = []

    def tearDown(self):
        chat_module.workout_history_collection = self.orig_workout_col
        chat_module.exercises_collection = self.orig_exercises_col
        chat_module.conversations_col = self.orig_conversations_col
        self.app.dependency_overrides.clear()

    def _mock_ai_reply(self, prompt: str) -> str:
        self.captured_prompts.append(prompt)
        return "Chào bạn! Đây là câu trả lời thử nghiệm từ AI."

    # 1. Test ngày cụ thể khác hôm nay
    def test_specific_date_query_grounding(self):
        self.active_user = self.user_a

        # Buổi tập ngày 12/10/2026 tại Việt Nam
        # 12/10/2026 09:00 VN = 02:00 UTC
        start_utc = datetime(2026, 10, 12, 2, 0, 0, tzinfo=timezone.utc)
        finish_utc = datetime(2026, 10, 12, 2, 45, 0, tzinfo=timezone.utc)

        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "email": self.user_a["email"],
            "plan_name": "Lưng và Bắp Tay",
            "started_at": start_utc,
            "finished_at": finish_utc,
            "date": "2026-10-12",
            "total_duration_minutes": 45,
            "total_volume_kg": 350,
            "exercise_logs": [
                {
                    "exercise_slug": "pull-up",
                    "exercise_id": "pull-up",
                    "set_number": 1,
                    "reps_completed": 10,
                    "unit": "reps",
                    "weight_kg": 0.0,
                    "is_completed": True,
                },
                {
                    "exercise_slug": "pull-up",
                    "exercise_id": "pull-up",
                    "set_number": 2,
                    "reps_completed": 8,
                    "unit": "reps",
                    "weight_kg": 0.0,
                    "is_completed": True,
                },
            ],
        })

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post("/api/chat", json={"message": "Hôm 12/10/2026 tôi đã tập những bài nào?"})
            self.assertEqual(res.status_code, 200)
            body = res.json()
            self.assertEqual(body["status"], "success")
            self.assertTrue(body["retrieval"]["grounded"])
            self.assertEqual(body["retrieval"]["sessions_found"], 1)

            # Kiểm tra exact captured prompt
            self.assertEqual(len(self.captured_prompts), 1)
            prompt = self.captured_prompts[0]

            self.assertIn("12/10/2026", prompt)
            self.assertIn("Lưng và Bắp Tay", prompt)
            self.assertIn("45 phút", prompt)
            self.assertIn("350 kg", prompt)
            # Pull-up tra catalog chuẩn repo
            self.assertIn("Kéo xà (Pull-up)", prompt)
            self.assertIn("10 reps", prompt)
            self.assertIn("mức tạ 0.0 kg", prompt)
            # Không rò rỉ email/user_id nhạy cảm vào prompt
            self.assertNotIn(str(self.user_a["_id"]), prompt)
            self.assertNotIn(self.user_a["email"], prompt)
            # Không có calories ước lượng
            self.assertNotIn("calories", prompt.lower())

    # 2. Test hôm nay
    def test_today_query_grounding(self):
        self.active_user = self.user_a

        now_ict = datetime.now(chat_module.ICT_ZONE)
        today_str = now_ict.strftime("%Y-%m-%d")

        start_utc = datetime.now(timezone.utc) - timedelta(minutes=40)
        finish_utc = datetime.now(timezone.utc)

        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "email": self.user_a["email"],
            "plan_name": "Buổi Tập Hôm Nay",
            "started_at": start_utc,
            "finished_at": finish_utc,
            "date": today_str,
            "total_duration_minutes": 40,
            "total_volume_kg": 150,
            "exercise_logs": [
                {
                    "exercise_slug": "pull-up",
                    "set_number": 1,
                    "reps_completed": 12,
                    "weight_kg": 0.0,
                    "is_completed": True,
                }
            ],
        })

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post("/api/chat", json={"message": "Hôm nay tôi đã tập những bài nào?"})
            self.assertEqual(res.status_code, 200)
            self.assertEqual(res.json()["status"], "success")

            self.assertEqual(len(self.captured_prompts), 1)
            prompt = self.captured_prompts[0]
            self.assertIn("Buổi Tập Hôm Nay", prompt)
            self.assertIn("Kéo xà (Pull-up)", prompt)

    # 3. Test buổi tập gần nhất (sort timestamp giảm dần)
    def test_recent_workout_query(self):
        self.active_user = self.user_a

        # Buổi cũ: 2026-10-09
        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_name": "Buổi Cũ 09/10",
            "started_at": datetime(2026, 10, 9, 8, 0, tzinfo=timezone.utc),
            "finished_at": datetime(2026, 10, 9, 8, 30, tzinfo=timezone.utc),
            "date": "2026-10-09",
            "total_duration_minutes": 30,
            "total_volume_kg": 100,
            "exercise_logs": [],
        })

        # Buổi mới nhất: 2026-10-11
        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_name": "Buổi Gần Nhất 11/10",
            "started_at": datetime(2026, 10, 11, 10, 0, tzinfo=timezone.utc),
            "finished_at": datetime(2026, 10, 11, 10, 50, tzinfo=timezone.utc),
            "date": "2026-10-11",
            "total_duration_minutes": 50,
            "total_volume_kg": 500,
            "exercise_logs": [],
        })

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post("/api/chat", json={"message": "Tóm tắt buổi tập gần nhất của tôi."})
            self.assertEqual(res.status_code, 200)

            self.assertEqual(len(self.captured_prompts), 1)
            prompt = self.captured_prompts[0]
            self.assertIn("Buổi Gần Nhất 11/10", prompt)
            self.assertNotIn("Buổi Cũ 09/10", prompt)

    # 4. Test ngày được hỏi không có session, không lấy ngày khác thay thế
    def test_empty_date_does_not_use_other_day(self):
        self.active_user = self.user_a

        # Chỉ có session ngày 10/10/2026
        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_name": "Buổi Ngày 10",
            "started_at": datetime(2026, 10, 10, 8, 0, tzinfo=timezone.utc),
            "finished_at": datetime(2026, 10, 10, 8, 45, tzinfo=timezone.utc),
            "date": "2026-10-10",
            "total_duration_minutes": 45,
            "total_volume_kg": 200,
            "exercise_logs": [],
        })

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post("/api/chat", json={"message": "Hôm 12/10/2026 tôi đã tập những bài nào?"})
            self.assertEqual(res.status_code, 200)

            self.assertEqual(len(self.captured_prompts), 1)
            prompt = self.captured_prompts[0]

            # Phải nói rõ chưa có dữ liệu hoàn tất cho ngày 12/10/2026
            self.assertIn("Chưa có dữ liệu buổi tập hoàn tất được ghi nhận", prompt)
            self.assertIn("12/10/2026", prompt)
            # Tuyệt đối không lấy buổi ngày 10 để trả lời
            self.assertNotIn("Buổi Ngày 10", prompt)
            # Hướng dẫn AI không kết luận người dùng không tập
            self.assertIn("KHÔNG kết luận là người dùng chưa tập hoặc không tập", prompt)

    # 5. Test owner isolation giữa User A và User B
    def test_owner_isolation(self):
        # Session của User B
        self.memory_workout_col.insert_one({
            "user_id": str(self.user_b["_id"]),
            "plan_name": "Buổi Tập Bí Mật Của User B",
            "started_at": datetime(2026, 10, 12, 10, 0, tzinfo=timezone.utc),
            "finished_at": datetime(2026, 10, 12, 10, 30, tzinfo=timezone.utc),
            "date": "2026-10-12",
            "total_duration_minutes": 30,
            "total_volume_kg": 100,
            "exercise_logs": [],
        })

        # User A gọi chat hỏi ngày 12/10/2026
        self.active_user = self.user_a
        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post("/api/chat", json={"message": "Hôm 12/10/2026 tôi đã tập những bài nào?"})
            self.assertEqual(res.status_code, 200)

            prompt = self.captured_prompts[0]
            self.assertNotIn("Buổi Tập Bí Mật Của User B", prompt)
            self.assertIn("Chưa có dữ liệu buổi tập hoàn tất", prompt)

    # 6. Test session chưa hoàn tất (finished_at = None hoặc timestamp không hợp lệ) bị loại bỏ
    def test_unfinished_session_ignored(self):
        self.active_user = self.user_a

        # Session 1: finished_at là None
        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_name": "Buổi Đang Dở Dang 1",
            "started_at": datetime(2026, 10, 12, 9, 0, tzinfo=timezone.utc),
            "finished_at": None,
            "date": "2026-10-12",
            "total_duration_minutes": 0,
            "exercise_logs": [],
        })

        # Session 2: finished_at là string invalid
        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_name": "Buổi Đang Dở Dang 2",
            "started_at": datetime(2026, 10, 12, 10, 0, tzinfo=timezone.utc),
            "finished_at": "not_a_valid_timestamp",
            "date": "2026-10-12",
            "total_duration_minutes": 0,
            "exercise_logs": [],
        })

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post("/api/chat", json={"message": "Hôm 12/10/2026 tôi đã tập những bài nào?"})
            self.assertEqual(res.status_code, 200)

            prompt = self.captured_prompts[0]
            self.assertNotIn("Buổi Đang Dở Dang 1", prompt)
            self.assertNotIn("Buổi Đang Dở Dang 2", prompt)
            self.assertIn("Chưa có dữ liệu buổi tập hoàn tất", prompt)

    # 7. Test metrics: duration 0 phút hiển thị <1 phút, phân biệt với None; weight 0.0 kg hiển thị rõ
    def test_metrics_zero_and_null_preserved(self):
        self.active_user = self.user_a

        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_name": "Buổi Test Metrics 0",
            "started_at": datetime(2026, 10, 12, 9, 0, tzinfo=timezone.utc),
            "finished_at": datetime(2026, 10, 12, 9, 0, 30, tzinfo=timezone.utc),
            "date": "2026-10-12",
            "total_duration_minutes": 0,  # Hợp lệ, <1 phút
            "total_volume_kg": 0,         # Hợp lệ, 0 kg
            "exercise_logs": [
                {
                    "exercise_slug": "pull-up",
                    "set_number": 1,
                    "seconds_completed": 45,
                    "unit": "seconds",
                    "weight_kg": 0.0,
                    "is_completed": True,
                }
            ],
        })

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post("/api/chat", json={"message": "Hôm 12/10/2026 tôi đã tập những bài nào?"})
            self.assertEqual(res.status_code, 200)

            prompt = self.captured_prompts[0]
            self.assertIn("0 phút (<1 phút)", prompt)
            self.assertIn("0 kg", prompt)
            self.assertIn("45 giây", prompt)
            self.assertIn("mức tạ 0.0 kg", prompt)

        # Trường hợp thứ hai: duration và volume là None (chưa ghi nhận)
        self.memory_workout_col.documents.clear()
        self.captured_prompts.clear()

        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_name": "Buổi Test Metrics Null",
            "started_at": datetime(2026, 10, 12, 9, 0, tzinfo=timezone.utc),
            "finished_at": datetime(2026, 10, 12, 9, 30, tzinfo=timezone.utc),
            "date": "2026-10-12",
            "total_duration_minutes": None,
            "total_volume_kg": None,
            "exercise_logs": [
                {
                    "exercise_slug": "pull-up",
                    "set_number": 1,
                    "reps_completed": 8,
                    "weight_kg": None,
                    "is_completed": True,
                }
            ],
        })

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post("/api/chat", json={"message": "Hôm 12/10/2026 tôi đã tập những bài nào?"})
            self.assertEqual(res.status_code, 200)

            prompt = self.captured_prompts[0]
            self.assertIn("Chưa ghi nhận thời lượng", prompt)
            self.assertIn("Tổng khối lượng tạ (volume): Chưa ghi nhận", prompt)
            self.assertIn("mức tạ: chưa ghi nhận", prompt)

    # 8. Test tên bài chưa resolve trong catalog: không bịa, không titlecase
    def test_unresolved_exercise_name_not_fabricated(self):
        self.active_user = self.user_a

        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_name": "Buổi Bài Lạ",
            "started_at": datetime(2026, 10, 12, 9, 0, tzinfo=timezone.utc),
            "finished_at": datetime(2026, 10, 12, 9, 30, tzinfo=timezone.utc),
            "date": "2026-10-12",
            "total_duration_minutes": 30,
            "total_volume_kg": 50,
            "exercise_logs": [
                {
                    "exercise_slug": "custom-unknown-movement-123",
                    "set_number": 1,
                    "reps_completed": 10,
                    "weight_kg": 5.0,
                    "is_completed": True,
                }
            ],
        })

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post("/api/chat", json={"message": "Hôm 12/10/2026 tôi đã tập những bài nào?"})
            self.assertEqual(res.status_code, 200)

            prompt = self.captured_prompts[0]
            # Giữ nguyên slug và ghi rõ chưa xác định
            self.assertIn("custom-unknown-movement-123 (tên chưa xác định)", prompt)
            self.assertIn("chưa xác định trong catalog chuẩn", prompt)
            # Tuyệt đối không tự titlecase
            self.assertNotIn("Custom Unknown Movement 123", prompt)

    # 9. Test tra catalog DB ưu tiên (exercises_collection)
    def test_db_catalog_exercise_resolution(self):
        self.active_user = self.user_a

        self.memory_exercises_col.insert_one({
            "slug": "seated-cable-row",
            "name": "Seated Cable Row",
            "nameVi": "Kéo cáp ngồi",
        })

        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_name": "Buổi Kéo Cáp",
            "started_at": datetime(2026, 10, 12, 9, 0, tzinfo=timezone.utc),
            "finished_at": datetime(2026, 10, 12, 9, 30, tzinfo=timezone.utc),
            "date": "2026-10-12",
            "total_duration_minutes": 30,
            "total_volume_kg": 100,
            "exercise_logs": [
                {
                    "exercise_slug": "seated-cable-row",
                    "set_number": 1,
                    "reps_completed": 12,
                    "weight_kg": 40.0,
                    "is_completed": True,
                }
            ],
        })

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post("/api/chat", json={"message": "Hôm 12/10/2026 tôi đã tập những bài nào?"})
            self.assertEqual(res.status_code, 200)

            prompt = self.captured_prompts[0]
            self.assertIn("Kéo cáp ngồi (Seated Cable Row)", prompt)
            self.assertIn("catalog DB (exercises_collection)", prompt)

    # 10. Test DB error không bị biến thành "không có dữ liệu"
    def test_db_error_not_reported_as_empty(self):
        self.active_user = self.user_a
        self.memory_workout_col.simulate_error = True

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post("/api/chat", json={"message": "Hôm 12/10/2026 tôi đã tập những bài nào?"})
            self.assertEqual(res.status_code, 200)

            body = res.json()
            self.assertEqual(body["status"], "error")
            # Reply phải báo lỗi hệ thống/DB, không được bảo "Chưa có dữ liệu"
            self.assertIn("Lỗi hệ thống", body["reply"])
            self.assertNotIn("Chưa có dữ liệu buổi tập hoàn tất", body["reply"])
            # Provider không được gọi khi có lỗi DB trước đó
            self.assertEqual(len(self.captured_prompts), 0)

    # 11. Test client context giả không ghi đè DB truth
    def test_fake_client_context_ignored(self):
        self.active_user = self.user_a

        # Session thật của user A
        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_name": "Buổi Thật Của User A",
            "started_at": datetime(2026, 10, 12, 9, 0, tzinfo=timezone.utc),
            "finished_at": datetime(2026, 10, 12, 9, 30, tzinfo=timezone.utc),
            "date": "2026-10-12",
            "total_duration_minutes": 30,
            "total_volume_kg": 100,
            "exercise_logs": [],
        })

        fake_client_context = {
            "user_id": "malicious_spoofed_user",
            "plan_name": "Buổi Giả Mạo Từ Client Context",
            "date": "2026-10-12",
        }

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            res = self.client.post(
                "/api/chat",
                json={
                    "message": "Hôm 12/10/2026 tôi đã tập những bài nào?",
                    "context": fake_client_context,
                }
            )
            self.assertEqual(res.status_code, 200)

            prompt = self.captured_prompts[0]
            self.assertIn("Buổi Thật Của User A", prompt)
            self.assertNotIn("Buổi Giả Mạo Từ Client Context", prompt)

    # 12. Test ngày sai hoặc mơ hồ không tự ý chuyển thành hôm nay
    def test_invalid_date_not_silently_converted_to_today(self):
        self.active_user = self.user_a

        # Có session hôm nay
        now_ict = datetime.now(chat_module.ICT_ZONE)
        today_str = now_ict.strftime("%Y-%m-%d")
        self.memory_workout_col.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_name": "Buổi Tập Hôm Nay",
            "started_at": datetime.now(timezone.utc) - timedelta(minutes=30),
            "finished_at": datetime.now(timezone.utc),
            "date": today_str,
            "total_duration_minutes": 30,
            "exercise_logs": [],
        })

        with patch.object(chat_module, "get_ai_reply", side_effect=self._mock_ai_reply):
            # 31/02/2026 là ngày không có trên lịch
            res = self.client.post("/api/chat", json={"message": "Hôm 31/02/2026 tôi đã tập những bài nào?"})
            self.assertEqual(res.status_code, 200)

            prompt = self.captured_prompts[0]
            self.assertIn("Ngày 31/02/2026 không hợp lệ", prompt)
            self.assertIn("Tuyệt đối không tự ý đoán ngày sang hôm nay", prompt)
            # Tuyệt đối không trả về buổi của hôm nay
            self.assertNotIn("Buổi Tập Hôm Nay", prompt)

    # 13. Test provider error không được đánh dấu grounded=True
    def test_provider_error_does_not_set_grounded_true(self):
        self.active_user = self.user_a

        with patch.object(chat_module, "get_ai_reply", return_value="Lỗi: Model AI không khả dụng"):
            res = self.client.post("/api/chat", json={"message": "Tóm tắt buổi tập gần nhất của tôi."})
            self.assertEqual(res.status_code, 200)

            body = res.json()
            self.assertEqual(body["status"], "error")
            self.assertIn("retrieval", body)
            self.assertFalse(body["retrieval"]["grounded"])


if __name__ == "__main__":
    unittest.main()
