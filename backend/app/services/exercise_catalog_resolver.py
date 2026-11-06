import hashlib
import json
from pathlib import Path
from types import MappingProxyType


_REQUIRED_RECORD_FIELDS = {
    "id",
    "slug",
    "name",
    "nameVi",
    "muscleGroup",
    "targetMuscles",
    "secondaryMuscles",
    "equipment",
    "difficulty",
    "thumbnailUrl",
    "youtubeVideoId",
    "cues",
    "commonMistakes",
    "defaultSets",
    "defaultReps",
    "restSeconds",
    "repType",
    "cvSupported",
    "cvModuleId",
}
_REQUIRED_STRING_FIELDS = {
    "id",
    "slug",
    "name",
    "nameVi",
    "muscleGroup",
    "difficulty",
    "thumbnailUrl",
    "defaultReps",
    "repType",
}
_STRING_LIST_FIELDS = {
    "targetMuscles",
    "secondaryMuscles",
    "equipment",
    "cues",
    "commonMistakes",
}
_OPTIONAL_STRING_FIELDS = {"youtubeVideoId", "cvModuleId"}
_SYNTHETIC_ID_PREFIX = "plan_ex_"


class _CatalogFormatError(ValueError):
    pass


def _reject_duplicate_json_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise _CatalogFormatError("duplicate JSON object key")
        result[key] = value
    return result


