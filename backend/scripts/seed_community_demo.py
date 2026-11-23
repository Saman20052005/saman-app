"""
Demo Seeding Script for Saman Community Ecosystem.

Provides idempotent upsert of rich demo data (users, stories, posts, Q&A answers,
comments, likes, follows, DM conversations & messages) flagged with `is_demo_seed: True`.
Also supports safe, clean removal (`clean_demo_data` / `--clean`) targeting ONLY
documents with `{"is_demo_seed": True}` without touching real user data.

Usage:
    python -m backend.scripts.seed_community_demo [--clean] [--for-email EMAIL] [--for-user-id UID]
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional
from bson import ObjectId


# ---------------------------------------------------------------------------
# Deterministic IDs for idempotent demo data
# ---------------------------------------------------------------------------

DEMO_USER_COACH_ID = "demo_coach_kinetic"
DEMO_USER_GYM_ID = "demo_gym_beast"
DEMO_USER_CHEF_ID = "demo_chef_healthy"
DEMO_USER_RUNNER_ID = "demo_runner_longdist"
DEMO_USER_YOGA_ID = "demo_yoga_recovery"
DEMO_USER_NEWBIE_ID = "demo_newbie_journey"

DEMO_USER_IDS = [
    DEMO_USER_COACH_ID,
    DEMO_USER_GYM_ID,
    DEMO_USER_CHEF_ID,
    DEMO_USER_RUNNER_ID,
    DEMO_USER_YOGA_ID,
    DEMO_USER_NEWBIE_ID,
]

DEMO_USERS: List[Dict[str, Any]] = [
    {
        "_id": DEMO_USER_COACH_ID,
        "id": DEMO_USER_COACH_ID,
        "email": "coach.kinetic@saman.demo",
        "name": "HLV Minh Kinetic",
        "full_name": "HLV Minh Kinetic",
        "handle": "minh_kinetic",
        "avatar_url": "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400",
        "avatar": "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400",
        "title": "Chuyên gia Kinetic & Phục hồi",
        "is_verified": True,
        "bio": "HLV Chuyển động Kinetic & Phục hồi chức năng khớp Saman. Tối ưu sinh cơ học và phòng tránh chấn thương.",
        "interest_topics": ["#Kinetic", "#PhucHoi", "#GiaiPhau"],
        "is_demo_seed": True,
    },
    {
        "_id": DEMO_USER_GYM_ID,
        "id": DEMO_USER_GYM_ID,
        "email": "gym.beast@saman.demo",
        "name": "Hải Nam Power",
        "full_name": "Hải Nam Power",
        "handle": "hainam_lift",
        "avatar_url": "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400",
        "avatar": "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400",
        "title": "Vận động viên Thể hình",
        "is_verified": True,
        "bio": "Ăn sạch - Tập nặng - Kỷ luật mỗi ngày. 6 năm theo đuổi Hypertrophy & Tăng cơ giảm mỡ chuẩn khoa học.",
        "interest_topics": ["#GymLife", "#TangCo", "#Powerlifting"],
        "is_demo_seed": True,
    },
    {
        "_id": DEMO_USER_CHEF_ID,
        "id": DEMO_USER_CHEF_ID,
        "email": "chef.healthy@saman.demo",
        "name": "Lan Anh EatClean",
        "full_name": "Lan Anh EatClean",
        "handle": "lananh_eatclean",
        "avatar_url": "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400",
        "avatar": "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400",
        "title": "Bếp Trưởng Dinh Dưỡng",
        "is_verified": False,
        "bio": "Chia sẻ công thức meal-prep ngon, đủ macro, nấu dưới 20 phút. Ăn ngon mà vẫn thon gọn cùng Saman!",
        "interest_topics": ["#EatClean", "#MealPrep", "#HealthyFood"],
        "is_demo_seed": True,
    },
    {
        "_id": DEMO_USER_RUNNER_ID,
        "id": DEMO_USER_RUNNER_ID,
        "email": "runner.longdist@saman.demo",
        "name": "Tuấn Kiệt Marathon",
        "full_name": "Tuấn Kiệt Marathon",
        "handle": "kiet_runner",
        "avatar_url": "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400",
        "avatar": "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400",
        "title": "Chân chạy 42km",
        "is_verified": True,
        "bio": "Sub 3:15 Marathon finisher. Đam mê nhịp tim Zone 2 và những cung đường mòn dài bất tận.",
        "interest_topics": ["#ChayBo", "#Marathon", "#Cadence"],
        "is_demo_seed": True,
    },
    {
        "_id": DEMO_USER_YOGA_ID,
        "id": DEMO_USER_YOGA_ID,
        "email": "yoga.recovery@saman.demo",
        "name": "Mai Thảo Flow",
        "full_name": "Mai Thảo Flow",
        "handle": "maithao_yoga",
        "avatar_url": "https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400",
        "avatar": "https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400",
        "title": "HLV Yoga & Thở",
        "is_verified": False,
        "bio": "Hít thở sâu, tâm an yên, cơ thể dẻo dai. Lớp Vinyasa & Yin Yoga phục hồi hệ thần kinh mỗi tối.",
        "interest_topics": ["#YogaFlow", "#DanCo", "#ThienDinh"],
        "is_demo_seed": True,
    },
    {
        "_id": DEMO_USER_NEWBIE_ID,
        "id": DEMO_USER_NEWBIE_ID,
        "email": "newbie.journey@saman.demo",
        "name": "Bảo Ngọc Rookie",
        "full_name": "Bảo Ngọc Rookie",
        "handle": "ngoc_newbie",
        "avatar_url": "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400",
        "avatar": "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400",
        "title": "Hành trình khởi đầu",
        "is_verified": False,
        "bio": "Dân văn phòng bắt đầu tập luyện từ con số 0. Mục tiêu giảm 5kg và tạm biệt đau lưng gáy!",
        "interest_topics": ["#KhoiDau", "#TuTap", "#GiamCan"],
        "is_demo_seed": True,
    },
]

DEMO_COLLECTIONS = [
    "users",
    "community_posts",
    "community_stories",
    "community_comments",
    "community_answers",
    "community_answer_votes",
    "community_follows",
    "community_interactions",
    "community_conversations",
    "community_messages",
    "community_user_settings",
]


def _make_pair_key(user_a: str, user_b: str) -> str:
    ordered = sorted([str(user_a), str(user_b)])
    return f"{ordered[0]}::{ordered[1]}"


def seed_demo_data(
    db: Any,
    *,
    for_user_id: Optional[str] = None,
    for_email: Optional[str] = None,
) -> Dict[str, int]:
    """
    Idempotently seeds community demo users, stories, posts, answers, comments,
    interactions, and DM conversations/messages. All records are tagged with `is_demo_seed: True`.
    """
    if db is None:
        raise RuntimeError("Database instance is unavailable")

    now = datetime.now(timezone.utc)
    stats: Dict[str, int] = {c: 0 for c in DEMO_COLLECTIONS}

    # -----------------------------------------------------------------------
    # 1. Seed 6 Demo Users & Default Settings
    # -----------------------------------------------------------------------
    users_col = db["users"]
    settings_col = db["community_user_settings"]

    for u in DEMO_USERS:
        uid = u["_id"]
        users_col.update_one(
            {"_id": uid},
            {"$set": dict(u, updated_at=now), "$setOnInsert": {"created_at": now}},
            upsert=True,
        )
        stats["users"] += 1

        settings_doc = {
            "_id": uid,
            "user_id": uid,
            "is_private_account": False,
            "who_can_dm": "everyone",
            "who_can_comment": "everyone",
            "who_can_reply_story": "everyone",
            "allow_mentions": "everyone",
            "hide_like_counts": False,
            "show_activity_status": True,
            "auto_prompt_share_workout": True,
            "auto_prompt_share_meal": True,
            "muted_keywords": [],
            "is_demo_seed": True,
            "updated_at": now,
        }
        settings_col.update_one(
            {"user_id": uid},
            {"$set": settings_doc, "$setOnInsert": {"created_at": now}},
            upsert=True,
        )
        stats["community_user_settings"] += 1

    # -----------------------------------------------------------------------
    # 2. Seed Follow Relationships among Demo Users
    # -----------------------------------------------------------------------
    follows_col = db["community_follows"]
    follow_pairs = [
        (DEMO_USER_NEWBIE_ID, DEMO_USER_COACH_ID),
        (DEMO_USER_NEWBIE_ID, DEMO_USER_CHEF_ID),
        (DEMO_USER_GYM_ID, DEMO_USER_COACH_ID),
        (DEMO_USER_RUNNER_ID, DEMO_USER_YOGA_ID),
        (DEMO_USER_CHEF_ID, DEMO_USER_GYM_ID),
        (DEMO_USER_YOGA_ID, DEMO_USER_COACH_ID),
    ]
    for follower_id, following_id in follow_pairs:
        f_doc = {
            "follower_id": follower_id,
            "following_id": following_id,
            "created_at": now - timedelta(days=2),
            "is_demo_seed": True,
        }
        follows_col.update_one(
            {"follower_id": follower_id, "following_id": following_id},
            {"$set": f_doc},
            upsert=True,
        )
        stats["community_follows"] += 1

    # -----------------------------------------------------------------------
    # 3. Seed 5 Active Stories (24h lifespan)
    # -----------------------------------------------------------------------
    stories_col = db["community_stories"]
    demo_stories = [
        {
            "_id": "demo_story_01",
            "id": "demo_story_01",
            "user_id": DEMO_USER_COACH_ID,
            "author": {
                "id": DEMO_USER_COACH_ID,
                "name": "HLV Minh Kinetic",
                "avatar_url": DEMO_USERS[0]["avatar_url"],
                "title": "Chuyên gia Kinetic & Phục hồi",
                "is_verified": True,
            },
            "media_type": "photo",
            "media_url": "https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=800",
            "caption": "Khởi động kỹ khớp cổ chân & háng trước khi squat sáng nay! 🏋️‍♂️",
            "background_color": "#1A1A24",
            "privacy": "public",
            "is_deleted": False,
            "created_at": now - timedelta(hours=2),
            "expires_at": now + timedelta(hours=22),
            "is_demo_seed": True,
        },
        {
            "_id": "demo_story_02",
            "id": "demo_story_02",
            "user_id": DEMO_USER_CHEF_ID,
            "author": {
                "id": DEMO_USER_CHEF_ID,
                "name": "Lan Anh EatClean",
                "avatar_url": DEMO_USERS[2]["avatar_url"],
                "title": "Bếp Trưởng Dinh Dưỡng",
                "is_verified": False,
            },
            "media_type": "photo",
            "media_url": "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800",
            "caption": "Tô salad ức gà áp chảo sốt sữa chua Hy Lạp chuẩn 35g protein 🥗✨",
            "background_color": "#16281E",
            "privacy": "public",
            "is_deleted": False,
            "created_at": now - timedelta(hours=5),
            "expires_at": now + timedelta(hours=19),
            "is_demo_seed": True,
        },
        {
            "_id": "demo_story_03",
            "id": "demo_story_03",
            "user_id": DEMO_USER_RUNNER_ID,
            "author": {
                "id": DEMO_USER_RUNNER_ID,
                "name": "Tuấn Kiệt Marathon",
                "avatar_url": DEMO_USERS[3]["avatar_url"],
                "title": "Chân chạy 42km",
                "is_verified": True,
            },
            "media_type": "photo",
            "media_url": "https://images.unsplash.com/photo-1452626038306-9aae5e071dd3?w=800",
            "caption": "Hoàn thành bài chạy Zone 2 12km dưới bình minh sông Sài Gòn 🌅👟",
            "background_color": "#1B2232",
            "privacy": "public",
            "is_deleted": False,
            "created_at": now - timedelta(hours=8),
            "expires_at": now + timedelta(hours=16),
            "is_demo_seed": True,
        },
        {
            "_id": "demo_story_04",
            "id": "demo_story_04",
            "user_id": DEMO_USER_YOGA_ID,
            "author": {
                "id": DEMO_USER_YOGA_ID,
                "name": "Mai Thảo Flow",
                "avatar_url": DEMO_USERS[4]["avatar_url"],
                "title": "HLV Yoga & Thở",
                "is_verified": False,
            },
            "media_type": "photo",
            "media_url": "https://images.unsplash.com/photo-1506126613408-eca07ce68773?w=800",
            "caption": "Giữ nhịp thở chậm, giải tỏa căng thẳng thắt lưng cuối ngày 🧘‍♀️🌿",
            "background_color": "#2A1E24",
            "privacy": "public",
            "is_deleted": False,
            "created_at": now - timedelta(hours=12),
            "expires_at": now + timedelta(hours=12),
            "is_demo_seed": True,
        },
        {
            "_id": "demo_story_05",
            "id": "demo_story_05",
            "user_id": DEMO_USER_NEWBIE_ID,
            "author": {
                "id": DEMO_USER_NEWBIE_ID,
                "name": "Bảo Ngọc Rookie",
                "avatar_url": DEMO_USERS[5]["avatar_url"],
                "title": "Hành trình khởi đầu",
                "is_verified": False,
            },
            "media_type": "text",
            "caption": "Ngày thứ 7 liên tiếp duy trì đủ 2 lít nước và 6.000 bước chân! Tự hào về bản thân 💪🎉",
            "background_color": "#223127",
            "privacy": "public",
            "is_deleted": False,
            "created_at": now - timedelta(hours=3),
            "expires_at": now + timedelta(hours=21),
            "is_demo_seed": True,
        },
    ]

    for s in demo_stories:
        stories_col.update_one(
            {"_id": s["_id"]},
            {"$set": s},
            upsert=True,
        )
        stats["community_stories"] += 1

    # -----------------------------------------------------------------------
    # 4. Seed 10 Feed Posts (Album, Meal, Workout/Kinetic, Q&A)
    # -----------------------------------------------------------------------
    posts_col = db["community_posts"]
    comments_col = db["community_comments"]
    answers_col = db["community_answers"]
    interactions_col = db["community_interactions"]

    demo_posts: List[Dict[str, Any]] = [
        # Post 1: Album 4 ảnh về kỹ thuật Kinetic Squat (Coach)
        {
            "_id": "demo_post_01",
            "id": "demo_post_01",
            "type": "photo",
            "author_id": DEMO_USER_COACH_ID,
            "author": {
                "id": DEMO_USER_COACH_ID,
                "name": "HLV Minh Kinetic",
                "avatar_url": DEMO_USERS[0]["avatar_url"],
                "title": "Chuyên gia Kinetic & Phục hồi",
                "is_verified": True,
            },
            "caption": "Album phân tích 4 góc nhìn chuẩn sinh cơ học cho động tác Squat. Hãy chú ý góc gấp cổ chân và sự thăng bằng của cột sống trung tính!",
            "photo_urls": [
                "https://images.unsplash.com/photo-1574680096145-d05b474e2155?w=800",
                "https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=800",
                "https://images.unsplash.com/photo-1583454110551-21f2fa2afe61?w=800",
                "https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800",
            ],
            "privacy": "public",
            "status": "published",
            "topic": "#Kinetic",
            "time_ago": "1 giờ trước",
            "like_count": 28,
            "liked_by_ids": [DEMO_USER_GYM_ID, DEMO_USER_NEWBIE_ID, DEMO_USER_RUNNER_ID],
            "liked_by_names": ["Hải Nam Power", "Bảo Ngọc Rookie"],
            "liked_by_summary": "Hải Nam Power và 27 người khác",
            "is_deleted": False,
            "created_at": now - timedelta(hours=1),
            "is_demo_seed": True,
        },
        # Post 2: Meal Healthy Ăn sạch đầy đủ Macro (Chef)
        {
            "_id": "demo_post_02",
            "id": "demo_post_02",
            "type": "meal",
            "author_id": DEMO_USER_CHEF_ID,
            "author": {
                "id": DEMO_USER_CHEF_ID,
                "name": "Lan Anh EatClean",
                "avatar_url": DEMO_USERS[2]["avatar_url"],
                "title": "Bếp Trưởng Dinh Dưỡng",
                "is_verified": False,
            },
            "caption": "Thực đơn phục hồi cơ bắp buổi tối: Cá hồi nướng măng tây, khoai lang vàng và bơ sáp. Đủ đạm tốt, carb phức và chất béo lành mạnh!",
            "photo_urls": ["https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=800"],
            "nutrition_info": {
                "calories": 540.0,
                "protein_grams": 42.0,
                "carbs_grams": 48.0,
                "fat_grams": 18.0,
                "badge_label": "Giàu Protein & Omega 3",
                "pro_tip": "Nướng ở 180 độ trong 12 phút giữ trọn độ ẩm và dầu cá tự nhiên.",
            },
            "privacy": "public",
            "status": "published",
            "topic": "#BữaĂn",
            "time_ago": "2 giờ trước",
            "like_count": 35,
            "liked_by_ids": [DEMO_USER_COACH_ID, DEMO_USER_YOGA_ID, DEMO_USER_NEWBIE_ID],
            "liked_by_names": ["Mai Thảo Flow", "HLV Minh Kinetic"],
            "liked_by_summary": "Mai Thảo Flow và 34 người khác",
            "is_deleted": False,
            "created_at": now - timedelta(hours=2),
            "is_demo_seed": True,
        },
        # Post 3: Thẻ buổi tập Workout/Kinetic Privacy-by-design (Gym)
        {
            "_id": "demo_post_03",
            "id": "demo_post_03",
            "type": "workout",
            "author_id": DEMO_USER_GYM_ID,
            "author": {
                "id": DEMO_USER_GYM_ID,
                "name": "Hải Nam Power",
                "avatar_url": DEMO_USERS[1]["avatar_url"],
                "title": "Vận động viên Thể hình",
                "is_verified": True,
            },
            "caption": "Hôm nay Push Day tập trung vào ngực trên và vai trước. Cảm giác pump cực kỳ đã khi duy trì tempo 3-0-1-0!",
            "photo_urls": ["https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=800"],
            "workout_attachment": {
                "title": "Buổi tập Đẩy Ngực & Vai Nâng Cao",
                "category": "Saman Kinetic Strength",
                "duration_formatted": "62 phút",
                "exercise_count": 5,
                "set_count": 18,
                "include_duration": True,
                "include_exercises_or_foods": True,
                "exercises": [
                    {"title": "Incline Dumbbell Press", "image_url": "https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=200"},
                    {"title": "Barbell Overhead Press", "image_url": "https://images.unsplash.com/photo-1574680096145-d05b474e2155?w=200"},
                    {"title": "Cable Lateral Raise", "image_url": "https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=200"},
                ],
            },
            "privacy": "public",
            "status": "published",
            "topic": "#BuổiTập",
            "time_ago": "3 giờ trước",
            "like_count": 41,
            "liked_by_ids": [DEMO_USER_COACH_ID, DEMO_USER_RUNNER_ID],
            "liked_by_names": ["HLV Minh Kinetic"],
            "liked_by_summary": "HLV Minh Kinetic và 40 người khác",
            "is_deleted": False,
            "created_at": now - timedelta(hours=3),
            "is_demo_seed": True,
        },
        # Post 4: Bài Q&A Hỏi đáp kỹ thuật chạy bộ & chấn thương IT band (Newbie hỏi)
        {
            "_id": "demo_post_04",
            "id": "demo_post_04",
            "type": "qa",
            "author_id": DEMO_USER_NEWBIE_ID,
            "author": {
                "id": DEMO_USER_NEWBIE_ID,
                "name": "Bảo Ngọc Rookie",
                "avatar_url": DEMO_USERS[5]["avatar_url"],
                "title": "Hành trình khởi đầu",
                "is_verified": False,
            },
            "caption": "Mọi người cho em hỏi cách xử lý đau mặt ngoài đầu gối sau khi chạy được khoảng 3-4km với ạ?",
            "qa_info": {
                "question": "Làm sao để phòng ngừa và giảm đau dải chậu chày (IT Band) khi mới tập chạy?",
                "category_tag": "#HỏiĐáp",
                "details": "Em mới bắt đầu chạy được 2 tuần. Cứ chạy qua mốc 3km là đầu gối bên phải bắt đầu nhói đau âm ỉ, đi bộ thì hết nhưng chạy lại đau. Em nên giãn cơ hay tập bổ trợ nhóm cơ nào ạ?",
                "respondent_count": 2,
                "respondents_summary": "2 câu trả lời từ chuyên gia",
                "respondent_initials": ["MK", "TK"],
            },
            "privacy": "public",
            "status": "published",
            "topic": "#HỏiĐáp",
            "time_ago": "4 giờ trước",
            "like_count": 19,
            "liked_by_ids": [DEMO_USER_COACH_ID, DEMO_USER_RUNNER_ID, DEMO_USER_YOGA_ID],
            "is_deleted": False,
            "created_at": now - timedelta(hours=4),
            "is_demo_seed": True,
        },
        # Post 5: Chạy bộ đường dài Pace & Cadence (Runner)
        {
            "_id": "demo_post_05",
            "id": "demo_post_05",
            "type": "photo",
            "author_id": DEMO_USER_RUNNER_ID,
            "author": {
                "id": DEMO_USER_RUNNER_ID,
                "name": "Tuấn Kiệt Marathon",
                "avatar_url": DEMO_USERS[3]["avatar_url"],
                "title": "Chân chạy 42km",
                "is_verified": True,
            },
            "caption": "Chìa khóa để chạy bền không mệt mỏi: Giữ nhịp bước chân (Cadence) đều đặn ở mức 175-180 spm và thở nhịp 3:3.",
            "photo_urls": ["https://images.unsplash.com/photo-1452626038306-9aae5e071dd3?w=800"],
            "privacy": "public",
            "status": "published",
            "topic": "#ChayBo",
            "time_ago": "5 giờ trước",
            "like_count": 31,
            "liked_by_ids": [DEMO_USER_NEWBIE_ID, DEMO_USER_YOGA_ID],
            "is_deleted": False,
            "created_at": now - timedelta(hours=5),
            "is_demo_seed": True,
        },
        # Post 6: Yoga phục hồi khớp háng & thắt lưng (Yoga)
        {
            "_id": "demo_post_06",
            "id": "demo_post_06",
            "type": "photo",
            "author_id": DEMO_USER_YOGA_ID,
            "author": {
                "id": DEMO_USER_YOGA_ID,
                "name": "Mai Thảo Flow",
                "avatar_url": DEMO_USERS[4]["avatar_url"],
                "title": "HLV Yoga & Thở",
                "is_verified": False,
            },
            "caption": "Chuỗi 5 tư thế Yin Yoga giúp mở khớp háng và giải phóng áp lực cột sống thắt lưng sau ngày dài ngồi bàn làm việc.",
            "photo_urls": [
                "https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=800",
                "https://images.unsplash.com/photo-1506126613408-eca07ce68773?w=800",
                "https://images.unsplash.com/photo-1518611012118-696072aa579a?w=800",
            ],
            "privacy": "public",
            "status": "published",
            "topic": "#PhụcHồi",
            "time_ago": "6 giờ trước",
            "like_count": 47,
            "liked_by_ids": [DEMO_USER_COACH_ID, DEMO_USER_NEWBIE_ID, DEMO_USER_CHEF_ID],
            "is_deleted": False,
            "created_at": now - timedelta(hours=6),
            "is_demo_seed": True,
        },
        # Post 7: Kinetic Foam Rolling & Massage bóng giải cơ (Coach)
        {
            "_id": "demo_post_07",
            "id": "demo_post_07",
            "type": "attachment",
            "author_id": DEMO_USER_COACH_ID,
            "author": {
                "id": DEMO_USER_COACH_ID,
                "name": "HLV Minh Kinetic",
                "avatar_url": DEMO_USERS[0]["avatar_url"],
                "title": "Chuyên gia Kinetic & Phục hồi",
                "is_verified": True,
            },
            "caption": "Đừng bỏ qua việc giải phóng mạc cơ (Myofascial Release) sau những buổi tập nặng. Đây là liệu trình 15 phút phục hồi nhanh nhất.",
            "photo_urls": ["https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=800"],
            "attachment_snapshot": {
                "id": "att_demo_foam_rolling",
                "type": "workout",
                "title": "Liệu trình Kinetic SMR & Giải cơ",
                "subtitle": "15 phút - Toàn thân",
                "summary": "Tập trung giải tỏa cơ mông nhỡ, cơ đùi trước và dải chậu chày.",
                "thumbnail_url": "https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=400",
            },
            "privacy": "public",
            "status": "published",
            "topic": "#Kinetic",
            "time_ago": "7 giờ trước",
            "like_count": 26,
            "liked_by_ids": [DEMO_USER_RUNNER_ID, DEMO_USER_GYM_ID],
            "is_deleted": False,
            "created_at": now - timedelta(hours=7),
            "is_demo_seed": True,
        },
        # Post 8: Bữa sáng yến mạch ngâm qua đêm Overnight Oats (Chef)
        {
            "_id": "demo_post_08",
            "id": "demo_post_08",
            "type": "meal",
            "author_id": DEMO_USER_CHEF_ID,
            "author": {
                "id": DEMO_USER_CHEF_ID,
                "name": "Lan Anh EatClean",
                "avatar_url": DEMO_USERS[2]["avatar_url"],
                "title": "Bếp Trưởng Dinh Dưỡng",
                "is_verified": False,
            },
            "caption": "Bữa sáng chuẩn bị từ đêm trước trong 3 phút: Yến mạch cán dẹt, sữa hạt hạnh nhân, hạt chia và dâu tây tươi 🍓🥛",
            "photo_urls": ["https://images.unsplash.com/photo-1517673132405-a56a62b18caf?w=800"],
            "nutrition_info": {
                "calories": 380.0,
                "protein_grams": 22.0,
                "carbs_grams": 56.0,
                "fat_grams": 8.0,
                "badge_label": "Giàu Chất Xơ Tự Nhiên",
                "pro_tip": "Thêm 1 muỗng whey vani để tăng đạm mà không làm biến đổi vị bùi béo.",
            },
            "privacy": "public",
            "status": "published",
            "topic": "#BữaĂn",
            "time_ago": "8 giờ trước",
            "like_count": 52,
            "liked_by_ids": [DEMO_USER_NEWBIE_ID, DEMO_USER_YOGA_ID, DEMO_USER_RUNNER_ID],
            "is_deleted": False,
            "created_at": now - timedelta(hours=8),
            "is_demo_seed": True,
        },
        # Post 9: Nhật ký hành trình ngày thứ 14 của Newbie (Newbie)
        {
            "_id": "demo_post_09",
            "id": "demo_post_09",
            "type": "photo",
            "author_id": DEMO_USER_NEWBIE_ID,
            "author": {
                "id": DEMO_USER_NEWBIE_ID,
                "name": "Bảo Ngọc Rookie",
                "avatar_url": DEMO_USERS[5]["avatar_url"],
                "title": "Hành trình khởi đầu",
                "is_verified": False,
            },
            "caption": "Check-in phòng tập tuần thứ 2! Cảm ơn anh Minh Kinetic và chị Lan Anh đã giúp em bớt sợ tạ và biết cách tính calo. Cảm thấy khỏe khoắn rõ rệt!",
            "photo_urls": ["https://images.unsplash.com/photo-1518310383802-640c2de311b2?w=800"],
            "privacy": "public",
            "status": "published",
            "topic": "#KhoiDau",
            "time_ago": "9 giờ trước",
            "like_count": 64,
            "liked_by_ids": [DEMO_USER_COACH_ID, DEMO_USER_CHEF_ID, DEMO_USER_GYM_ID, DEMO_USER_YOGA_ID],
            "is_deleted": False,
            "created_at": now - timedelta(hours=9),
            "is_demo_seed": True,
        },
        # Post 10: Chia sẻ kỷ luật tập luyện và giấc ngủ (Gym)
        {
            "_id": "demo_post_10",
            "id": "demo_post_10",
            "type": "photo",
            "author_id": DEMO_USER_GYM_ID,
            "author": {
                "id": DEMO_USER_GYM_ID,
                "name": "Hải Nam Power",
                "avatar_url": DEMO_USERS[1]["avatar_url"],
                "title": "Vận động viên Thể hình",
                "is_verified": True,
            },
            "caption": "Tập luyện là kích thích, dinh dưỡng là nguyên liệu, nhưng giấc ngủ 8 tiếng mới là lúc cơ bắp thực sự phát triển và hormone đồng hóa đạt đỉnh.",
            "photo_urls": ["https://images.unsplash.com/photo-1540497077202-7c8a3999166f?w=800"],
            "privacy": "public",
            "status": "published",
            "topic": "#KỷLuật",
            "time_ago": "10 giờ trước",
            "like_count": 39,
            "liked_by_ids": [DEMO_USER_COACH_ID, DEMO_USER_RUNNER_ID],
            "is_deleted": False,
            "created_at": now - timedelta(hours=10),
            "is_demo_seed": True,
        },
    ]

    for p in demo_posts:
        posts_col.update_one(
            {"_id": p["_id"]},
            {"$set": p},
            upsert=True,
        )
        stats["community_posts"] += 1

        # Seed authoritative likes in community_interactions
        for liker_id in p.get("liked_by_ids", []):
            like_doc = {
                "user_id": liker_id,
                "post_id": p["_id"],
                "interaction_type": "like",
                "created_at": now - timedelta(hours=1),
                "is_demo_seed": True,
            }
            interactions_col.update_one(
                {"user_id": liker_id, "post_id": p["_id"], "interaction_type": "like"},
                {"$set": like_doc},
                upsert=True,
            )
            stats["community_interactions"] += 1

    # -----------------------------------------------------------------------
    # 5. Seed Realistic Answers for Q&A Post (Post 4)
    # -----------------------------------------------------------------------
    demo_answers = [
        {
            "_id": "demo_ans_01",
            "id": "demo_ans_01",
            "question_id": "demo_post_04",
            "user_id": DEMO_USER_COACH_ID,
            "author": {
                "id": DEMO_USER_COACH_ID,
                "name": "HLV Minh Kinetic",
                "avatar_url": DEMO_USERS[0]["avatar_url"],
                "is_verified": True,
            },
            "content": "Chào bạn, đau dải chậu chày (ITBS) ở người mới chạy 90% xuất phát từ cơ mông nhỡ (Gluteus Medius) bị yếu khiến xương đùi xoay trong khi tiếp đất. Bạn hãy tạm giảm cự ly xuống 2km, bổ sung bài tập Clamshell và Single Leg Glute Bridge 3 buổi/tuần nhé!",
            "time_ago": "3 giờ trước",
            "is_pinned_best": True,
            "is_deleted": False,
            "created_at": now - timedelta(hours=3),
            "is_demo_seed": True,
        },
        {
            "_id": "demo_ans_02",
            "id": "demo_ans_02",
            "question_id": "demo_post_04",
            "user_id": DEMO_USER_RUNNER_ID,
            "author": {
                "id": DEMO_USER_RUNNER_ID,
                "name": "Tuấn Kiệt Marathon",
                "avatar_url": DEMO_USERS[3]["avatar_url"],
                "is_verified": True,
            },
            "content": "Đồng ý với Coach Minh. Ngoài ra bạn kiểm tra lại đôi giày chạy xem có quá mòn hoặc bị lệch gót trong không. Tăng guồng chân lên 175 bước/phút sẽ giảm chấn động dội lên khớp gối rất nhiều!",
            "time_ago": "2 giờ trước",
            "is_pinned_best": False,
            "is_deleted": False,
            "created_at": now - timedelta(hours=2),
            "is_demo_seed": True,
        },
    ]

    for ans in demo_answers:
        answers_col.update_one(
            {"_id": ans["_id"]},
            {"$set": ans},
            upsert=True,
        )
        stats["community_answers"] += 1

    # -----------------------------------------------------------------------
    # 6. Seed Realistic Comments for Posts
    # -----------------------------------------------------------------------
    demo_comments = [
        {
            "_id": "demo_cmt_01",
            "id": "demo_cmt_01",
            "post_id": "demo_post_01",
            "user_id": DEMO_USER_GYM_ID,
            "author": {
                "id": DEMO_USER_GYM_ID,
                "name": "Hải Nam Power",
                "avatar_url": DEMO_USERS[1]["avatar_url"],
                "is_verified": True,
            },
            "content": "Phân tích cực kỳ chuẩn anh ơi! Chỉnh lại cổ chân phát là lực đạp dội thẳng vào gót ngay.",
            "time_ago": "45 phút trước",
            "like_count": 4,
            "is_liked": False,
            "is_deleted": False,
            "created_at": now - timedelta(minutes=45),
            "is_demo_seed": True,
        },
        {
            "_id": "demo_cmt_02",
            "id": "demo_cmt_02",
            "post_id": "demo_post_02",
            "user_id": DEMO_USER_NEWBIE_ID,
            "author": {
                "id": DEMO_USER_NEWBIE_ID,
                "name": "Bảo Ngọc Rookie",
                "avatar_url": DEMO_USERS[5]["avatar_url"],
                "is_verified": False,
            },
            "content": "Món này nhìn hấp dẫn quá chị Lan Anh ơi! Em lưu lại để tối nay làm thử luôn 😋",
            "time_ago": "1 giờ trước",
            "like_count": 2,
            "is_liked": False,
            "is_deleted": False,
            "created_at": now - timedelta(hours=1),
            "is_demo_seed": True,
        },
    ]

    for cmt in demo_comments:
        comments_col.update_one(
            {"_id": cmt["_id"]},
            {"$set": cmt},
            upsert=True,
        )
        stats["community_comments"] += 1

    # -----------------------------------------------------------------------
    # 7. Seed 2 Base DM Conversations + Messages among Demo Users
    # -----------------------------------------------------------------------
    convs_col = db["community_conversations"]
    msgs_col = db["community_messages"]

    # Conversation 1: Coach Kinetic <-> Newbie (Tư vấn giáo án)
    conv1_id = "demo_conv_coach_newbie"
    conv1_pair = _make_pair_key(DEMO_USER_COACH_ID, DEMO_USER_NEWBIE_ID)
    conv1_doc = {
        "_id": conv1_id,
        "participant_pair_key": conv1_pair,
        "participants": sorted([DEMO_USER_COACH_ID, DEMO_USER_NEWBIE_ID]),
        "last_message_preview": "Cứ duy trì đúng form như video em nhé!",
        "last_message_type": "text",
        "last_message_at": now - timedelta(minutes=30),
        "unread_counts": {DEMO_USER_COACH_ID: 0, DEMO_USER_NEWBIE_ID: 1},
        "created_at": now - timedelta(days=1),
        "updated_at": now - timedelta(minutes=30),
        "is_demo_seed": True,
    }
    convs_col.update_one({"_id": conv1_id}, {"$set": conv1_doc}, upsert=True)
    stats["community_conversations"] += 1

    conv1_msgs = [
        {
            "_id": "demo_msg_01_01",
            "conversation_id": conv1_id,
            "sender_id": DEMO_USER_NEWBIE_ID,
            "type": "text",
            "content": "Chào anh Minh, hôm nay em tập theo chuỗi khởi động Kinetic của anh thấy lưng nhẹ hẳn ra!",
            "is_deleted": False,
            "created_at": now - timedelta(minutes=40),
            "is_demo_seed": True,
        },
        {
            "_id": "demo_msg_01_02",
            "conversation_id": conv1_id,
            "sender_id": DEMO_USER_COACH_ID,
            "type": "text",
            "content": "Tuyệt vời em! Cứ duy trì đúng form như video em nhé, đừng vội nâng mức tạ.",
            "is_deleted": False,
            "created_at": now - timedelta(minutes=30),
            "is_demo_seed": True,
        },
    ]
    for m in conv1_msgs:
        msgs_col.update_one({"_id": m["_id"]}, {"$set": m}, upsert=True)
        stats["community_messages"] += 1

    # Conversation 2: Gym Beast <-> Chef Healthy (Trao đổi macro + photo message)
    conv2_id = "demo_conv_gym_chef"
    conv2_pair = _make_pair_key(DEMO_USER_GYM_ID, DEMO_USER_CHEF_ID)
    conv2_doc = {
        "_id": conv2_id,
        "participant_pair_key": conv2_pair,
        "participants": sorted([DEMO_USER_GYM_ID, DEMO_USER_CHEF_ID]),
        "last_message_preview": "📷 Hình ảnh",
        "last_message_type": "photo",
        "last_message_at": now - timedelta(minutes=15),
        "unread_counts": {DEMO_USER_GYM_ID: 0, DEMO_USER_CHEF_ID: 0},
        "created_at": now - timedelta(days=2),
        "updated_at": now - timedelta(minutes=15),
        "is_demo_seed": True,
    }
    convs_col.update_one({"_id": conv2_id}, {"$set": conv2_doc}, upsert=True)
    stats["community_conversations"] += 1

    conv2_msgs = [
        {
            "_id": "demo_msg_02_01",
            "conversation_id": conv2_id,
            "sender_id": DEMO_USER_GYM_ID,
            "type": "text",
            "content": "Chị Lan Anh có công thức nước sốt ức gà nào ít natri không chỉ em với?",
            "is_deleted": False,
            "created_at": now - timedelta(minutes=25),
            "is_demo_seed": True,
        },
        {
            "_id": "demo_msg_02_02",
            "conversation_id": conv2_id,
            "sender_id": DEMO_USER_CHEF_ID,
            "type": "photo",
            "media_url": "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=600",
            "content": "Đây nè em, sốt sữa chua chanh vàng ngò rí siêu ít calo nhé!",
            "is_deleted": False,
            "created_at": now - timedelta(minutes=15),
            "is_demo_seed": True,
        },
    ]
    for m in conv2_msgs:
        msgs_col.update_one({"_id": m["_id"]}, {"$set": m}, upsert=True)
        stats["community_messages"] += 1

    # -----------------------------------------------------------------------
    # 8. Optional: Link targeted Real User (--for-user-id or --for-email)
    # -----------------------------------------------------------------------
    target_user: Optional[Dict[str, Any]] = None
    if for_user_id:
        target_user = users_col.find_one({"$or": [{"_id": for_user_id}, {"id": for_user_id}]})
    elif for_email:
        target_user = users_col.find_one({"email": for_email})

    if target_user:
        target_uid = str(target_user.get("_id") or target_user.get("id"))
        # 1. Have Coach and Chef follow the real user, and real user follow Coach
        follows_col.update_one(
            {"follower_id": DEMO_USER_COACH_ID, "following_id": target_uid},
            {"$set": {"follower_id": DEMO_USER_COACH_ID, "following_id": target_uid, "created_at": now, "is_demo_seed": True}},
            upsert=True,
        )
        follows_col.update_one(
            {"follower_id": target_uid, "following_id": DEMO_USER_COACH_ID},
            {"$set": {"follower_id": target_uid, "following_id": DEMO_USER_COACH_ID, "created_at": now, "is_demo_seed": True}},
            upsert=True,
        )
        stats["community_follows"] += 2

        # 2. Create 2 DM conversations with the real user: from Coach & from Chef
        # Conversation with Coach
        real_conv1_id = f"demo_conv_real_{target_uid[:8]}_coach"
        real_conv1_pair = _make_pair_key(target_uid, DEMO_USER_COACH_ID)
        convs_col.update_one(
            {"_id": real_conv1_id},
            {
                "$set": {
                    "participant_pair_key": real_conv1_pair,
                    "participants": sorted([target_uid, DEMO_USER_COACH_ID]),
                    "last_message_preview": "Chào mừng bạn đến với cộng đồng Saman!",
                    "last_message_type": "text",
                    "last_message_at": now - timedelta(minutes=10),
                    "unread_counts": {target_uid: 1, DEMO_USER_COACH_ID: 0},
                    "created_at": now - timedelta(hours=1),
                    "updated_at": now - timedelta(minutes=10),
                    "is_demo_seed": True,
                }
            },
            upsert=True,
        )
        stats["community_conversations"] += 1

        msgs_col.update_one(
            {"_id": f"demo_msg_real_{target_uid[:8]}_01"},
            {
                "$set": {
                    "conversation_id": real_conv1_id,
                    "sender_id": DEMO_USER_COACH_ID,
                    "type": "text",
                    "content": "Chào mừng bạn đến với cộng đồng Saman! Mình là HLV Minh Kinetic. Nếu cần hướng dẫn kỹ thuật hoặc giải đáp thắc mắc về phục hồi cơ bắp, bạn cứ nhắn mình nhé!",
                    "is_deleted": False,
                    "created_at": now - timedelta(minutes=10),
                    "is_demo_seed": True,
                }
            },
            upsert=True,
        )
        stats["community_messages"] += 1

        # Conversation with Chef
        real_conv2_id = f"demo_conv_real_{target_uid[:8]}_chef"
        real_conv2_pair = _make_pair_key(target_uid, DEMO_USER_CHEF_ID)
        convs_col.update_one(
            {"_id": real_conv2_id},
            {
                "$set": {
                    "participant_pair_key": real_conv2_pair,
                    "participants": sorted([target_uid, DEMO_USER_CHEF_ID]),
                    "last_message_preview": "🎤 Tin nhắn thoại",
                    "last_message_type": "voice",
                    "last_message_at": now - timedelta(minutes=5),
                    "unread_counts": {target_uid: 1, DEMO_USER_CHEF_ID: 0},
                    "created_at": now - timedelta(hours=1),
                    "updated_at": now - timedelta(minutes=5),
                    "is_demo_seed": True,
                }
            },
            upsert=True,
        )
        stats["community_conversations"] += 1

        msgs_col.update_one(
            {"_id": f"demo_msg_real_{target_uid[:8]}_02"},
            {
                "$set": {
                    "conversation_id": real_conv2_id,
                    "sender_id": DEMO_USER_CHEF_ID,
                    "type": "voice",
                    "media_url": "https://example.com/audio/demo_welcome.m4a",
                    "duration_seconds": 12.5,
                    "content": "",
                    "is_deleted": False,
                    "created_at": now - timedelta(minutes=5),
                    "is_demo_seed": True,
                }
            },
            upsert=True,
        )
        stats["community_messages"] += 1

    return stats


def clean_demo_data(db: Any) -> Dict[str, int]:
    """
    Safely purges ONLY documents having `{"is_demo_seed": True}` across all community collections.
    Guaranteed NEVER to modify or delete real user data (`is_demo_seed != True`).
    """
    if db is None:
        raise RuntimeError("Database instance is unavailable")

    deleted_counts: Dict[str, int] = {}
    strict_demo_filter = {"is_demo_seed": True}

    for coll_name in DEMO_COLLECTIONS:
        col = db[coll_name]
        res = col.delete_many(strict_demo_filter)
        deleted_counts[coll_name] = getattr(res, "deleted_count", 0)

    return deleted_counts


def _get_database() -> Any:
    from backend.app.database import db
    return db


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Saman Community Demo Data Seeder & Cleaner (Idempotent, Safe, Commercial-Ready)"
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Purge all demo seed data (only documents with is_demo_seed: True). Never touches real data.",
    )
    parser.add_argument(
        "--for-email",
        type=str,
        default=None,
        help="Target a specific real user by email to establish demo DM & follow interactions.",
    )
    parser.add_argument(
        "--for-user-id",
        type=str,
        default=None,
        help="Target a specific real user by ID to establish demo DM & follow interactions.",
    )

    args = parser.parse_args(argv)
    db = _get_database()
    if db is None:
        print("[ERROR] MongoDB database is not available. Check configuration.")
        return 1

    if args.clean:
        print("🧹 Cleaning community demo data (is_demo_seed == True)...")
        results = clean_demo_data(db)
        total_deleted = sum(results.values())
        print(f"✅ Successfully deleted {total_deleted} demo documents:")
        for col, cnt in results.items():
            if cnt > 0:
                print(f"   - {col}: {cnt}")
        return 0

    print("🌱 Seeding community demo data (idempotent upsert)...")
    results = seed_demo_data(db, for_user_id=args.for_user_id, for_email=args.for_email)
    total_seeded = sum(results.values())
    print(f"✅ Successfully upserted demo documents across collections:")
    for col, cnt in results.items():
        print(f"   - {col}: {cnt}")
    if args.for_email or args.for_user_id:
        print(f"🎯 Linked demo conversations & follows to target user: {args.for_email or args.for_user_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
