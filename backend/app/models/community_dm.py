from datetime import datetime
from typing import List, Literal, Optional
from pydantic import BaseModel, Field


class DmParticipantModel(BaseModel):
    id: str
    name: str
    avatar_url: Optional[str] = None
    is_verified: bool = False
    show_activity_status: bool = True


class DmSharedPostPreviewModel(BaseModel):
    id: str
    type: str
    author_name: str
    caption: str = ""
    thumbnail_url: Optional[str] = None


class DmMessageModel(BaseModel):
    id: str
    conversation_id: str
    sender_id: str
    type: Literal["text", "voice", "photo", "video", "post_share", "story_reply", "call_log"]
    content: str = ""
    media_url: Optional[str] = None
    duration_seconds: Optional[float] = None
    shared_post_id: Optional[str] = None
    shared_post_preview: Optional[DmSharedPostPreviewModel] = None
    reply_to_message_id: Optional[str] = None
    is_deleted: bool = False
    created_at: datetime
    call_type: Optional[Literal["audio", "video"]] = None
    call_status: Optional[Literal["completed", "missed", "rejected"]] = None
    duration_sec: Optional[int] = None
    call_id: Optional[str] = None


class DmConversationModel(BaseModel):
    id: str
    peer: DmParticipantModel
    last_message_preview: str = ""
    last_message_type: Optional[str] = None
    last_message_at: Optional[datetime] = None
    unread_count: int = 0
    updated_at: datetime


class DmConversationsResponse(BaseModel):
    items: List[DmConversationModel]
    total_unread_count: int = 0
    next_cursor: Optional[str] = None


class DmMessagesResponse(BaseModel):
    items: List[DmMessageModel]
    next_cursor: Optional[str] = None


class CreateConversationRequest(BaseModel):
    target_user_id: str = Field(..., min_length=1, max_length=128)
    model_config = {"extra": "forbid"}


class SendDmMessageRequest(BaseModel):
    type: Literal["text", "voice", "photo", "video", "post_share", "story_reply"]
    content: str = Field("", max_length=4000)
    media_url: Optional[str] = Field(None, max_length=500)
    duration_seconds: Optional[float] = Field(None, ge=0.0, le=600.0)
    shared_post_id: Optional[str] = Field(None, max_length=128)
    reply_to_message_id: Optional[str] = Field(None, max_length=128)
    model_config = {"extra": "forbid"}


class DmMediaUploadResponse(BaseModel):
    media_url: str
    media_kind: Literal["image", "audio", "video"]
    content_type: str
    file_name: Optional[str] = None
    size_bytes: int


class DmUnreadCountResponse(BaseModel):
    unread_count: int = 0
