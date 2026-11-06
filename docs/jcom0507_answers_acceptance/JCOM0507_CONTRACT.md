# JCOM-05-07 — Answers / Helpful contract

Authority: attached direct user prompt for this checkpoint; no linked Issue required. Applies to local/test Q&A Answers and Helpful Votes only.

## API and canonical identity

- `GET /api/community/questions/{question_id}/answers?limit=20&cursor=...`: `{items,next_cursor,answer_count}`. Existing `/posts/{question_id}/answers` read alias retained. Limit1–50.
- `POST /api/community/questions/{question_id}/answers`: header `X-Idempotency-Key` (16–128 ASCII letters/digits/underscore/hyphen); body exactly `{content}`. All extra fields rejected, including author/badges/coach/verified/is_pinned_best. Trimmed nonempty text, maximum2000 Unicode code points; frontend limits2000 UTF-16 code units. Success/replay200 `{answer,answer_count}`.
- `GET /api/community/questions/{question_id}/answers/{answer_id}`: current canonical public answer/vote projection for reconciliation.
- `PUT /api/community/questions/{question_id}/answers/{answer_id}/helpful` selects helpful; `DELETE` removes it. Both return the canonical answer projection and authoritative `upvote_count/is_upvoted`. These are desired-state operations; repeated identical requests cannot add multiple votes.

All answer operations resolve the current canonical database user using the existing auth dependency and the established canonical-user guard. No auth implementation changes. Answer author snapshot derives exclusively from the database identity: id/name/avatar/verified. The response retains existing public answer fields, plus optional created_at; no email/password/health/tokens or whole User object. Question ID is resolved through the existing audience/ID boundary; its type must be qa and status must explicitly equal published. Deleted/missing/unpublished/unknown audience fails closed.

Self-vote has no approved product decision: authenticated self PUT/DELETE returns403 and no vote is stored. UI disables it when canonical active identity is known. Helpful never sets is_pinned_best; stored legacy best markers remain read-only. No best-answer mutation, question publishing, answer edit/delete, media, notifications or persistent drafts.

## Durable storage and counts

`community_answers` contains the answer and durable replay identity in one atomic document: ObjectId, question_id, user_id, request_key, normalized content, canonical public author snapshot, UTC created_at. A unique `(user_id,request_key)` partial index covers string request keys, allowing existing read-only legacy records without keys. Keys are scoped to the create-answer collection/user across all questions. Same key + same canonical question/content returns the same ID; a changed allowed payload returns409. An atomic insert plus DuplicateKeyError resolution handles concurrent retries on standalone MongoDB. No transaction, process lock, TTL or separate expiring replay record.

`community_answer_votes` has unique `(user_id,answer_id)`. PUT atomically inserts if absent; DELETE removes only that viewer's vote for that answer. Both recount records. Cached answer upvote_count and post respondent_count are never written or trusted as authoritative. Old cached upvoted_by_ids/count fields are not migrated or used as the durable vote source in this checkpoint.

Counts exclude answer records marked is_deleted. `answer_count` and the retained Feed JSON field `qa_info.respondent_count` both mean total visible answers, not distinct authors. Feed/R15/list/create use the same source. No cached post counter writes. Frontend session answer-count cache is monotonic because answer deletion is excluded; a confirmed send cannot be reduced by an older Feed response. It resets on account change. Vote counts can decrease and always use the canonical server receipt/reconciliation state, not increment/decrement guesses.

Explicit index script: `backend/scripts/setup_community_answer_indexes.py`. It only accepts loopback Mongo27046 and a `saman_jcom0507_test_` database name; no startup migration. Missing required unique indexes returns503 before mutation. Guarantee lasts while the answer/vote data and indexes are retained; no cleanup or live/shared DB migration is performed.

## Pagination

Answers form one chronological ascending stream `(created_at,_id)`. Cursor continuation uses strict greater-than with the same tie-breaker. Helpful counts and existing pinned flags do not change stream order, avoiding unstable vote-ranked pagination. Limit and opaque cursor are validated; canonical IDs merge/deduplicate across pages and retries. UI exposes Load more. Refresh restarts the stream. A revision guard discards reads that began before a confirmed answer/vote mutation.

## Permission matrix

| Current resource/viewer | Read list/single/count | Send/replay | Helpful PUT/DELETE |
| --- | --- | --- | --- |
| Public, anonymous |200|401|401|
| Public, canonical user |200|200|200, except self403|
| Private, owner |200|200|200, except self403|
| Private, non-owner |404|404|404|
| Followers-only, owner/follower |200|200|200, except self403|
| Followers-only, non-follower/revoked |404|404|404|
| Missing/deleted/not explicitly published/non-Q&A/unknown audience |404|404|404|
| Signed identity no longer canonical |401|401|401|
| Answer missing/deleted or belongs to another question |404 on single|N/A|404|

Question audience is checked before answer/replay/vote access and rechecked before returning projection/count. A concurrent revocation may leave an already-written record retained but inaccessible; replay cannot reveal it. Denials return only detail, with no answer/count/cursor. Request-time checks do not claim a transaction with external audience changes.

## Recovery / account isolation

| Outcome | Draft/key or desired vote | Behavior |
| --- | --- | --- |
| Canonical answer success |Clear draft/key|Merge canonical ID, sync Feed/R15 count|
| Timeout/drop/5xx/unknown outcome |Retain/freeze original content and key|Explicit unconfirmed state, manual same-key retry|
| Initial definite4xx other than404/408, with no earlier unknown |Retain editable draft, release key|Localized rejection|
| Later rejection after unknown |Retain original key/content|A later failure cannot disprove an earlier commit|
| Access401/403/404 |Keep only own draft/pending key|Hide question, answers/count/cursor and remove its cached Feed card|
| Helpful unknown result |Retain desired state while unresolved|GET the canonical single-answer state; adopt it if available; retain uncertainty/error if resolution fails|
| Account switch/disposed provider |Clear session state|Invalidate Q&A family, clear visible controller draft, repository generation rejects late cache writes and old notifier cannot update B|

Answer composer keeps a stable keyed input Row across error insertion/removal, owns a disposed controller/FocusNode in R15, and locks editing for unknown payloads. Persistent drafts across browser/process restart are deliberately excluded. Remote failures never fall back to fake data. Existing preview initialPost is honored only in explicit fake mode; remote R15 renders its verified fetched question.

## Runtime method

Final main-entrypoint run `ui_20261102T152759Z_ede4cf` is PASS. Actual Login A/B, keyboard input, navigation, real local HTTP and Mongo were used. Deliberate response-loss probes first obtained actual server200/persistence through Playwright route.fetch, then aborted only browser delivery. Vote recovery used the real single-answer GET. Audience changes/follow relationship were explicitly synthetic isolated fixtures. Each server/browser run has a unique directory; no previous evidence or Comments acceptance artifact was overwritten.
