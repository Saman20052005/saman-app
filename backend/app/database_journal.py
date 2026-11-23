"""Explicit journal MongoDB index setup; importing this module has no side effects."""


def ensure_journal_indexes(db):
    """Create idempotent indexes required by Saman Journal collections."""
    if db is None:
        raise RuntimeError("Database is unavailable")

    created = {}

    reading_progress = db["journal_reading_progress"]
    created["journal_reading_progress"] = [
        reading_progress.create_index(
            [("user_id", 1), ("article_id", 1)],
            unique=True,
            name="idx_journal_progress_user_article",
        ),
        reading_progress.create_index(
            [("user_id", 1), ("updated_at", -1)],
            name="idx_journal_progress_user_updated",
        ),
    ]

    bookmarks = db["journal_bookmarks"]
    created["journal_bookmarks"] = [
        bookmarks.create_index(
            [("user_id", 1), ("article_id", 1)],
            unique=True,
            name="idx_journal_bookmark_user_article",
        ),
        bookmarks.create_index(
            [("user_id", 1), ("created_at", -1)],
            name="idx_journal_bookmark_user_created",
        ),
    ]

    return created
