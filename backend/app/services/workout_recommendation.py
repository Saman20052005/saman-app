from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Mapping, Optional, Sequence


HISTORY_WINDOW_DAYS = 90
MAX_RECOMMENDATIONS = 5
_HISTORY_TIMESTAMP_FIELDS = (
    "start_time",
    "started_at",
    "created_at",
    "date",
    "end_time",
    "finished_at",
)
_MUSCLE_SCORES = {
    "primary": 100,
    "target": 60,
    "secondary": 30,
}
_RECENT_SESSION_PENALTY = 10
_MAX_RECENT_SESSION_PENALTY_COUNT = 3


def _normalized_text(value):
    if not isinstance(value, str):
        return None
    normalized = value.strip().casefold()
    return normalized or None


def _principal_identity(principal):
    if not isinstance(principal, Mapping):
        return None, None
    email = _normalized_text(principal.get("email"))
    raw_id = principal.get("_id")
    if raw_id is None:
        raw_id = principal.get("id")
    owner_id = str(raw_id).strip() if raw_id is not None else ""
    if not email or not owner_id:
        return None, None
    return email, owner_id


def _record_owner_matches(record, email, owner_id):
    if not isinstance(record, Mapping):
        return False
    record_email = _normalized_text(record.get("email"))
    if record_email != email:
        return False
    record_id = record.get("_id")
    if record_id is None:
        record_id = record.get("id")
    return record_id is None or str(record_id).strip() == owner_id


def _history_record_owner_matches(record, email, owner_id):
    if not isinstance(record, Mapping):
        return False
    observed_owner = False
    for key in ("user_id",):
        value = record.get(key)
        if value is not None and str(value).strip():
            observed_owner = True
            if str(value).strip() != owner_id:
                return False
    for key in ("email", "user_email"):
        value = _normalized_text(record.get(key))
        if value:
            observed_owner = True
            if value != email:
                return False
    return observed_owner


def _profile_field(profile, field):
    nested = profile.get("profile")
    if isinstance(nested, Mapping) and nested.get(field) is not None:
        value = nested.get(field)
        source = "profile." + field
    elif profile.get(field) is not None:
        value = profile.get(field)
        source = field
    else:
        return {"status": "unknown", "value": None, "source": None}

    if hasattr(value, "value"):
        value = value.value
    if not isinstance(value, str) or not value.strip():
        return {"status": "unknown", "value": None, "source": source}
    return {"status": "known", "value": value.strip(), "source": source}


def _empty_context(profile_status, profile_reason, history_status, history_reason):
    return {
        "profile_status": profile_status,
        "profile_reason": profile_reason,
        "profile_source": "authorized_profile_reader",
        "profile_fields": {
            "activity_level": {
                "status": "unknown",
                "value": None,
                "source": None,
            },
            "goal": {"status": "unknown", "value": None, "source": None},
        },
        "profile_fields_used": [],
        "unknown_profile_fields": {
            "training_experience": "not_persisted",
            "available_equipment": "not_persisted",
            "injuries": "not_persisted",
            "schedule": "not_persisted",
        },
        "history_status": history_status,
        "history_reason": history_reason,
        "history_source": "authorized_workout_history_reader",
        "history_identity_provenance": (
            "caller_injected_cp_ai03_history_normalizer_and_generated_resolver"
        ),
        "history_window_days": HISTORY_WINDOW_DAYS,
        "history_records_read": 0,
        "history_sessions_in_window": 0,
        "unresolved_history_exercises": 0,
        "recent_exercise_session_counts": {},
        "recent_exercise_provenance": {},
    }


