"""FastAPI Router for Saman Journey & Gamification Wallet.

Provides:
- Journey creation, active journey tracking, and daily task management.
- Real activity verification against MongoDB nutrition & workout collections.
- Streak calculation standardized to Asia/Ho_Chi_Minh (UTC+7).
- Separate day index, completed days, and consecutive streak.
- Idempotent Daily Reward claim (20 SP) on MongoDB standalone.
- Dual-currency Point & AI Credit wallet with atomic deduction and rejection of unavailable rewards.
"""

from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
from typing import Optional, List, Dict, Any
from bson import ObjectId
from pymongo.errors import DuplicateKeyError
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from backend.auth_utils import get_current_user
from backend.app.database import db

router = APIRouter(prefix="/api", tags=["journey"])

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")

def _get_vn_today() -> str:
    """Return today's date string YYYY-MM-DD in Asia/Ho_Chi_Minh timezone."""
    return datetime.now(VN_TZ).strftime("%Y-%m-%d")

def _serialize_doc(doc: Optional[dict]) -> Optional[dict]:
    if not doc:
        return None
    res = dict(doc)
    if "_id" in res:
        res["id"] = str(res["_id"])
        del res["_id"]
    return res

def compute_journey_stats(days: list, today_str: str, previous_best_streak: int = 0) -> dict:
    """Compute completed_days_count, current_streak, and best_streak.
    
    Rules:
    - New journey with 0 completed days -> streak = 0.
    - Completed days = total days where is_completed is True.
    - Past days (strictly before today): must be completed or rest_day to sustain streak.
    - Today: if completed, increments current streak; if not yet completed, today is not over,
      so streak from past is preserved without penalty.
    - A missed past day resets current streak to 0.
    """
    completed_days_count = sum(1 for d in days if d.get("is_completed"))
    sorted_days = sorted(days, key=lambda x: x.get("date", ""))

    today_rec = next((d for d in sorted_days if d.get("date") == today_str), None)
    past_days = [d for d in sorted_days if d.get("date") < today_str]

    streak_from_past = 0
    for d in reversed(past_days):
        if d.get("is_completed") or d.get("is_rest_day"):
            streak_from_past += 1
        else:
            break

    if today_rec and today_rec.get("is_completed"):
        current_streak = streak_from_past + 1
    else:
        current_streak = streak_from_past

    best_streak = max(previous_best_streak, current_streak)
    return {
        "completed_days_count": completed_days_count,
        "current_streak": current_streak,
        "best_streak": best_streak,
    }

# ----------------- SCHEMAS -----------------

class CreateJourneyRequest(BaseModel):
    focus: str = Field(..., description="nutrition, workout, or hybrid")
    total_days: int = Field(14, description="7, 14, 21, or 30 days - default 14")
    reminder_time: Optional[str] = Field(None, description="HH:mm format preference")

class CompleteTaskRequest(BaseModel):
    journey_id: str
    task_id: str
    activity_id: Optional[str] = None

class ClaimDailyRewardRequest(BaseModel):
    journey_id: str
    date: Optional[str] = None

class RedeemRewardRequest(BaseModel):
    reward_id: str

# ----------------- CATALOG CONFIG -----------------

REWARDS_CATALOG_VERSION = "2026.10.experimental_v1"

DEFAULT_REWARDS = [
    {
        "id": "rew_ai_credit_1",
        "title": "1 lượt AI",
        "description": "Phân tích ảnh món ăn hoặc tư vấn chuyên sâu cùng Saman Coach",
        "points_cost": 100,
        "ai_credits": 1,
        "category": "ai_credit",
        "icon_name": "smart_toy",
        "is_available": False,
        "status_note": "Chưa khả dụng · Đang kết nối hạ tầng AI quota",
    },
    {
        "id": "rew_ai_credit_3",
        "title": "3 lượt AI",
        "description": "Gói tiết kiệm 3 lượt phân tích ảnh món ăn và tư vấn Coach",
        "points_cost": 280,
        "ai_credits": 3,
        "category": "ai_credit",
        "icon_name": "smart_toy",
        "is_available": False,
        "status_note": "Chưa khả dụng · Đang kết nối hạ tầng AI quota",
    },
    {
        "id": "rew_champion_badge",
        "title": "Huy hiệu Chiến binh Saman",
        "description": "Huy hiệu vinh danh độc quyền trên hồ sơ cá nhân",
        "points_cost": 500,
        "ai_credits": 0,
        "category": "profile_perk",
        "icon_name": "military_tech",
        "is_available": False,
        "status_note": "Chưa khả dụng trong phiên bản hiện tại",
    },
]

