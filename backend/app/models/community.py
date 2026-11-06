from datetime import datetime
from typing import List, Optional, Literal
from pydantic import BaseModel, Field, StrictBool


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
    photo_urls: List[str] = Field(..., min_length=1, max_length=1)
    privacy: Literal["public", "private", "followers_only"]
    topic: Literal["#BữaĂn", "#TậpLuyện", "#PhụcHồi", "#ChiaSẻ", "#KỷLuật", "#Mẹo"]
    allow_comments: StrictBool = True
    model_config = {"extra": "forbid"}


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
