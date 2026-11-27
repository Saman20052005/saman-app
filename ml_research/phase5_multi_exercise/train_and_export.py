"""Phase 5 Multi-Exercise ML Training & Pure-Dart Weight Export Pipeline.

Reads Read-Only real landmark files from ``ml_research/data/`` (never modifies
any file outside ``ml_research/phase5_multi_exercise/``), combines them with a
deterministic multi-body-type 3D biomechanical dataset covering all 5 exercises
and all 3 camera view angles, evaluates strictly with leakage-proof
``GroupKFold(n_splits=5)`` on ``subject_id`` (augmenting ONLY ``X_train`` inside
each fold), and exports:
  - ``exported/phase5_ml_weights.json`` (< 150 KB, rounded to 6 decimals)
  - ``exported/phase5_eval_report.json`` (GroupKFold metrics + real/synth breakdown)
  - ``exported/parity_vectors.json`` (10 end-to-end verification vectors for Dart)
"""

from __future__ import annotations

import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score
from sklearn.model_selection import GroupKFold
from sklearn.neural_network import MLPClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

# Support running both as script (`python ml_research/phase5_multi_exercise/train_and_export.py`)
# and as module (`python -m ml_research.phase5_multi_exercise.train_and_export`).
_THIS_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _THIS_DIR.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from ml_research.phase5_multi_exercise.augmentation import (  # noqa: E402
    augment_training_samples,
    rotate_3d,
    simulate_mobile_noise,
)
from ml_research.phase5_multi_exercise.feature_extractor import (  # noqa: E402
    EXERCISES,
    FEATURE_NAMES,
    PHASE_LABELS,
    VIEW_ANGLE_LABELS,
    extract_features,
    extract_features_batch,
)

SEED: int = 42
HIDDEN_UNITS: int = 16
N_FOLDS: int = 5
SYNTH_SUBJECTS_PER_EXERCISE: int = 15
SAMPLES_PER_PHASE_PER_VIEW: int = 4
WEIGHT_DECIMALS: int = 6
ACTIVE_WINDOW_MARGIN_FRAMES: int = 30

DATA_DIR: Path = _THIS_DIR.parent / "data"
EXPORT_DIR: Path = _THIS_DIR / "exported"

REAL_PHASE_MAP: Dict[str, str] = {
    "EXTENDED": "top_idle",
    "TRANSITION": "transition",
    "CONTRACTED": "bottom_peak",
}

REAL_VIDEO_META: Dict[str, Dict[str, str | None]] = {
    "pullup": {"exercise": "pull-up", "view_angle": "frontal"},
    "pullup_45": {"exercise": "pull-up", "view_angle": "oblique45"},
    "lat_pulldown": {"exercise": "lat-pulldown", "view_angle": "frontal"},
    "blindspot": {"exercise": None, "view_angle": "side90"},
}


@dataclass
class PoseRecord:
    landmarks: np.ndarray  # (33, 4)
    exercise: str | None
    phase: str | None
    view_angle: str
    subject_id: str
    source: str  # "real" or "biomechanical_synthetic"


def _row_to_landmarks(row: np.ndarray) -> np.ndarray:
    return row.reshape(33, 4).astype(np.float64)


def load_real_records(data_dir: Path = DATA_DIR) -> Tuple[List[PoseRecord], Dict[str, int]]:
    """Read-Only loader for ml_research/data/{full_fps, mobile_4_5fps, frames_labeled}."""
    full_path = data_dir / "landmarks_full_fps.parquet"
    mobile_path = data_dir / "landmarks_mobile_4_5fps.parquet"
    labels_path = data_dir / "frames_labeled.csv"

    lm_cols: List[str] = []
    for i in range(33):
        lm_cols.extend([f"lm_{i}_x", f"lm_{i}_y", f"lm_{i}_z", f"lm_{i}_vis"])

    stats: Dict[str, int] = {
        "full_fps_rows_read": 0,
        "mobile_4_5fps_rows_read": 0,
        "frames_labeled_rows_read": 0,
        "real_records_loaded": 0,
    }
    if not (full_path.exists() and mobile_path.exists() and labels_path.exists()):
        return [], stats

    df_full = pd.read_parquet(full_path)
    df_mobile = pd.read_parquet(mobile_path)
    df_labels = pd.read_csv(labels_path)

    stats["full_fps_rows_read"] = int(len(df_full))
    stats["mobile_4_5fps_rows_read"] = int(len(df_mobile))
    stats["frames_labeled_rows_read"] = int(len(df_labels))

    label_cols = df_labels[["video_id", "frame_idx", "phase_label", "rep_id"]].drop_duplicates(
        subset=["video_id", "frame_idx"]
    )

    # Determine active exercise frame window [min_rep - margin, max_rep + margin] per video
    # so walk-in / camera-setup / post-set idle frames (rep_id == 0 outside the set)
    # do not corrupt exercise phase labels.
    active_windows: Dict[str, Tuple[int, int]] = {}
    for vid, grp in label_cols.groupby("video_id"):
        rep_frames = grp[grp["rep_id"] > 0]["frame_idx"]
        if len(rep_frames) > 0:
            active_windows[str(vid)] = (
                int(rep_frames.min()) - ACTIVE_WINDOW_MARGIN_FRAMES,
                int(rep_frames.max()) + ACTIVE_WINDOW_MARGIN_FRAMES,
            )

    # Prioritize every valid 4.5 FPS mobile frame, then add strided full_fps frames
    # (stride=5) deduplicated by (video_id, frame_idx) so real videos remain balanced
    # and never duplicate exact frames.
    df_mobile_valid = df_mobile[df_mobile["pose_detected"] == True].copy()  # noqa: E712
    df_full_valid = df_full[df_full["pose_detected"] == True].iloc[::5].copy()  # noqa: E712

    df_combined = pd.concat([df_mobile_valid, df_full_valid], ignore_index=True)
    df_combined = df_combined.drop_duplicates(subset=["video_id", "frame_idx"], keep="first")
    df_merged = df_combined.merge(label_cols, on=["video_id", "frame_idx"], how="inner")

    records: List[PoseRecord] = []
    lm_matrix = df_merged[lm_cols].to_numpy(dtype=np.float64)
    walkin_excluded = 0

    for idx, meta_row in enumerate(
        df_merged[["video_id", "frame_idx", "phase_label"]].itertuples(index=False)
    ):
        vid = str(meta_row.video_id)
        fidx = int(meta_row.frame_idx)
        if vid not in REAL_VIDEO_META:
            continue
        meta = REAL_VIDEO_META[vid]
        in_active_window = True
        if meta["exercise"] is not None and vid in active_windows:
            lo_f, hi_f = active_windows[vid]
            if fidx < lo_f or fidx > hi_f:
                in_active_window = False
                walkin_excluded += 1

        mapped_phase = REAL_PHASE_MAP.get(str(meta_row.phase_label))
        lm = _row_to_landmarks(lm_matrix[idx])
        if not np.all(np.isfinite(lm)):
            continue
        records.append(
            PoseRecord(
                landmarks=lm,
                exercise=meta["exercise"] if in_active_window else None,
                phase=(mapped_phase if (meta["exercise"] is not None and in_active_window) else None),
                view_angle=str(meta["view_angle"]),
                subject_id=f"real_{vid}",
                source="real",
            )
        )

    stats["real_records_loaded"] = len(records)
    stats["real_outside_active_window_excluded_from_phase"] = walkin_excluded
    return records, stats


