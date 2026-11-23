from datetime import datetime
from typing import List, Optional, Literal
from pydantic import BaseModel, Field, StrictBool, field_validator


class CommunityAuthorModel(BaseModel):
    id: str
    name: str
    avatar_url: Optional[str] = None
    title: Optional[str] = None
    is_verified: bool = False
    follower_count: int = 0
    is_following: bool = False


class ExerciseThumbnailPreviewModel(BaseModel):
    title: str
    image_url: Optional[str] = None


class PostWorkoutAttachmentModel(BaseModel):
    title: str
    category: str = "Saman Kinetic"
    duration_formatted: Optional[str] = None
    exercise_count: Optional[int] = None
    set_count: Optional[int] = None
    exercises: List[ExerciseThumbnailPreviewModel] = []


class PostNutritionInfoModel(BaseModel):
    calories: Optional[int] = None
    protein_grams: Optional[float] = None
    carbs_grams: Optional[float] = 0.0
    fat_grams: Optional[float] = 0.0
    badge_label: Optional[str] = None
    pro_tip: Optional[str] = None


class PostQaInfoModel(BaseModel):
    question: str
    category_tag: str
    details: Optional[str] = None
    respondent_count: int = 0
    respondents_summary: str = ""
    respondent_initials: List[str] = []


class CommunityCommentModel(BaseModel):
    id: str
    author: CommunityAuthorModel
    time_ago: str
    created_at: Optional[datetime] = None
    is_author_reply: bool = False
    content: str
    like_count: int = 0
    is_liked: bool = False
    parent_comment_id: Optional[str] = None
    reply_to_author_name: Optional[str] = None
    replies: List["CommunityCommentModel"] = []


CommunityCommentModel.model_rebuild()


class PublishTextPostRequest(BaseModel):
    type: Literal["text"]
    content: str = Field(..., min_length=1, max_length=5000)
    privacy: Literal["public", "private", "followers_only"]
    topic: Literal["#BữaĂn", "#TậpLuyện", "#PhụcHồi", "#ChiaSẻ", "#KỷLuật", "#Mẹo"]
    allow_comments: StrictBool = True
    model_config = {"extra": "forbid"}


class PublishQuestionRequest(BaseModel):
    type: Literal["qa"]
    title: str = Field(..., min_length=1, max_length=150)
    body: str = Field("", max_length=2000)
    privacy: Literal["public", "private", "followers_only"]
    topic: Literal["Dinh dưỡng", "Tập luyện", "Phục hồi", "Thói quen", "Thực phẩm bổ sung"]
    model_config = {"extra": "forbid"}


class AttachmentSelection(BaseModel):
    source_id: str = Field(..., min_length=1, max_length=128)
    preview_hash: str = Field(..., pattern=r"^[a-f0-9]{64}$")
    include_duration: StrictBool
    include_exercises_or_foods: StrictBool
    include_load_or_macros: StrictBool
    model_config = {"extra": "forbid"}


class PublishAttachmentPostRequest(BaseModel):
    type: Literal["workout", "meal"]
    content: str = Field("", max_length=5000)
    privacy: Literal["public", "private", "followers_only"]
    topic: Literal["#BữaĂn", "#TậpLuyện", "#PhụcHồi", "#ChiaSẻ", "#KỷLuật", "#Mẹo"]
    allow_comments: StrictBool = True
    attachment: AttachmentSelection
    model_config = {"extra": "forbid"}


class MediaUploadResponse(BaseModel):
    media_url: str
    content_type: Optional[str] = None
    file_name: Optional[str] = None


