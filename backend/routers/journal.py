"""
FastAPI Router for Saman Journal Public Read API.
Subsystem: Saman Journal (JCOM-05-02).

Invariants:
- Read-only public content (no authentication required).
- No personal user health, workout, or nutrition log records are exposed.
- Exercises search reuses backend.app.database.exercises_collection.
- Foods search reuses backend.app.database.foods_collection.
- Recipes search reuses backend.app.database.recipes_collection (returns empty if no recipe contract).
- Honest attribution: Synthetic test articles carry provenance='synthetic_test_data'.
"""

import os
import re
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from fastapi import APIRouter, HTTPException, Query
from bson import ObjectId

from backend.app.database import (
    db,
    exercises_collection,
    foods_collection,
    recipes_collection,
)
from backend.app.models.journal import (
    JournalTopicEnum,
    JournalSearchCategoryEnum,
    JournalArticleModel,
    JournalArticlesResponse,
    JournalFeaturedResponse,
    JournalTopicModel,
    JournalTopicsResponse,
    JournalAdviceTipModel,
    JournalSearchResultItemModel,
    JournalSearchResponse,
)

router = APIRouter(prefix="/api/journal", tags=["Journal"])

# ─── Standard Static Topics ──────────────────────────────────────────────────

JOURNAL_TOPICS: List[JournalTopicModel] = [
    JournalTopicModel(id="all", name="Tất cả", name_en="All"),
    JournalTopicModel(id="workout", name="Tập luyện", name_en="Workout"),
    JournalTopicModel(id="nutrition", name="Dinh dưỡng", name_en="Nutrition"),
    JournalTopicModel(id="recovery", name="Phục hồi", name_en="Recovery"),
    JournalTopicModel(id="habits", name="Thói quen", name_en="Habits"),
]

# ─── Synthetic Test Articles (for isolated test environments only) ───────────

SYNTHETIC_TEST_ARTICLES: List[Dict[str, Any]] = [
    {
        "id": "article_leg_day_recovery",
        "title": "Phục hồi tốt hơn sau buổi tập chân",
        "summary": "Chiến lược giảm đau nhức cơ bắp DOMS và bổ sung glycogen giúp cơ thể sẵn sàng cho chu kỳ tải lực tiếp theo.",
        "topic": "recovery",
        "read_time_minutes": 4,
        "cover_image_asset": "assets/images/home_journal_recovery.jpg",
        "badge_label": "Phục hồi",
        "is_featured": True,
        "content_body": (
            "Sau các bài tập cường độ cao như Squat hoặc Romanian Deadlift, các sợi cơ trải qua các vi tổn thương (microtrauma). "
            "Quá trình phục hồi yêu cầu kết hợp giữa dinh dưỡng đủ đạm (1.6 - 2.2g/kg), bổ sung nước và giấc ngủ sâu ít nhất 7-8 tiếng."
        ),
        "tags": ["recovery", "doms", "leg day", "phục hồi"],
        "provenance": "synthetic_test_data",
        "created_at": "2026-11-01T08:00:00Z",
    },
    {
        "id": "article_protein_basics",
        "title": "Hiểu protein trong bữa ăn hằng ngày",
        "summary": "Cách tính lượng đạm tối ưu cho mục tiêu tăng cơ và phục hồi.",
        "topic": "nutrition",
        "read_time_minutes": 5,
        "cover_image_asset": "assets/images/nutrition/food_uc_ga_luoc_hap.jpg",
        "badge_label": "Kiến thức",
        "is_featured": False,
        "content_body": (
            "Protein đóng vai trò cấu trúc nền tảng cho sự tái tạo cơ bắp sau khi tập luyện. "
            "Chia đều lượng protein qua 3-4 bữa ăn giúp tối ưu hóa tổng hợp protein cơ bắp (MPS) suốt cả ngày."
        ),
        "tags": ["protein", "nutrition", "đạm", "dinh dưỡng"],
        "provenance": "synthetic_test_data",
        "created_at": "2026-11-01T08:30:00Z",
    },
    {
        "id": "article_calories_and_macros",
        "title": "Hiểu calories và các chất dinh dưỡng",
        "summary": "Phân bổ tỷ lệ carb, đạm và chất béo theo chu kỳ luyện tập thể thao.",
        "topic": "nutrition",
        "read_time_minutes": 6,
        "cover_image_asset": "assets/images/nutrition.jpg",
        "badge_label": "Dinh dưỡng",
        "is_featured": False,
        "content_body": (
            "Cân bằng năng lượng và tỷ lệ dinh dưỡng đa lượng quyết định sự thay đổi vóc dáng và sức mạnh thể chất."
        ),
        "tags": ["calories", "macros", "dinh dưỡng"],
        "provenance": "synthetic_test_data",
        "created_at": "2026-11-01T09:00:00Z",
    },
    {
        "id": "article_progressive_overload",
        "title": "Nguyên lý quá tải tăng tiến (Progressive Overload)",
        "summary": "Cách tăng tạ và khối lượng tập luyện thông minh mà không gây chấn thương.",
        "topic": "workout",
        "read_time_minutes": 7,
        "cover_image_asset": "assets/images/workout.jpg",
        "badge_label": "Tập luyện",
        "is_featured": False,
        "content_body": (
            "Nguyên tắc cốt lõi của việc phát triển cơ bắp là liên tục đặt cơ bắp dưới một mức căng thẳng cơ học lớn dần theo thời gian."
        ),
        "tags": ["workout", "hypertrophy", "progressive overload", "tập tạ"],
        "provenance": "synthetic_test_data",
        "created_at": "2026-11-01T09:30:00Z",
    },
    {
        "id": "article_sleep_and_muscle",
        "title": "Tối ưu giấc ngủ cho hiệu suất tập luyện",
        "summary": "Khoa học về các giai đoạn giấc ngủ và sự phục hồi hệ thần kinh trung ương.",
        "topic": "habits",
        "read_time_minutes": 4,
        "cover_image_asset": "assets/images/home_hero_leg_day.jpg",
        "badge_label": "Thói quen",
        "is_featured": False,
        "content_body": (
            "Giấc ngủ sóng chậm (slow-wave sleep) là thời điểm hormone tăng trưởng được giải phóng mạnh mẽ nhất."
        ),
        "tags": ["sleep", "habits", "thói quen", "giấc ngủ"],
        "provenance": "synthetic_test_data",
        "created_at": "2026-11-01T10:00:00Z",
    },
]