# ---------------------------------------------------------------------------
# Biomechanical 3D Multi-Body-Type Skeleton Synthesizer
# ---------------------------------------------------------------------------


def _build_base_pose_dict(
    torso_len: float,
    sh_half_w: float,
    hip_half_w: float,
    torso_lean_forward_rad: float,
    hip_y: float = 0.56,
    hip_x: float = 0.50,
    hip_z: float = 0.0,
) -> Dict[int, np.ndarray]:
    """Construct upper-torso & head joints in canonical body frame (facing -Z)."""
    # Standing upright: shoulder is above hip (-Y) and tilted forward (-Z) if leaning
    sh_mid = np.array(
        [
            hip_x,
            hip_y - torso_len * math.cos(torso_lean_forward_rad),
            hip_z - torso_len * math.sin(torso_lean_forward_rad),
        ],
        dtype=np.float64,
    )
    hip_mid = np.array([hip_x, hip_y, hip_z], dtype=np.float64)

    pts: Dict[int, np.ndarray] = {}
    # MediaPipe left is +X (viewer's right) when facing camera
    pts[11] = sh_mid + np.array([sh_half_w, 0.0, 0.0])
    pts[12] = sh_mid + np.array([-sh_half_w, 0.0, 0.0])
    pts[23] = hip_mid + np.array([hip_half_w, 0.0, 0.0])
    pts[24] = hip_mid + np.array([-hip_half_w, 0.0, 0.0])

    # Head/face landmarks (0..10) above shoulder midpoint
    head_up = np.array(
        [
            0.0,
            -0.30 * torso_len * math.cos(torso_lean_forward_rad),
            -0.30 * torso_len * math.sin(torso_lean_forward_rad),
        ],
        dtype=np.float64,
    )
    nose = sh_mid + head_up + np.array([0.0, 0.0, -0.06 * torso_len])
    pts[0] = nose
    eye_dx = 0.09 * torso_len
    ear_dx = 0.17 * torso_len
    mouth_dx = 0.06 * torso_len
    pts[1] = nose + np.array([0.5 * eye_dx, -0.04 * torso_len, 0.02 * torso_len])
    pts[2] = nose + np.array([eye_dx, -0.04 * torso_len, 0.02 * torso_len])
    pts[3] = nose + np.array([1.4 * eye_dx, -0.04 * torso_len, 0.03 * torso_len])
    pts[4] = nose + np.array([-0.5 * eye_dx, -0.04 * torso_len, 0.02 * torso_len])
    pts[5] = nose + np.array([-eye_dx, -0.04 * torso_len, 0.02 * torso_len])
    pts[6] = nose + np.array([-1.4 * eye_dx, -0.04 * torso_len, 0.03 * torso_len])
    pts[7] = nose + np.array([ear_dx, -0.02 * torso_len, 0.08 * torso_len])
    pts[8] = nose + np.array([-ear_dx, -0.02 * torso_len, 0.08 * torso_len])
    pts[9] = nose + np.array([mouth_dx, 0.07 * torso_len, 0.01 * torso_len])
    pts[10] = nose + np.array([-mouth_dx, 0.07 * torso_len, 0.01 * torso_len])
    return pts


def _fill_hands_and_feet(pts: Dict[int, np.ndarray], torso_len: float) -> None:
    """Populate finger (17..22) and foot (29..32) landmarks from wrists/ankles."""
    hand_scale = 0.10 * torso_len
    for wrist_i, elbow_i, pinky_i, index_i, thumb_i, side in (
        (15, 13, 17, 19, 21, 1.0),
        (16, 14, 18, 20, 22, -1.0),
    ):
        d = pts[wrist_i] - pts[elbow_i]
        norm = max(float(np.linalg.norm(d)), 1e-4)
        u = d / norm
        pts[pinky_i] = pts[wrist_i] + u * hand_scale + np.array([side * 0.02 * torso_len, 0.0, 0.0])
        pts[index_i] = pts[wrist_i] + u * (1.2 * hand_scale)
        pts[thumb_i] = pts[wrist_i] + u * (0.7 * hand_scale) + np.array([-side * 0.03 * torso_len, 0.0, 0.0])

    foot_scale = 0.14 * torso_len
    for ankle_i, heel_i, foot_i in ((27, 29, 31), (28, 30, 32)):
        pts[heel_i] = pts[ankle_i] + np.array([0.0, 0.04 * torso_len, 0.06 * torso_len])
        pts[foot_i] = pts[ankle_i] + np.array([0.0, 0.05 * torso_len, -foot_scale])