class PublishPhotoPostRequest(BaseModel):
    type: Literal["photo"]
    content: str = Field("", max_length=5000)
    photo_urls: List[str] = Field(..., min_length=1, max_length=10)
    privacy: Literal["public", "private", "followers_only"]
    topic: Literal["#BữaĂn", "#TậpLuyện", "#PhụcHồi", "#ChiaSẻ", "#KỷLuật", "#Mẹo"]
    allow_comments: StrictBool = True
    model_config = {"extra": "forbid"}

    @field_validator("photo_urls")
    @classmethod
    def validate_photo_urls(cls, value: List[str]) -> List[str]:
        cleaned: List[str] = []
        for raw in value:
            if not isinstance(raw, str):
                raise ValueError("Each photo URL must be a string")
            url = raw.strip()
            if not url:
                raise ValueError("Photo URL must not be empty")
            if url.startswith("/static/community/"):
                remainder = url[len("/static/community/"):]
                if not remainder or "/" in remainder or "\\" in remainder or ".." in remainder:
                    raise ValueError("Invalid community media URL")
            elif url.startswith("http://") or url.startswith("https://"):
                scheme_len = 8 if url.startswith("https://") else 7
                if len(url) <= scheme_len or any(ch.isspace() for ch in url):
                    raise ValueError("Invalid HTTP(S) photo URL")
            else:
                raise ValueError("Photo URL must start with /static/community/ or http(s)://")
            cleaned.append(url)
        return cleaned


class CommunityVisualGridItemModel(BaseModel):
    id: str
    post_id: Optional[str] = None
    image_url: str
    like_count: int = 0
    has_multi_photo: bool = False
    has_video: bool = False
    alt_text: Optional[str] = None


class CommunityTrendingTopicModel(BaseModel):
    id: str
    hashtag: str
    post_count_formatted: str
    growth_percent: str = "Ổn định"
    is_stable: bool = True
    icon_name: str = "tag"


class CommunityDiscoverResponse(BaseModel):
    topic_chips: List[str]
    active_topic: str
    grid_items: List[CommunityVisualGridItemModel]
    trending_topics: List[CommunityTrendingTopicModel]
    recommended_creators: List[CommunityAuthorModel]


class CommunityPostModel(BaseModel):
    id: str
    privacy: str = "public"
    topic: str = ""
    attachment_snapshot: Optional[dict] = None
    type: str = "photo"  # "photo" | "workout" | "qa"
    author: CommunityAuthorModel
    time_ago: str
    caption: str
    photo_urls: List[str] = []
    nutrition_info: Optional[PostNutritionInfoModel] = None
    workout_attachment: Optional[PostWorkoutAttachmentModel] = None
    qa_info: Optional[PostQaInfoModel] = None
    like_count: int = 0
    comment_count: int = 0
    share_count: int = 0
    is_like_count_hidden: bool = False
    is_liked: bool = False
    is_bookmarked: bool = False
    liked_by_names: List[str] = []
    liked_by_summary: str = ""
    comments: List[CommunityCommentModel] = []


class CommunityFeedResponse(BaseModel):
    items: List[CommunityPostModel]
    next_cursor: Optional[str] = None


class CreateQuestionAnswerRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=2000)

    model_config = {"extra": "forbid"}


class QuestionAnswerModel(BaseModel):
    id: str
    question_id: str
    created_at: Optional[datetime] = None
    author: CommunityAuthorModel
    content: str
    time_ago: str
    upvote_count: int = 0
    is_upvoted: bool = False
    is_pinned_best: bool = False


class QuestionAnswersResponse(BaseModel):
    items: List[QuestionAnswerModel]
    next_cursor: Optional[str] = None
    answer_count: int = 0


class QuestionAnswerReceipt(BaseModel):
    answer: QuestionAnswerModel
    answer_count: int


class InteractionLikeResponse(BaseModel):
    post_id: str
    is_liked: bool
    like_count: int


class InteractionSaveResponse(BaseModel):
    post_id: str
    is_saved: bool


class CommunitySavedResponse(BaseModel):
    items: List[CommunityPostModel]