def _get_journal_collection():
    """Returns the journal articles collection from active DB, or None."""
    if db is not None:
        return db["journal_articles"]
    return None


def ensure_test_articles_seeded(collection):
    """Seed synthetic sample articles only if collection is empty in test/dev environment."""
    if collection is None:
        return
    try:
        count = collection.count_documents({})
        if count == 0:
            env = os.getenv("ENVIRONMENT", "development")
            if env in ("development", "test"):
                collection.insert_many(SYNTHETIC_TEST_ARTICLES)
    except Exception:
        pass


def _doc_to_article(doc: Dict[str, Any]) -> JournalArticleModel:
    return JournalArticleModel(
        id=str(doc.get("id") or doc.get("_id")),
        title=doc.get("title", ""),
        summary=doc.get("summary", ""),
        topic=doc.get("topic", "recovery"),
        read_time_minutes=int(doc.get("read_time_minutes") or 5),
        cover_image_asset=doc.get("cover_image_asset") or "assets/images/home_journal_recovery.jpg",
        badge_label=doc.get("badge_label"),
        is_featured=bool(doc.get("is_featured", False)),
        content_body=doc.get("content_body"),
        tags=doc.get("tags") or [],
        provenance=doc.get("provenance"),
        created_at=doc.get("created_at"),
    )


# ─── Endpoints ───────────────────────────────────────────────────────────────

@router.get("/topics", response_model=JournalTopicsResponse)
async def get_journal_topics():
    """Returns the list of scientific topics available in Saman Journal."""
    return JournalTopicsResponse(topics=JOURNAL_TOPICS)


@router.get("/featured", response_model=JournalFeaturedResponse)
async def get_featured_article():
    """Returns the primary featured editorial article for Saman Journal."""
    col = _get_journal_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    ensure_test_articles_seeded(col)

    try:
        doc = col.find_one({"is_featured": True})
        if not doc:
            # Fallback to the latest article if no explicit featured article
            doc = col.find_one(sort=[("created_at", -1)])
        if doc:
            return JournalFeaturedResponse(article=_doc_to_article(doc))
        return JournalFeaturedResponse(article=None)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch featured article: {str(e)}")