def load_workout_recommendation_context(
    principal: Mapping[str, Any],
    profile_reader: Callable[[str], Optional[Mapping[str, Any]]],
    history_reader: Callable[[str], Sequence[Mapping[str, Any]]],
    history_normalizer: Callable[[Mapping[str, Any], Any], Mapping[str, Any]],
    history_timestamp_parser: Callable[[Any], Optional[datetime]],
    catalog_resolver: Any,
    *,
    now: Optional[datetime] = None,
) -> Dict[str, Any]:
    email, owner_id = _principal_identity(principal)
    if email is None or owner_id is None:
        return _empty_context(
            "unavailable",
            "authenticated_principal_missing_identity",
            "unavailable",
            "authenticated_principal_missing_identity",
        )

    profile_status = "missing"
    profile_reason = None
    profile_fields = {
        "activity_level": {"status": "unknown", "value": None, "source": None},
        "goal": {"status": "unknown", "value": None, "source": None},
    }
    try:
        profile = profile_reader(email)
    except Exception as exc:
        profile = None
        profile_status = "unavailable"
        profile_reason = "profile_read_error:" + type(exc).__name__
    else:
        if profile is not None:
            if not _record_owner_matches(profile, email, owner_id):
                profile_status = "unavailable"
                profile_reason = "profile_owner_mismatch"
            else:
                profile_status = "available"
                profile_fields = {
                    "activity_level": _profile_field(profile, "activity_level"),
                    "goal": _profile_field(profile, "goal"),
                }

    history_status = "unavailable"
    history_reason = None
    history_records = []
    try:
        result = history_reader(owner_id)
        if isinstance(result, (str, bytes)) or not isinstance(result, Sequence):
            raise TypeError("history reader must return a sequence")
        history_records = list(result)
    except Exception as exc:
        history_reason = "history_read_error:" + type(exc).__name__
    else:
        history_records = [
            record
            for record in history_records
            if _history_record_owner_matches(record, email, owner_id)
        ]
        history_status = "empty" if not history_records else "available"

    context = _empty_context(
        profile_status,
        profile_reason,
        history_status,
        history_reason,
    )
    context["profile_fields"] = profile_fields
    context["history_records_read"] = len(history_records)
    if history_status == "unavailable":
        return context

    current_time = now or datetime.now(timezone.utc)
    if current_time.tzinfo is None:
        current_time = current_time.replace(tzinfo=timezone.utc)
    current_time = current_time.astimezone(timezone.utc)
    cutoff = current_time - timedelta(days=HISTORY_WINDOW_DAYS)
    exercise_session_counts = {}
    exercise_provenance = {}
    unresolved_exercises = 0
    sessions_in_window = 0

    for session in history_records:
        if not isinstance(session, Mapping):
            continue
        if not _history_record_owner_matches(session, email, owner_id):
            continue

        raw_timestamp = None
        for field in _HISTORY_TIMESTAMP_FIELDS:
            candidate = session.get(field)
            if candidate is not None and (
                not isinstance(candidate, str) or candidate.strip()
            ):
                raw_timestamp = candidate
                break
        try:
            timestamp = history_timestamp_parser(raw_timestamp)
        except Exception:
            timestamp = None
        if not isinstance(timestamp, datetime):
            continue
        if timestamp.tzinfo is None:
            timestamp = timestamp.replace(tzinfo=timezone.utc)
        timestamp = timestamp.astimezone(timezone.utc)
        if timestamp < cutoff or timestamp > current_time:
            continue

        sessions_in_window += 1
        try:
            normalized = history_normalizer(session, catalog_resolver)
        except Exception as exc:
            context["history_status"] = "unavailable"
            context["history_reason"] = (
                "history_normalization_error:" + type(exc).__name__
            )
            context["recent_exercise_session_counts"] = {}
            context["recent_exercise_provenance"] = {}
            context["history_sessions_in_window"] = sessions_in_window
            return context

        exercises = normalized.get("exercises")
        if not isinstance(exercises, list):
            continue
        resolved_ids = set()
        resolved_provenance = {}
        for exercise in exercises:
            if not isinstance(exercise, Mapping):
                unresolved_exercises += 1
                continue
            canonical_id = exercise.get("canonical_exercise_id")
            if exercise.get("identity_status") != "resolved" or not isinstance(
                canonical_id, str
            ):
                unresolved_exercises += 1
                continue
            resolution = catalog_resolver.resolve(canonical_id)
            metadata = resolution.get("exercise")
            if (
                resolution.get("status") != "resolved"
                or not isinstance(metadata, Mapping)
                or metadata.get("id") != canonical_id
            ):
                unresolved_exercises += 1
                continue
            resolved_ids.add(canonical_id)
            provenance = exercise.get("identity_provenance")
            provenance_kind = (
                provenance.get("kind")
                if isinstance(provenance, Mapping)
                else None
            )
            if isinstance(provenance_kind, str) and provenance_kind.strip():
                resolved_provenance.setdefault(canonical_id, set()).add(
                    provenance_kind
                )

        for canonical_id in resolved_ids:
            exercise_session_counts[canonical_id] = (
                exercise_session_counts.get(canonical_id, 0) + 1
            )
            exercise_provenance.setdefault(canonical_id, set()).update(
                resolved_provenance.get(canonical_id, set())
            )

    context["history_sessions_in_window"] = sessions_in_window
    context["unresolved_history_exercises"] = unresolved_exercises
    context["recent_exercise_session_counts"] = exercise_session_counts
    context["recent_exercise_provenance"] = {
        canonical_id: sorted(provenance)
        for canonical_id, provenance in exercise_provenance.items()
    }
    return context