class CommunityAuthorProfileResponse(BaseModel):
    id: str
    name: str
    avatar_url: Optional[str] = None
    title: Optional[str] = None
    is_verified: bool = False
    follower_count: int = 0
    following_count: int = 0
    post_count: int = 0
    is_following: bool = False
    handle: Optional[str] = None
    bio: Optional[str] = None
    interest_topics: List[str] = Field(default_factory=list)
    workout_post_count: int = 0
    meal_post_count: int = 0
    total_likes_received: int = 0


class UpdateCommunityProfileRequest(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=50)
    handle: Optional[str] = Field(None, max_length=32)
    title: Optional[str] = Field(None, max_length=80)
    bio: Optional[str] = Field(None, max_length=150)
    interest_topics: Optional[List[str]] = Field(None, max_length=3)
    avatar_url: Optional[str] = Field(None, max_length=500)
    model_config = {"extra": "forbid"}


class CommunityNotificationModel(BaseModel):
    id: str
    actor_id: Optional[str] = None
    actor_name: str
    actor_avatar_url: Optional[str] = None
    action_text: str
    target_snippet: Optional[str] = None
    time_ago: str
    created_at: Optional[datetime] = None
    is_unread: bool = True
    type: Literal["like", "comment", "follow", "answer", "system"]
    target_post_id: Optional[str] = None
    target_post_type: Optional[str] = None


class CommunityNotificationsResponse(BaseModel):
    items: List[CommunityNotificationModel]
    unread_count: int = 0
    next_cursor: Optional[str] = None


class NotificationReadResponse(BaseModel):
    id: str
    is_unread: bool
    unread_count: int


class NotificationsReadAllResponse(BaseModel):
    unread_count: int = 0


class CommunityDraftUpsertRequest(BaseModel):
    id: Optional[str] = None
    caption: str = Field("", max_length=5000)
    media_urls: List[str] = Field(default_factory=list, max_length=10)
    aspect_ratio: str = "1:1"
    rotation: int = 0
    brightness: float = 0.0
    contrast: float = 0.0
    audience: str = "Công khai"
    topic: str = "#BữaĂn"
    allow_comments: StrictBool = True
    attachment: Optional[dict] = None
    question_title: Optional[str] = Field(None, max_length=150)
    question_details: Optional[str] = Field(None, max_length=2000)
    model_config = {"extra": "forbid"}


class CommunityDraftModel(BaseModel):
    id: str
    user_id: str
    caption: str = ""
    media_urls: List[str] = Field(default_factory=list)
    aspect_ratio: str = "1:1"
    rotation: int = 0
    brightness: float = 0.0
    contrast: float = 0.0
    audience: str = "Công khai"
    topic: str = "#BữaĂn"
    allow_comments: bool = True
    attachment: Optional[dict] = None
    question_title: Optional[str] = None
    question_details: Optional[str] = None
    updated_at: datetime


class CommunityDraftsResponse(BaseModel):
    items: List[CommunityDraftModel]


class FollowResponse(BaseModel):
    author_id: str
    is_following: bool
    follower_count: int
    following_count: int


class CommunityFollowListResponse(BaseModel):
    items: List[CommunityAuthorModel]
    next_cursor: Optional[str] = None
    total_count: int = 0




class CreateCommunityCommentRequest(BaseModel):
    content: str = Field(min_length=1, max_length=2000)
    parent_comment_id: Optional[str] = Field(default=None, min_length=1, max_length=128)

    model_config = {"extra": "forbid"}


class CommunityCommentsResponse(BaseModel):
    items: List[CommunityCommentModel]
    next_cursor: Optional[str] = None
    comment_count: int


class CommunityCommentMutationResponse(BaseModel):
    comment: CommunityCommentModel
    comment_count: int


# --- WAVE 4: SOCIAL SETTINGS, BLOCK/MUTE/REPORT, STORIES 24H, SHARE ---


