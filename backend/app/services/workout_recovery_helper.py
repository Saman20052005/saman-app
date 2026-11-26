"""Workout recovery and rolling anomaly calculation helpers.

Extracted pure functions for 72-hour muscle fatigue recovery calculation
and rolling anomaly tag detection from exercise rep timelines.
"""

from collections import defaultdict
from datetime import datetime, timezone
import math
from typing import Any, Dict, List, Optional, Tuple

CANONICAL_MUSCLE_GROUPS: Tuple[str, ...] = ("chest", "back", "legs", "shoulders", "arms", "core")

MUSCLE_GROUP_ALIASES: Dict[str, str] = {
    "chest": "chest",
    "pectorals": "chest",
    "pecs": "chest",
    "upper_chest": "chest",
    "lower_chest": "chest",
    "inner_chest": "chest",
    "back": "back",
    "lats": "back",
    "latissimus": "back",
    "latissimus_dorsi": "back",
    "upper_back": "back",
    "lower_back": "back",
    "middle_back": "back",
    "traps": "back",
    "trapezius": "back",
    "rhomboids": "back",
    "erector_spinae": "back",
    "legs": "legs",
    "leg": "legs",
    "quads": "legs",
    "quadriceps": "legs",
    "hamstrings": "legs",
    "glutes": "legs",
    "gluteus": "legs",
    "calves": "legs",
    "calf": "legs",
    "lower_body": "legs",
    "thighs": "legs",
    "adductors": "legs",
    "abductors": "legs",
    "hip_flexors": "legs",
    "shoulders": "shoulders",
    "shoulder": "shoulders",
    "delts": "shoulders",
    "deltoids": "shoulders",
    "front_delts": "shoulders",
    "side_delts": "shoulders",
    "rear_delts": "shoulders",
    "lateral_delts": "shoulders",
    "anterior_deltoid": "shoulders",
    "posterior_deltoid": "shoulders",
    "arms": "arms",
    "arm": "arms",
    "biceps": "arms",
    "triceps": "arms",
    "forearms": "arms",
    "forearm": "arms",
    "brachialis": "arms",
    "wrists": "arms",
    "core": "core",
    "abs": "core",
    "abdominals": "core",
    "obliques": "core",
    "rectus_abdominis": "core",
    "transverse_abdominis": "core",
    "lower_abs": "core",
}

FALLBACK_SLUG_MUSCLE_RULES: Tuple[Tuple[str, Tuple[str, ...]], ...] = (
    (
        "core",
        (
            "leg-raise",
            "leg_raise",
            "plank",
            "crunch",
            "sit-up",
            "situp",
            "oblique",
            "russian-twist",
            "dead-bug",
            "ab-",
            "abs",
            "core",
        ),
    ),
    (
        "legs",
        (
            "leg-curl",
            "leg_curl",
            "hamstring-curl",
            "hamstring_curl",
            "nordic-curl",
        ),
    ),
    (
        "arms",
        (
            "curl",
            "tricep",
            "bicep",
            "pushdown",
            "skullcrusher",
            "skull-crusher",
            "preacher",
            "forearm",
            "wrist",
        ),
    ),
    (
        "chest",
        (
            "bench",
            "chest",
            "pec",
            "fly",
            "push-up",
            "pushup",
            "incline-press",
            "decline-press",
            "crossover",
        ),
    ),
    (
        "shoulders",
        (
            "face-pull",
            "face_pull",
            "lateral-raise",
            "lateral_raise",
            "front-raise",
            "rear-delt",
            "shoulder",
            "overhead-press",
            "overhead_press",
            "military-press",
            "arnold-press",
            "upright-row",
            "shrug",
            "delt",
        ),
    ),
    (
        "legs",
        (
            "squat",
            "lunge",
            "leg-press",
            "leg_press",
            "leg-extension",
            "leg-",
            "leg_",
            "calf",
            "calves",
            "glute",
            "hip-thrust",
            "bulgarian",
            "step-up",
            "hamstring",
            "quad",
            "rdl",
        ),
    ),
    (
        "back",
        (
            "row",
            "pulldown",
            "pull-down",
            "pull-up",
            "pullup",
            "chin-up",
            "chinup",
            "deadlift",
            "lat-",
            "lat_",
            "back",
            "hyperextension",
            "good-morning",
        ),
    ),
    ("shoulders", ("press",)),
)


