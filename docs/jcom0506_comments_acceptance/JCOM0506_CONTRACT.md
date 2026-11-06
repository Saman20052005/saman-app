# JCOM-05-06 - Comment and recovery contract

## API and storage

- `POST /api/community/posts/{post_id}/comments`, authenticated canonical database user; header `X-Idempotency-Key` (16-128 ASCII letters/digits/underscore/hyphen). Body `{content, parent_comment_id?}`; all extra fields rejected. Trimmed nonempty content, maximum 2000 Unicode code points on server (frontend limits 2000 UTF-16 code units). Successful response 200 `{comment, comment_count}` for both creation and replay.
- Server assigns ObjectId and UTC `created_at`; response includes canonical public author snapshot (id/name/avatar/verified from canonical server user), content, parent ID, reply target name, author-reply flag and time. No whole User serialization. The comment route additionally requires a database-backed identity; it does not accept the legacy auth dependency's missing-user fallback as a comment author.
- Replies target an existing root on the same currently accessible post. One reply level; replying to a reply is 422. UI replies to an existing nested reply target its root and canonical root author. Q&A post comment writes and disabled comments are rejected (409). No edit/delete implementation.
- Each new comment document in `community_comments` is also its replay record. Unique index `[(user_id,1),(request_key,1)]`; one collection implicitly scopes the operation to create-comment. Key is unique across all posts for that user. Same normalized post/content/parent returns the same canonical ID; changed payload returns 409, provided the requested post is accessible. Keys belonging to different users are independent.
- Atomic insert plus duplicate-key recovery works on standalone MongoDB. No transactions, process-local locks, secondary idempotency documents, or cached counter writes. A missing unique index fails closed with 503 before inserting. Setup is explicit and restricted to loopback port 27046 and database prefix `saman_jcom0506_test_`; no application startup migration.
- Guarantee lasts for the lifetime of the retained comment document/unique index: no TTL, expiration, or automatic deletion. Removing records/indexes outside this contract invalidates that guarantee. A response loss after insert is recovered by repeating POST with the same key; no separate resolve endpoint or privacy backdoor.

## Read, count and pagination

`GET /api/community/posts/{post_id}/comments?limit=20&cursor=...` returns `{items,next_cursor,comment_count}`. Limit 1-100. A **single flat chronological stream** paginates roots and replies together, ascending `(created_at,_id)` with strict cursor continuation. Replies carry `parent_comment_id`; they are not an unbounded nested response. UI groups by parent, orders canonical timestamps/IDs, deduplicates IDs and exposes a working load-more button. Refetch restarts the stream and resets the cursor.

`comment_count` includes **roots plus replies**. Feed, Detail, list and mutation responses use the same authoritative collection count, plus actual visible legacy embedded comments/replies. Existing embedded preview/read fixtures are projected read-only, without migration writes; their stable IDs use an epoch timestamp in the stream. Their hidden/deleted entries are excluded. Existing snapshots are not silently overwritten. Persisted responses normalize MongoDB's naive UTC dates to explicit UTC.

Counter data in post documents is not updated. Display time uses a compact UTC timestamp while `created_at` retains the full canonical value. A completed local send synchronizes R05/R03 from its canonical count; stale feed reads cannot reduce a confirmed local count (comment deletion is outside this contract). A page started before a confirmed send is discarded by the detail revision guard.

## Permission matrix

| Situation | Read stream | New send | Same-key replay |
|---|---|---|---|
| Public post / valid canonical user | 200 | 200 | 200, same ID |
| Public anonymous viewer | 200 | 401 | 401 |
| Private post / owner | 200 | 200 | 200 |
| Private post / other user | 404 | 404 | 404 |
| Followers-only / follower or owner | 200 | 200 | 200 |
| Followers-only / unfollowed or revoked | 404 | 404 | 404 |
| Deleted / unpublished / draft / unknown audience | 404 | 404 | 404 |
| Deleted canonical user, even with otherwise signed token | 401 | 401 | 401 |
| Parent missing or on another post | N/A | 404 | Parent validation also applies |
| Parent is a reply | N/A | 422 | 422 |
| Same key with a different permitted payload | N/A | 409 | 409 |

Audience is checked before any lookup/replay, and revalidated immediately before returning data. A concurrent revocation can leave an already-written comment inaccessible, but cannot recover it through replay. Normal request-time permission checking does not promise a transaction with concurrent external visibility changes.

## Client recovery and account isolation

| Outcome | Draft / target | Key | UI / recovery |
|---|---|---|---|
| Confirmed canonical success | Clear | Release | Merge canonical ID; synchronize count |
| Timeout, connection drop, 5xx, unknown exception | Keep and freeze pending payload | Retain | Explicit unconfirmed message; manual same-key retry |
| Initial definite 4xx rejection (except 404/408) | Keep editable draft/target | Release only if no earlier unknown outcome | Localized rejection; allow edit and another operation |
| 401/403/404 | Retain own draft; hide inaccessible post | Retain after any unknown outcome; always retain on 404 | Localized access error; never show cached thread |
| Comment-page error | Preserve loaded state except revoked access | Unchanged | Localized load retry/load-more |
| Account reset | Clear detail providers, drafts, targets and caches | Drop old session state | Repository generation + disposed notifier guards reject late responses |

A later 4xx cannot establish that an earlier timed-out request did not commit. A 404 can also occur after an insert if the final audience recheck detects revocation. In both cases the operation retains its original key/payload for recovery.

Cancel reply leaves text intact; cancel/edit is locked while a send has an unknown result so another payload cannot silently acquire a fresh key. Double tap is locally locked in addition to durable server idempotency. Drafts/keys survive retries/navigation while the provider session lives; **persistent drafts across browser/process restart are excluded**. Reload persistence refers to confirmed server comments.

## Evidence boundaries

Dio-interceptor frontend tests simulate controlled transport faults; they are not real database evidence. Backend integration/concurrency tests use a dedicated real standalone MongoDB database with random database name, synthetic users and real JWT dependency. Browser traversal uses the production `lib/main.dart` release build, real UI login, real FastAPI and real local MongoDB. Any browser response interception is separately labeled as fault injection. Unrelated existing mock AI/image services are not evidence of Community persistence.


## Verified composer lifecycle invariant (resume)

The main input Row has a stable ValueKey so conditional reply/error Row siblings cannot reuse its Element as a banner. R05 retains the controller and FocusNode; the same EditableTextState/editing connection survives Reply insertion and successful removal. The regression sends via the already-open TextInput client; reconnecting with showKeyboard/enterText after selecting Reply would hide the original failure. Real-browser probes use trusted keyboard input, never controller/DOM value assignments or API mutations as a substitute for UI actions.


## Final runtime validation

Remaining contract stages cleared on the newly authorized final backend14152/15192; source attribution in backend_version.json, actual sanitized HTTP/DB/UI evidence in runtime.json. Revocation fixture changes followers_only to private during an actual UI thread GET, then retries a genuinely persisted unknown operation with the same key via UI: both real404 responses contain only detail, UI hides old thread and DB does not duplicate. Follow records/data remain. Response-loss cases explicitly use actual server200/Mongo persistence followed by Playwright response abort. Unit/integration evidence remains inherited; no old suite rerun.