def _assemble_33x4(
    pts: Dict[int, np.ndarray],
    view_angle: str,
    yaw_sign: float,
    base_vis: float,
    rng: np.random.Generator,
) -> np.ndarray:
    lm = np.zeros((33, 4), dtype=np.float64)
    for i in range(33):
        lm[i, :3] = pts[i]

    # View-dependent bilateral visibility pattern (far side slightly occluded at 45°/90°)
    vis = np.full((33,), base_vis, dtype=np.float64)
    left_set = {1, 2, 3, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31}
    right_set = {4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32}
    far_set = left_set if yaw_sign > 0 else right_set

    if view_angle == "oblique45":
        drop = float(rng.uniform(0.06, 0.18))
        for j in far_set:
            vis[j] -= drop
    elif view_angle == "side90":
        drop = float(rng.uniform(0.18, 0.42))
        for j in far_set:
            vis[j] -= drop

    vis += rng.normal(0.0, 0.025, size=33)
    lm[:, 3] = np.clip(vis, 0.10, 0.999)
    return lm


def _synthesize_pose(
    exercise: str,
    progress: float,
    view_angle: str,
    subject_params: Dict[str, float],
    rng: np.random.Generator,
) -> np.ndarray:
    """Generate a single 3D pose for (exercise, progress in [0, 1], view_angle)."""
    p = float(np.clip(progress, 0.0, 1.0))
    torso_len = subject_params["torso_len"]
    sh_half_w = 0.5 * subject_params["shoulder_width_ratio"] * torso_len
    hip_half_w = 0.5 * subject_params["hip_width_ratio"] * torso_len
    upper_arm = subject_params["upper_arm_ratio"] * torso_len
    forearm = subject_params["forearm_ratio"] * torso_len
    thigh = subject_params["thigh_ratio"] * torso_len
    shin = subject_params["shin_ratio"] * torso_len
    hip_x = subject_params["base_x"] + float(rng.normal(0.0, 0.02))
    hip_y = subject_params["base_y"] + float(rng.normal(0.0, 0.02))
    asym = subject_params["asym_bias"]

    if exercise in ("pull-up", "lat-pulldown"):
        # Overhead wide-grip pulling calibrated to real biomechanics:
        # p=0 dead-hang / overhead (elbow ~148°, wr_rel_sh ~ -0.70, el_rel_sh ~ -0.32)
        # p=0.5 mid-pull transition (elbow ~92°, wr_rel_sh ~ -0.47, el_rel_sh ~ -0.07)
        # p=1.0 peak contraction (elbow ~43°, wr_rel_sh ~ -0.07, el_rel_sh ~ +0.30)
        is_lat = exercise == "lat-pulldown"
        lean_deg = (10.0 if is_lat else 4.0) + 8.0 * p + float(rng.normal(0.0, 2.5))
        pts = _build_base_pose_dict(
            torso_len, sh_half_w, hip_half_w, math.radians(-lean_deg), hip_y=hip_y, hip_x=hip_x
        )

        # Wide-grip shoulder elevation from vertical-down (+Y): ~144° (p=0) -> ~38° (p=1)
        sh_elev_deg = 144.0 - (108.0 if is_lat else 102.0) * (p ** 0.92) + float(rng.normal(0.0, 5.0))
        sh_elev_deg = float(np.clip(sh_elev_deg, 25.0, 168.0))
        # Nonlinear flexion curve matching real pull-up/lat-pulldown transition (~90° at p=0.5)
        elbow_int_deg = 148.0 - 108.0 * (p ** 0.85) + float(rng.normal(0.0, 5.0))
        elbow_int_deg = float(np.clip(elbow_int_deg, 26.0, 172.0))

        # Effective foreshortened arm lengths in wide-grip overhead plane
        eff_upper = upper_arm * 0.86
        eff_fore = forearm * 0.86

        for side, sh_i, el_i, wr_i in ((1.0, 11, 13, 15), (-1.0, 12, 14, 16)):
            s_deg = sh_elev_deg + side * asym * 4.0
            e_deg = elbow_int_deg + side * asym * 4.0
            rad_s = math.radians(s_deg)
            u_dir = np.array(
                [side * math.sin(rad_s), math.cos(rad_s), -0.14 * math.sin(rad_s)],
                dtype=np.float64,
            )
            u_dir /= np.linalg.norm(u_dir)
            elbow = pts[sh_i] + eff_upper * u_dir

            # Forearm angles upward toward bar (interior angle e_deg at elbow)
            inward = np.array([-side * u_dir[1], side * u_dir[0], 0.0], dtype=np.float64)
            in_norm = float(np.linalg.norm(inward))
            if in_norm < 1e-6:
                inward = np.array([-side, 0.0, 0.0])
            else:
                inward /= in_norm
            if inward[1] > 0:
                inward = -inward
            rad_e = math.radians(e_deg)
            f_dir = (-u_dir) * math.cos(rad_e) + inward * math.sin(rad_e)
            f_dir[2] = -0.14 if is_lat else -0.08
            f_dir /= np.linalg.norm(f_dir)
            wrist = elbow + eff_fore * f_dir

            pts[el_i] = elbow
            pts[wr_i] = wrist

        # Legs: seated (~90° hip/knee) for lat-pulldown, slightly bent hanging for pull-up
        for side, hip_i, knee_i, ankle_i in ((1.0, 23, 25, 27), (-1.0, 24, 26, 28)):
            if is_lat:
                knee = pts[hip_i] + np.array(
                    [side * 0.10 * torso_len, 0.22 * thigh, -0.92 * thigh]
                )
                ankle = knee + np.array([0.0, 0.94 * shin, 0.14 * shin])
            else:
                bend = float(rng.uniform(0.20, 0.55))
                knee = pts[hip_i] + np.array(
                    [side * 0.05 * torso_len, thigh * math.cos(bend), -thigh * math.sin(bend)]
                )
                ankle = knee + np.array(
                    [0.0, shin * math.cos(bend * 1.3), shin * math.sin(bend * 1.3)]
                )
            pts[knee_i] = knee
            pts[ankle_i] = ankle

    elif exercise == "squat":
        # p=0 standing upright (top_idle), p=1 parallel/below-parallel bottom (bottom_peak)
        lean_deg = 4.0 + 30.0 * p + float(rng.normal(0.0, 3.0))
        drop_y = 0.72 * thigh * (p ** 1.05)
        cur_hip_y = hip_y - 0.15 * torso_len + drop_y
        pts = _build_base_pose_dict(
            torso_len, sh_half_w, hip_half_w, math.radians(lean_deg), hip_y=cur_hip_y, hip_x=hip_x
        )

        # Thigh angle from vertical down (+Y) swinging forward (-Z): 5° -> 96°
        thigh_fwd_deg = 5.0 + 90.0 * p + float(rng.normal(0.0, 4.0))
        # Shin leans slightly forward (-Z) from ankle up to knee: 2° -> 22°
        shin_fwd_deg = 2.0 + 20.0 * p + float(rng.normal(0.0, 2.5))
        t_rad = math.radians(thigh_fwd_deg)
        s_rad = math.radians(shin_fwd_deg)

        for side, hip_i, knee_i, ankle_i in ((1.0, 23, 25, 27), (-1.0, 24, 26, 28)):
            knee_out = side * (0.06 + 0.16 * p) * torso_len
            knee = pts[hip_i] + np.array(
                [knee_out, thigh * math.cos(t_rad), -thigh * math.sin(t_rad)]
            )
            ankle = knee + np.array(
                [0.0, shin * math.cos(s_rad), shin * math.sin(s_rad)]
            )
            pts[knee_i] = knee
            pts[ankle_i] = ankle

        # Arms: either forward counterbalance or hands near chest/shoulders
        arms_forward = subject_params["style_flag"] > 0.5
        for side, sh_i, el_i, wr_i in ((1.0, 11, 13, 15), (-1.0, 12, 14, 16)):
            if arms_forward:
                elbow = pts[sh_i] + np.array(
                    [side * 0.08 * torso_len, 0.25 * upper_arm * (1.0 - p), -0.92 * upper_arm]
                )
                wrist = elbow + np.array([0.0, 0.05 * forearm, -0.98 * forearm])
            else:
                elbow = pts[sh_i] + np.array(
                    [side * 0.20 * torso_len, 0.85 * upper_arm, -0.35 * upper_arm]
                )
                wrist = elbow + np.array(
                    [-side * 0.15 * torso_len, -0.55 * forearm, -0.75 * forearm]
                )
            pts[el_i] = elbow
            pts[wr_i] = wrist

    elif exercise == "push-up":
        # Prone plank: body lies horizontal along Z (head at -Z, feet at +Z),
        # facing floor (+Y). Rotating by yaw puts body horizontal in X at side90,
        # angled at oblique45, and head-on at frontal.
        # p=0 high plank (top_idle), p=1 chest near floor (bottom_peak)
        plank_pitch_deg = 78.0 + 10.0 * p + float(rng.normal(0.0, 2.5))
        # Build upright first then pitch forward ~85° so torso is horizontal!
        pts = _build_base_pose_dict(
            torso_len,
            sh_half_w,
            hip_half_w,
            math.radians(plank_pitch_deg),
            hip_y=hip_y + 0.05 * p,
            hip_x=hip_x,
        )

        # Straight legs continuing back along +Z (and slightly +Y to floor)
        leg_slope_rad = math.radians(max(2.0, 12.0 - 8.0 * p))
        for side, hip_i, knee_i, ankle_i in ((1.0, 23, 25, 27), (-1.0, 24, 26, 28)):
            knee = pts[hip_i] + np.array(
                [side * 0.02 * torso_len, thigh * math.sin(leg_slope_rad), thigh * math.cos(leg_slope_rad)]
            )
            ankle = knee + np.array(
                [0.0, shin * math.sin(leg_slope_rad), shin * math.cos(leg_slope_rad)]
            )
            pts[knee_i] = knee
            pts[ankle_i] = ankle

        # Floor y level under hands (constant relative to wrists)
        arm_reach = upper_arm + forearm
        # Height of shoulder above wrist drops from ~0.96*arm_reach (p=0) to ~0.28*arm_reach (p=1)
        sh_to_wr_y = arm_reach * (0.96 - 0.68 * p) + float(rng.normal(0.0, 0.015))
        sh_to_wr_y = max(0.18 * arm_reach, min(0.99 * arm_reach, sh_to_wr_y))

        for side, sh_i, el_i, wr_i in ((1.0, 11, 13, 15), (-1.0, 12, 14, 16)):
            wrist = pts[sh_i] + np.array([side * 0.14 * torso_len, sh_to_wr_y, 0.02 * torso_len])
            # Solve triangle for elbow flaring outward (+side*X) and backward (+Z)
            d_vec = wrist - pts[sh_i]
            d_len = max(float(np.linalg.norm(d_vec)), 1e-4)
            d_len_clamped = min(d_len, upper_arm + forearm - 1e-4)
            # Law of cosines for shoulder-to-elbow offset along d_vec
            cos_a = (upper_arm**2 + d_len_clamped**2 - forearm**2) / (
                2.0 * upper_arm * d_len_clamped
            )
            cos_a = float(np.clip(cos_a, -1.0, 1.0))
            sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
            u_along = d_vec / d_len
            # Flare direction: outward in X and backward in +Z
            flare = np.array([side * 0.65, -0.15, 0.75], dtype=np.float64)
            flare = flare - np.dot(flare, u_along) * u_along
            flare /= max(float(np.linalg.norm(flare)), 1e-6)
            elbow = pts[sh_i] + upper_arm * (cos_a * u_along + sin_a * flare)
            pts[el_i] = elbow
            pts[wr_i] = wrist

    elif exercise == "bicep-curl":
        # Standing upright, upper arms tucked at sides, forearms curl up (-Z -> -Y)
        # p=0 extended down (top_idle), p=1 fully curled (bottom_peak)
        lean_deg = 2.0 + float(rng.normal(0.0, 3.0))
        pts = _build_base_pose_dict(
            torso_len, sh_half_w, hip_half_w, math.radians(lean_deg), hip_y=hip_y, hip_x=hip_x
        )

        # Standing straight legs
        for side, hip_i, knee_i, ankle_i in ((1.0, 23, 25, 27), (-1.0, 24, 26, 28)):
            knee = pts[hip_i] + np.array([side * 0.03 * torso_len, thigh * 0.99, -0.05 * thigh])
            ankle = knee + np.array([0.0, shin * 0.99, 0.04 * shin])
            pts[knee_i] = knee
            pts[ankle_i] = ankle

        # Upper arm hangs near torso (slight forward swing at peak curl)
        upper_fwd_deg = 4.0 + 10.0 * p + float(rng.normal(0.0, 2.5))
        # Interior elbow angle: 168° at p=0 down to 36° at p=1
        elbow_int_deg = 168.0 - 130.0 * p + float(rng.normal(0.0, 4.5))
        elbow_int_deg = float(np.clip(elbow_int_deg, 25.0, 179.0))

        for side, sh_i, el_i, wr_i in ((1.0, 11, 13, 15), (-1.0, 12, 14, 16)):
            u_rad = math.radians(upper_fwd_deg)
            u_dir = np.array(
                [side * 0.08, math.cos(u_rad), -math.sin(u_rad)],
                dtype=np.float64,
            )
            u_dir /= np.linalg.norm(u_dir)
            elbow = pts[sh_i] + upper_arm * u_dir

            # Forearm bends forward (-Z) and upward (-Y) from elbow
            e_rad = math.radians(elbow_int_deg + side * asym * 3.0)
            fwd_perp = np.array([0.0, -math.sin(u_rad), -math.cos(u_rad)], dtype=np.float64)
            fwd_perp /= np.linalg.norm(fwd_perp)
            f_dir = (-u_dir) * math.cos(e_rad) + fwd_perp * math.sin(e_rad)
            f_dir /= np.linalg.norm(f_dir)
            wrist = elbow + forearm * f_dir

            pts[el_i] = elbow
            pts[wr_i] = wrist
    else:
        raise ValueError(f"Unsupported exercise: {exercise}")

    _fill_hands_and_feet(pts, torso_len)

    # Sample target camera yaw angle for the requested view_angle
    yaw_sign = 1.0 if rng.random() < 0.5 else -1.0
    if view_angle == "frontal":
        yaw_deg = float(rng.uniform(-16.0, 16.0))
    elif view_angle == "oblique45":
        yaw_deg = yaw_sign * float(rng.uniform(33.0, 57.0))
    elif view_angle == "side90":
        yaw_deg = yaw_sign * float(rng.uniform(76.0, 104.0))
    else:
        raise ValueError(f"Unsupported view_angle: {view_angle}")

    lm = _assemble_33x4(
        pts,
        view_angle=view_angle,
        yaw_sign=yaw_sign,
        base_vis=subject_params["base_vis"],
        rng=rng,
    )

    pitch_deg = float(rng.uniform(-7.0, 7.0))
    roll_deg = float(rng.uniform(-5.0, 5.0))
    lm = rotate_3d(lm, yaw_deg=yaw_deg, pitch_deg=pitch_deg, roll_deg=roll_deg)

    # Match MediaPipe Z-depth scaling variance seen in real footage
    z_center = 0.5 * (lm[23, 2] + lm[24, 2])
    lm[:, 2] = z_center + (lm[:, 2] - z_center) * subject_params["z_scale"]

    # Light sensor noise on raw pose capture
    lm = simulate_mobile_noise(lm, rng=rng, pos_sigma=0.006, vis_drop_prob=0.02)
    return lm


