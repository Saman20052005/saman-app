"""
End-to-End (E2E) Real MongoDB Smoke Test for Saman Backend (CP0 -> CP4).
Connects directly to real MongoDB (NO mock DB / NO mongomock) via FastAPI TestClient.
"""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import secrets
import socket
import sys
import uuid

_repo_root = str(Path(__file__).resolve().parents[2])
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

from bson import ObjectId
from pymongo import MongoClient
from pymongo.database import Database


def _resolve_real_mongo_uri() -> str:
    """Resolve active real MongoDB URI from environment or local mongod ports."""
    env_uri = os.environ.get("MONGO_URI") or os.environ.get("MONGODB_URI")
    if env_uri:
        try:
            c = MongoClient(env_uri, serverSelectionTimeoutMS=1500)
            c.admin.command("ping")
            c.close()
            return env_uri
        except Exception:
            pass
    for port in (27017, 27028):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1.0):
                return f"mongodb://127.0.0.1:{port}"
        except OSError:
            continue
    return "mongodb://127.0.0.1:27017"


def _bind_real_db_to_modules(db: Database, mongo_uri: str, db_name: str):
    """Ensure all backend modules and routers point to real PyMongo collections (even after unit test mocks)."""
    import backend.app.database as app_db_mod

    sys.modules["backend.app.database"] = app_db_mod
    try:
        import backend.app
        backend.app.database = app_db_mod
    except Exception:
        pass

    app_db_mod.MONGO_URI = mongo_uri
    app_db_mod.DB_NAME = db_name
    app_db_mod.db = db
    app_db_mod.users_collection = db["users"]
    app_db_mod.foods_collection = db["foods"]
    app_db_mod.nutrition_collection = db["nutrition_plans"]
    app_db_mod.story_logs_collection = db["story_logs"]
    app_db_mod.workout_history_collection = db["workout_history"]
    app_db_mod.custom_plans_collection = db["custom_plans"]
    app_db_mod.recipes_collection = db["recipes"]
    app_db_mod.water_collection = db["water_logs"]
    app_db_mod.supplements_collection = db["supplement_logs"]
    app_db_mod.user_foods_collection = db["user_foods"]
    app_db_mod.exercises_collection = db["exercises"]
    app_db_mod.conversations_collection = db["conversations"]
    app_db_mod.messages_collection = db["messages"]
    app_db_mod.weight_history_collection = db["weight_history"]
    app_db_mod.journeys_collection = db["journeys"]
    app_db_mod.community_posts_collection = db["community_posts"]
    app_db_mod.community_interactions_collection = db["community_interactions"]
    app_db_mod.community_follows_collection = db["community_follows"]
    app_db_mod.shop_products_collection = db["shop_products"]
    app_db_mod.journal_articles_collection = db["journal_articles"]
    app_db_mod.chat_training_logs_collection = db["chat_training_logs"]
    app_db_mod.get_db = lambda: db
    app_db_mod.get_users_collection = lambda: db["users"]

    import backend.auth_utils as auth_utils_mod
    auth_utils_mod.users_collection = db["users"]

    import backend.routers.auth as auth_router_mod
    auth_router_mod.users_collection = db["users"]
    auth_router_mod.db = db
    auth_router_mod.otp_collection = db["otps"]

    import backend.routers.user as user_router_mod
    user_router_mod.weight_history_collection = db["weight_history"]
    if hasattr(user_router_mod, "user_repo") and user_router_mod.user_repo is not None:
        user_router_mod.user_repo.collection = db["users"]

    import backend.routers.workout as workout_router_mod
    workout_router_mod.workout_history_collection = db["workout_history"]
    workout_router_mod.custom_plans_collection = db["custom_plans"]
    workout_router_mod.exercises_collection = db["exercises"]

    import backend.routers.nutrition as nutrition_router_mod
    nutrition_router_mod._db_module = app_db_mod
    nutrition_router_mod.db = db
    nutrition_router_mod.nutrition_collection = db["nutrition_plans"]
    nutrition_router_mod.story_logs_collection = db["story_logs"]
    nutrition_router_mod.foods_collection = db["foods"]
    nutrition_router_mod.water_collection = db["water_logs"]
    nutrition_router_mod.workout_history_collection = db["workout_history"]
    nutrition_router_mod.user_foods_collection = db["user_foods"]
    nutrition_router_mod.supplements_collection = db["supplement_logs"]
    nutrition_router_mod.recipes_collection = db["recipes"]

    import backend.routers.journey as journey_router_mod
    journey_router_mod.db = db

    import backend.routers.chat as chat_router_mod
    chat_router_mod._db_mod = app_db_mod
    chat_router_mod.users_collection = db["users"]
    chat_router_mod.users_col = db["users"]
    chat_router_mod.nutrition_collection = db["nutrition_plans"]
    chat_router_mod.nutrition_col = db["nutrition_plans"]
    chat_router_mod.workout_history_collection = db["workout_history"]
    chat_router_mod.workout_history_col = db["workout_history"]
    chat_router_mod.conversations_collection = db["conversations"]
    chat_router_mod.conversations_col = db["conversations"]
    chat_router_mod.messages_collection = db["messages"]
    chat_router_mod.messages_col = db["messages"]
    chat_router_mod.water_collection = db["water_logs"]
    chat_router_mod.water_col = db["water_logs"]
    chat_router_mod.exercises_collection = db["exercises"]
    chat_router_mod.exercises_col = db["exercises"]
    chat_router_mod.custom_plans_collection = db["custom_plans"]
    chat_router_mod.custom_plans_col = db["custom_plans"]

    import backend.routers.analytics as analytics_router_mod
    analytics_router_mod.db = db


