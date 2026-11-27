"""Unit and integration tests for the Phase 5 Multi-Exercise ML Pipeline."""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pytest

from ml_research.phase5_multi_exercise.augmentation import (
    MAX_BONE_SCALE,
    MIN_BONE_SCALE,
    MIRROR_PAIRS,
    augment_training_samples,
    mirror_horizontal,
    rotate_3d,
    scale_bone_proportions,
    simulate_mobile_noise,
)
from ml_research.phase5_multi_exercise.feature_extractor import (
    EXERCISES,
    FEATURE_NAMES,
    PHASE_LABELS,
    VIEW_ANGLE_LABELS,
    extract_features,
    extract_features_batch,
)
from ml_research.phase5_multi_exercise.train_and_export import (
    EXPORT_DIR,
    forward_pass_from_weights,
)


def _sample_pose(seed: int = 7) -> np.ndarray:
    rng = np.random.default_rng(seed)
    lm = np.zeros((33, 4), dtype=np.float64)
    lm[:, 0] = rng.uniform(0.25, 0.75, size=33)
    lm[:, 1] = rng.uniform(0.15, 0.85, size=33)
    lm[:, 2] = rng.uniform(-0.25, 0.25, size=33)
    lm[:, 3] = rng.uniform(0.55, 0.99, size=33)
    # Give well-defined torso geometry
    lm[11] = [0.60, 0.30, -0.04, 0.96]
    lm[12] = [0.40, 0.30, 0.03, 0.92]
    lm[13] = [0.68, 0.44, -0.05, 0.94]
    lm[14] = [0.32, 0.44, 0.04, 0.89]
    lm[15] = [0.64, 0.56, -0.08, 0.91]
    lm[16] = [0.36, 0.56, 0.06, 0.87]
    lm[23] = [0.56, 0.55, -0.02, 0.95]
    lm[24] = [0.44, 0.55, 0.02, 0.93]
    lm[25] = [0.57, 0.75, -0.05, 0.90]
    lm[26] = [0.43, 0.75, 0.01, 0.88]
    lm[27] = [0.57, 0.93, 0.00, 0.86]
    lm[28] = [0.43, 0.93, 0.02, 0.85]
    return lm


# ---------------------------------------------------------------------------
# 1. Augmentation Tests
# ---------------------------------------------------------------------------


def test_mirror_horizontal_swaps_left_right_and_flips_x() -> None:
    lm = _sample_pose()
    original = lm.copy()
    mirrored = mirror_horizontal(lm)

    # Original must not be mutated
    np.testing.assert_array_equal(lm, original)

    # Check shoulder swap explicitly (11 <-> 12) and all MediaPipe pairs
    np.testing.assert_allclose(mirrored[11, 0], 1.0 - lm[12, 0], atol=1e-12)
    np.testing.assert_allclose(mirrored[12, 0], 1.0 - lm[11, 0], atol=1e-12)
    np.testing.assert_allclose(mirrored[11, 1:], lm[12, 1:], atol=1e-12)
    np.testing.assert_allclose(mirrored[12, 1:], lm[11, 1:], atol=1e-12)

    for left_idx, right_idx in MIRROR_PAIRS:
        np.testing.assert_allclose(mirrored[left_idx, 0], 1.0 - lm[right_idx, 0], atol=1e-12)
        np.testing.assert_allclose(mirrored[right_idx, 0], 1.0 - lm[left_idx, 0], atol=1e-12)
        np.testing.assert_allclose(mirrored[left_idx, 1:], lm[right_idx, 1:], atol=1e-12)
        np.testing.assert_allclose(mirrored[right_idx, 1:], lm[left_idx, 1:], atol=1e-12)

    # Double mirror returns exact original
    np.testing.assert_allclose(mirror_horizontal(mirrored), lm, atol=1e-12)

    # Sequence shape (T, 33, 4) support
    seq = np.stack([lm, _sample_pose(11)], axis=0)
    seq_m = mirror_horizontal(seq)
    assert seq_m.shape == (2, 33, 4)
    np.testing.assert_allclose(seq_m[0], mirrored, atol=1e-12)


