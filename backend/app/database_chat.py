"""Explicit chat operation index setup; importing this module has no side effects."""


def ensure_chat_operation_indexes(db):
    """Create the tenant-scoped idempotency index on an injected database."""
    return db["chat_operations"].create_index(
        [("user_id", 1), ("operation_id", 1)],
        unique=True,
        name="uniq_chat_operation_user_id_operation_id",
    )