def normalize_muscle_group(raw: Any) -> Optional[str]:
    if not isinstance(raw, str):
        return None
    cleaned = raw.strip().lower().replace("-", "_").replace(" ", "_")
    if not cleaned:
        return None
    if cleaned in MUSCLE_GROUP_ALIASES:
        return MUSCLE_GROUP_ALIASES[cleaned]
    if "pec" in cleaned or "chest" in cleaned:
        return "chest"
    if "lat" in cleaned or "trap" in cleaned or "rhomb" in cleaned or "back" in cleaned:
        return "back"
    if "quad" in cleaned or "hamstring" in cleaned or "glute" in cleaned or "calf" in cleaned or "calves" in cleaned or "leg" in cleaned:
        return "legs"
    if "delt" in cleaned or "shoulder" in cleaned:
        return "shoulders"
    if "bicep" in cleaned or "tricep" in cleaned or "forearm" in cleaned or "arm" in cleaned:
        return "arms"
    if "ab" in cleaned or "oblique" in cleaned or "core" in cleaned:
        return "core"
    return None


def resolve_exercise_muscles_pure(
    exercise_id: str,
    exercise_slug: str,
    exercise_muscle_cache: Optional[Dict[str, Tuple[List[str], List[str]]]] = None,
) -> Dict[str, float]:
    """Resolve target muscle groups using cache or fallback slug rules."""
    muscles: Dict[str, float] = {}
    key = (exercise_id or "").strip() or (exercise_slug or "").strip()

    if exercise_muscle_cache and key in exercise_muscle_cache:
        target, secondary = exercise_muscle_cache[key]
        if target:
            for tm in target:
                norm = normalize_muscle_group(tm)
                if norm:
                    muscles[norm] = 1.0
                    break
        if secondary:
            for sm in secondary:
                norm = normalize_muscle_group(sm)
                if norm and norm not in muscles:
                    muscles[norm] = 0.4
        if muscles:
            return muscles

    combined = f"{exercise_slug} {exercise_id}".lower().strip()
    if combined:
        for muscle_group, keywords in FALLBACK_SLUG_MUSCLE_RULES:
            if any(kw in combined for kw in keywords):
                muscles[muscle_group] = 1.0
                break

    return muscles