def generate_biomechanical_records(
    rng: np.random.Generator,
    subjects_per_exercise: int = SYNTH_SUBJECTS_PER_EXERCISE,
    samples_per_phase_per_view: int = SAMPLES_PER_PHASE_PER_VIEW,
) -> List[PoseRecord]:
    """Generate multi-body-type 3D poses across all 5 exercises and 3 view angles."""
    phase_ranges: Dict[str, Tuple[float, float]] = {
        "top_idle": (0.00, 0.20),
        "transition": (0.32, 0.68),
        "bottom_peak": (0.80, 1.00),
    }

    records: List[PoseRecord] = []
    for ex in EXERCISES:
        for s_idx in range(subjects_per_exercise):
            subject_id = f"synth_{ex}_subj_{s_idx:02d}"
            subject_params = {
                "torso_len": float(rng.uniform(0.16, 0.31)),
                "shoulder_width_ratio": float(rng.uniform(0.70, 0.94)),
                "hip_width_ratio": float(rng.uniform(0.38, 0.56)),
                "upper_arm_ratio": float(rng.uniform(0.50, 0.62)),
                "forearm_ratio": float(rng.uniform(0.45, 0.58)),
                "thigh_ratio": float(rng.uniform(0.76, 0.92)),
                "shin_ratio": float(rng.uniform(0.72, 0.88)),
                "base_x": float(rng.uniform(0.40, 0.60)),
                "base_y": float(rng.uniform(0.44, 0.60)),
                "asym_bias": float(rng.uniform(-1.0, 1.0)),
                "base_vis": float(rng.uniform(0.84, 0.98)),
                "z_scale": float(rng.uniform(1.05, 1.65)),
                "style_flag": float(rng.random()),
            }
            for view_angle in VIEW_ANGLE_LABELS:
                for phase in PHASE_LABELS:
                    lo, hi = phase_ranges[phase]
                    for _ in range(samples_per_phase_per_view):
                        prog = float(rng.uniform(lo, hi))
                        lm = _synthesize_pose(ex, prog, view_angle, subject_params, rng)
                        records.append(
                            PoseRecord(
                                landmarks=lm,
                                exercise=ex,
                                phase=phase,
                                view_angle=view_angle,
                                subject_id=subject_id,
                                source="biomechanical_synthetic",
                            )
                        )
    return records