def _cleanup_test_user(db: Database, user_id_str: str, email: str) -> None:
    """Remove all documents created for the temporary E2E test user across MongoDB collections."""
    if db is None:
        return
    from backend.app.services.context_utils import build_user_query, normalize_email
    from backend.app.services.training_log_service import hash_user_id

    clean_email = normalize_email(email)
    user_q = build_user_query(user_id_str, clean_email)

    for col_name in (
        "weight_history",
        "workout_history",
        "custom_plans",
        "nutrition_plans",
        "water_logs",
        "supplement_logs",
        "recipes",
        "user_foods",
        "story_logs",
        "day_resets",
        "journeys",
        "conversations",
        "messages",
        "chat_operations",
        "history_analytics_quotes",
        "revenue_entitlement_grants",
    ):
        try:
            db[col_name].delete_many(user_q)
        except Exception:
            pass

    if user_id_str:
        try:
            u_hash = hash_user_id(user_id_str)
            if u_hash:
                db["chat_training_logs"].delete_many({"user_hash": u_hash})
        except Exception:
            pass

    try:
        clauses = [{"email": clean_email}]
        if user_id_str:
            clauses.append({"_id": user_id_str})
            if ObjectId.is_valid(user_id_str):
                clauses.append({"_id": ObjectId(user_id_str)})
        db["users"].delete_many({"$or": clauses})
    except Exception:
        pass


