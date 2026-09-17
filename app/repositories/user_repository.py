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

    def update_profile_stats(self, email: str, profile: UserProfileInput, stats: UserHealthStats):
        """
        Cập nhật đồng thời Profile (User nhập) và HealthStats (Máy tính)
        """
        update_data = {
            "health_stats": stats.dict(),
            # Giữ lại các trường lẻ để tương thích ngược nếu cần
            "gender": profile.gender,
            "height": profile.height,
            "weight": profile.weight,
            "activity_level": profile.activity_level,
            "goal": profile.goal,
        }
        
        # Only update profile if email is provided in profile
        if profile.email:
            update_data["profile"] = profile.dict()
        else:
            # Create profile dict without email
            profile_dict = profile.dict()
            profile_dict.pop("email", None)
            update_data["profile"] = profile_dict
        
        return self.collection.update_one(
            {"email": email},
            {"$set": update_data}
        )