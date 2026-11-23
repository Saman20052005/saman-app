"""
FastAPI Router for Saman Journal API.
Subsystem: Saman Journal (JCOM-05-02 + W1 E2E extension).

Invariants:
- Public read endpoints (/topics, /featured, /articles, /articles/{id}, /search,
  /library-summary, /guided-series) require no authentication.
- Optional-auth read endpoints (/reading-progress, /bookmarks) return safe empty
  defaults when anonymous (progress=None / articles=[]) rather than 401.
- Write endpoints (PUT /reading-progress/{id}, PUT/DELETE /bookmarks/{id})
  require valid JWT user authentication.
- No personal user health, workout, or nutrition log records are exposed publicly.
- Exercises search/count reuses backend.app.database.exercises_collection.
- Foods search/count reuses backend.app.database.foods_collection.
- Recipes search/count reuses backend.app.database.recipes_collection.
- Honest attribution: Synthetic test articles carry provenance='synthetic_test_data'.
"""

import os
import re
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from bson import ObjectId
from fastapi import APIRouter, Depends, Header, HTTPException, Query
import jwt

from backend.app.database import (
    db,
    exercises_collection,
    foods_collection,
    recipes_collection,
)
from backend.app.models.journal import (
    JournalAdviceTipModel,
    JournalArticleModel,
    JournalArticlesResponse,
    JournalBookmarkToggleResponse,
    JournalFeaturedResponse,
    JournalGuidedSeriesModel,
    JournalGuidedSeriesResponse,
    JournalLibraryEntryModel,
    JournalLibrarySummaryResponse,
    JournalReadingProgressModel,
    JournalReadingProgressResponse,
    JournalReadingProgressUpsertRequest,
    JournalSearchCategoryEnum,
    JournalSearchResponse,
    JournalSearchResultItemModel,
    JournalTopicEnum,
    JournalTopicModel,
    JournalTopicsResponse,
)
from backend.auth.config import JWT_ALGORITHM, JWT_SECRET

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
            "Sau các bài tập thân dưới cường độ cao như Back Squat, Romanian Deadlift hay Bulgarian Split Squat, "
            "nhóm cơ đùi trước, đùi sau và cơ mông phải chịu áp lực cơ học rất lớn. Cảm giác căng tức xuất hiện sau 24-48 giờ "
            "(DOMS) là phản ứng thích nghi bình thường, nhưng cách bạn phục hồi sẽ quyết định buổi tập tiếp theo có đạt hiệu suất tốt hay không.\n\n"
            "## Vì sao buổi tập chân cần chiến lược phục hồi riêng\n"
            "Nhóm cơ thân dưới chiếm tỷ trọng khối lượng cơ lớn nhất toàn cơ thể. Mỗi buổi tập chân tiêu hao lượng glycogen dự trữ "
            "rất cao đồng thời tạo ra nhiều vi tổn thương (microtrauma) trong các sợi cơ và gây mệt mỏi đáng kể cho hệ thần kinh trung ương.\n\n"
            "## Dinh dưỡng tái tạo cơ và bù glycogen\n"
            "Trong vòng 2 giờ sau buổi tập, hãy ưu tiên một bữa ăn giàu đạm chất lượng cao (25-40g protein) kết hợp tinh bột hấp thu vừa phải "
            "như cơm, khoai lang hoặc yến mạch. Tổng lượng protein cả ngày nên duy trì ở mức 1.6 - 2.2g/kg trọng lượng cơ thể cùng 2.5 - 3 lít nước "
            "và điện giải đầy đủ để giảm chuột rút.\n\n"
            "## Vận động nhẹ và giấc ngủ sâu\n"
            "Thay vì nằm yên hoàn toàn ngày hôm sau, 15-20 phút đi bộ nhẹ hoặc giãn cơ chủ động giúp tăng tuần hoàn máu và đào thải chất chuyển hóa. "
            "Cuối cùng, giấc ngủ sâu 7-8 tiếng là yếu tố không thể thay thế để cơ thể sửa chữa mô cơ và phục hồi sức mạnh thần kinh."
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
            "Protein (chất đạm) là nguyên liệu cấu tạo nên sợi cơ, enzyme, hormone và hệ miễn dịch. "
            "Với người tập luyện thể chất thường xuyên, ăn đủ đạm không chỉ giúp tăng khối lượng cơ nạc mà còn giữ cơ hiệu quả khi giảm mỡ "
            "và duy trì cảm giác no lâu hơn giữa các bữa.\n\n"
            "## Nhu cầu protein thực tế theo mục tiêu\n"
            "Mức khuyến nghị phổ biến cho người tập kháng lực nằm trong khoảng 1.6 - 2.2g protein cho mỗi kg cân nặng mỗi ngày. "
            "Ví dụ, một người nặng 65kg nên hướng tới khoảng 105 - 140g protein mỗi ngày tùy cường độ tập và mức thâm hụt năng lượng.\n\n"
            "## Phân bổ đạm đều trong ngày\n"
            "Thay vì dồn phần lớn lượng đạm vào một bữa tối quá nặng, hãy chia đều thành 3-4 bữa với mỗi bữa khoảng 25-40g protein. "
            "Cách phân bổ này kích hoạt quá trình tổng hợp protein cơ bắp (MPS) đều đặn suốt cả ngày và dễ tiêu hóa hơn.\n\n"
            "## Lựa chọn nguồn protein chất lượng\n"
            "Kết hợp đa dạng nguồn đạm hoàn chỉnh như ức gà, cá, trứng, thịt nạc, sữa chua Hy Lạp cùng nguồn đạm thực vật như đậu phụ, "
            "đậu lăng và các loại hạt giúp bạn đạt đủ axit amin thiết yếu mà bữa ăn vẫn phong phú, dễ duy trì lâu dài."
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
            "Calories là đơn vị đo năng lượng bạn nạp vào từ thực phẩm và tiêu hao qua chuyển hóa cơ bản lẫn vận động. "
            "Tuy nhiên, cùng một mức calories nhưng tỷ lệ các chất dinh dưỡng đa lượng (macros) khác nhau sẽ mang lại cảm giác no, "
            "hiệu suất tập luyện và thay đổi thành phần cơ thể rất khác biệt.\n\n"
            "## Cân bằng năng lượng: TDEE và mục tiêu vóc dáng\n"
            "Tổng năng lượng tiêu hao hằng ngày (TDEE) là mốc tham chiếu cốt lõi. Để giảm mỡ bền vững, mức thâm hụt nhẹ 300-500 kcal/ngày "
            "giúp bảo toàn cơ bắp và tránh suy giảm năng lượng. Ngược lại, giai đoạn tăng cơ chỉ cần dư nhẹ 200-300 kcal/ngày kết hợp tập tạ tăng tiến.\n\n"
            "## Vai trò của 3 nhóm chất đa lượng\n"
            "Protein (4 kcal/g) chịu trách nhiệm xây dựng và bảo vệ mô cơ. Carbohydrate (4 kcal/g) là nguồn nhiên liệu ưu tiên cho các buổi tập "
            "cường độ cao và hoạt động não bộ. Chất béo lành mạnh (9 kcal/g) đóng vai trò thiết yếu trong sản xuất hormone và hấp thu vitamin tan trong dầu.\n\n"
            "## Điều chỉnh linh hoạt theo ngày tập\n"
            "Vào những ngày tập nặng như tập chân hoặc toàn thân, bạn có thể tăng nhẹ lượng carb phức hợp quanh buổi tập để duy trì sức mạnh. "
            "Vào ngày nghỉ, giữ nguyên lượng protein và tăng rau xanh giàu chất xơ giúp kiểm soát cơn đói một cách tự nhiên."
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
            "Cơ thể con người thích nghi rất nhanh với những kích thích quen thuộc. Nếu bạn lặp lại cùng một mức tạ, số hiệp và số lần đẩy "
            "trong nhiều tháng liền, cơ bắp sẽ không còn lý do để phát triển thêm. Nguyên lý quá tải tăng tiến (Progressive Overload) chính là "
            "chìa khóa khoa học tạo ra sự tiến bộ bền vững.\n\n"
            "## Quá tải tăng tiến không chỉ là tăng thêm tạ\n"
            "Nhiều người hiểu nhầm rằng buổi nào cũng phải nâng mức tạ nặng hơn. Thực tế, bạn có thể tạo quá tải thông minh theo nhiều cách: "
            "tăng thêm 1-2 reps ở cùng mức tạ, thêm 1 hiệp tập chất lượng, kiểm soát pha hạ tạ chậm hơn (tempo), hoặc cải thiện biên độ chuyển động chuẩn kỹ thuật.\n\n"
            "## Phương pháp tăng tiến kép (Double Progression)\n"
            "Hãy chọn một khoảng rep mục tiêu, chẳng hạn 8-12 reps cho bài Đẩy ngực. Khi bạn hoàn thành trọn vẹn cả 3 hiệp ở mức 12 reps với form chuẩn "
            "và kiểm soát tốt, hãy tăng mức tạ thêm 2.5 - 5% ở buổi kế tiếp và quay lại chinh phục từ mốc 8 reps.\n\n"
            "## Ghi chép và tôn trọng ngưỡng an toàn\n"
            "Theo dõi nhật ký buổi tập giúp bạn nhìn rõ xu hướng tiến bộ thay vì tập theo cảm tính. Nếu kỹ thuật bắt đầu mất kiểm soát hoặc khớp xuất hiện "
            "đau nhói, hãy giảm tải (deload) một tuần để gân, dây chằng và hệ thần kinh hồi phục hoàn toàn."
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
            "Bạn có thể sở hữu giáo án hoàn hảo và thực đơn chuẩn từng gram, nhưng nếu thường xuyên ngủ dưới 6 tiếng mỗi đêm, "
            "hiệu suất tập luyện và khả năng phục hồi sẽ suy giảm rõ rệt. Giấc ngủ chất lượng là công cụ tăng hiệu suất tự nhiên mạnh mẽ nhất mà bạn đang có.\n\n"
            "## Điều gì xảy ra với cơ bắp khi bạn ngủ\n"
            "Trong giai đoạn giấc ngủ sóng chậm (Slow-Wave Sleep), tuyến yên giải phóng lượng lớn hormone tăng trưởng (GH) thúc đẩy sửa chữa mô cơ. "
            "Đồng thời, giấc ngủ REM giúp củng cố kỹ năng vận động (motor learning) và tái thiết lập độ tỉnh táo của hệ thần kinh trung ương.\n\n"
            "## Tác hại của thiếu ngủ lên hormone và cân nặng\n"
            "Thiếu ngủ kéo dài làm tăng hormone căng thẳng cortisol, giảm độ nhạy insulin và làm rối loạn hai hormone kiểm soát cảm giác đói là ghrelin "
            "và leptin. Kết quả là bạn dễ thèm đồ ngọt hơn, tập nhanh mệt hơn và tỷ lệ mất cơ khi ăn kiêng tăng cao.\n\n"
            "## Quy trình 3 bước cải thiện giấc ngủ ngay tối nay\n"
            "Duy trì giờ đi ngủ và thức dậy cố định kể cả cuối tuần; tránh caffeine sau 14h chiều và hạn chế ánh sáng xanh 45 phút trước khi ngủ. "
            "Giữ phòng ngủ mát mẻ, tối và yên tĩnh sẽ giúp bạn bước vào giấc ngủ sâu nhanh hơn và thức dậy tràn đầy năng lượng."
        ),
        "tags": ["sleep", "habits", "thói quen", "giấc ngủ"],
        "provenance": "synthetic_test_data",
        "created_at": "2026-11-01T10:00:00Z",
    },
]