def run_e2e_real_mongo_smoke() -> dict:
    """Execute the full CP0 -> CP4 E2E flow against real MongoDB and return step results."""
    mongo_uri = _resolve_real_mongo_uri()
    db_name = os.environ.get("E2E_DB_NAME", "saman_e2e_real_smoke")
    mongo_client = MongoClient(mongo_uri, serverSelectionTimeoutMS=5000)
    db = mongo_client[db_name]

    assert isinstance(db, Database), f"Expected real pymongo Database, got {type(db)}"
    db.command("ping")

    from fastapi.testclient import TestClient
    from backend.app.services.context_utils import get_vn_date_str
    from backend.app.services.history_analytics_service import ensure_history_analytics_indexes
    from backend.app.services.training_log_service import hash_user_id
    from backend.main import app

    _bind_real_db_to_modules(db, mongo_uri, db_name)
    ensure_history_analytics_indexes(db)

    today_vn = get_vn_date_str()
    unique_tag = uuid.uuid4().hex[:10]
    test_email = f"e2e_cp0_cp4_{unique_tag}@saman.vn"
    test_password = "SamanE2E!Password2026"
    user_id_str = ""
    results = {}

    prev_chat_provider = os.environ.get("CHAT_AI_PROVIDER")
    prev_paywall = os.environ.get("ENABLE_AI_PAYWALL")
    os.environ["CHAT_AI_PROVIDER"] = "fake"
    os.environ["ENABLE_AI_PAYWALL"] = "false"

    app.dependency_overrides.clear()
    client = TestClient(app)

    try:
        # =====================================================================
        # STEP 0: Route & Auth Verification
        # =====================================================================
        r_unauth_weight = client.get("/api/user/weight-history")
        assert r_unauth_weight.status_code == 401, (
            f"Expected 401 on unauth /api/user/weight-history, got {r_unauth_weight.status_code}: {r_unauth_weight.text}"
        )

        r_unauth_journey = client.get("/api/journey/active")
        assert r_unauth_journey.status_code == 401, (
            f"Expected 401 on unauth /api/journey/active, got {r_unauth_journey.status_code}: {r_unauth_journey.text}"
        )

        r_unauth_wishlist = client.get("/api/shop/wishlist")
        assert r_unauth_wishlist.status_code == 401, (
            f"Expected 401 on unauth /api/shop/wishlist, got {r_unauth_wishlist.status_code}: {r_unauth_wishlist.text}"
        )

        r_reg = client.post(
            "/api/auth/register",
            json={
                "email": test_email,
                "password": test_password,
                "full_name": "E2E Real Mongo Tester",
            },
        )
        assert r_reg.status_code == 200, f"Register failed: {r_reg.status_code} {r_reg.text}"

        r_login = client.post(
            "/api/auth/login",
            json={"email": test_email, "password": test_password},
        )
        assert r_login.status_code == 200, f"Login failed: {r_login.status_code} {r_login.text}"
        token = r_login.json().get("access_token")
        assert token, "Missing access_token in login response"
        headers = {"Authorization": f"Bearer {token}"}

        user_doc = db["users"].find_one({"email": test_email})
        assert user_doc is not None, "User document not found in real MongoDB after register"
        user_id_str = str(user_doc["_id"])

        r_journey_auth = client.get("/api/journey/active", headers=headers)
        assert r_journey_auth.status_code == 200, (
            f"Expected 200 on auth /api/journey/active, got {r_journey_auth.status_code}: {r_journey_auth.text}"
        )

        results["step0_auth"] = {
            "unauth_weight_history": r_unauth_weight.status_code,
            "unauth_journey_active": r_unauth_journey.status_code,
            "unauth_shop_wishlist": r_unauth_wishlist.status_code,
            "register": r_reg.status_code,
            "login": r_login.status_code,
            "auth_journey_active": r_journey_auth.status_code,
        }

        # =====================================================================
        # STEP 1: Wishlist & Weight (UTC+7 + Preference Preservation)
        # =====================================================================
        r_prof_put = client.put(
            "/api/user/profile",
            headers=headers,
            json={
                "full_name": "E2E Real Mongo Tester",
                "age": 28,
                "gender": "male",
                "height": 175.0,
                "weight": 72.0,
                "activity_level": "moderate",
                "goal": "gain_muscle",
                "preferences": {
                    "coach_persona": "strict_coach",
                    "reply_style": "concise",
                    "food_dislikes": ["mỡ heo"],
                },
            },
        )
        assert r_prof_put.status_code == 200, f"PUT /api/user/profile failed: {r_prof_put.status_code} {r_prof_put.text}"

        r_wl_get_init = client.get("/api/shop/wishlist", headers=headers)
        assert r_wl_get_init.status_code == 200, f"GET /api/shop/wishlist failed: {r_wl_get_init.status_code}"
        assert r_wl_get_init.json()["saved_product_ids"] == []

        r_wl_put = client.put(
            "/api/shop/wishlist",
            headers=headers,
            json={"saved_product_ids": ["prod_tg_01", "prod_sp_05", "prod_tg_01"]},
        )
        assert r_wl_put.status_code == 200, f"PUT /api/shop/wishlist failed: {r_wl_put.status_code} {r_wl_put.text}"
        assert r_wl_put.json()["saved_product_ids"] == ["prod_tg_01", "prod_sp_05"]

        r_wl_get_after = client.get("/api/shop/wishlist", headers=headers)
        assert r_wl_get_after.status_code == 200
        assert r_wl_get_after.json()["saved_product_ids"] == ["prod_tg_01", "prod_sp_05"]

        db_user_after_wl = db["users"].find_one({"_id": ObjectId(user_id_str)})
        assert db_user_after_wl is not None
        prefs = db_user_after_wl.get("preferences") or {}
        assert prefs.get("saved_product_ids") == ["prod_tg_01", "prod_sp_05"]
        assert prefs.get("coach_persona") == "strict_coach", f"coach_persona was lost! prefs={prefs}"
        assert prefs.get("food_dislikes") == ["mỡ heo"], f"food_dislikes was lost! prefs={prefs}"

        r_weight_post = client.post(
            "/api/user/weight-history",
            headers=headers,
            json={"weight_kg": 72.5},
        )
        assert r_weight_post.status_code == 200, f"POST /api/user/weight-history failed: {r_weight_post.text}"
        assert r_weight_post.json()["date"] == today_vn

        r_weight_get = client.get("/api/user/weight-history?days=30", headers=headers)
        assert r_weight_get.status_code == 200
        weight_entries = r_weight_get.json()["entries"]
        assert len(weight_entries) >= 1
        assert weight_entries[-1]["date"] == today_vn
        assert weight_entries[-1]["weight_kg"] == 72.5

        db_weight_doc = db["weight_history"].find_one({"user_id": user_id_str, "date": today_vn})
        assert db_weight_doc is not None, "weight_history doc missing in MongoDB"
        assert db_weight_doc["weight_kg"] == 72.5
        assert db_weight_doc["user_email"] == test_email

        db_user_after_weight = db["users"].find_one({"_id": ObjectId(user_id_str)})
        assert db_user_after_weight["weight"] == 72.5
        assert db_user_after_weight["profile"]["weight"] == 72.5

        results["step1_wishlist_and_weight"] = {
            "put_profile": r_prof_put.status_code,
            "get_wishlist_init": r_wl_get_init.status_code,
            "put_wishlist": r_wl_put.status_code,
            "get_wishlist_after": r_wl_get_after.status_code,
            "post_weight_history": r_weight_post.status_code,
            "get_weight_history": r_weight_get.status_code,
        }

        # =====================================================================
        # STEP 2: Workout + CV Form Summary + Progressive Overload
        # =====================================================================
        cv_summary = {
            "valid_reps": 10,
            "fast_reps": 1,
            "avg_elbow_angle_deg": 42.5,
            "avg_tempo_sec": 2.1,
        }
        now_iso = datetime.now(timezone.utc).isoformat()
        r_workout_post = client.post(
            "/api/workouts/sessions",
            headers=headers,
            json={
                "planName": "Upper Body Strength",
                "startedAt": now_iso,
                "totalDurationMinutes": 45,
                "totalVolumeKg": 600,
                "calories_burned": 320,
                "exerciseLogs": [
                    {
                        "exerciseId": "ex_lat_pulldown",
                        "exerciseSlug": "lat-pulldown",
                        "setNumber": 1,
                        "repsCompleted": 10,
                        "weightKg": 60.0,
                        "isCompleted": True,
                        "cvDetected": True,
                        "cvFormSummary": cv_summary,
                    }
                ],
                "cvFormSummary": cv_summary,
            },
        )
        assert r_workout_post.status_code == 201, (
            f"POST /api/workouts/sessions failed: {r_workout_post.status_code} {r_workout_post.text}"
        )
        session_id = r_workout_post.json()["session_id"]

        r_last_perf = client.get(
            "/api/workouts/last-performance",
            params={"exercise_ids": "lat-pulldown"},
            headers=headers,
        )
        assert r_last_perf.status_code == 200, f"GET /api/workouts/last-performance failed: {r_last_perf.text}"
        perf_item = r_last_perf.json()["items"].get("lat-pulldown")
        assert perf_item is not None, f"lat-pulldown not found in last-performance: {r_last_perf.json()}"
        assert perf_item["last_weight_kg"] == 60.0
        assert perf_item["last_reps"] == 10
        assert perf_item["suggested_weight_kg"] == 62.5

        r_workout_hist = client.get("/api/workouts/history", headers=headers)
        assert r_workout_hist.status_code == 200
        hist_sessions = r_workout_hist.json()["sessions"]
        assert len(hist_sessions) == 1
        assert hist_sessions[0]["id"] == session_id
        assert hist_sessions[0]["exerciseLogs"][0]["cvFormSummary"] == cv_summary

        r_workout_detail = client.get(f"/api/workouts/sessions/{session_id}", headers=headers)
        assert r_workout_detail.status_code == 200
        assert r_workout_detail.json()["session"]["exerciseLogs"][0]["cvFormSummary"] == cv_summary

        results["step2_workout"] = {
            "post_session": r_workout_post.status_code,
            "get_last_performance": r_last_perf.status_code,
            "get_history": r_workout_hist.status_code,
            "get_session_detail": r_workout_detail.status_code,
        }

        # =====================================================================
        # STEP 3: Nutrition + Dynamic Macro + Quick Relog + Supplements + Recipes
        # =====================================================================
        r_nutri_init = client.get(f"/api/nutrition/{today_vn}", headers=headers)
        assert r_nutri_init.status_code == 200, f"GET /api/nutrition/{today_vn} failed: {r_nutri_init.text}"
        nutri_init_data = r_nutri_init.json()
        assert nutri_init_data["day_mode"] == "training", f"Expected day_mode='training', got {nutri_init_data['day_mode']}"
        assert "dynamic_target" in nutri_init_data
        assert nutri_init_data["dynamic_target"]["calorie_delta"] > 0
        assert isinstance(nutri_init_data["supplements"], list)

        r_meal_log = client.post(
            "/api/nutrition/logs",
            headers=headers,
            json={
                "date": today_vn,
                "meal_type": "breakfast",
                "foods": [
                    {
                        "name": "Phở bò tái",
                        "weight_grams": 300,
                        "calories": 450,
                        "protein": 28.0,
                        "carbs": 55.0,
                        "fat": 12.0,
                    }
                ],
                "total_calories": 450,
                "total_protein": 28.0,
                "total_carbs": 55.0,
                "total_fat": 12.0,
            },
        )
        assert r_meal_log.status_code == 200, f"POST /api/nutrition/logs failed: {r_meal_log.text}"
        source_log_id = r_meal_log.json()["id"]

        r_recent = client.get("/api/nutrition/recent-meals", headers=headers)
        assert r_recent.status_code == 200, f"GET /api/nutrition/recent-meals failed: {r_recent.text}"
        recent_meals = r_recent.json()["meals"]
        assert len(recent_meals) >= 1
        assert recent_meals[0]["source_log_id"] == source_log_id

        r_relog = client.post(
            "/api/nutrition/quick-relog",
            headers=headers,
            json={
                "source_log_id": source_log_id,
                "meal_type": "lunch",
                "date": today_vn,
            },
        )
        assert r_relog.status_code == 200, f"POST /api/nutrition/quick-relog failed: {r_relog.status_code} {r_relog.text}"
        assert r_relog.json()["meal"]["total_calories"] == 450

        r_nutri_after_relog = client.get(f"/api/nutrition/{today_vn}", headers=headers)
        assert r_nutri_after_relog.status_code == 200
        assert r_nutri_after_relog.json()["total_calories"] == 900

        r_sup_post = client.post(
            "/api/nutrition/supplements",
            headers=headers,
            json={
                "name": "Creatine Monohydrate",
                "amount": 5.0,
                "unit": "g",
                "dosage": "5g",
                "timing": "08:00",
            },
        )
        assert r_sup_post.status_code == 200, f"POST /api/nutrition/supplements failed: {r_sup_post.text}"
        sup_id = r_sup_post.json()["id"]
        assert r_sup_post.json()["date"] == today_vn

        r_sup_get = client.get(f"/api/nutrition/supplements/{today_vn}", headers=headers)
        assert r_sup_get.status_code == 200
        assert len(r_sup_get.json()["supplements"]) == 1
        assert r_sup_get.json()["supplements"][0]["id"] == sup_id

        r_nutri_with_sup = client.get(f"/api/nutrition/{today_vn}", headers=headers)
        assert r_nutri_with_sup.status_code == 200
        assert len(r_nutri_with_sup.json()["supplements"]) == 1
        assert r_nutri_with_sup.json()["supplements"][0]["name"] == "Creatine Monohydrate"

        db_sup = db["supplement_logs"].find_one({"_id": ObjectId(sup_id)})
        assert db_sup is not None
        assert db_sup["user_id"] == user_id_str
        assert db_sup["user_email"] == test_email
        assert db_sup["date"] == today_vn

        r_sup_del = client.delete(f"/api/nutrition/supplements/{sup_id}", headers=headers)
        assert r_sup_del.status_code == 200
        assert db["supplement_logs"].find_one({"_id": ObjectId(sup_id)}) is None

        r_rec_post = client.post(
            "/api/nutrition/recipes",
            headers=headers,
            json={
                "name": "Ức gà áp chảo khoai lang",
                "servings": 2,
                "ingredients": [
                    {"name": "Ức gà", "calories": 400, "protein": 60.0, "carbs": 0.0, "fat": 8.0},
                    {"name": "Khoai lang", "calories": 200, "protein": 4.0, "carbs": 46.0, "fat": 0.0},
                ],
            },
        )
        assert r_rec_post.status_code == 200, f"POST /api/nutrition/recipes failed: {r_rec_post.text}"
        recipe_id = r_rec_post.json()["id"]
        assert r_rec_post.json()["calories_per_serving"] == 300
        assert r_rec_post.json()["protein_per_serving"] == 32.0

        db_rec = db["recipes"].find_one({"_id": ObjectId(recipe_id)})
        assert db_rec is not None
        assert db_rec["user_id"] == user_id_str
        assert db_rec["user_email"] == test_email
        assert db_rec["date"] == today_vn

        r_rec_get = client.get("/api/nutrition/recipes", headers=headers)
        assert r_rec_get.status_code == 200
        assert any(r["id"] == recipe_id for r in r_rec_get.json()["recipes"])

        r_rec_log = client.post(
            f"/api/nutrition/recipes/{recipe_id}/log",
            headers=headers,
            json={"date": today_vn, "meal_type": "dinner", "servings_consumed": 1.0},
        )
        assert r_rec_log.status_code == 200, f"POST /api/nutrition/recipes/{recipe_id}/log failed: {r_rec_log.text}"
        assert r_rec_log.json()["meal"]["total_calories"] == 300

        r_nutri_after_rec = client.get(f"/api/nutrition/{today_vn}", headers=headers)
        assert r_nutri_after_rec.status_code == 200
        assert r_nutri_after_rec.json()["total_calories"] == 1200

        results["step3_nutrition_supplements_recipes"] = {
            "get_nutrition_training_mode": r_nutri_init.status_code,
            "post_nutrition_log": r_meal_log.status_code,
            "get_recent_meals": r_recent.status_code,
            "post_quick_relog": r_relog.status_code,
            "post_supplement": r_sup_post.status_code,
            "get_supplements_by_date": r_sup_get.status_code,
            "delete_supplement": r_sup_del.status_code,
            "post_recipe": r_rec_post.status_code,
            "get_recipes": r_rec_get.status_code,
            "post_recipe_log": r_rec_log.status_code,
        }

        # =====================================================================
        # STEP 4: AI Chat 3 Tiers + Stream + Action Card + Training Logs + Daily Brief
        # =====================================================================
        for mode in ("swift3", "core3", "pro3"):
            op_id = secrets.token_hex(16)
            r_chat_mode = client.post(
                "/api/chat",
                headers=headers,
                json={
                    "message": f"Đánh giá tiến độ hôm nay ở chế độ {mode}",
                    "contract_version": "core3-local-v1",
                    "operation_id": op_id,
                    "ai_mode": mode,
                },
            )
            assert r_chat_mode.status_code == 200, (
                f"POST /api/chat ({mode}) failed: {r_chat_mode.status_code} {r_chat_mode.text}"
            )
            assert r_chat_mode.json()["status"] == "success"
            assert f"[TEST/{mode}]" in r_chat_mode.json()["reply"]

        stream_op_id = secrets.token_hex(16)
        r_stream = client.post(
            "/api/chat/stream",
            headers=headers,
            json={
                "message": "Tư vấn trực tiếp qua SSE stream",
                "contract_version": "core3-local-v1",
                "operation_id": stream_op_id,
                "ai_mode": "core3",
            },
        )
        assert r_stream.status_code == 200, f"POST /api/chat/stream failed: {r_stream.status_code} {r_stream.text}"
        assert "event: meta" in r_stream.text
        assert "event: delta" in r_stream.text
        assert "event: done" in r_stream.text

        water_op_id = secrets.token_hex(16)
        r_chat_water = client.post(
            "/api/chat",
            headers=headers,
            json={
                "message": "Tôi vừa uống 300ml nước",
                "contract_version": "core3-local-v1",
                "operation_id": water_op_id,
                "ai_mode": "core3",
            },
        )
        assert r_chat_water.status_code == 200, f"POST /api/chat (water) failed: {r_chat_water.text}"
        chat_water_data = r_chat_water.json()
        action = chat_water_data.get("action")
        assert action is not None, f"Expected log_water action, got None: {chat_water_data}"
        assert action["type"] == "log_water"
        assert action["amount_ml"] == 300
        conv_id = chat_water_data["conversation_id"]
        action_id = action["id"]

        r_confirm = client.post(
            "/api/chat/actions/confirm",
            headers=headers,
            json={
                "conversation_id": conv_id,
                "action_id": action_id,
                "decision": "confirm",
            },
        )
        assert r_confirm.status_code == 200, f"POST /api/chat/actions/confirm failed: {r_confirm.text}"
        assert r_confirm.json()["amount_ml"] == 300

        db_water = db["water_logs"].find_one({"user_id": user_id_str, "date": today_vn})
        assert db_water is not None, "water_logs document not found in MongoDB"
        assert db_water["amount_ml"] == 300
        assert db_water["user_email"] == test_email

        u_hash = hash_user_id(user_id_str)
        db_training = db["chat_training_logs"].find_one(
            {"user_hash": u_hash, "operation_id": water_op_id}
        )
        assert db_training is not None, "chat_training_logs document not found in MongoDB"
        assert db_training["user_action_taken"] == "confirmed"
        serialized_training = json.dumps(db_training, default=str)
        assert test_email not in serialized_training, "Raw email leaked into chat_training_logs!"
        assert user_id_str not in serialized_training, "Raw user_id leaked into chat_training_logs!"

        r_brief = client.get("/api/chat/daily-brief", headers=headers)
        assert r_brief.status_code == 200, f"GET /api/chat/daily-brief failed: {r_brief.text}"
        brief_data = r_brief.json()
        assert brief_data["status"] == "success"
        assert brief_data["metrics"]["calories"] == 1200
        assert brief_data["metrics"]["water_ml"] == 300
        assert brief_data["metrics"]["worked_out_today"] is True
        assert isinstance(brief_data.get("nudge"), dict)
        assert brief_data["nudge"].get("id") is not None

        results["step4_chat_and_brief"] = {
            "chat_swift3_core3_pro3": 200,
            "chat_stream": r_stream.status_code,
            "chat_water_intent": r_chat_water.status_code,
            "confirm_water_action": r_confirm.status_code,
            "get_daily_brief": r_brief.status_code,
        }

        # =====================================================================
        # STEP 5: Paywall Gate (ENABLE_AI_PAYWALL=true vs false)
        # =====================================================================
        os.environ["ENABLE_AI_PAYWALL"] = "true"

        r_pro3_blocked = client.post(
            "/api/chat",
            headers=headers,
            json={
                "message": "Thử gọi Pro 3 khi bật paywall",
                "contract_version": "core3-local-v1",
                "operation_id": secrets.token_hex(16),
                "ai_mode": "pro3",
            },
        )
        assert r_pro3_blocked.status_code == 403, (
            f"Expected 403 on pro3 with paywall enabled, got {r_pro3_blocked.status_code}: {r_pro3_blocked.text}"
        )
        assert r_pro3_blocked.json()["detail"]["code"] == "entitlement_required"

        r_analytics_30_blocked = client.post(
            "/api/coach/analytics/preflight",
            headers=headers,
            json={"range_days": 30},
        )
        assert r_analytics_30_blocked.status_code == 403, (
            f"Expected 403 on analytics 30d preflight with paywall enabled, got {r_analytics_30_blocked.status_code}"
        )
        assert r_analytics_30_blocked.json()["detail"]["code"] == "entitlement_required"

        r_analytics_30_exec_blocked = client.post(
            "/api/coach/analytics/execute",
            headers=headers,
            json={"quote_id": "dummy_quote", "range_days": 30, "confirm": True},
        )
        assert r_analytics_30_exec_blocked.status_code == 403
        assert r_analytics_30_exec_blocked.json()["detail"]["code"] == "entitlement_required"

        os.environ["ENABLE_AI_PAYWALL"] = "false"
        r_analytics_30_unlocked = client.post(
            "/api/coach/analytics/preflight",
            headers=headers,
            json={"range_days": 30},
        )
        assert r_analytics_30_unlocked.status_code == 200, (
            f"Expected 200 on analytics 30d preflight when paywall disabled, got {r_analytics_30_unlocked.status_code}"
        )

        results["step5_paywall_gate"] = {
            "pro3_blocked_when_enabled": r_pro3_blocked.status_code,
            "analytics_30d_preflight_blocked": r_analytics_30_blocked.status_code,
            "analytics_30d_execute_blocked": r_analytics_30_exec_blocked.status_code,
            "analytics_30d_preflight_unlocked_when_disabled": r_analytics_30_unlocked.status_code,
        }

        return results

    finally:
        if prev_chat_provider is None:
            os.environ.pop("CHAT_AI_PROVIDER", None)
        else:
            os.environ["CHAT_AI_PROVIDER"] = prev_chat_provider

        if prev_paywall is None:
            os.environ.pop("ENABLE_AI_PAYWALL", None)
        else:
            os.environ["ENABLE_AI_PAYWALL"] = prev_paywall

        _cleanup_test_user(db, user_id_str, test_email)
        mongo_client.close()


def test_e2e_real_mongo_smoke():
    results = run_e2e_real_mongo_smoke()
    assert "step0_auth" in results
    assert "step1_wishlist_and_weight" in results
    assert "step2_workout" in results
    assert "step3_nutrition_supplements_recipes" in results
    assert "step4_chat_and_brief" in results
    assert "step5_paywall_gate" in results


if __name__ == "__main__":
    summary = run_e2e_real_mongo_smoke()
    print("\n=== E2E REAL MONGODB SMOKE RESULTS ===")
    print(json.dumps(summary, indent=2))
    print("=== ALL E2E CHECKS PASSED & CLEANED UP ===")