@router.get("/articles", response_model=JournalArticlesResponse)
async def get_journal_articles(
    topic: str = Query("all", description="Topic filter (all, workout, nutrition, recovery, habits)"),
    limit: int = Query(10, ge=1, le=50, description="Items per page"),
    cursor: Optional[str] = Query(None, description="Pagination cursor (created_at tie-breaker)"),
):
    """Returns a list of published journal articles optionally filtered by topic with stable cursor pagination."""
    # Validate topic
    valid_topics = [t.value for t in JournalTopicEnum]
    if topic not in valid_topics:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid topic '{topic}'. Must be one of: {', '.join(valid_topics)}",
        )

    col = _get_journal_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    ensure_test_articles_seeded(col)

    try:
        query: Dict[str, Any] = {}
        if topic != "all":
            query["topic"] = topic

        if cursor:
            # Stable tie-breaker cursor format: ISO timestamp string
            query["created_at"] = {"$lt": cursor}

        # Stable sort: created_at DESC, _id DESC
        sort_order = [("created_at", -1), ("_id", -1)]

        cursor_res = col.find(query).sort(sort_order).limit(limit + 1)
        docs = list(cursor_res)

        has_more = len(docs) > limit
        if has_more:
            docs = docs[:limit]

        articles = [_doc_to_article(d) for d in docs]
        next_cursor = docs[-1].get("created_at") if (has_more and docs) else None
        total = col.count_documents({"topic": topic} if topic != "all" else {})

        return JournalArticlesResponse(
            articles=articles,
            total=total,
            next_cursor=next_cursor,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch articles: {str(e)}")


@router.get("/articles/{article_id}", response_model=JournalArticleModel)
async def get_journal_article_by_id(article_id: str):
    """Returns details for a specific article by ID or slug."""
    if not article_id or len(article_id.strip()) == 0:
        raise HTTPException(status_code=400, detail="Invalid article_id")

    col = _get_journal_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    ensure_test_articles_seeded(col)

    try:
        # Search by 'id' slug or Mongo ObjectId
        query: Dict[str, Any] = {"id": article_id}
        if ObjectId.is_valid(article_id):
            query = {"$or": [{"id": article_id}, {"_id": ObjectId(article_id)}]}

        doc = col.find_one(query)
        if not doc:
            raise HTTPException(status_code=404, detail=f"Article '{article_id}' not found")

        return _doc_to_article(doc)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch article: {str(e)}")


@router.get("/search", response_model=JournalSearchResponse)
async def search_journal(
    q: str = Query("", max_length=100, description="Search query keyword"),
    category: str = Query("all", description="Category filter (all, articles, exercises, foods, recipes)"),
    limit: int = Query(20, ge=1, le=50, description="Max search results"),
):
    """
    Unified multi-entity search for Saman Journal across:
    - articles (journal_articles collection)
    - exercises (exercises collection from Workout subsystem)
    - foods (foods collection from Nutrition subsystem)
    - recipes (recipes collection, empty if no recipes in database)
    """
    # 1. Validate Category
    valid_categories = [c.value for c in JournalSearchCategoryEnum]
    if category not in valid_categories:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid category '{category}'. Must be one of: {', '.join(valid_categories)}",
        )

    clean_q = q.strip()
    if not clean_q:
        return JournalSearchResponse(
            query="",
            category=category,
            items=[],
            total=0,
            advice_tip=None,
        )

    items: List[JournalSearchResultItemModel] = []

    # 2. Search Articles
    if category in ("all", "articles"):
        col = _get_journal_collection()
        if col is not None:
            ensure_test_articles_seeded(col)
            try:
                article_query = {
                    "$or": [
                        {"title": {"$regex": re.escape(clean_q), "$options": "i"}},
                        {"summary": {"$regex": re.escape(clean_q), "$options": "i"}},
                        {"tags": {"$regex": re.escape(clean_q), "$options": "i"}},
                    ]
                }
                found_articles = list(col.find(article_query).limit(limit))
                for a in found_articles:
                    items.append(
                        JournalSearchResultItemModel(
                            id=str(a.get("id") or a.get("_id")),
                            category="articles",
                            title=a.get("title", ""),
                            subtitle=a.get("summary", ""),
                            badge_text=a.get("badge_label") or "Kiến thức",
                            metric_text=None,
                            read_time_minutes=int(a.get("read_time_minutes") or 5),
                            image_asset=a.get("cover_image_asset") or "assets/images/nutrition/food_uc_ga_luoc_hap.jpg",
                            is_verified=True,
                            detail_description=a.get("content_body"),
                        )
                    )
            except Exception:
                pass

    # 3. Search Exercises (Reusing Workout collection)
    if category in ("all", "exercises"):
        if exercises_collection is not None:
            try:
                ex_query = {
                    "$or": [
                        {"name": {"$regex": re.escape(clean_q), "$options": "i"}},
                        {"nameVi": {"$regex": re.escape(clean_q), "$options": "i"}},
                    ]
                }
                found_exercises = list(exercises_collection.find(ex_query).limit(limit))
                for e in found_exercises:
                    muscle = e.get("muscleGroup") or e.get("target_muscles") or "Toàn thân"
                    if isinstance(muscle, list):
                        muscle = ", ".join(muscle[:2])
                    equip = e.get("equipment") or "Bodyweight"
                    items.append(
                        JournalSearchResultItemModel(
                            id=str(e.get("_id") or e.get("id")),
                            category="exercises",
                            title=e.get("nameVi") or e.get("name", "Bài tập"),
                            subtitle=f"{str(muscle).capitalize()} • {str(equip).capitalize()}",
                            badge_text="Bài tập",
                            metric_text="Giáo án",
                            read_time_minutes=None,
                            image_asset=e.get("thumbnailUrl") or "assets/images/exercises/barbell-bench-press-thumb.jpg",
                            is_verified=True,
                            detail_description=e.get("description"),
                        )
                    )
            except Exception:
                pass

    # 4. Search Foods (Reusing Nutrition collection)
    if category in ("all", "foods"):
        if foods_collection is not None:
            try:
                food_query = {
                    "$or": [
                        {"name": {"$regex": re.escape(clean_q), "$options": "i"}},
                        {"name_search": {"$regex": re.escape(clean_q), "$options": "i"}},
                    ]
                }
                found_foods = list(foods_collection.find(food_query).limit(limit))
                for f in found_foods:
                    cal = f.get("calories", 0)
                    pro = f.get("protein", 0)
                    items.append(
                        JournalSearchResultItemModel(
                            id=str(f.get("_id") or f.get("id")),
                            category="foods",
                            title=f.get("name", "Thực phẩm"),
                            subtitle=f"Thực phẩm tự nhiên • Đạm cao, ít chất béo",
                            badge_text="Thực phẩm",
                            metric_text=f"{pro}g Protein / 100g • {cal} kcal",
                            read_time_minutes=None,
                            image_asset="assets/images/nutrition/food_uc_ga_luoc_hap.jpg",
                            is_verified=True,
                            detail_description=None,
                        )
                    )
            except Exception:
                pass

    # 5. Search Recipes (Reusing Recipes collection; empty if collection empty)
    if category in ("all", "recipes"):
        if recipes_collection is not None:
            try:
                recipe_query = {
                    "$or": [
                        {"name": {"$regex": re.escape(clean_q), "$options": "i"}},
                        {"title": {"$regex": re.escape(clean_q), "$options": "i"}},
                    ]
                }
                found_recipes = list(recipes_collection.find(recipe_query).limit(limit))
                for r in found_recipes:
                    items.append(
                        JournalSearchResultItemModel(
                            id=str(r.get("_id") or r.get("id")),
                            category="recipes",
                            title=r.get("name") or r.get("title", "Công thức"),
                            subtitle=r.get("subtitle", "Công thức giàu đạm"),
                            badge_text="Công thức",
                            metric_text=r.get("metric_text", "10 phút chuẩn bị"),
                            read_time_minutes=None,
                            image_asset=r.get("image_asset") or "assets/images/nutrition.jpg",
                            is_verified=True,
                            detail_description=r.get("instructions"),
                        )
                    )
            except Exception:
                pass

    # 6. Contextual Advice Tip
    advice_tip: Optional[JournalAdviceTipModel] = None
    lower_q = clean_q.lower()
    if any(k in lower_q for k in ("protein", "đạm", "dam")):
        advice_tip = JournalAdviceTipModel(
            id="tip_protein_window",
            title="Lời khuyên dinh dưỡng Saman",
            content="Cơ thể tổng hợp protein cơ bắp hiệu quả nhất khi nạp đủ 25-40g protein chất lượng cao trong vòng 2 giờ sau buổi tập.",
        )
    elif any(k in lower_q for k in ("recovery", "phục hồi", "phuc hoi", "doms", "chân", "chan")):
        advice_tip = JournalAdviceTipModel(
            id="tip_recovery_science",
            title="Nguyên lý phục hồi thần kinh",
            content="Sau các bài tập hợp lực nặng, hệ thần kinh trung ương cần 48-72 giờ để phục hồi hoàn toàn trước khi tải lực lại cùng nhóm cơ.",
        )

    # Sort results stably by title
    items.sort(key=lambda x: (0 if clean_q.lower() in x.title.lower() else 1, x.title))

    return JournalSearchResponse(
        query=clean_q,
        category=category,
        items=items[:limit],
        total=len(items),
        advice_tip=advice_tip,
    )