# ─── Collection & Auth Helpers ───────────────────────────────────────────────

def _get_journal_collection():
    """Returns the journal articles collection from active DB, or None."""
    if db is not None:
        return db["journal_articles"]
    return None


def _get_reading_progress_collection():
    """Returns the journal reading progress collection from active DB, or None."""
    if db is not None:
        return db["journal_reading_progress"]
    return None


def _get_bookmarks_collection():
    """Returns the journal bookmarks collection from active DB, or None."""
    if db is not None:
        return db["journal_bookmarks"]
    return None


async def _get_optional_journal_user(
    authorization: Optional[str] = Header(None),
) -> Optional[Dict[str, Any]]:
    """
    Extracts canonical current_user if Authorization header is present.
    If no Authorization header: returns None (public anonymous viewer).
    If header is present but invalid/expired: raises HTTP 401.
    """
    if not authorization:
        return None

    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(status_code=401, detail="Invalid authorization header format")

    token = parts[1]
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        email = payload.get("email")
        if not email:
            raise HTTPException(status_code=401, detail="Invalid token payload")

        if db is not None:
            user = db["users"].find_one({"email": email})
            if user:
                return user

        # Fallback for mock/test environments
        user_id = payload.get("sub") or payload.get("user_id") or payload.get("id") or email
        return {
            "_id": user_id,
            "email": email,
            "name": payload.get("name", "User"),
        }
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token Expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid Token")