# ---------------------------------------------------------------------------
# Model Training, Leakage-Proof GroupKFold, Serialization & Pure Forward Pass
# ---------------------------------------------------------------------------


def _build_pipeline(seed: int = SEED) -> Pipeline:
    return Pipeline(
        [
            ("scaler", StandardScaler()),
            (
                "mlp",
                MLPClassifier(
                    hidden_layer_sizes=(HIDDEN_UNITS,),
                    activation="relu",
                    solver="adam",
                    alpha=0.01,
                    batch_size=128,
                    learning_rate_init=0.008,
                    max_iter=350,
                    n_iter_no_change=12,
                    tol=5e-4,
                    random_state=seed,
                ),
            ),
        ]
    )


def evaluate_and_train_model(
    landmarks: np.ndarray,
    labels: np.ndarray,
    groups: np.ndarray,
    sources: Sequence[str],
    canonical_labels: Tuple[str, ...],
    model_name: str,
    seed: int = SEED,
    yaw_jitter_deg: float = 15.0,
    copies_per_sample: int = 3,
) -> Tuple[Dict[str, object], Dict[str, object]]:
    """Run leakage-proof GroupKFold evaluation, then train final exportable model."""
    unique_groups = np.unique(groups)
    n_splits = min(N_FOLDS, len(unique_groups))
    if n_splits < 2:
        raise ValueError(f"{model_name}: Need >= 2 distinct subject groups, got {len(unique_groups)}")

    gkf = GroupKFold(n_splits=n_splits)
    y_true_all: List[str] = []
    y_pred_all: List[str] = []
    fold_metrics: List[Dict[str, object]] = []

    for fold_idx, (train_idx, test_idx) in enumerate(gkf.split(landmarks, labels, groups)):
        train_groups = set(groups[train_idx].tolist())
        test_groups = set(groups[test_idx].tolist())
        # Hard anti-leakage invariant
        assert train_groups.isdisjoint(test_groups), (
            f"DATA LEAKAGE DETECTED in {model_name} fold {fold_idx}"
        )

        # Augment ONLY X_train inside this fold; X_test stays 100% raw & unaugmented
        fold_rng = np.random.default_rng(seed + 1000 + fold_idx * 37)
        lm_train_aug, y_train_aug = augment_training_samples(
            landmarks[train_idx],
            labels[train_idx],
            rng=fold_rng,
            copies_per_sample=copies_per_sample,
            yaw_jitter_deg=yaw_jitter_deg,
            pitch_jitter_deg=8.0,
            roll_jitter_deg=8.0,
            pos_sigma=0.012,
            vis_drop_prob=0.05,
            allow_mirror=True,
        )

        x_train = extract_features_batch(lm_train_aug)
        x_test = extract_features_batch(landmarks[test_idx])
        y_test = labels[test_idx]

        pipe = _build_pipeline(seed=seed + fold_idx)
        pipe.fit(x_train, y_train_aug)
        preds = pipe.predict(x_test)

        y_true_all.extend(y_test.tolist())
        y_pred_all.extend(preds.tolist())

        fold_metrics.append(
            {
                "fold": fold_idx,
                "train_raw_samples": int(len(train_idx)),
                "train_augmented_samples": int(len(lm_train_aug)),
                "test_raw_samples": int(len(test_idx)),
                "test_subjects": sorted(list(test_groups)),
                "macro_f1": round(
                    float(f1_score(y_test, preds, labels=list(canonical_labels), average="macro", zero_division=0)),
                    6,
                ),
                "accuracy": round(float(accuracy_score(y_test, preds)), 6),
            }
        )

    overall_macro_f1 = float(
        f1_score(y_true_all, y_pred_all, labels=list(canonical_labels), average="macro", zero_division=0)
    )
    overall_acc = float(accuracy_score(y_true_all, y_pred_all))
    cm = confusion_matrix(y_true_all, y_pred_all, labels=list(canonical_labels)).tolist()

    # Train final model on all available samples (with deterministic train augmentation)
    final_rng = np.random.default_rng(seed + 9999)
    lm_full_aug, y_full_aug = augment_training_samples(
        landmarks,
        labels,
        rng=final_rng,
        copies_per_sample=copies_per_sample,
        yaw_jitter_deg=yaw_jitter_deg,
        pitch_jitter_deg=8.0,
        roll_jitter_deg=8.0,
        pos_sigma=0.012,
        vis_drop_prob=0.05,
        allow_mirror=True,
    )
    x_full = extract_features_batch(lm_full_aug)
    final_pipe = _build_pipeline(seed=seed)
    final_pipe.fit(x_full, y_full_aug)

    weights_dict = _export_pipeline_weights(final_pipe, canonical_labels)

    src_counts = {
        "real": int(sum(1 for s in sources if s == "real")),
        "biomechanical_synthetic": int(sum(1 for s in sources if s == "biomechanical_synthetic")),
    }
    eval_summary: Dict[str, object] = {
        "labels": list(canonical_labels),
        "n_splits": n_splits,
        "total_raw_samples": int(len(landmarks)),
        "distinct_subjects": int(len(unique_groups)),
        "source_breakdown": src_counts,
        "macro_f1": round(overall_macro_f1, 6),
        "accuracy": round(overall_acc, 6),
        "confusion_matrix": cm,
        "folds": fold_metrics,
    }
    return weights_dict, eval_summary