def _request_values(values, field_name):
    if values is None:
        return set()
    if isinstance(values, (str, bytes)) or not isinstance(values, Sequence):
        raise ValueError(field_name + " must be a sequence of strings")
    normalized = set()
    for value in values:
        item = _normalized_text(value)
        if item is None:
            raise ValueError(field_name + " contains an invalid value")
        normalized.add(item)
    return normalized


def _valid_candidate_metadata(candidate, resolver):
    exercise_id = candidate.get("id")
    slug = candidate.get("slug")
    if not isinstance(exercise_id, str) or not exercise_id.strip():
        return None
    if not isinstance(slug, str) or not slug.strip():
        return None
    resolution = resolver.resolve(exercise_id, slug)
    metadata = resolution.get("exercise")
    if (
        resolution.get("status") != "resolved"
        or not isinstance(metadata, Mapping)
        or metadata.get("id") != exercise_id
        or metadata.get("slug") != slug
    ):
        return None
    if not isinstance(metadata.get("name"), str) or not metadata["name"].strip():
        return None
    return metadata


def _muscle_match(candidate, requested_muscles):
    muscle_group = _normalized_text(candidate.get("muscleGroup"))
    targets = candidate.get("targetMuscles")
    secondary = candidate.get("secondaryMuscles")
    if (
        muscle_group is None
        or not isinstance(targets, list)
        or not isinstance(secondary, list)
        or any(_normalized_text(item) is None for item in targets + secondary)
    ):
        return None
    if muscle_group in requested_muscles:
        return "primary", _MUSCLE_SCORES["primary"]
    if any(_normalized_text(item) in requested_muscles for item in targets):
        return "target", _MUSCLE_SCORES["target"]
    if any(_normalized_text(item) in requested_muscles for item in secondary):
        return "secondary", _MUSCLE_SCORES["secondary"]
    return None


