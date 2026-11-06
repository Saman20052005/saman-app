"""Read-only Community projections of owned Workout/Nutrition records."""
import hashlib
import json
from bson import ObjectId
from fastapi import HTTPException


def source_collection(db, kind):
    if kind not in ("workout", "meal"):
        raise HTTPException(422, "Unsupported attachment type")
    return db["workout_history" if kind == "workout" else "nutrition_plans"]


def owner_query(user, kind):
    if kind == "workout":
        return {"user_id": str(user["_id"]), "$or": [{"finished_at": {"$ne": None}}, {"end_time": {"$ne": None}}], "is_deleted": {"$ne": True}}
    return {"user_email": user["email"], "is_deleted": {"$ne": True}}


def public_snapshot(raw):
    if not isinstance(raw, dict) or raw.get("kind") not in ("workout", "meal"):
        return None
    keys = {"kind", "title", "date", "category"}
    keys |= {"duration_minutes", "exercise_count", "set_count", "load_kg"} if raw["kind"] == "workout" else {"calories", "protein_grams", "carbs_grams", "fat_grams"}
    result = {k: raw[k] for k in keys if k in raw and raw[k] is not None}
    nested = "exercises" if raw["kind"] == "workout" else "foods"
    if nested in raw:
        result[nested] = [{"name": str(x["name"])} for x in raw[nested] if isinstance(x, dict) and "name" in x]
    return result


def project(db, source, kind, duration=True, items=True, sensitive=False):
    if kind == "meal" and duration:
        raise HTTPException(422, "Meal duration is not available")
    result = {"kind": kind, "title": str(source.get("plan_name") or source.get("name") or "Workout Session") if kind == "workout" else str(source.get("meal_type") or "Bữa ăn"),
        "date": str(source.get("date") or ""), "category": "Saman Kinetic" if kind == "workout" else "Bữa ăn"}
    if kind == "workout":
        logs = [x for x in source.get("exercise_logs", []) if x.get("is_completed", True)]
        if duration:
            value = source.get("total_duration_minutes", source.get("duration_minutes"))
            if value is not None: result["duration_minutes"] = value
        if items:
            names = []
            for item in logs:
                slug = str(item.get("exercise_slug") or "Exercise")
                catalog = db["exercises"].find_one({"slug": slug})
                name = str((catalog or {}).get("name") or slug.replace("-", " ").title())
                if name not in names: names.append(name)
            result["exercises"] = [{"name": x} for x in names]
            result["exercise_count"] = len(names)
        if sensitive:
            result["set_count"] = len(logs)
            if source.get("total_volume_kg") is not None: result["load_kg"] = source["total_volume_kg"]
    else:
        if items: result["foods"] = [{"name": str(x["name"])} for x in source.get("foods", []) if x.get("name")]
        if sensitive:
            for output, field in [("calories", "total_calories"), ("protein_grams", "total_protein"), ("carbs_grams", "total_carbs"), ("fat_grams", "total_fat")]:
                if source.get(field) is not None: result[output] = source[field]
    return public_snapshot(result)


def preview(db, user, kind, source_id, duration=True, items=True, sensitive=False):
    col = source_collection(db, kind)
    if not ObjectId.is_valid(source_id): raise HTTPException(404, "Attachment source not found")
    source = col.find_one(dict(owner_query(user, kind), _id=ObjectId(source_id)))
    if source is None: raise HTTPException(404, "Attachment source not found")
    snapshot = project(db, source, kind, duration, items, sensitive)
    digest = hashlib.sha256(json.dumps({"kind": kind, "source_id": source_id, "snapshot": snapshot}, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    return {"source_id": source_id, "preview_hash": digest, "snapshot": snapshot}


def recent(db, user, kind):
    return [preview(db, user, kind, str(doc["_id"]), kind == "workout")
        for doc in source_collection(db, kind).find(owner_query(user, kind)).sort("date", -1).limit(20)]