def _round_list(arr: np.ndarray, decimals: int = WEIGHT_DECIMALS) -> List:
    return np.round(arr, decimals).tolist()


def _export_pipeline_weights(
    pipe: Pipeline,
    canonical_labels: Tuple[str, ...],
) -> Dict[str, object]:
    """Serialize StandardScaler + 1-hidden-layer ReLU MLP in canonical label order."""
    scaler: StandardScaler = pipe.named_steps["scaler"]
    mlp: MLPClassifier = pipe.named_steps["mlp"]

    classes = list(mlp.classes_)
    col_order = [classes.index(lbl) for lbl in canonical_labels]

    w1 = mlp.coefs_[0]  # (18, 16)
    b1 = mlp.intercepts_[0]  # (16,)
    w2 = mlp.coefs_[1][:, col_order]  # (16, 3)
    b2 = mlp.intercepts_[1][col_order]  # (3,)

    # Guard against zero scale
    scale = np.where(np.abs(scaler.scale_) < 1e-8, 1.0, scaler.scale_)

    return {
        "labels": list(canonical_labels),
        "scaler_mean": _round_list(scaler.mean_),
        "scaler_scale": _round_list(scale),
        "w1": _round_list(w1),
        "b1": _round_list(b1),
        "w2": _round_list(w2),
        "b2": _round_list(b2),
    }