async def _get_required_journal_user(
    authorization: Optional[str] = Header(None),
) -> Dict[str, Any]:
    """Extracts canonical current_user; raises HTTP 401 if not authenticated."""
    if not authorization:
        raise HTTPException(status_code=401, detail="Authentication required")
    user = await _get_optional_journal_user(authorization)
    if not user:
        raise HTTPException(status_code=401, detail="Authentication required")
    return user


def ensure_test_articles_seeded(collection):
    """Seed synthetic sample articles only if collection is empty in test/dev environment."""
    if collection is None:
        return
    try:
        count = collection.count_documents({})
        if count == 0:
            env = os.getenv("ENVIRONMENT", "development")
            if env in ("development", "test"):
                collection.insert_many([dict(article) for article in SYNTHETIC_TEST_ARTICLES])
    except Exception:
        pass


def _find_article_doc(col, article_id: str) -> Optional[Dict[str, Any]]:
    """Find an article document by slug 'id' or Mongo ObjectId."""
    query: Dict[str, Any] = {"id": article_id}
    if ObjectId.is_valid(article_id):
        query = {"$or": [{"id": article_id}, {"_id": ObjectId(article_id)}]}
    return col.find_one(query)


def _safe_count_documents(col) -> int:
    """Safely count documents in a collection, returning 0 if unavailable or empty."""
    if col is None:
        return 0
    try:
        return max(0, int(col.count_documents({})))
    except Exception:
        return 0


