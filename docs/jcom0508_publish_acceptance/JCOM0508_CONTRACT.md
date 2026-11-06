# JCOM-05-08 — Text and local/test Q&A publishing

## Authority and product boundary

Direct attached prompt replaces the linked Issue for this checkpoint. PRD CP2/R06D specifies explicit Share and a text-only path, with no text-post approval workflow. Text creation therefore publishes only after that user action. No automatic posting on composer open, audience changes or draft restoration.

The user explicitly resolved §6.3 on resume: in local/test questions publish immediately only after explicit Đăng and successful backend confirmation. They appear in Q&A Feed for the chosen audience. Production moderation is outside this checkpoint. No moderation workflow is added.

### Local/test Q&A request

Same authenticated `POST /api/community/posts` and X-Idempotency-Key/index/receipt contract, strict alternate body:
```json
{"type":"qa","title":"Question?","body":"Optional context","privacy":"public","topic":"Dinh dưỡng"}
```
Title1–150 characters, trimmed/nonblank; body optional default empty, trimmed,0–2000 characters. Existing R08 topics exactly Dinh dưỡng/Tập luyện/Phục hồi/Thói quen/Thực phẩm bổ sung; public/private/followers_only only. Unknown fields, client author/status/counters, media and health attachments reject422. Server assigns typeqa, caption empty (title rendered once from qa_info), canonical qa_info question/details/category_tag, empty answer counts and statuspublished. Same-key payload includes title/body/topic/privacy/type; cross-type key reuse conflicts409. The existing unique index requires no additional migration. Current identity/audience/publication guards run before replay/conflict and before payload return.

R08 displays audience before Đăng; canonical success selects Q&A Feed and same-ID R15. The existing composer notifier is reused with independent question provider/state (title, details, topic, audience), immutable unknown-outcome payload/key, readOnly pending editor and stale/account guards. Text and question drafts remain separate, session-only. Friends is never Followers.

## Implemented API and storage

`POST /api/community/posts`, authenticated canonical database user, `X-Idempotency-Key`16–128 ASCII letters/digits/underscore/hyphen. Body exactly:

```json
{"type":"text","content":"...","privacy":"public","topic":"#ChiaSẻ","allow_comments":true}
```

- Content1–5000 code points, trimmed and nonblank; Flutter caps5000 UTF-16 units. Privacy exactly public/private/followers_only. Topic is one of the existing R06D choices: #BữaĂn,#TậpLuyện,#PhụcHồi,#ChiaSẻ,#KỷLuật,#Mẹo. allow_comments is a strict boolean, defaulttrue.
- Extra fields are forbidden: no author/author_id/counters/status/badges/timestamps/photo_urls/media_urls/attachment/workout_attachment/nutrition_info. Media type/photo/workout requests are rejected by the publication schema, not silently downgraded or stripped.
- Success/replay200 returns the canonical existing CommunityPost projection: canonical id/type/author/caption, privacy/topic, authoritative default interaction counts and no media/health/profile payload. Server assigns ObjectId, UTC created_at and status=published. Current user is resolved through the existing canonical-user guard; auth/Profile implementation is untouched.

The single community_posts document is also its durable replay record: user_id/request_key, normalized publication_payload and canonical public fields. Explicit partial unique index `(user_id,request_key)` covers string request keys and leaves older records without keys unaffected. Atomic insert plus DuplicateKeyError lookup works on standalone Mongo; no transaction, TTL, expiring replay table or process lock. Same user/key and same normalized payload returns the same post ID; changed content/audience/topic/allow_comments yields409 only after verifying current access/publication status of the existing resource.

Missing index is503 before insertion. Index setup script only accepts dedicated loopback Mongo27048 and DB prefix saman_jcom0508_test_. No startup migration, live/shared DB writes, data cleanup or destructive index operation.

## Audience / replay matrix

| Current state | Owner read | Other read | Same-key replay by creating user |
| --- | --- | --- | --- |
| Public published |200|200|200, same ID|
| Private published |200|404|200 while still owner|
| Followers-only published |200|200 only if viewer follows author|200 while authorized|
| Author follows viewer, viewer does not follow author |200|404|Unchanged owner rule|
| Follow relationship revoked |200|404|No access bypass through replay|
| Missing/deleted/draft/unpublished/statusNone |404|404|404, never resurrect or insert another record|
| Creating user no longer canonical |401|Public read depends on normal endpoint|401|
| Private resource ownership revoked |New owner only|404 for former owner|404 with only detail|

Replay resolves the retained record through current audience and explicit published status before conflict/canonical data and again before returning projection. Responses never include private identity/health fields, operation keys or internal payload. Request-time rechecks do not claim a transaction with external visibility changes. Existing audience read rules are reused rather than changed.

Frontend maps only supported Vietnamese labels or canonical public/private/followers_only values. Friends/Bạn bè is not Followers and is explicitly unsupported. Selected audience appears in the existing R06D header/settings before Share.

## Client recovery and isolation

| Outcome | Draft/settings/key | Result |
| --- | --- | --- |
| Canonical success |Clear only that operation|Insert/replace one canonical Feed item; correct R05 ID; no fixture author/counter|
| Timeout/drop/5xx/unknown |Retain/freeze content/audience/topic/allow_comments and original key|Localized unconfirmed state; same-key Share retry|
| Initial definite4xx other than404/408 or local unsupported payload |Keep editable draft; release key if no previous unknown|Localized rejection/unsupported state|
| Rejection after unknown or404 |Keep original key/payload|Do not claim earlier persistence failed or create another operation|
| Account switch/provider disposal |Clear that account's visible draft; ignore old response|No A state/Feed update in B|
| Explicit new draft revision |Do not clear new content with an old response|Generation guard ignores late canonical receipt|
| Refetch started before publication |Ignore stale success or failure|Neither duplicate nor hide the confirmed canonical Feed item|

Media/activity operations in remote create flow give an explicit unsupported message. Remote create opens the existing text R06D directly. Existing fake preview/media editing remains outside persistent publishing. No remote error falls back to fake publication. Draft/key lifetime is session-only; persistent drafts are excluded.

## Verification boundary

Real Mongo tests cover implemented text and Q&A contracts; controlled Dio failures are client recovery tests, not real-DB proof. Main-app runtime uses real login/profile gate, actual keyboard input, explicit Share, real HTTP/Mongo and immutable run directories. Response-loss injection sends a real request and receives the canonical server200 before aborting browser delivery. Q&A runtime evidence is recorded in separate immutable runs; the product decision applies to local/test only.