def forward_pass_from_weights(
    features_18: Sequence[float] | np.ndarray,
    model_weights: Dict[str, object],
) -> np.ndarray:
    """Pure NumPy forward pass matching pure Dart inference 1-to-1.

    Steps:
      1. ``x = (features - scaler_mean) / scaler_scale``
      2. ``h = relu(x @ w1 + b1)``
      3. ``logits = h @ w2 + b2``
      4. ``probs = softmax(logits - max(logits))``
    """
    x = np.asarray(features_18, dtype=np.float64)
    mean = np.asarray(model_weights["scaler_mean"], dtype=np.float64)
    scale = np.asarray(model_weights["scaler_scale"], dtype=np.float64)
    w1 = np.asarray(model_weights["w1"], dtype=np.float64)
    b1 = np.asarray(model_weights["b1"], dtype=np.float64)
    w2 = np.asarray(model_weights["w2"], dtype=np.float64)
    b2 = np.asarray(model_weights["b2"], dtype=np.float64)

    x_norm = (x - mean) / scale
    hidden = np.maximum(0.0, x_norm @ w1 + b1)
    logits = hidden @ w2 + b2
    logits = logits - np.max(logits)
    exp_logits = np.exp(logits)
    probs = exp_logits / np.sum(exp_logits)
    return probs


def build_parity_vectors(
    records: Sequence[PoseRecord],
    loaded_weights: Dict[str, object],
) -> List[Dict[str, object]]:
    """Select 10 diverse verification vectors covering all 5 exercises & 3 views."""
    targets: List[Tuple[str, str, str]] = [
        ("pull-up", "frontal", "bottom_peak"),
        ("pull-up", "oblique45", "top_idle"),
        ("lat-pulldown", "frontal", "bottom_peak"),
        ("lat-pulldown", "side90", "transition"),
        ("squat", "frontal", "top_idle"),
        ("squat", "side90", "bottom_peak"),
        ("push-up", "oblique45", "bottom_peak"),
        ("push-up", "side90", "top_idle"),
        ("bicep-curl", "frontal", "bottom_peak"),
        ("bicep-curl", "oblique45", "transition"),
    ]

    vectors: List[Dict[str, object]] = []
    used_indices = set()

    for idx_vec, (ex, view, phase) in enumerate(targets):
        # Prefer a real sample when available for the requested (ex, view, phase)
        chosen = None
        for r_idx, rec in enumerate(records):
            if r_idx in used_indices:
                continue
            if rec.exercise == ex and rec.view_angle == view and rec.phase == phase:
                if rec.source == "real":
                    chosen = (r_idx, rec)
                    break
                if chosen is None:
                    chosen = (r_idx, rec)
        assert chosen is not None, f"No sample found for parity vector {(ex, view, phase)}"
        r_idx, rec = chosen
        used_indices.add(r_idx)

        lm_rounded = np.round(rec.landmarks, 6)
        feats = extract_features(lm_rounded)
        view_probs = forward_pass_from_weights(feats, loaded_weights["view_angle_model"])
        phase_probs = forward_pass_from_weights(
            feats, loaded_weights["exercise_phase_models"][ex]
        )

        vectors.append(
            {
                "vector_id": f"pv_{idx_vec + 1:02d}_{ex}_{view}_{phase}",
                "exercise_slug": ex,
                "ground_truth_view_angle": view,
                "ground_truth_phase": phase,
                "source": rec.source,
                "landmarks_33x4": lm_rounded.tolist(),
                "expected_features_18": np.round(feats, 8).tolist(),
                "expected_view_angle_probs": np.round(view_probs, 8).tolist(),
                "expected_phase_probs": np.round(phase_probs, 8).tolist(),
            }
        )

    return vectors