# ----------------- JOURNEY ENDPOINTS -----------------

@router.get("/journey/active")
async def get_active_journey(current_user: dict = Depends(get_current_user)):
    user_email = current_user.get("email")
    if not user_email:
        raise HTTPException(status_code=401, detail="Unauthorized")

    if db is None:
        return {"journey": None}

    journeys_col = db["journeys"]
    doc = journeys_col.find_one(
        {"user_email": user_email, "status": "active"},
        sort=[("created_at", -1)]
    )
    if not doc:
        return {"journey": None}

    today_str = _get_vn_today()
    days = doc.get("days", [])
    
    # Recalculate streak & completed days
    stats = compute_journey_stats(days, today_str, doc.get("best_streak", 0))
    if stats["current_streak"] != doc.get("current_streak") or stats["completed_days_count"] != doc.get("completed_days_count"):
        journeys_col.update_one(
            {"_id": doc["_id"]},
            {"$set": {
                "current_streak": stats["current_streak"],
                "completed_days_count": stats["completed_days_count"],
                "best_streak": stats["best_streak"],
            }}
        )
        doc["current_streak"] = stats["current_streak"]
        doc["completed_days_count"] = stats["completed_days_count"]
        doc["best_streak"] = stats["best_streak"]

    today_rec = next((d for d in days if d.get("date") == today_str), None)
    serialized = _serialize_doc(doc)
    serialized["today_record"] = today_rec
    return {"journey": serialized}


@router.post("/journey/create", status_code=201)
async def create_journey(req: CreateJourneyRequest, current_user: dict = Depends(get_current_user)):
    user_email = current_user.get("email")
    if not user_email:
        raise HTTPException(status_code=401, detail="Unauthorized")

    if db is None:
        raise HTTPException(status_code=503, detail="Database not available")

    journeys_col = db["journeys"]

    # Archive existing active journey if any
    journeys_col.update_many(
        {"user_email": user_email, "status": "active"},
        {"$set": {"status": "abandoned", "updated_at": datetime.now(timezone.utc)}}
    )

    today = datetime.now(VN_TZ)
    today_str = today.strftime("%Y-%m-%d")
    end_date = today + timedelta(days=req.total_days - 1)
    end_str = end_date.strftime("%Y-%m-%d")

    # Generate daily records
    days = []
    for i in range(req.total_days):
        day_dt = today + timedelta(days=i)
        d_str = day_dt.strftime("%Y-%m-%d")
        
        # Day 6 of each 7-day cycle is designated as a Rest Day in default plan
        is_rest = ((i + 1) % 7 == 6)
        
        tasks = []
        if is_rest:
            tasks.append({
                "id": f"task_{d_str}_rest",
                "type": "workout",
                "title": "Nghỉ ngơi & phục hồi",
                "subtitle": "Thả lỏng cơ thể, giãn cơ nhẹ nhàng hoặc đi bộ",
                "is_completed": False,
                "points": 0,
                "activity_id": None,
            })
        else:
            if req.focus in ("workout", "hybrid"):
                tasks.append({
                    "id": f"task_{d_str}_workout",
                    "type": "workout",
                    "title": "Hoàn thành buổi tập",
                    "subtitle": "Thực hiện và lưu 1 buổi tập theo lịch",
                    "is_completed": False,
                    "points": 0,
                    "activity_id": None,
                })
        
        if req.focus in ("nutrition", "hybrid"):
            tasks.append({
                "id": f"task_{d_str}_nutri",
                "type": "nutrition",
                "title": "Ghi nhận bữa ăn",
                "subtitle": "Lưu ít nhất 1 bữa ăn trong ngày",
                "is_completed": False,
                "points": 0,
                "activity_id": None,
            })

        days.append({
            "date": d_str,
            "day_index": i + 1,
            "is_completed": False,
            "is_rest_day": is_rest,
            "is_daily_reward_claimed": False,
            "daily_reward_points": 20,
            "tasks": tasks,
            "points_earned": 0,
        })

    new_doc = {
        "user_email": user_email,
        "user_id": str(current_user.get("_id") or current_user.get("id", user_email)),
        "focus": req.focus,
        "total_days": req.total_days,
        "start_date": today_str,
        "end_date": end_str,
        "reminder_time": req.reminder_time,
        "status": "active",
        "current_streak": 0,       # Rule: newly created journey has streak = 0
        "completed_days_count": 0, # Rule: 0 completed days initially
        "best_streak": 0,
        "points_earned": 0,
        "days": days,
        "created_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc),
    }

    res = journeys_col.insert_one(new_doc)
    new_doc["_id"] = res.inserted_id

    serialized = _serialize_doc(new_doc)
    serialized["today_record"] = days[0] if days else None
    return {"journey": serialized}