def _freeze(value):
    if isinstance(value, dict):
        return MappingProxyType({key: _freeze(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(item) for item in value)
    return value


def _copy_for_caller(value):
    if isinstance(value, MappingProxyType):
        return {key: _copy_for_caller(item) for key, item in value.items()}
    if isinstance(value, tuple):
        return [_copy_for_caller(item) for item in value]
    return value


def _normalized_slug(value):
    return value.strip().lower()


def _validate_catalog(payload):
    if not isinstance(payload, dict) or set(payload) != {
        "schema_version",
        "generated",
        "generator",
        "source",
        "source_sha256",
        "exercises",
    }:
        raise _CatalogFormatError("invalid catalog envelope")
    if type(payload["schema_version"]) is not int or payload["schema_version"] != 1:
        raise _CatalogFormatError("unsupported catalog schema version")
    if (
        payload["generated"] is not True
        or payload["generator"]
        != "frontend/tool/export_ai_exercise_catalog.dart"
    ):
        raise _CatalogFormatError("catalog is not marked as generated")
    if not isinstance(payload["source"], str) or not payload["source"].strip():
        raise _CatalogFormatError("catalog source is missing")
    digest = payload["source_sha256"]
    if (
        not isinstance(digest, str)
        or len(digest) != 64
        or any(character not in "0123456789abcdef" for character in digest)
    ):
        raise _CatalogFormatError("invalid catalog source digest")
    records = payload["exercises"]
    if not isinstance(records, list) or not records:
        raise _CatalogFormatError("catalog exercises must be a non-empty list")
    actual_digest = hashlib.sha256(
        json.dumps(
            records,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()
    if actual_digest != digest:
        raise _CatalogFormatError("catalog source digest mismatch")

    by_id = {}
    by_slug = {}
    for record in records:
        if not isinstance(record, dict) or set(record) != _REQUIRED_RECORD_FIELDS:
            raise _CatalogFormatError("invalid exercise record schema")
        for field in _REQUIRED_STRING_FIELDS:
            value = record[field]
            if not isinstance(value, str) or not value.strip():
                raise _CatalogFormatError("invalid required exercise string")
        for field in _OPTIONAL_STRING_FIELDS:
            value = record[field]
            if value is not None and (
                not isinstance(value, str) or not value.strip()
            ):
                raise _CatalogFormatError("invalid optional exercise string")
        for field in _STRING_LIST_FIELDS:
            value = record[field]
            if not isinstance(value, list) or any(
                not isinstance(item, str) or not item.strip() for item in value
            ):
                raise _CatalogFormatError("invalid exercise string list")
        if (
            type(record["defaultSets"]) is not int
            or record["defaultSets"] < 1
            or type(record["restSeconds"]) is not int
            or record["restSeconds"] < 0
            or type(record["cvSupported"]) is not bool
        ):
            raise _CatalogFormatError("invalid exercise numeric or boolean field")

        exercise_id = record["id"]
        if exercise_id.startswith(_SYNTHETIC_ID_PREFIX):
            raise _CatalogFormatError("synthetic plan IDs cannot be canonical")
        slug_key = _normalized_slug(record["slug"])
        if exercise_id in by_id:
            raise _CatalogFormatError("duplicate exercise ID")
        if slug_key in by_slug:
            raise _CatalogFormatError("duplicate normalized exercise slug")
        frozen_record = _freeze(record)
        by_id[exercise_id] = frozen_record
        by_slug[slug_key] = frozen_record

    return MappingProxyType(by_id), MappingProxyType(by_slug)


class ExerciseCatalogResolver:
    def __init__(self, artifact_path=None):
        self._by_id = MappingProxyType({})
        self._by_slug = MappingProxyType({})
        self._unavailable = False
        if artifact_path is None:
            artifact_path = (
                Path(__file__).resolve().parents[1]
                / "data"
                / "ai_exercise_catalog.generated.json"
            )
        try:
            text = Path(artifact_path).read_text(encoding="utf-8")
            payload = json.loads(text, object_pairs_hook=_reject_duplicate_json_keys)
            self._by_id, self._by_slug = _validate_catalog(payload)
        except (
            OSError,
            UnicodeDecodeError,
            ValueError,
            RecursionError,
        ):
            self._unavailable = True

    @property
    def available(self):
        return not self._unavailable

    def list_exercises(self):
        if self._unavailable:
            return []
        return [_copy_for_caller(record) for record in self._by_id.values()]

    def _result(self, status, reason=None, record=None, provenance=None):
        return {
            "status": status,
            "reason": reason,
            "exercise": _copy_for_caller(record) if record is not None else None,
            "provenance": dict(provenance or {}),
        }

    def resolve(self, exercise_id=None, exercise_slug=None):
        if self._unavailable:
            return self._result(
                "unavailable",
                "catalog artifact unavailable",
                provenance={"kind": "catalog_unavailable"},
            )

        if not isinstance(exercise_id, str) or not exercise_id.strip():
            exercise_id = None
        if not isinstance(exercise_slug, str) or not exercise_slug.strip():
            exercise_slug = None

        slug_record = (
            self._by_slug.get(_normalized_slug(exercise_slug))
            if exercise_slug is not None
            else None
        )
        if exercise_id is None:
            if slug_record is None:
                reason = "unknown slug" if exercise_slug else "ID/slug missing"
                return self._result("unresolved", reason)
            return self._result(
                "resolved",
                record=slug_record,
                provenance={
                    "kind": "exact_slug",
                    "exact_slug": exercise_slug,
                },
            )

        if exercise_id.startswith(_SYNTHETIC_ID_PREFIX):
            if slug_record is None:
                return self._result(
                    "unresolved",
                    "synthetic plan ID requires an exact catalog slug",
                )
            return self._result(
                "resolved",
                record=slug_record,
                provenance={
                    "kind": "synthetic_id+exact_slug",
                    "synthetic_id": exercise_id,
                    "exact_slug": exercise_slug,
                },
            )

        id_record = self._by_id.get(exercise_id)
        if id_record is None:
            return self._result("unresolved", "unknown canonical ID")

        if exercise_slug is not None and slug_record is not id_record:
            return self._result("conflict", "ID/slug conflict")

        provenance = {"kind": "canonical_id", "canonical_id": exercise_id}
        if exercise_slug is not None:
            provenance = {
                "kind": "canonical_id+exact_slug",
                "canonical_id": exercise_id,
                "exact_slug": exercise_slug,
            }
        return self._result("resolved", record=id_record, provenance=provenance)
