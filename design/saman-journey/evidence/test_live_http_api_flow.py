import json
import os
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
import pymongo

BASE_URL = "http://127.0.0.1:8008"
DB_NAME = "saman_journey_live_e2e_db"
MONGO_URI = "mongodb://127.0.0.1:27028"

EVIDENCE_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE = os.path.join(EVIDENCE_DIR, "http_api_flow.log")
JSON_FILE = os.path.join(EVIDENCE_DIR, "http_api_flow_results.json")

logs_list = []
results_data = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "base_url": BASE_URL,
    "database": DB_NAME,
    "test_user": "live_athlete@saman.app",
    "total_requests": 0,
    "passed_assertions": 0,
    "failed_assertions": 0,
    "requests": []
}

def log(msg: str):
    print(msg)
    logs_list.append(msg)

def make_request(method: str, path: str, token: str = None, payload: dict = None, expected_status: int = 200) -> dict:
    url = f"{BASE_URL}{path}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    
    data_bytes = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data_bytes, headers=headers, method=method)
    
    start_time = time.perf_counter()
    status_code = None
    res_body = None
    error_msg = None
    
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            status_code = response.getcode()
            raw_content = response.read().decode("utf-8")
            try:
                res_body = json.loads(raw_content)
            except Exception:
                res_body = raw_content
    except urllib.error.HTTPError as e:
        status_code = e.code
        raw_content = e.read().decode("utf-8")
        try:
            res_body = json.loads(raw_content)
        except Exception:
            res_body = raw_content
    except Exception as e:
        error_msg = str(e)
    
    elapsed_ms = round((time.perf_counter() - start_time) * 1000, 2)
    
    status_match = (status_code == expected_status)
    results_data["total_requests"] += 1
    if status_match:
        results_data["passed_assertions"] += 1
    else:
        results_data["failed_assertions"] += 1

    sanitized_payload = dict(payload) if isinstance(payload, dict) else payload
    if isinstance(sanitized_payload, dict) and "password" in sanitized_payload:
        sanitized_payload["password"] = "***MASKED***"

    sanitized_response = res_body
    if isinstance(sanitized_response, dict) and "access_token" in sanitized_response:
        sanitized_response = dict(sanitized_response)
        sanitized_response["access_token"] = "***MASKED_JWT***"

    entry = {
        "index": results_data["total_requests"],
        "method": method,
        "path": path,
        "expected_status": expected_status,
        "actual_status": status_code,
        "status_match": status_match,
        "elapsed_ms": elapsed_ms,
        "request_payload": sanitized_payload,
        "response_body": sanitized_response,
        "error": error_msg
    }
    results_data["requests"].append(entry)
    
    status_icon = "PASS" if status_match else "FAIL"
    log(f"[{status_icon}] #{entry['index']} {method} {path} -> Status {status_code} (Expected {expected_status}) [{elapsed_ms}ms]")
    if not status_match:
        log(f"       ERROR: Expected {expected_status}, got {status_code}. Response: {res_body}")
    
    return {
        "status": status_code,
        "body": res_body,
        "matched": status_match
    }