def recommend_workouts(
    context: Mapping[str, Any],
    catalog_resolver: Any,
    *,
    requested_muscle_groups=None,
    available_equipment=None,
    limit=MAX_RECOMMENDATIONS,
) -> Dict[str, Any]:
    requested_muscles = _request_values(
        requested_muscle_groups, "requested_muscle_groups"
    )
    equipment_filter = (
        None
        if available_equipment is None
        else _request_values(available_equipment, "available_equipment")
    )
    if type(limit) is not int:
        raise ValueError("limit must be an integer")
    limit = min(MAX_RECOMMENDATIONS, max(0, limit))

    result = {
        "status": "ok",
        "reason": "ranked_from_verified_catalog",
        "recommendations": [],
        "personalization_level": "general",
        "clarification_required": available_equipment is None,
        "clarification_fields": (
            ["available_equipment"] if available_equipment is None else []
        ),
        "profile_status": context.get("profile_status", "unavailable"),
        "profile_reason": context.get("profile_reason"),
        "history_status": context.get("history_status", "unavailable"),
        "history_reason": context.get("history_reason"),
        "history_window_days": HISTORY_WINDOW_DAYS,
        "unresolved_history_exercises": context.get(
            "unresolved_history_exercises", 0
        ),
        "unknown_profile_fields": dict(
            context.get("unknown_profile_fields", {})
        ),
    }
    if available_equipment is None:
        result.update(
            {
                "status": "limited_context",
                "reason": "available_equipment_unknown",
            }
        )
    if requested_muscles or available_equipment is not None:
        result["personalization_level"] = "request"

    history_counts = context.get("recent_exercise_session_counts", {})
    if (
        context.get("history_status") == "available"
        and isinstance(history_counts, Mapping)
        and any(count > 0 for count in history_counts.values())
    ):
        result["personalization_level"] = (
            "request_and_history"
            if result["personalization_level"] == "request"
            else "history"
        )

    if not getattr(catalog_resolver, "available", False):
        result.update(
            {
                "status": "catalog_unavailable",
                "reason": "generated_catalog_unavailable",
            }
        )
        return result
    try:
        catalog_records = catalog_resolver.list_exercises()
    except Exception as exc:
        result.update(
            {
                "status": "catalog_unavailable",
                "reason": "generated_catalog_read_error:" + type(exc).__name__,
            }
        )
        return result
    if not isinstance(catalog_records, Sequence) or isinstance(
        catalog_records, (str, bytes)
    ):
        result.update(
            {
                "status": "catalog_unavailable",
                "reason": "generated_catalog_list_invalid",
            }
        )
        return result
    if not catalog_records:
        result.update({"status": "no_candidates", "reason": "catalog_empty"})
        return result

    candidates = []
    seen_ids = set()
    for record in catalog_records:
        if not isinstance(record, Mapping):
            continue
        metadata = _valid_candidate_metadata(record, catalog_resolver)
        if metadata is None:
            continue
        canonical_id = metadata["id"]
        if canonical_id in seen_ids:
            continue
        seen_ids.add(canonical_id)

        muscle_match = None
        if requested_muscles:
            muscle_match = _muscle_match(metadata, requested_muscles)
            if muscle_match is None:
                continue

        equipment = metadata.get("equipment")
        if equipment_filter is not None:
            if not isinstance(equipment, list) or any(
                _normalized_text(item) is None for item in equipment
            ):
                continue
            if not {
                _normalized_text(item) for item in equipment
            }.issubset(equipment_filter):
                continue

        match_type, muscle_score = muscle_match or (None, 0)
        if context.get("history_status") != "available":
            recent_sessions = 0
        else:
            raw_count = history_counts.get(canonical_id, 0)
            recent_sessions = (
                raw_count
                if isinstance(raw_count, int) and not isinstance(raw_count, bool)
                else 0
            )
            recent_sessions = max(0, recent_sessions)
        penalty_count = min(
            recent_sessions, _MAX_RECENT_SESSION_PENALTY_COUNT
        )
        history_penalty = -_RECENT_SESSION_PENALTY * penalty_count
        score = muscle_score + history_penalty
        reason_codes = []
        if match_type:
            reason_codes.append("requested_muscle_" + match_type + "_match")
        if equipment_filter is not None:
            reason_codes.append("available_equipment_filter")
        if recent_sessions:
            reason_codes.append("recent_history_variety")
        if not reason_codes:
            reason_codes.append("general_catalog_baseline")
        candidates.append(
            {
                "canonical_id": canonical_id,
                "slug": metadata["slug"],
                "score": score,
                "match_type": match_type,
                "muscle_score": muscle_score,
                "recent_sessions": recent_sessions,
                "history_penalty": history_penalty,
                "reason_codes": reason_codes,
                "history_provenance": list(
                    context.get("recent_exercise_provenance", {}).get(
                        canonical_id, []
                    )
                )
                if recent_sessions
                else [],
                "exercise": metadata,
            }
        )

    if not candidates:
        result.update(
            {
                "status": "no_candidates",
                "reason": (
                    "no_candidates_match_explicit_filters"
                    if requested_muscles or equipment_filter is not None
                    else "no_valid_canonical_candidates"
                ),
            }
        )
        return result

    candidates.sort(key=lambda candidate: (-candidate["score"], candidate["canonical_id"]))
    score_counts = {}
    for candidate in candidates:
        score_counts[candidate["score"]] = score_counts.get(candidate["score"], 0) + 1

    recommendations = []
    for rank, candidate in enumerate(candidates[:limit], start=1):
        reasons = list(candidate["reason_codes"])
        if score_counts[candidate["score"]] > 1:
            reasons.append("canonical_id_tiebreak")
        recommendations.append(
            {
                "canonical_id": candidate["canonical_id"],
                "slug": candidate["slug"],
                "rank": rank,
                "score": candidate["score"],
                "score_components": {
                    "muscle_match": candidate["muscle_score"],
                    "recent_session_penalty": candidate["history_penalty"],
                    "recent_sessions_in_window": candidate["recent_sessions"],
                    "history_provenance": candidate["history_provenance"],
                },
                "reason_codes": reasons,
                "exercise": candidate["exercise"],
            }
        )
    result["recommendations"] = recommendations
    return result
