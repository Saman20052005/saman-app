"""Explicit community DM MongoDB index setup; importing this module has no side effects."""

COLL_DM_CONVERSATIONS = "community_conversations"
COLL_DM_MESSAGES = "community_messages"


def ensure_community_dm_indexes(db):
    """Create idempotent indexes required by Saman Community Messenger-Lite DM collections."""
    if db is None:
        raise RuntimeError("Database is unavailable")

    created = {}

    conversations = db[COLL_DM_CONVERSATIONS]
    created[COLL_DM_CONVERSATIONS] = [
        conversations.create_index(
            [("participant_pair_key", 1)],
            unique=True,
            name="idx_dm_pair_unique",
        ),
        conversations.create_index(
            [("participants", 1), ("last_message_at", -1), ("_id", -1)],
            name="idx_dm_user_inbox",
        ),
    ]

    messages = db[COLL_DM_MESSAGES]
    created[COLL_DM_MESSAGES] = [
        messages.create_index(
            [("conversation_id", 1), ("created_at", -1), ("_id", -1)],
            name="idx_dm_messages_stream",
        ),
        messages.create_index(
            [("sender_id", 1), ("request_key", 1)],
            unique=True,
            partialFilterExpression={"request_key": {"$type": "string"}},
            name="idx_dm_msg_idempotent",
        ),
    ]

    return created