def _doc_to_article(
    doc: Dict[str, Any],
    is_bookmarked: bool = False,
) -> JournalArticleModel:
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
        is_bookmarked=is_bookmarked,
    )


def _doc_to_reading_progress(
    doc: Dict[str, Any],
    fallback_article: Optional[Dict[str, Any]] = None,
) -> JournalReadingProgressModel:
    updated_at_val = doc.get("updated_at")
    if isinstance(updated_at_val, datetime):
        updated_at_str: Optional[str] = updated_at_val.isoformat()
    elif updated_at_val is not None:
        updated_at_str = str(updated_at_val)
    else:
        updated_at_str = None

    title = doc.get("title") or (fallback_article.get("title") if fallback_article else "") or ""
    cover_image_asset = (
        doc.get("cover_image_asset")
        or (fallback_article.get("cover_image_asset") if fallback_article else None)
        or "assets/images/home_journal_recovery.jpg"
    )
    summary = doc.get("summary")
    if summary is None:
        summary = (fallback_article.get("summary") if fallback_article else "") or ""

    return JournalReadingProgressModel(
        article_id=str(doc.get("article_id") or ""),
        title=title,
        progress_percent=float(doc.get("progress_percent", 0.0)),
        remaining_minutes=int(doc.get("remaining_minutes", 0)),
        cover_image_asset=cover_image_asset,
        summary=summary,
        updated_at=updated_at_str,
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
async def get_journal_article_by_id(
    article_id: str,
    current_user: Optional[Dict[str, Any]] = Depends(_get_optional_journal_user),
):
    """Returns details for a specific article by ID or slug."""
    if not article_id or len(article_id.strip()) == 0:
        raise HTTPException(status_code=400, detail="Invalid article_id")

    col = _get_journal_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    ensure_test_articles_seeded(col)

    try:
        doc = _find_article_doc(col, article_id)
        if not doc:
            raise HTTPException(status_code=404, detail=f"Article '{article_id}' not found")

        canonical_id = str(doc.get("id") or doc.get("_id"))
        is_bookmarked = False
        if current_user is not None:
            bookmarks_col = _get_bookmarks_collection()
            if bookmarks_col is not None:
                try:
                    existing_bookmark = bookmarks_col.find_one(
                        {"user_id": str(current_user["_id"]), "article_id": canonical_id}
                    )
                    is_bookmarked = existing_bookmark is not None
                except Exception:
                    is_bookmarked = False

        return _doc_to_article(doc, is_bookmarked=is_bookmarked)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch article: {str(e)}")


@router.get("/reading-progress", response_model=JournalReadingProgressResponse)
async def get_reading_progress(
    current_user: Optional[Dict[str, Any]] = Depends(_get_optional_journal_user),
):
    """
    Returns the most recently updated reading progress for the current user.
    Anonymous callers safely receive progress=None instead of 401.
    """
    if current_user is None:
        return JournalReadingProgressResponse(progress=None)

    progress_col = _get_reading_progress_collection()
    if progress_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    try:
        user_id = str(current_user["_id"])
        docs = list(
            progress_col.find({"user_id": user_id})
            .sort([("updated_at", -1)])
            .limit(1)
        )
        if not docs:
            return JournalReadingProgressResponse(progress=None)

        doc = docs[0]
        fallback_article = None
        if not doc.get("title") or not doc.get("cover_image_asset"):
            articles_col = _get_journal_collection()
            if articles_col is not None and doc.get("article_id"):
                fallback_article = _find_article_doc(articles_col, str(doc["article_id"]))

        return JournalReadingProgressResponse(
            progress=_doc_to_reading_progress(doc, fallback_article=fallback_article)
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch reading progress: {str(e)}")


@router.put("/reading-progress/{article_id}", response_model=JournalReadingProgressResponse)
async def upsert_reading_progress(
    article_id: str,
    payload: JournalReadingProgressUpsertRequest,
    current_user: Dict[str, Any] = Depends(_get_required_journal_user),
):
    """Creates or updates reading progress for an existing journal article for the current user."""
    if not article_id or len(article_id.strip()) == 0:
        raise HTTPException(status_code=400, detail="Invalid article_id")

    articles_col = _get_journal_collection()
    progress_col = _get_reading_progress_collection()
    if articles_col is None or progress_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    ensure_test_articles_seeded(articles_col)

    try:
        article_doc = _find_article_doc(articles_col, article_id)
        if not article_doc:
            raise HTTPException(status_code=404, detail=f"Article '{article_id}' not found")

        canonical_article_id = str(article_doc.get("id") or article_doc.get("_id"))
        user_id = str(current_user["_id"])
        now_iso = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

        progress_doc: Dict[str, Any] = {
            "user_id": user_id,
            "article_id": canonical_article_id,
            "title": article_doc.get("title", ""),
            "progress_percent": float(payload.progress_percent),
            "remaining_minutes": int(payload.remaining_minutes),
            "cover_image_asset": article_doc.get("cover_image_asset")
            or "assets/images/home_journal_recovery.jpg",
            "summary": article_doc.get("summary", ""),
            "updated_at": now_iso,
        }

        progress_col.update_one(
            {"user_id": user_id, "article_id": canonical_article_id},
            {"$set": progress_doc},
            upsert=True,
        )

        return JournalReadingProgressResponse(
            progress=_doc_to_reading_progress(progress_doc)
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update reading progress: {str(e)}")


@router.get("/bookmarks", response_model=JournalArticlesResponse)
async def get_bookmarked_articles(
    current_user: Optional[Dict[str, Any]] = Depends(_get_optional_journal_user),
):
    """
    Returns bookmarked articles for the current user ordered by bookmark creation DESC.
    Anonymous callers safely receive articles=[] instead of 401.
    """
    if current_user is None:
        return JournalArticlesResponse(articles=[], total=0, next_cursor=None)

    bookmarks_col = _get_bookmarks_collection()
    articles_col = _get_journal_collection()
    if bookmarks_col is None or articles_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    ensure_test_articles_seeded(articles_col)

    try:
        user_id = str(current_user["_id"])
        bookmark_docs = list(
            bookmarks_col.find({"user_id": user_id}).sort([("created_at", -1)])
        )
        article_ids = [
            str(b["article_id"]) for b in bookmark_docs if b.get("article_id")
        ]
        if not article_ids:
            return JournalArticlesResponse(articles=[], total=0, next_cursor=None)

        found_docs = list(articles_col.find({"id": {"$in": article_ids}}))
        docs_by_id: Dict[str, Dict[str, Any]] = {}
        for doc in found_docs:
            if doc.get("id"):
                docs_by_id[str(doc["id"])] = doc
            if doc.get("_id"):
                docs_by_id[str(doc["_id"])] = doc

        missing_oid_ids = [
            aid for aid in article_ids if aid not in docs_by_id and ObjectId.is_valid(aid)
        ]
        if missing_oid_ids:
            oid_docs = list(
                articles_col.find({"_id": {"$in": [ObjectId(aid) for aid in missing_oid_ids]}})
            )
            for doc in oid_docs:
                docs_by_id[str(doc["_id"])] = doc
                if doc.get("id"):
                    docs_by_id[str(doc["id"])] = doc

        articles = [
            _doc_to_article(docs_by_id[aid], is_bookmarked=True)
            for aid in article_ids
            if aid in docs_by_id
        ]

        return JournalArticlesResponse(
            articles=articles,
            total=len(articles),
            next_cursor=None,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch bookmarks: {str(e)}")


@router.put("/bookmarks/{article_id}", response_model=JournalBookmarkToggleResponse)
async def add_article_bookmark(
    article_id: str,
    current_user: Dict[str, Any] = Depends(_get_required_journal_user),
):
    """Idempotently bookmarks an existing journal article for the current user."""
    if not article_id or len(article_id.strip()) == 0:
        raise HTTPException(status_code=400, detail="Invalid article_id")

    articles_col = _get_journal_collection()
    bookmarks_col = _get_bookmarks_collection()
    if articles_col is None or bookmarks_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    ensure_test_articles_seeded(articles_col)

    try:
        article_doc = _find_article_doc(articles_col, article_id)
        if not article_doc:
            raise HTTPException(status_code=404, detail=f"Article '{article_id}' not found")

        canonical_article_id = str(article_doc.get("id") or article_doc.get("_id"))
        user_id = str(current_user["_id"])
        now_iso = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

        bookmarks_col.update_one(
            {"user_id": user_id, "article_id": canonical_article_id},
            {
                "$setOnInsert": {
                    "user_id": user_id,
                    "article_id": canonical_article_id,
                    "created_at": now_iso,
                },
                "$set": {
                    "updated_at": now_iso,
                },
            },
            upsert=True,
        )

        return JournalBookmarkToggleResponse(
            article_id=canonical_article_id,
            is_bookmarked=True,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to bookmark article: {str(e)}")


@router.delete("/bookmarks/{article_id}", response_model=JournalBookmarkToggleResponse)
async def remove_article_bookmark(
    article_id: str,
    current_user: Dict[str, Any] = Depends(_get_required_journal_user),
):
    """Idempotently removes a bookmark for the current user."""
    if not article_id or len(article_id.strip()) == 0:
        raise HTTPException(status_code=400, detail="Invalid article_id")

    bookmarks_col = _get_bookmarks_collection()
    if bookmarks_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    try:
        user_id = str(current_user["_id"])
        bookmarks_col.delete_one({"user_id": user_id, "article_id": article_id})
        return JournalBookmarkToggleResponse(
            article_id=article_id,
            is_bookmarked=False,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to remove bookmark: {str(e)}")


@router.get("/library-summary", response_model=JournalLibrarySummaryResponse)
async def get_library_summary():
    """Returns summary counts for the Saman Exercise and Nutrition libraries."""
    exercise_count = _safe_count_documents(exercises_collection)
    food_count = _safe_count_documents(foods_collection)
    recipe_count = _safe_count_documents(recipes_collection)
    nutrition_count = food_count + recipe_count

    food_label = (
        f"{nutrition_count} thực phẩm & công thức"
        if recipe_count > 0
        else f"{nutrition_count} thực phẩm"
    )

    entries = [
        JournalLibraryEntryModel(
            id="library_exercises",
            title="Thư viện bài tập",
            item_count_label=f"{exercise_count} bài tập",
            category="exercises",
            cover_image_asset="assets/images/workout.jpg",
            route_description="Tra cứu kỹ thuật, nhóm cơ tác động và hướng dẫn tập luyện an toàn.",
            count=exercise_count,
        ),
        JournalLibraryEntryModel(
            id="library_foods",
            title="Thư viện thực phẩm & công thức",
            item_count_label=food_label,
            category="foods",
            cover_image_asset="assets/images/nutrition.jpg",
            route_description="Tra cứu bảng dinh dưỡng, macro và công thức bữa ăn khoa học.",
            count=nutrition_count,
        ),
    ]
    return JournalLibrarySummaryResponse(entries=entries)


@router.get("/guided-series", response_model=JournalGuidedSeriesResponse)
async def get_guided_series():
    """Returns the foundational guided reading series ('Bắt đầu cùng Saman') with sorted lessons."""
    col = _get_journal_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    ensure_test_articles_seeded(col)

    try:
        docs = list(col.find({}).sort([("created_at", 1), ("_id", 1)]).limit(10))
        if not docs:
            return JournalGuidedSeriesResponse(series=None)

        lessons = [_doc_to_article(doc) for doc in docs]
        series = JournalGuidedSeriesModel(
            id="series_foundation",
            title="Bắt đầu cùng Saman",
            subtitle="Lộ trình nền tảng về tập luyện, dinh dưỡng, phục hồi và xây dựng thói quen bền vững.",
            badge_label="Chuỗi hướng dẫn",
            total_lessons=len(lessons),
            cover_image_asset="assets/images/home_hero_leg_day.jpg",
            lessons=lessons,
        )
        return JournalGuidedSeriesResponse(series=series)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch guided series: {str(e)}")


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
                            subtitle="Thực phẩm tự nhiên • Đạm cao, ít chất béo",
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