def test_scale_bone_proportions_bounds_and_visibility() -> None:
    lm = _sample_pose()
    hip_mid = 0.5 * (lm[23, :2] + lm[24, :2])
    orig_sh_span = abs(lm[11, 0] - lm[12, 0])
    orig_torso_dy = abs(lm[11, 1] - hip_mid[1])

    scaled = scale_bone_proportions(lm, scale_x=1.12, scale_y=0.90)
    assert np.all(np.isfinite(scaled))
    np.testing.assert_allclose(scaled[:, 3], lm[:, 3], atol=1e-12)
    np.testing.assert_allclose(abs(scaled[11, 0] - scaled[12, 0]), orig_sh_span * 1.12, atol=1e-12)
    np.testing.assert_allclose(abs(scaled[11, 1] - hip_mid[1]), orig_torso_dy * 0.90, atol=1e-12)

    # Out-of-range inputs are strictly clamped to ±15% ([0.85, 1.15])
    clamped_hi = scale_bone_proportions(lm, scale_x=2.0, scale_y=0.2)
    ratio_x = abs(clamped_hi[11, 0] - clamped_hi[12, 0]) / orig_sh_span
    ratio_y = abs(clamped_hi[11, 1] - hip_mid[1]) / orig_torso_dy
    assert MIN_BONE_SCALE - 1e-9 <= ratio_x <= MAX_BONE_SCALE + 1e-9
    assert MIN_BONE_SCALE - 1e-9 <= ratio_y <= MAX_BONE_SCALE + 1e-9
    np.testing.assert_allclose(ratio_x, MAX_BONE_SCALE, atol=1e-12)
    np.testing.assert_allclose(ratio_y, MIN_BONE_SCALE, atol=1e-12)


def test_rotate_3d_rigid_and_finite() -> None:
    lm = _sample_pose()
    orig_dist = float(np.linalg.norm(lm[11, :3] - lm[23, :3]))

    for yaw, pitch, roll in ((15.0, -10.0, 8.0), (45.0, 5.0, -5.0), (90.0, 0.0, 0.0)):
        rot = rotate_3d(lm, yaw_deg=yaw, pitch_deg=pitch, roll_deg=roll)
        assert rot.shape == (33, 4)
        assert np.all(np.isfinite(rot))
        np.testing.assert_allclose(rot[:, 3], lm[:, 3], atol=1e-12)
        new_dist = float(np.linalg.norm(rot[11, :3] - rot[23, :3]))
        np.testing.assert_allclose(new_dist, orig_dist, atol=1e-10)


def test_simulate_mobile_noise_and_augment_batch_determinism() -> None:
    lm = _sample_pose()
    noisy_a = simulate_mobile_noise(lm, np.random.default_rng(42))
    noisy_b = simulate_mobile_noise(lm, np.random.default_rng(42))
    np.testing.assert_array_equal(noisy_a, noisy_b)
    assert np.all(np.isfinite(noisy_a))
    assert np.all((noisy_a[:, 3] >= 0.0) & (noisy_a[:, 3] <= 1.0))

    batch = np.stack([lm, _sample_pose(9)], axis=0)
    labels = np.array(["top_idle", "bottom_peak"])
    aug_x1, aug_y1 = augment_training_samples(batch, labels, np.random.default_rng(42), copies_per_sample=3)
    aug_x2, aug_y2 = augment_training_samples(batch, labels, np.random.default_rng(42), copies_per_sample=3)

    assert aug_x1.shape == (8, 33, 4)
    assert aug_y1.shape == (8,)
    np.testing.assert_array_equal(aug_x1, aug_x2)
    np.testing.assert_array_equal(aug_y1, aug_y2)
    np.testing.assert_array_equal(aug_x1[:2], batch)


# ---------------------------------------------------------------------------
# 2. Feature Extractor Tests
# ---------------------------------------------------------------------------


