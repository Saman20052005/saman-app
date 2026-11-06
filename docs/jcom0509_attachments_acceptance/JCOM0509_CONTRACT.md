# Attachment snapshot contract

Source reads only: backend workout router /sessions uses workout_history.user_id authenticated canonical ID (completed = finished_at/end_time present); Nutrition /logs/{date} uses nutrition_plans.user_email canonical user's email. Community resolves current canonical user, then applies these existing ownership keys. Workouts with no canonical user_id, unfinished/deleted sources and foreign sources are not selectable. Read-only adapters do not change original feature APIs/storage.

|Shared field|Workout source|Meal source|Default / display|
|---|---|---|---|
|kind/title/date/category|plan_name/date; fixed Saman Kinetic|meal_type/date|Always shown in R07/R06D/Feed/R05 after explicit attach|
|duration_minutes|total_duration_minutes or duration_minutes|No source|ON workout; OFF/disabled meal|
|exercises / exercise_count|completed exercise_logs, public catalog name or slug display fallback; names only|Absent|ON; no per-set/internal IDs|
|foods|Absent|foods[].name, names only|ON; quantities/food IDs/nested macros never allowed|
|set_count / load_kg|completed log count / canonical total_volume_kg|Absent|OFF; explicit sensitive toggle only|
|calories / protein_grams / carbs_grams / fat_grams|Absent|canonical total_calories/total_protein/total_carbs/total_fat|OFF; explicit sensitive toggle only|

The R07 source list/preview is private to its owner. GET /api/community/attachment-sources/{kind} returns default-privacy previews (limit20), each {source_id,preview_hash,snapshot}; GET /attachment-sources/{kind}/{source_id} accepts three strict boolean selections and returns the exact selected preview. Metadata images, notes, email/user IDs, plan/food/exercise IDs, CV/rest/health measurements are not in the share allowlist. Unsupported field choices reject; unknown request fields reject. No absent/off metric is materialized as null/zero or retained in nested public structures.

POST /api/community/posts keeps the same key/index. Strict attachment alternative type=workout|meal, content(default empty,max5000), privacy/topic/allow_comments and attachment {source_id,preview_hash,include_duration,include_exercises_or_foods,include_load_or_macros}. Backend builds canonical projection and hashes only source identity + selected share content. If it differs from the preview, reject409 and require fresh preview/explicit confirmation before any new insertion. Hidden-only source edits need no review. UI shows every included field, selected audience and explicit Share; removing attachment keeps caption.

Existing same-key records are checked before resolving source again: after current account/audience/publication checks, same normalized payload returns persisted post/snapshot even when the source changed/deleted. Changed key payload conflicts409. Atomic post insert stores only selected snapshot and normalized reference/options/hash; no source dump. Public CommunityPost.attachment_snapshot contains no source_id/hash/key or private references; all Feed/detail/replay projections use the stored whitelist snapshot. No source reads in public rendering. Source pointers stay only in the internal operation payload. Existing durable partial unique index covers all publication types, no transaction/TTL.

Draft/options/audience/key frozen after unknown outcome, later rejection cannot discard unknown key. Before any unknown outcome, preview mismatch409 keeps editable draft for review; new preview is not auto-submitted. Account invalidation ignores late source-list/preview/send responses and clears composer. R07 has loading/empty/error/retry; fake preview remains explicit, remote never falls back to fake.