def run_pipeline(
    data_dir: Path = DATA_DIR,
    export_dir: Path = EXPORT_DIR,
    seed: int = SEED,
) -> Tuple[Path, Path, Path]:
    """Execute full Phase 5 training, GroupKFold evaluation, and JSON export."""
    export_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)

    real_records, real_stats = load_real_records(data_dir=data_dir)
    synth_records = generate_biomechanical_records(rng=rng)
    all_records = real_records + synth_records

    print(
        f"[Phase5-ML] Loaded real records: {len(real_records)} "
        f"(full_fps={real_stats['full_fps_rows_read']}, "
        f"mobile_4_5fps={real_stats['mobile_4_5fps_rows_read']}, "
        f"labeled={real_stats['frames_labeled_rows_read']})"
    )
    print(f"[Phase5-ML] Generated biomechanical synthetic records: {len(synth_records)}")

    # 1. Train & evaluate View Angle Model (use smaller yaw jitter ±8° to keep angle labels pure)
    va_lm = np.stack([r.landmarks for r in all_records], axis=0)
    va_labels = np.array([r.view_angle for r in all_records])
    va_groups = np.array([r.subject_id for r in all_records])
    va_sources = [r.source for r in all_records]

    view_weights, view_eval = evaluate_and_train_model(
        landmarks=va_lm,
        labels=va_labels,
        groups=va_groups,
        sources=va_sources,
        canonical_labels=VIEW_ANGLE_LABELS,
        model_name="view_angle_model",
        seed=seed,
        yaw_jitter_deg=8.0,
        copies_per_sample=3,
    )
    print(
        f"[Phase5-ML] view_angle_model     | GroupKFold macro_f1={view_eval['macro_f1']:.4f} "
        f"| acc={view_eval['accuracy']:.4f} | raw={view_eval['total_raw_samples']} "
        f"(real={view_eval['source_breakdown']['real']}, synth={view_eval['source_breakdown']['biomechanical_synthetic']})"
    )

    # 2. Train & evaluate 5 Exercise Phase Models
    phase_weights_map: Dict[str, Dict[str, object]] = {}
    phase_eval_map: Dict[str, Dict[str, object]] = {}

    for ex_idx, ex in enumerate(EXERCISES):
        ex_recs = [r for r in all_records if r.exercise == ex and r.phase is not None]
        ex_lm = np.stack([r.landmarks for r in ex_recs], axis=0)
        ex_labels = np.array([str(r.phase) for r in ex_recs])
        ex_groups = np.array([r.subject_id for r in ex_recs])
        ex_sources = [r.source for r in ex_recs]

        ex_w, ex_ev = evaluate_and_train_model(
            landmarks=ex_lm,
            labels=ex_labels,
            groups=ex_groups,
            sources=ex_sources,
            canonical_labels=PHASE_LABELS,
            model_name=f"phase_model_{ex}",
            seed=seed + (ex_idx + 1) * 101,
            yaw_jitter_deg=15.0,
            copies_per_sample=3,
        )
        phase_weights_map[ex] = ex_w
        phase_eval_map[ex] = ex_ev
        print(
            f"[Phase5-ML] phase:{ex:13s} | GroupKFold macro_f1={ex_ev['macro_f1']:.4f} "
            f"| acc={ex_ev['accuracy']:.4f} | raw={ex_ev['total_raw_samples']} "
            f"(real={ex_ev['source_breakdown']['real']}, synth={ex_ev['source_breakdown']['biomechanical_synthetic']})"
        )

    # 3. Export compact JSON weights
    weights_payload: Dict[str, object] = {
        "schema_version": "saman_p5_ml_v1",
        "architecture": {
            "type": "standard_scaler_mlp_relu_softmax",
            "input_dim": len(FEATURE_NAMES),
            "hidden_dim": HIDDEN_UNITS,
            "output_dim": 3,
            "activation": "relu",
            "ops_per_inference": len(FEATURE_NAMES) * HIDDEN_UNITS + HIDDEN_UNITS + HIDDEN_UNITS * 3 + 3,
        },
        "feature_names": list(FEATURE_NAMES),
        "view_angle_model": view_weights,
        "exercise_phase_models": phase_weights_map,
    }

    weights_path = export_dir / "phase5_ml_weights.json"
    with open(weights_path, "w", encoding="utf-8") as fh:
        json.dump(weights_payload, fh, separators=(",", ":"))
    weights_size_bytes = weights_path.stat().st_size

    # Reload exact serialized JSON so parity vectors reflect quantized JSON weights
    with open(weights_path, "r", encoding="utf-8") as fh:
        reloaded_weights = json.load(fh)

    # 4. Export 10 parity vectors
    parity_vectors = build_parity_vectors(all_records, reloaded_weights)
    parity_payload = {
        "schema_version": "saman_p5_ml_v1",
        "weights_file": "phase5_ml_weights.json",
        "tolerance": 1e-4,
        "feature_names": list(FEATURE_NAMES),
        "view_angle_labels": list(VIEW_ANGLE_LABELS),
        "phase_labels": list(PHASE_LABELS),
        "vectors": parity_vectors,
    }
    parity_path = export_dir / "parity_vectors.json"
    with open(parity_path, "w", encoding="utf-8") as fh:
        json.dump(parity_payload, fh, indent=2)

    # 5. Export GroupKFold evaluation report
    eval_report = {
        "schema_version": "saman_p5_ml_v1",
        "seed": seed,
        "anti_leakage_protocol": {
            "cv_strategy": "GroupKFold(n_splits=5) on subject_id",
            "augmentation_scope": "X_train_only_inside_each_fold",
            "test_fold_augmented": False,
            "disjoint_subject_assertion": True,
        },
        "data_provenance": {
            "real_data_dir": "ml_research/data/ (Read-Only)",
            "real_files_stats": real_stats,
            "real_video_mapping": REAL_VIDEO_META,
            "synthetic_generator": {
                "type": "3D biomechanical multi-body-type kinematics",
                "subjects_per_exercise": SYNTH_SUBJECTS_PER_EXERCISE,
                "samples_per_phase_per_view": SAMPLES_PER_PHASE_PER_VIEW,
                "total_synthetic_records": len(synth_records),
            },
        },
        "weights_artifact": {
            "path": "ml_research/phase5_multi_exercise/exported/phase5_ml_weights.json",
            "size_bytes": weights_size_bytes,
            "size_kb": round(weights_size_bytes / 1024.0, 2),
        },
        "view_angle_model": view_eval,
        "exercise_phase_models": phase_eval_map,
    }
    report_path = export_dir / "phase5_eval_report.json"
    with open(report_path, "w", encoding="utf-8") as fh:
        json.dump(eval_report, fh, indent=2)

    print(
        f"[Phase5-ML] Exported {weights_path.name} ({weights_size_bytes / 1024.0:.2f} KB), "
        f"{report_path.name}, and {parity_path.name} ({len(parity_vectors)} vectors)."
    )
    return weights_path, report_path, parity_path


if __name__ == "__main__":
    run_pipeline()
