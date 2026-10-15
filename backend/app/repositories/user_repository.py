from typing import Optional
from backend.app.database import users_collection
from backend.app.models.user import UserDB, UserProfileInput, UserHealthStats

class UserRepository:
    def __init__(self):
        self.collection = users_collection

    def get_by_email(self, email: str) -> Optional[dict]:
        return self.collection.find_one({"email": email})

    def create_user(self, user_data: dict):
        return self.collection.insert_one(user_data)

    def update_password(self, email: str, new_password_hash: str):
        return self.collection.update_one(
            {"email": email},
            {"$set": {"password": new_password_hash, "auth_provider": "local"}}
        )

    def update_profile_stats_cas(
        self,
        email: str,
        current_user: dict,
        profile_input: UserProfileInput,
        merged_profile: dict,
        stats: UserHealthStats,
        field_sources: Optional[dict] = None,
    ):
        """
        Cập nhật đồng thời Profile và HealthStats với:
        - Atomic dot-notation $set để bảo toàn extra fields và logs.
        - Optimistic Compare-And-Set (CAS) dựa trên snapshot DB thực của calculation inputs (nested vs root).
        - Đồng bộ root mirror fields theo contract hiện tại.
        - Trả về update_one result (matched_count, modified_count).
        """
        CALCULATION_FIELDS = ("age", "gender", "height", "weight", "activity_level", "goal")
        ALLOWED_PROFILE_FIELDS = ("full_name", "age", "gender", "height", "weight", "activity_level", "goal")

        raw_profile = current_user.get("profile")
        existing_profile = raw_profile if isinstance(raw_profile, dict) else None

        if field_sources is None:
            field_sources = {}
            for f in CALCULATION_FIELDS:
                if f in profile_input.model_fields_set and getattr(profile_input, f) is not None:
                    field_sources[f] = "input"
                elif existing_profile is not None and existing_profile.get(f) is not None:
                    field_sources[f] = "nested"
                elif current_user.get(f) is not None:
                    field_sources[f] = "root"
                else:
                    field_sources[f] = "none"

        # 1. CAS Predicate
        query = {"email": email}

        # Parent profile state protection
        if existing_profile is None:
            query["profile"] = {"$in": [None, {}]}
            for f in CALCULATION_FIELDS:
                src = field_sources.get(f)
                if src == "root":
                    query[f] = current_user.get(f)
                elif src == "input" and current_user.get(f) is not None:
                    query[f] = current_user.get(f)
        elif len(existing_profile) == 0:
            query["profile"] = {}
            for f in CALCULATION_FIELDS:
                src = field_sources.get(f)
                if src == "root":
                    query[f] = current_user.get(f)
                elif src == "input" and current_user.get(f) is not None:
                    query[f] = current_user.get(f)
        else:
            for f in CALCULATION_FIELDS:
                src = field_sources.get(f)
                if src == "nested":
                    query[f"profile.{f}"] = existing_profile.get(f)
                elif src == "root":
                    query[f] = current_user.get(f)
                    query[f"profile.{f}"] = {"$in": [None]}
                elif src == "input":
                    if existing_profile.get(f) is not None:
                        query[f"profile.{f}"] = existing_profile.get(f)
                    elif current_user.get(f) is not None:
                        query[f] = current_user.get(f)
                        query[f"profile.{f}"] = {"$in": [None]}
                    else:
                        query[f"profile.{f}"] = {"$in": [None]}

        # Parent health_stats protection if currently missing/null
        existing_stats = current_user.get("health_stats")
        if not isinstance(existing_stats, dict):
            query["health_stats"] = {"$in": [None, {}]}

        # 2. $set fields with atomic dot-notation
        set_fields = {}

        if existing_profile is None:
            # First-time profile initialization
            set_fields["profile"] = {
                k: (merged_profile[k].value if hasattr(merged_profile[k], "value") else merged_profile[k])
                for k in ALLOWED_PROFILE_FIELDS
                if k in merged_profile and merged_profile[k] is not None
            }
        else:
            # Dot-notation to preserve unmanaged subfields (e.g. allergies, notes)
            # Write all merged fields so persisted profile is consistent with stats (including root fallback)
            for k in ALLOWED_PROFILE_FIELDS:
                if k in merged_profile and merged_profile[k] is not None:
                    val = merged_profile[k]
                    if hasattr(val, "value"):
                        val = val.value
                    set_fields[f"profile.{k}"] = val

        # Health stats with dot-notation
        stats_dict = stats.dict() if hasattr(stats, "dict") else stats.model_dump()
        if isinstance(existing_stats, dict):
            for k, v in stats_dict.items():
                if v is not None:
                    set_fields[f"health_stats.{k}"] = v
        else:
            set_fields["health_stats"] = stats_dict

        # Root mirror fields
        for mirror_key in ("gender", "height", "weight", "activity_level", "goal"):
            if mirror_key in merged_profile and merged_profile[mirror_key] is not None:
                val = merged_profile[mirror_key]
                if hasattr(val, "value"):
                    val = val.value
                set_fields[mirror_key] = val

        if "full_name" in profile_input.model_fields_set and profile_input.full_name is not None:
            set_fields["full_name"] = profile_input.full_name
        elif "full_name" in merged_profile and merged_profile["full_name"] is not None:
            set_fields["full_name"] = merged_profile["full_name"]

        return self.collection.update_one(query, {"$set": set_fields})

    def update_profile_stats(self, email: str, profile: UserProfileInput, stats: UserHealthStats):
        """
        Legacy compatibility wrapper.
        """
        user = self.get_by_email(email) or {}
        raw_p = user.get("profile")
        existing_p = raw_p if isinstance(raw_p, dict) else {}
        merged = {
            "age": profile.age if profile.age is not None else existing_p.get("age", user.get("age")),
            "gender": profile.gender.value if hasattr(profile.gender, "value") else (profile.gender or existing_p.get("gender", user.get("gender"))),
            "height": profile.height if profile.height is not None else existing_p.get("height", user.get("height")),
            "weight": profile.weight if profile.weight is not None else existing_p.get("weight", user.get("weight")),
            "activity_level": profile.activity_level.value if hasattr(profile.activity_level, "value") else (profile.activity_level or existing_p.get("activity_level", user.get("activity_level"))),
            "goal": profile.goal.value if hasattr(profile.goal, "value") else (profile.goal or existing_p.get("goal", user.get("goal"))),
            "full_name": profile.full_name or existing_p.get("full_name", user.get("full_name")),
        }
        return self.update_profile_stats_cas(email, user, profile, merged, stats)