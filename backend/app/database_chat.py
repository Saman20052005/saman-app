"""Explicit chat operation index setup; importing this module has no side effects."""


def ensure_chat_operation_indexes(db):
    """Create the tenant-scoped idempotency index on an injected database."""
    return db["chat_operations"].create_index(
        [("user_id", 1), ("operation_id", 1)],
        unique=True,
        name="uniq_chat_operation_user_id_operation_id",
    )


def ensure_chat_training_log_indexes(db):
    """Create indexing for chat training logs on an injected database."""
    col = db["chat_training_logs"]
    idx1 = col.create_index(
        [("user_hash", 1), ("operation_id", 1)],
        unique=True,
        name="uniq_chat_training_user_hash_operation_id",
    )
    idx2 = col.create_index(
        [("user_hash", 1), ("action_id", 1)],
        name="idx_chat_training_user_hash_action_id",
        sparse=True,
    )
    idx3 = col.create_index(
        [("created_at", -1)],
        name="idx_chat_training_created_at",
    )
    return [idx1, idx2, idx3]