def test_feature_extractor_count_finiteness_and_symmetry() -> None:
    assert len(FEATURE_NAMES) == 18

    lm = _sample_pose()
    feats = extract_features(lm)
    assert feats.shape == (18,)
    assert np.all(np.isfinite(feats))

    # Degenerate all-zero pose must still yield 18 finite floats
    zero_feats = extract_features(np.zeros((33, 4), dtype=np.float64))
    assert zero_feats.shape == (18,)
    assert np.all(np.isfinite(zero_feats))

    # Left/right symmetry check under mirror_horizontal
    mirrored_feats = extract_features(mirror_horizontal(lm))
    idx = {name: i for i, name in enumerate(FEATURE_NAMES)}

    # Swapped bilateral angle pairs
    for left_name, right_name in (
        ("left_elbow_angle_deg", "right_elbow_angle_deg"),
        ("left_shoulder_angle_deg", "right_shoulder_angle_deg"),
        ("left_hip_angle_deg", "right_hip_angle_deg"),
        ("left_knee_angle_deg", "right_knee_angle_deg"),
    ):
        np.testing.assert_allclose(mirrored_feats[idx[left_name]], feats[idx[right_name]], atol=1e-10)
        np.testing.assert_allclose(mirrored_feats[idx[right_name]], feats[idx[left_name]], atol=1e-10)

    # Mirror-invariant features
    for inv_name in (
        "active_elbow_angle_norm",
        "wrist_rel_shoulder_y",
        "elbow_rel_shoulder_y",
        "hip_rel_knee_y",
        "shoulder_to_torso_ratio",
        "hip_to_torso_ratio",
        "shoulder_z_diff",
        "torso_lean_norm",
        "upper_vis_mean",
        "bilateral_vis_asym",
    ):
        np.testing.assert_allclose(mirrored_feats[idx[inv_name]], feats[idx[inv_name]], atol=1e-10)

    # Batch extractor matches single extractor
    batch_feats = extract_features_batch(np.stack([lm, mirror_horizontal(lm)], axis=0))
    np.testing.assert_allclose(batch_feats[0], feats, atol=1e-12)
    np.testing.assert_allclose(batch_feats[1], mirrored_feats, atol=1e-12)


def test_feature_extractor_known_angles() -> None:
    lm = np.zeros((33, 4), dtype=np.float64)
    lm[:, 3] = 1.0
    # Vertical torso: shoulder mid at (0.5, 0.3), hip mid at (0.5, 0.6) -> torso_len = 0.3
    lm[11] = [0.6, 0.3, 0.0, 1.0]
    lm[12] = [0.4, 0.3, 0.0, 1.0]
    lm[23] = [0.55, 0.6, 0.0, 1.0]
    lm[24] = [0.45, 0.6, 0.0, 1.0]
    # Left elbow 90 deg: 11=(0.6, 0.3), 13=(0.6, 0.5), 15=(0.8, 0.5)
    lm[13] = [0.6, 0.5, 0.0, 1.0]
    lm[15] = [0.8, 0.5, 0.0, 1.0]
    # Right elbow 180 deg straight: 12=(0.4, 0.3), 14=(0.4, 0.5), 16=(0.4, 0.7)
    lm[14] = [0.4, 0.5, 0.0, 1.0]
    lm[16] = [0.4, 0.7, 0.0, 1.0]

    feats = extract_features(lm)
    idx = {name: i for i, name in enumerate(FEATURE_NAMES)}
    np.testing.assert_allclose(feats[idx["left_elbow_angle_deg"]], 0.5, atol=1e-9)
    np.testing.assert_allclose(feats[idx["right_elbow_angle_deg"]], 1.0, atol=1e-9)
    np.testing.assert_allclose(feats[idx["active_elbow_angle_norm"]], 0.75, atol=1e-9)
    np.testing.assert_allclose(feats[idx["torso_lean_norm"]], 0.0, atol=1e-9)
    np.testing.assert_allclose(feats[idx["shoulder_to_torso_ratio"]], 0.2 / 0.3, atol=1e-9)
    np.testing.assert_allclose(feats[idx["upper_vis_mean"]], 1.0, atol=1e-9)
    np.testing.assert_allclose(feats[idx["bilateral_vis_asym"]], 0.0, atol=1e-9)


# ---------------------------------------------------------------------------
# 3. Exported Weights, Parity Vectors & GroupKFold Eval Report Tests
# ---------------------------------------------------------------------------


