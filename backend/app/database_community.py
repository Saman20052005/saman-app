"""Explicit community MongoDB index setup; importing this module has no side effects."""


def ensure_community_indexes(db):
    """Create idempotent indexes required by Saman Community collections."""
    if db is None:
        raise RuntimeError("Database is unavailable")

    created = {}

    posts = db["community_posts"]
    created["community_posts"] = [
        posts.create_index(
            [("user_id", 1), ("request_key", 1)],
            unique=True,
            partialFilterExpression={"request_key": {"$type": "string"}},
            name="publish_request_unique",
        ),
        posts.create_index(
            [("created_at", -1), ("_id", -1)],
            name="idx_posts_created_at_desc",
        ),
        posts.create_index(
            [("privacy", 1), ("is_deleted", 1)],
            name="idx_posts_privacy_deleted",
        ),
    ]

    comments = db["community_comments"]
    created["community_comments"] = [
        comments.create_index(
            [("user_id", 1), ("request_key", 1)],
            unique=True,
            partialFilterExpression={"request_key": {"$type": "string"}},
            name="comment_request_unique",
        ),
        comments.create_index(
            [("post_id", 1), ("created_at", 1), ("_id", 1)],
            name="comment_stream",
        ),
    ]

    answers = db["community_answers"]
    created["community_answers"] = [
        answers.create_index(
            [("user_id", 1), ("request_key", 1)],
            unique=True,
            partialFilterExpression={"request_key": {"$type": "string"}},
            name="answer_request_unique",
        ),
        answers.create_index(
            [("question_id", 1), ("created_at", 1), ("_id", 1)],
            name="answer_stream",
        ),
    ]

    answer_votes = db["community_answer_votes"]
    created["community_answer_votes"] = [
        answer_votes.create_index(
            [("user_id", 1), ("answer_id", 1)],
            unique=True,
            name="answer_vote_unique",
        ),
    ]

    interactions = db["community_interactions"]
    created["community_interactions"] = [
        interactions.create_index(
            [("user_id", 1), ("interaction_type", 1), ("post_id", 1)],
            unique=True,
            name="idx_user_interaction_post_unique",
        ),
        interactions.create_index(
            [("post_id", 1), ("interaction_type", 1)],
            name="idx_post_interaction_count",
        ),
    ]

    follows = db["community_follows"]
    created["community_follows"] = [
        follows.create_index(
            [("follower_id", 1), ("following_id", 1)],
            unique=True,
            name="idx_follow_unique",
        ),
        follows.create_index(
            [("follower_id", 1), ("created_at", -1)],
            name="idx_follower_created",
        ),
        follows.create_index(
            [("following_id", 1), ("created_at", -1)],
            name="idx_following_created",
        ),
    ]

    notifications = db["community_notifications"]
    created["community_notifications"] = [
        notifications.create_index(
            [("recipient_id", 1), ("created_at", -1), ("_id", -1)],
            name="idx_notifications_recipient_created",
        ),
        notifications.create_index(
            [("recipient_id", 1), ("is_read", 1)],
            name="idx_notifications_recipient_unread",
        ),
    ]

    drafts = db["community_drafts"]
    created["community_drafts"] = [
        drafts.create_index(
            [("user_id", 1), ("updated_at", -1), ("_id", -1)],
            name="idx_drafts_user_updated",
        ),
    ]

    return created