def parse_utc_datetime(val: Any) -> Optional[datetime]:
    if val is None:
        return None
    if isinstance(val, datetime):
        if val.tzinfo is None:
            return val.replace(tzinfo=timezone.utc)
        return val.astimezone(timezone.utc)
    if isinstance(val, str):
        try:
            dt = datetime.fromisoformat(val.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                return dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except Exception:
            return None
    return None


def format_utc_iso(dt_val: Optional[datetime]) -> Optional[str]:
    if dt_val is None:
        return None
    if isinstance(dt_val, str):
        return dt_val
    if isinstance(dt_val, datetime):
        if dt_val.tzinfo is None:
            dt_val = dt_val.replace(tzinfo=timezone.utc)
        else:
            dt_val = dt_val.astimezone(timezone.utc)
        return dt_val.isoformat().replace("+00:00", "Z")
    return None


def calculate_muscle_recovery_load(
    sessions: List[dict],
    now_utc: datetime,
    exercise_muscle_cache: Optional[Dict[str, Tuple[List[str], List[str]]]] = None,
) -> Dict[str, Any]:
    """Calculate 0-100% muscle recovery across 6 canonical muscle groups from the last 72 hours.

    100% matches workout.py lines 1877-1977.
    """
    if now_utc.tzinfo is None:
        now_utc = now_utc.replace(tzinfo=timezone.utc)
    else:
        now_utc = now_utc.astimezone(timezone.utc)

    set_type_multiplier = {
        "warmup": 0.3,
        "normal": 1.0,
        "drop": 1.15,
        "failure": 1.25,
    }
    base_points_per_set = 10.5
    fatigue_scale = 85.0
    decay_exponent = 1.45

    muscle_fatigue_load: Dict[str, float] = {m: 0.0 for m in CANONICAL_MUSCLE_GROUPS}
    muscle_last_trained: Dict[str, Optional[datetime]] = {m: None for m in CANONICAL_MUSCLE_GROUPS}
    muscle_recent_sets: Dict[str, int] = {m: 0 for m in CANONICAL_MUSCLE_GROUPS}

    for session_doc in sessions:
        session_dt = (
            parse_utc_datetime(session_doc.get("finished_at"))
            or parse_utc_datetime(session_doc.get("end_time"))
            or parse_utc_datetime(session_doc.get("started_at"))
            or parse_utc_datetime(session_doc.get("start_time"))
            or parse_utc_datetime(session_doc.get("created_at"))
        )
        if session_dt is None:
            continue

        hours_ago = (now_utc - session_dt).total_seconds() / 3600.0
        if hours_ago < 0.0:
            hours_ago = 0.0
        if hours_ago > 72.0:
            continue

        time_decay = max(0.0, 1.0 - hours_ago / 72.0) ** decay_exponent
        raw_logs = session_doc.get("exercise_logs") or session_doc.get("completed_exercises") or []

        for item in raw_logs:
            if not isinstance(item, dict):
                continue
            is_comp = item.get("is_completed") if item.get("is_completed") is not None else item.get("isCompleted", True)
            if not is_comp:
                continue

            ex_id = str(item.get("exercise_id") or item.get("exerciseId") or "").strip()
            ex_slug = str(item.get("exercise_slug") or item.get("exerciseSlug") or "").strip()
            muscles = resolve_exercise_muscles_pure(ex_id, ex_slug, exercise_muscle_cache)
            if not muscles:
                continue

            st = str(item.get("set_type") or item.get("setType") or "normal").lower()
            if st not in set_type_multiplier:
                st = "normal"
            type_mult = set_type_multiplier.get(st, 1.0)

            raw_rpe = item.get("rpe")
            if raw_rpe is not None:
                try:
                    rpe_mult = max(0.7, min(1.3, float(raw_rpe) / 8.0))
                except (ValueError, TypeError):
                    rpe_mult = 1.0
            else:
                rpe_mult = 1.0

            set_load = base_points_per_set * type_mult * rpe_mult * time_decay

            for muscle_name, muscle_factor in muscles.items():
                if muscle_name not in muscle_fatigue_load:
                    continue
                muscle_fatigue_load[muscle_name] += set_load * muscle_factor
                muscle_recent_sets[muscle_name] += 1
                prev_dt = muscle_last_trained[muscle_name]
                if prev_dt is None or session_dt > prev_dt:
                    muscle_last_trained[muscle_name] = session_dt

    muscles_out: List[dict] = []
    for muscle_name in CANONICAL_MUSCLE_GROUPS:
        raw_load = muscle_fatigue_load[muscle_name]
        fatigue = 100.0 * (1.0 - math.exp(-raw_load / fatigue_scale)) if raw_load > 0.0 else 0.0
        recovery_percent = int(round(max(0.0, min(100.0, 100.0 - fatigue))))
        if recovery_percent >= 80:
            status = "ready"
        elif recovery_percent >= 50:
            status = "recovering"
        else:
            status = "fatigued"

        last_dt = muscle_last_trained[muscle_name]
        hours_since = (
            round(max(0.0, (now_utc - last_dt).total_seconds() / 3600.0), 1)
            if last_dt is not None
            else None
        )

        muscles_out.append({
            "muscleGroup": muscle_name,
            "recoveryPercent": recovery_percent,
            "status": status,
            "lastTrainedAt": format_utc_iso(last_dt),
            "hoursSinceLastTrained": hours_since,
            "recentSets": muscle_recent_sets[muscle_name],
        })

    return {
        "window_hours": 72,
        "muscles": muscles_out,
        "generatedAt": format_utc_iso(now_utc),
    }


def compact_muscle_recovery_for_ai(recovery_data: dict) -> dict:
    """Return an ultra-compact summary of recovery {group: {"recovery_pct": int, "status": str}}."""
    if not isinstance(recovery_data, dict):
        return {}
    muscles = recovery_data.get("muscles") or []
    compact = {}
    for m in muscles:
        group = m.get("muscleGroup")
        if group:
            compact[group] = {
                "recovery_pct": m.get("recoveryPercent", 100),
                "status": m.get("status", "ready"),
            }
    return compact


def compute_rolling_anomaly_tags(
    sessions: List[dict],
    *,
    recovery_compact: Optional[dict] = None,
    min_visibility: float = 0.6,
) -> List[str]:
    """Detect up to 4 concise Vietnamese anomaly tags from recent sessions.

    Considers rep_timeline with visibility_confidence >= min_visibility and CV form summaries.
    No hallucinations; only supported by factual data.
    """
    if not sessions:
        return []

    tags: List[str] = []

    # 1. Inspect recent sessions (up to 10) for recurring issues across sessions
    # Track per-session exercise issues
    session_exercise_issues: List[Dict[str, Dict[str, List[int]]]] = []
    # session_exercise_issues[i][slug][issue_type] = list of rep_indices

    for s in sessions[:10]:
        logs = s.get("exercise_logs") or s.get("completed_exercises") or []
        ex_map: Dict[str, Dict[str, List[int]]] = defaultdict(lambda: defaultdict(list))
        for item in logs:
            if not isinstance(item, dict):
                continue
            slug = str(item.get("exercise_slug") or item.get("exercise_id") or "exercise").strip()
            rep_tl = item.get("rep_timeline") or item.get("repTimeline")
            if isinstance(rep_tl, list):
                for r in rep_tl:
                    if not isinstance(r, dict):
                        continue
                    vis = float(r.get("visibility_confidence") if r.get("visibility_confidence") is not None else r.get("visibilityConfidence", 1.0))
                    if vis < min_visibility:
                        continue
                    issue = r.get("issue_type") or r.get("issueType")
                    if issue and issue != "none":
                        rep_idx = int(r.get("rep_index", r.get("repIndex", 0)) or 0)
                        ex_map[slug][issue].append(rep_idx)
            else:
                cv_sum = item.get("cv_form_summary") or item.get("cvFormSummary")
                if isinstance(cv_sum, dict):
                    fast = int(cv_sum.get("fast_reps") or 0)
                    if fast >= 2:
                        ex_map[slug]["tooFast"].extend([0] * fast)
        session_exercise_issues.append(ex_map)

    # Check recurring issue across 2+ consecutive sessions
    # Check if latest session (index 0) and prior session (index 1) share an issue
    if len(session_exercise_issues) >= 2:
        latest = session_exercise_issues[0]
        prior = session_exercise_issues[1]
        for slug, issues in latest.items():
            if slug in prior:
                for issue, rep_indices in issues.items():
                    if issue in prior[slug] and len(rep_indices) >= 2 and len(prior[slug][issue]) >= 2:
                        min_rep = min(rep_indices) if rep_indices and any(r > 0 for r in rep_indices) else None
                        if min_rep and min_rep >= 4:
                            tag = f"2+ buổi liên tiếp bài {slug} bị lỗi '{issue}' (đặc biệt từ rep {min_rep} trở đi)"
                        else:
                            tag = f"2+ buổi liên tiếp bài {slug} bị lỗi '{issue}'"
                        if tag not in tags:
                            tags.append(tag)
                            break
            if len(tags) >= 2:
                break

    # 2. Check latest session high error rate (>= 40% reps faulty and >= 2 reps)
    if sessions:
        latest_session = sessions[0]
        logs = latest_session.get("exercise_logs") or latest_session.get("completed_exercises") or []
        for item in logs:
            if not isinstance(item, dict):
                continue
            slug = str(item.get("exercise_slug") or item.get("exercise_id") or "exercise").strip()
            rep_tl = item.get("rep_timeline") or item.get("repTimeline")
            if isinstance(rep_tl, list) and rep_tl:
                valid_reps_count = 0
                issue_counts: Dict[str, int] = defaultdict(int)
                for r in rep_tl:
                    if not isinstance(r, dict):
                        continue
                    vis = float(r.get("visibility_confidence") if r.get("visibility_confidence") is not None else r.get("visibilityConfidence", 1.0))
                    if vis < min_visibility:
                        continue
                    valid_reps_count += 1
                    issue = r.get("issue_type") or r.get("issueType")
                    if issue and issue != "none":
                        issue_counts[issue] += 1
                if valid_reps_count >= 2:
                    for issue, cnt in issue_counts.items():
                        if cnt >= 2 and (cnt / valid_reps_count) >= 0.4:
                            tag = f"Buổi gần nhất bài {slug} có {cnt}/{valid_reps_count} rep bị '{issue}' (tin cậy CV >= {min_visibility})"
                            if tag not in tags:
                                tags.append(tag)
                            break
            else:
                cv_sum = item.get("cv_form_summary") or item.get("cvFormSummary")
                if isinstance(cv_sum, dict):
                    fast = int(cv_sum.get("fast_reps") or 0)
                    total = int(cv_sum.get("valid_reps") or 0) + fast
                    if total >= 2 and fast >= 2 and (fast / total) >= 0.4:
                        tag = f"Buổi gần nhất bài {slug} có {fast}/{total} rep bị 'tooFast' (tin cậy CV >= {min_visibility})"
                        if tag not in tags:
                            tags.append(tag)

    # 3. Check muscle fatigue load vs recovery (< 50% recovery_pct)
    if recovery_compact and isinstance(recovery_compact, dict):
        for group, info in recovery_compact.items():
            if isinstance(info, dict):
                pct = info.get("recovery_pct", 100)
                if pct < 50:
                    tag = f"Nhóm cơ {group.capitalize()} đang mệt ({pct}%) trong 72h gần nhất — cân nhắc giảm tải hoặc tập kỹ thuật"
                    if tag not in tags:
                        tags.append(tag)
                    if len(tags) >= 4:
                        break

    return tags[:4]
