"""
Pydantic Models and Schemas for Saman Journal Public Read API.
Subsystem: Saman Journal (JCOM-05-02).
"""

from enum import Enum
from typing import List, Optional
from pydantic import BaseModel, Field


class JournalTopicEnum(str, Enum):
    all = "all"
    workout = "workout"
    nutrition = "nutrition"
    recovery = "recovery"
    habits = "habits"


class JournalSearchCategoryEnum(str, Enum):
    all = "all"
    articles = "articles"
    exercises = "exercises"
    foods = "foods"
    recipes = "recipes"


class JournalArticleModel(BaseModel):
    id: str = Field(..., description="Unique slug or identifier of article")
    title: str = Field(..., min_length=2, max_length=200)
    summary: str = Field(..., min_length=5, max_length=500)
    topic: str = Field(..., description="Topic category id")
    read_time_minutes: int = Field(default=5, ge=1, le=120)
    cover_image_asset: str = Field(..., description="Image asset or URL")
    badge_label: Optional[str] = None
    is_featured: bool = False
    content_body: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    provenance: Optional[str] = Field(
        None, description="Editorial source or synthetic test label"
    )
    created_at: Optional[str] = None


class JournalArticlesResponse(BaseModel):
    articles: List[JournalArticleModel]
    total: int
    next_cursor: Optional[str] = None


class JournalFeaturedResponse(BaseModel):
    article: Optional[JournalArticleModel] = None


class JournalTopicModel(BaseModel):
    id: str
    name: str
    name_en: str


class JournalTopicsResponse(BaseModel):
    topics: List[JournalTopicModel]


class JournalAdviceTipModel(BaseModel):
    id: str
    title: str
    content: str


class JournalSearchResultItemModel(BaseModel):
    id: str
    category: str
    title: str
    subtitle: str
    badge_text: Optional[str] = None
    metric_text: Optional[str] = None
    read_time_minutes: Optional[int] = None
    image_asset: Optional[str] = None
    is_verified: bool = False
    detail_description: Optional[str] = None


class JournalSearchResponse(BaseModel):
    query: str
    category: str
    items: List[JournalSearchResultItemModel]
    total: int
    advice_tip: Optional[JournalAdviceTipModel] = None