def test_exported_weights_schema_and_size() -> None:
    weights_path = EXPORT_DIR / "phase5_ml_weights.json"
    assert weights_path.exists(), f"Missing exported weights: {weights_path}"

    size_bytes = weights_path.stat().st_size
    assert size_bytes < 150 * 1024, f"Weights file too large: {size_bytes} bytes (>= 150 KB)"

    payload = json.loads(weights_path.read_text(encoding="utf-8"))
    assert payload["schema_version"] == "saman_p5_ml_v1"
    assert tuple(payload["feature_names"]) == FEATURE_NAMES

    def _check_model(model: dict, expected_labels: tuple[str, ...]) -> None:
        assert tuple(model["labels"]) == expected_labels
        assert len(model["scaler_mean"]) == 18
        assert len(model["scaler_scale"]) == 18
        assert np.all(np.asarray(model["scaler_scale"]) > 0.0)
        w1 = np.asarray(model["w1"])
        b1 = np.asarray(model["b1"])
        w2 = np.asarray(model["w2"])
        b2 = np.asarray(model["b2"])
        assert w1.shape == (18, 16)
        assert b1.shape == (16,)
        assert w2.shape == (16, 3)
        assert b2.shape == (3,)
        for arr in (w1, b1, w2, b2):
            assert np.all(np.isfinite(arr))

    _check_model(payload["view_angle_model"], VIEW_ANGLE_LABELS)
    phase_models = payload["exercise_phase_models"]
    assert set(phase_models.keys()) == set(EXERCISES)
    for ex in EXERCISES:
        _check_model(phase_models[ex], PHASE_LABELS)


def test_parity_vectors_match_forward_pass_under_1e_5() -> None:
    weights = json.loads((EXPORT_DIR / "phase5_ml_weights.json").read_text(encoding="utf-8"))
    parity = json.loads((EXPORT_DIR / "parity_vectors.json").read_text(encoding="utf-8"))

    vectors = parity["vectors"]
    assert len(vectors) == 10

    covered_exercises = {v["exercise_slug"] for v in vectors}
    covered_views = {v["ground_truth_view_angle"] for v in vectors}
    assert covered_exercises == set(EXERCISES)
    assert covered_views == set(VIEW_ANGLE_LABELS)

    for v in vectors:
        lm = np.asarray(v["landmarks_33x4"], dtype=np.float64)
        assert lm.shape == (33, 4)
        feats = extract_features(lm)
        np.testing.assert_allclose(
            feats,
            np.asarray(v["expected_features_18"], dtype=np.float64),
            atol=1e-5,
        )

        view_probs = forward_pass_from_weights(feats, weights["view_angle_model"])
        phase_probs = forward_pass_from_weights(
            feats, weights["exercise_phase_models"][v["exercise_slug"]]
        )
        assert math.isclose(float(np.sum(view_probs)), 1.0, abs_tol=1e-6)
        assert math.isclose(float(np.sum(phase_probs)), 1.0, abs_tol=1e-6)

        np.testing.assert_allclose(
            view_probs,
            np.asarray(v["expected_view_angle_probs"], dtype=np.float64),
            atol=1e-5,
        )
        np.testing.assert_allclose(
            phase_probs,
            np.asarray(v["expected_phase_probs"], dtype=np.float64),
            atol=1e-5,
        )


def test_eval_report_groupkfold_quality_and_anti_leakage() -> None:
    report_path = EXPORT_DIR / "phase5_eval_report.json"
    assert report_path.exists(), f"Missing eval report: {report_path}"
    report = json.loads(report_path.read_text(encoding="utf-8"))

    proto = report["anti_leakage_protocol"]
    assert proto["test_fold_augmented"] is False
    assert proto["disjoint_subject_assertion"] is True

    # View angle model quality threshold
    va = report["view_angle_model"]
    assert va["macro_f1"] >= 0.85, f"view_angle_model macro_f1 too low: {va['macro_f1']}"
    assert va["accuracy"] >= 0.85
    assert va["source_breakdown"]["real"] > 0

    # All 5 exercises meet macro-F1 >= 0.85 on unaugmented unseen-subject GroupKFold test splits
    ex_reports = report["exercise_phase_models"]
    assert set(ex_reports.keys()) == set(EXERCISES)
    for ex in EXERCISES:
        ev = ex_reports[ex]
        assert ev["macro_f1"] >= 0.85, f"{ex} macro_f1 too low: {ev['macro_f1']}"
        assert ev["accuracy"] >= 0.85
        assert ev["distinct_subjects"] >= 12
        # Confirm every fold has distinct test subjects across folds
        seen_test_subjects = set()
        for fold in ev["folds"]:
            fold_subs = set(fold["test_subjects"])
            assert fold_subs.isdisjoint(seen_test_subjects)
            seen_test_subjects.update(fold_subs)