def main():
    log(f"============================================================")
    log(f"SAMAN JOURNEY LIVE HTTP E2E VERIFICATION ON PORT 8008")
    log(f"Target DB: {DB_NAME} on {MONGO_URI}")
    log(f"Time: {datetime.now(timezone.utc).isoformat()}")
    log(f"============================================================")
    
    # 0. Clean database setup
    client = pymongo.MongoClient(MONGO_URI)
    client.drop_database(DB_NAME)
    log("[DB SETUP] Cleaned and dropped test database: saman_journey_live_e2e_db")
    
    test_email = "live_athlete@saman.app"
    test_password = "SecurePassword123!"
    
    # 1. Register User via HTTP API
    log("\n--- STEP 1: Register User via HTTP API ---")
    reg_res = make_request(
        "POST", "/api/auth/register",
        payload={"email": test_email, "password": test_password, "full_name": "Live Athlete"},
        expected_status=200
    )
    assert reg_res["matched"], "Register failed"
    
    # 2. Login User via HTTP API
    log("\n--- STEP 2: Login User via HTTP API ---")
    login_res = make_request(
        "POST", "/api/auth/login",
        payload={"email": test_email, "password": test_password},
        expected_status=200
    )
    assert login_res["matched"], "Login failed"
    token = login_res["body"]["access_token"]
    assert token, "Token not returned from login"
    
    # 3. Check Initial Active Journey (should be null)
    log("\n--- STEP 3: Check Active Journey (Initial) ---")
    active_res = make_request("GET", "/api/journey/active", token=token, expected_status=200)
    assert active_res["body"]["journey"] is None, "Active journey should be None initially"
    
    # 4. Create 14-day Hybrid Journey via HTTP API
    log("\n--- STEP 4: Create Journey (14-day Hybrid) ---")
    create_res = make_request(
        "POST", "/api/journey/create",
        token=token,
        payload={"focus": "hybrid", "total_days": 14, "reminder_time": "08:00"},
        expected_status=201
    )
    assert create_res["matched"], "Create journey failed"
    journey = create_res["body"]["journey"]
    journey_id = journey["id"]
    assert journey["total_days"] == 14
    assert journey["current_streak"] == 0
    today_record = journey["days"][0]
    tasks = today_record["tasks"]
    assert len(tasks) == 2, f"Expected 2 tasks for both, got {len(tasks)}"
    nutrition_task = next(t for t in tasks if t["type"] == "nutrition")
    workout_task = next(t for t in tasks if t["type"] == "workout")
    log(f"   Journey created ID: {journey_id}, Day 1 Date: {today_record['date']}")
    
    # 5. Query Rewards Catalog
    log("\n--- STEP 5: Query Rewards Catalog ---")
    cat_res = make_request("GET", "/api/wallet/rewards", token=token, expected_status=200)
    assert cat_res["body"]["version"] == "2026.10.experimental_v1"
    for r in cat_res["body"]["rewards"]:
        assert r["is_available"] is False, f"Reward {r['id']} should be unavailable"
    log(f"   Verified catalog version {cat_res['body']['version']}: all {len(cat_res['body']['rewards'])} items is_available=False")
    
    # 6. Attempt Redeem Unavailable Reward (MUST fail with 400 without touching balance)
    log("\n--- STEP 6: Redeem Unavailable Package (Expect 400 Bad Request) ---")
    redeem_res = make_request(
        "POST", "/api/wallet/redeem",
        token=token,
        payload={"reward_id": "rew_ai_credit_1"},
        expected_status=400
    )
    assert redeem_res["matched"], "Redeem should have returned 400"
    assert "chưa khả dụng" in redeem_res["body"].get("detail", "").lower()
    
    # 7. Check Balance (Should remain 0 points, 0 credits)
    log("\n--- STEP 7: Check Balance After Rejected Redeem ---")
    bal_res = make_request("GET", "/api/wallet/balance", token=token, expected_status=200)
    assert bal_res["body"]["balance"] == 0
    assert bal_res["body"]["ai_credits"] == 0
    
    # 8. Save REAL Activities via REAL HTTP APIs (NOT direct DB seeding)
    log("\n--- STEP 8A: Save Real Nutrition Meal via POST /api/nutrition/logs ---")
    meal_payload = {
        "date": today_record["date"],
        "meal_type": "lunch",
        "foods": [{"food_name": "Ức gà áp chảo", "calories": 350.0, "protein": 45.0, "carbs": 5.0, "fat": 6.0}],
        "total_calories": 350.0,
        "notes": "Bữa trưa kiểm thử Journey HTTP API"
    }
    meal_res = make_request("POST", "/api/nutrition/logs", token=token, payload=meal_payload, expected_status=200)
    assert meal_res["matched"], "Save meal log failed"
    real_meal_id = meal_res["body"]["id"]
    log(f"   Real Meal Log Saved via API: ID = {real_meal_id}")
    
    log("\n--- STEP 8B: Save Real Workout Session via POST /api/workouts/sessions ---")
    session_payload = {
        "title": "Buổi tập ngực & tay sau",
        "plan_day_id": None,
        "exercise_logs": [
            {
                "exercise_id": "bench_press",
                "exercise_slug": "bench-press",
                "set_number": 1,
                "reps_completed": 12,
                "unit": "reps",
                "weight_kg": 60.0
            }
        ]
    }
    workout_res = make_request("POST", "/api/workouts/sessions", token=token, payload=session_payload, expected_status=201)
    assert workout_res["matched"], "Save workout session failed"
    real_session_id = workout_res["body"]["session_id"]
    log(f"   Real Workout Session Saved via API: ID = {real_session_id}")
    
    # 9. Complete Tasks with Real Activity IDs via HTTP API
    log("\n--- STEP 9A: Complete Nutrition Task with Real Meal ID ---")
    comp_nutri_res = make_request(
        "POST", "/api/journey/complete-task",
        token=token,
        payload={"journey_id": journey_id, "task_id": nutrition_task["id"], "activity_id": real_meal_id},
        expected_status=200
    )
    assert comp_nutri_res["matched"], "Complete nutrition task failed"
    
    log("\n--- STEP 9B: Complete Workout Task with Real Session ID ---")
    comp_work_res = make_request(
        "POST", "/api/journey/complete-task",
        token=token,
        payload={"journey_id": journey_id, "task_id": workout_task["id"], "activity_id": real_session_id},
        expected_status=200
    )
    assert comp_work_res["matched"], "Complete workout task failed"
    updated_journey = comp_work_res["body"]["journey"]
    updated_today = updated_journey["days"][0]
    assert updated_today["is_completed"] is True, "Day 1 should be complete after both tasks done"
    assert updated_today["is_daily_reward_claimed"] is False, "Daily reward must not be auto-claimed"
    
    # 10. Check Balance After Tasks Completed (CRITICAL: MUST NOT AUTO-CREDIT POINTS)
    log("\n--- STEP 10: Check Balance (Assert 0 Auto-Credit Points) ---")
    bal_after_tasks = make_request("GET", "/api/wallet/balance", token=token, expected_status=200)
    assert bal_after_tasks["body"]["balance"] == 0, f"Expected 0 points auto-credited, got {bal_after_tasks['body']['balance']}"
    log(f"   Verified: Tasks completed but Balance = {bal_after_tasks['body']['balance']} SP (NO auto-credit)")
    
    # 11. Claim Daily Reward (Expect +20 SP)
    log("\n--- STEP 11: Claim Daily Reward via HTTP API ---")
    claim_res = make_request(
        "POST", "/api/journey/claim-daily-reward",
        token=token,
        payload={"journey_id": journey_id, "date": today_record["date"]},
        expected_status=200
    )
    assert claim_res["matched"], "Claim daily reward failed"
    assert claim_res["body"]["new_balance"] == 20
    assert "20" in claim_res["body"]["message"]
    log(f"   Claimed successfully! New Balance: {claim_res['body']['new_balance']}, Message: '{claim_res['body']['message']}'")
    
    # 12. RETRY Claim Daily Reward (IDEMPOTENCY TEST: Must return 200, new_balance: 20)
    log("\n--- STEP 12: Retry Claim Daily Reward (Idempotent Retry Test) ---")
    retry_claim_res = make_request(
        "POST", "/api/journey/claim-daily-reward",
        token=token,
        payload={"journey_id": journey_id, "date": today_record["date"]},
        expected_status=200
    )
    assert retry_claim_res["matched"], "Retry claim failed"
    assert retry_claim_res["body"]["new_balance"] == 20, "Retry must preserve current balance 20"
    msg_lower = retry_claim_res["body"]["message"].lower()
    assert "đã được nhận" in msg_lower or "đã nhận" in msg_lower
    log(f"   Idempotent retry verified! Balance preserved: {retry_claim_res['body']['new_balance']} SP, Message: '{retry_claim_res['body']['message']}'")
    
    # 13. Check Wallet History Ledger
    log("\n--- STEP 13: Query Wallet Transaction History ---")
    hist_res = make_request("GET", "/api/wallet/history", token=token, expected_status=200)
    txs = hist_res["body"]["transactions"]
    assert len(txs) == 1, f"Expected exactly 1 transaction in history, got {len(txs)}"
    assert txs[0]["amount"] == 20
    assert txs[0]["type"] == "daily_reward"
    log(f"   Ledger verified: 1 transaction found: +{txs[0]['amount']} SP ({txs[0]['type']}) at {txs[0]['created_at']}")
    
    # 14. Check Final Active Journey State
    log("\n--- STEP 14: Query Final Active Journey State ---")
    final_j_res = make_request("GET", "/api/journey/active", token=token, expected_status=200)
    final_j = final_j_res["body"]["journey"]
    assert final_j["current_streak"] == 1, f"Expected streak 1, got {final_j['current_streak']}"
    assert final_j["completed_days_count"] == 1
    assert final_j["days"][0]["is_daily_reward_claimed"] is True
    log(f"   Final journey verified: Streak = {final_j['current_streak']}, Completed Days = {final_j['completed_days_count']}, Reward Claimed = True")
    
    # Write summary files
    with open(LOG_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(logs_list))
    
    with open(JSON_FILE, "w", encoding="utf-8") as f:
        json.dump(results_data, f, indent=2, ensure_ascii=False)
        
    log(f"\n============================================================")
    log(f"ALL HTTP E2E CHECKS PASSED: {results_data['passed_assertions']}/{results_data['total_requests']} requests succeeded!")
    log(f"Log written to: {LOG_FILE}")
    log(f"JSON data written to: {JSON_FILE}")
    log(f"============================================================")

if __name__ == "__main__":
    main()