@router.post("/journey/complete-task")
async def complete_journey_task(req: CompleteTaskRequest, current_user: dict = Depends(get_current_user)):
    user_email = current_user.get("email")
    if not user_email:
        raise HTTPException(status_code=401, detail="Unauthorized")

    if db is None:
        raise HTTPException(status_code=503, detail="Database not available")

    journeys_col = db["journeys"]

    try:
        j_oid = ObjectId(req.journey_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid journey ID")

    journey = journeys_col.find_one({"_id": j_oid, "user_email": user_email, "status": "active"})
    if not journey:
        raise HTTPException(status_code=404, detail="Active journey not found")

    # Find task and day
    days = journey.get("days", [])
    target_task = None
    target_day = None

    for d in days:
        for t in d.get("tasks", []):
            if t.get("id") == req.task_id:
                target_task = t
                target_day = d
                break
        if target_task:
            break

    if not target_task:
        raise HTTPException(status_code=404, detail="Task not found in journey")

    # Idempotent check: if already completed, return without error
    if target_task.get("is_completed"):
        today_str = _get_vn_today()
        serialized = _serialize_doc(journey)
        serialized["today_record"] = next((d for d in days if d.get("date") == today_str), None)
        return {"journey": serialized, "message": "Nhiệm vụ đã được hoàn thành trước đó"}

    # VERIFY REAL COMPLETION EVIDENCE
    task_type = target_task.get("type")
    task_date = target_day.get("date")
    verified_activity_id = None

    if task_type == "nutrition":
        nutri_col = db["nutrition_plans"]
        if req.activity_id:
            try:
                act_oid = ObjectId(req.activity_id)
                log_doc = nutri_col.find_one({
                    "_id": act_oid,
                    "$or": [{"user_email": user_email}, {"email": user_email}]
                })
            except Exception:
                log_doc = None
            if not log_doc:
                raise HTTPException(status_code=400, detail="Bản ghi bữa ăn không hợp lệ hoặc không thuộc về bạn")
            log_date = log_doc.get("date")
            if isinstance(log_date, datetime):
                log_date = log_date.strftime("%Y-%m-%d")
            elif isinstance(log_date, str) and len(log_date) >= 10:
                log_date = log_date[:10]
            if log_date and log_date != task_date:
                raise HTTPException(status_code=400, detail="Bản ghi bữa ăn không thuộc ngày của nhiệm vụ này")
            verified_activity_id = str(log_doc["_id"])
        else:
            # Reconcile path: look for user's meal log on task_date
            log_doc = nutri_col.find_one({
                "$or": [{"user_email": user_email}, {"email": user_email}],
                "date": task_date
            })
            if not log_doc:
                raise HTTPException(status_code=400, detail="Không tìm thấy bản ghi bữa ăn hợp lệ cho ngày này")
            verified_activity_id = str(log_doc["_id"])

    elif task_type == "workout":
        workout_col = db["workout_history"]
        if target_day.get("is_rest_day"):
            # Rest day can be confirmed directly
            verified_activity_id = f"rest_confirmed_{task_date}"
        else:
            user_id = str(current_user.get("_id") or current_user.get("id", user_email))
            if req.activity_id:
                sess_doc = None
                try:
                    act_oid = ObjectId(req.activity_id)
                    sess_doc = workout_col.find_one({
                        "_id": act_oid,
                        "$or": [{"email": user_email}, {"user_email": user_email}, {"user_id": user_id}]
                    })
                except Exception:
                    pass
                if not sess_doc:
                    sess_doc = workout_col.find_one({
                        "client_id": req.activity_id,
                        "$or": [{"email": user_email}, {"user_email": user_email}, {"user_id": user_id}]
                    })
                if not sess_doc:
                    raise HTTPException(status_code=400, detail="Bản ghi buổi tập không hợp lệ hoặc không thuộc về bạn")
                sess_date = sess_doc.get("date")
                if isinstance(sess_date, datetime):
                    sess_date = sess_date.strftime("%Y-%m-%d")
                elif isinstance(sess_date, str) and len(sess_date) >= 10:
                    sess_date = sess_date[:10]
                if sess_date and sess_date != task_date:
                    raise HTTPException(status_code=400, detail="Bản ghi buổi tập không thuộc ngày của nhiệm vụ này")
                verified_activity_id = str(sess_doc["_id"])
            else:
                # Reconcile path: look for workout session on task_date
                sess_doc = workout_col.find_one({
                    "$or": [{"email": user_email}, {"user_email": user_email}, {"user_id": user_id}],
                    "date": task_date,
                })
                if not sess_doc:
                    raise HTTPException(status_code=400, detail="Không tìm thấy bản ghi buổi tập hợp lệ cho ngày này")
                verified_activity_id = str(sess_doc["_id"])

    # Check for duplicate activity usage across all tasks in this journey
    if verified_activity_id and not target_day.get("is_rest_day"):
        for d in days:
            for t in d.get("tasks", []):
                if t.get("activity_id") == verified_activity_id and t.get("id") != target_task.get("id"):
                    raise HTTPException(status_code=400, detail="Bản ghi hoạt động này đã được dùng cho nhiệm vụ khác")

    # Mark task as completed
    target_task["is_completed"] = True
    target_task["activity_id"] = verified_activity_id

    # Check if all tasks in day are completed
    all_done = all(t.get("is_completed") for t in target_day.get("tasks", []))
    target_day["is_completed"] = all_done

    today_str = _get_vn_today()
    stats = compute_journey_stats(days, today_str, journey.get("best_streak", 0))

    # Single-document atomic update on journey
    journeys_col.update_one(
        {"_id": j_oid},
        {
            "$set": {
                "days": days,
                "completed_days_count": stats["completed_days_count"],
                "current_streak": stats["current_streak"],
                "best_streak": stats["best_streak"],
                "updated_at": datetime.now(timezone.utc),
            }
        }
    )

    updated_journey = journeys_col.find_one({"_id": j_oid})
    serialized = _serialize_doc(updated_journey)
    serialized["today_record"] = next((d for d in days if d.get("date") == today_str), None)

    return {"journey": serialized, "message": "Hoàn thành nhiệm vụ thành công"}


@router.post("/journey/claim-daily-reward")
async def claim_daily_reward(req: ClaimDailyRewardRequest, current_user: dict = Depends(get_current_user)):
    """Idempotent Daily Reward Claim (20 SP).
    
    Verifies that all tasks for the specified date are completed, prevents duplicate claims,
    and updates user balance & ledger atomically.
    """
    user_email = current_user.get("email")
    if not user_email:
        raise HTTPException(status_code=401, detail="Unauthorized")

    if db is None:
        raise HTTPException(status_code=503, detail="Database not available")

    journeys_col = db["journeys"]
    users_col = db["users"]
    tx_col = db["point_transactions"]
    claims_col = db["journey_claims"]

    try:
        j_oid = ObjectId(req.journey_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid journey ID")

    journey = journeys_col.find_one({"_id": j_oid, "user_email": user_email, "status": "active"})
    if not journey:
        raise HTTPException(status_code=404, detail="Active journey not found")

    target_date = req.date or _get_vn_today()
    days = journey.get("days", [])
    target_day = next((d for d in days if d.get("date") == target_date), None)
    if not target_day:
        raise HTTPException(status_code=404, detail="Không tìm thấy ngày này trong hành trình")

    if not target_day.get("is_completed"):
        raise HTTPException(status_code=400, detail="Chưa hoàn thành tất cả nhiệm vụ của ngày để nhận thưởng")

    if target_day.get("is_daily_reward_claimed"):
        serialized = _serialize_doc(journey)
        today_str = _get_vn_today()
        serialized["today_record"] = next((d for d in days if d.get("date") == today_str), None)
        user_doc = users_col.find_one({"email": user_email}) or {}
        return {
            "journey": serialized,
            "message": "Phần thưởng ngày hôm nay đã được nhận",
            "new_balance": user_doc.get("saman_points", 0),
        }

    pts = target_day.get("daily_reward_points", 20)
    user_id_clean = str(current_user.get("_id") or current_user.get("id", user_email)).replace(".", "_")
    claim_key = f"{user_id_clean}_{req.journey_id}_{target_date}_daily_reward"
    receipt_data = {
        "points": pts,
        "journey_id": str(j_oid),
        "user_email": user_email,
        "date": target_date,
        "day_index": target_day.get("day_index", 1),
        "type": "daily_reward",
        "policy_version": "2026.10_v2",
        "claimed_at": datetime.now(timezone.utc).isoformat(),
    }

    # ATOMIC MUTATION: Credit balance and record embedded claim receipt in the EXACT SAME single document operation.
    # Query condition: claim_key does NOT exist in user's applied_claims.
    # On MongoDB standalone, single-document updates are strictly atomic and serializable.
    updated_user = users_col.find_one_and_update(
        {
            "email": user_email,
            f"applied_claims.{claim_key}": {"$exists": False},
        },
        {
            "$inc": {"saman_points": pts},
            "$set": {f"applied_claims.{claim_key}": receipt_data},
        },
        return_document=True,
    )

    if not updated_user:
        # The claim was ALREADY applied (concurrent request, or retry after crash/timeout).
        # Reconcile downstream using the existing authoritative receipt recorded in the user document.
        user_doc = users_col.find_one({"email": user_email})
        if not user_doc:
            raise HTTPException(status_code=404, detail="User not found")
        applied_claims = user_doc.get("applied_claims", {})
        existing_receipt = applied_claims.get(claim_key)

        if existing_receipt:
            # Preserved points from original policy receipt
            original_pts = existing_receipt.get("points", pts)

            # Reconcile downstream ledger & presentation cache (idempotent upsert)
            tx_col.update_one(
                {"_id": f"tx_{claim_key}"},
                {"$setOnInsert": {
                    "_id": f"tx_{claim_key}",
                    "user_email": user_email,
                    "amount": original_pts,
                    "type": "daily_reward",
                    "description": f"Thưởng hoàn thành Ngày {existing_receipt.get('day_index', target_day.get('day_index'))}",
                    "created_at": existing_receipt.get("claimed_at", datetime.now(timezone.utc).isoformat()),
                    "reference_id": claim_key,
                    "policy_version": existing_receipt.get("policy_version", "2026.10_v2"),
                }},
                upsert=True
            )
            claims_col.update_one(
                {"_id": claim_key},
                {"$setOnInsert": {
                    "_id": claim_key,
                    "user_email": user_email,
                    "journey_id": req.journey_id,
                    "date": target_date,
                    "reward_type": "daily_reward",
                    "points": original_pts,
                    "policy_version": existing_receipt.get("policy_version", "2026.10_v2"),
                    "claimed_at": existing_receipt.get("claimed_at"),
                }},
                upsert=True
            )
            target_day["is_daily_reward_claimed"] = True
            journeys_col.update_one({"_id": j_oid}, {"$set": {"days": days}})

            updated_journey = journeys_col.find_one({"_id": j_oid})
            serialized = _serialize_doc(updated_journey)
            today_str = _get_vn_today()
            serialized["today_record"] = next((d for d in days if d.get("date") == today_str), None)

            return {
                "journey": serialized,
                "message": "Phần thưởng ngày hôm nay đã được nhận",
                "new_balance": user_doc.get("saman_points", 0),
            }
        else:
            raise HTTPException(status_code=500, detail="Không thể xác thực số dư người dùng")

    # Claim succeeded first time! Reconcile downstream ledger and journey state.
    tx_col.update_one(
        {"_id": f"tx_{claim_key}"},
        {"$setOnInsert": {
            "_id": f"tx_{claim_key}",
            "user_email": user_email,
            "amount": pts,
            "type": "daily_reward",
            "description": f"Thưởng hoàn thành Ngày {target_day.get('day_index')}",
            "created_at": receipt_data["claimed_at"],
            "reference_id": claim_key,
            "policy_version": receipt_data["policy_version"],
        }},
        upsert=True
    )
    claims_col.update_one(
        {"_id": claim_key},
        {"$setOnInsert": {
            "_id": claim_key,
            "user_email": user_email,
            "journey_id": req.journey_id,
            "date": target_date,
            "reward_type": "daily_reward",
            "points": pts,
            "policy_version": receipt_data["policy_version"],
            "claimed_at": receipt_data["claimed_at"],
        }},
        upsert=True
    )
    target_day["is_daily_reward_claimed"] = True
    new_points_total = journey.get("points_earned", 0) + pts
    journeys_col.update_one(
        {"_id": j_oid},
        {"$set": {
            "days": days,
            "points_earned": new_points_total,
            "updated_at": datetime.now(timezone.utc),
        }}
    )

    updated_journey = journeys_col.find_one({"_id": j_oid})
    serialized = _serialize_doc(updated_journey)
    today_str = _get_vn_today()
    serialized["today_record"] = next((d for d in days if d.get("date") == today_str), None)

    return {
        "journey": serialized,
        "message": f"Nhận thành công {pts} điểm thưởng!",
        "new_balance": updated_user.get("saman_points", 0),
    }

# ----------------- WALLET ENDPOINTS -----------------

@router.get("/wallet/balance")
async def get_wallet_balance(current_user: dict = Depends(get_current_user)):
    user_email = current_user.get("email")
    if not user_email:
        raise HTTPException(status_code=401, detail="Unauthorized")

    if db is None:
        return {"balance": 0, "ai_credits": 0}

    user_doc = db["users"].find_one({"email": user_email}) or {}
    balance = user_doc.get("saman_points", 0)
    ai_credits = user_doc.get("ai_credits", 0)
    return {"balance": balance, "ai_credits": ai_credits}


@router.get("/wallet/history")
async def get_wallet_history(current_user: dict = Depends(get_current_user)):
    user_email = current_user.get("email")
    if not user_email:
        raise HTTPException(status_code=401, detail="Unauthorized")

    if db is None:
        return {"transactions": []}

    tx_col = db["point_transactions"]
    cursor = tx_col.find({"user_email": user_email}).sort("created_at", -1).limit(50)
    results = [_serialize_doc(d) for d in cursor]
    return {"transactions": results}


@router.get("/wallet/rewards")
async def get_rewards_catalog():
    return {
        "version": REWARDS_CATALOG_VERSION,
        "rewards": DEFAULT_REWARDS,
    }


@router.post("/wallet/redeem")
async def redeem_reward(req: RedeemRewardRequest, current_user: dict = Depends(get_current_user)):
    user_email = current_user.get("email")
    if not user_email:
        raise HTTPException(status_code=401, detail="Unauthorized")

    if db is None:
        raise HTTPException(status_code=503, detail="Database not available")

    # Find reward
    reward = next((r for r in DEFAULT_REWARDS if r["id"] == req.reward_id), None)
    if not reward:
        raise HTTPException(status_code=404, detail="Phần thưởng không tồn tại")

    # Guard: Reject unavailable rewards immediately before touching any balance
    if not reward.get("is_available", False):
        raise HTTPException(
            status_code=400,
            detail=f"Phần thưởng '{reward['title']}' hiện chưa khả dụng để đổi."
        )

    cost = reward["points_cost"]
    credits_to_grant = reward.get("ai_credits", 0)
    users_col = db["users"]
    tx_col = db["point_transactions"]
    rewards_col = db["user_rewards"]

    # Atomic deduction and credit increment: find and update ONLY IF balance >= cost
    updated_user = users_col.find_one_and_update(
        {"email": user_email, "saman_points": {"$gte": cost}},
        {"$inc": {
            "saman_points": -cost,
            "ai_credits": credits_to_grant,
        }},
        return_document=True
    )

    if not updated_user:
        raise HTTPException(status_code=400, detail="Số dư Saman Points không đủ để đổi phần thưởng này")

    # Record redemption transaction
    tx_col.insert_one({
        "user_email": user_email,
        "amount": -cost,
        "type": "reward_redemption",
        "description": f"Đổi phần thưởng: {reward['title']}",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "reference_id": reward["id"],
    })

    # Record granted perk
    rewards_col.insert_one({
        "user_email": user_email,
        "reward_id": reward["id"],
        "title": reward["title"],
        "category": reward["category"],
        "ai_credits_granted": credits_to_grant,
        "status": "active",
        "granted_at": datetime.now(timezone.utc),
    })

    return {
        "status": "success",
        "message": f"Đổi thành công {reward['title']}",
        "new_balance": updated_user.get("saman_points", 0),
        "ai_credits": updated_user.get("ai_credits", 0),
    }