class CommunitySettingsModel(BaseModel):
    is_private_account: bool = False
    who_can_dm: Literal["everyone", "followers", "nobody"] = "everyone"
    who_can_comment: Literal["everyone", "followers", "nobody"] = "everyone"
    who_can_reply_story: Literal["everyone", "followers", "nobody"] = "everyone"
    allow_mentions: Literal["everyone", "followers", "nobody"] = "everyone"
    hide_like_counts: bool = False
    show_activity_status: bool = True
    auto_prompt_share_workout: bool = True
    auto_prompt_share_meal: bool = True
    muted_keywords: List[str] = Field(default_factory=list, max_length=50)


class UpdateCommunitySettingsRequest(BaseModel):
    is_private_account: Optional[StrictBool] = None
    who_can_dm: Optional[Literal["everyone", "followers", "nobody"]] = None
    who_can_comment: Optional[Literal["everyone", "followers", "nobody"]] = None
    who_can_reply_story: Optional[Literal["everyone", "followers", "nobody"]] = None
    allow_mentions: Optional[Literal["everyone", "followers", "nobody"]] = None
    hide_like_counts: Optional[StrictBool] = None
    show_activity_status: Optional[StrictBool] = None
    auto_prompt_share_workout: Optional[StrictBool] = None
    auto_prompt_share_meal: Optional[StrictBool] = None
    muted_keywords: Optional[List[str]] = Field(None, max_length=200)
    model_config = {"extra": "forbid"}


class BlockStatusResponse(BaseModel):
    target_user_id: str
    is_blocked: bool


class MuteStatusResponse(BaseModel):
    target_user_id: str
    is_muted: bool


class CommunityBlockedUsersResponse(BaseModel):
    items: List[CommunityAuthorModel] = Field(default_factory=list)
    total_count: int = 0


class CreateReportRequest(BaseModel):
    target_type: Literal["post", "comment", "answer", "user"]
    target_id: str = Field(..., min_length=1, max_length=128)
    reason: Literal["spam", "harassment", "misinformation", "inappropriate", "other"]
    details: str = Field("", max_length=1000)
    model_config = {"extra": "forbid"}


class ReportReceiptResponse(BaseModel):
    report_id: str
    target_type: Literal["post", "comment", "answer", "user"]
    target_id: str
    reason: Literal["spam", "harassment", "misinformation", "inappropriate", "other"]
    status: str = "received"
    created_at: datetime
    already_reported: bool = False


class CreateStoryRequest(BaseModel):
    media_type: Literal["photo", "video", "text"]
    media_url: Optional[str] = None
    caption: str = Field("", max_length=500)
    background_color: Optional[str] = Field(None, max_length=32)
    privacy: Literal["public", "followers_only"] = "public"
    model_config = {"extra": "forbid"}


class CommunityStoryModel(BaseModel):
    id: str
    author_id: str
    media_type: Literal["photo", "video", "text"]
    media_url: Optional[str] = None
    caption: str = ""
    background_color: Optional[str] = None
    privacy: Literal["public", "followers_only"] = "public"
    created_at: datetime
    expires_at: datetime
    time_ago: str = "Vừa xong"
    view_count: int = 0
    is_viewed: bool = False


class CommunityStoryAuthorGroupModel(BaseModel):
    author: CommunityAuthorModel
    is_self: bool = False
    has_unviewed: bool = False
    latest_created_at: Optional[datetime] = None
    stories: List[CommunityStoryModel] = Field(default_factory=list)


class CommunityStoriesFeedResponse(BaseModel):
    items: List[CommunityStoryAuthorGroupModel] = Field(default_factory=list)


class CommunityArchivedStoryModel(CommunityStoryModel):
    is_expired: bool = True


class CommunityStoriesArchiveResponse(BaseModel):
    items: List[CommunityArchivedStoryModel] = Field(default_factory=list)
    next_cursor: Optional[str] = None
    total_count: int = 0


class StoryViewResponse(BaseModel):
    story_id: str
    is_viewed: bool = True
    view_count: int = 0


class PostShareResponse(BaseModel):
    post_id: str
    share_count: int
