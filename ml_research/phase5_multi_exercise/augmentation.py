"""Geometric Data Augmentation for 33-landmark MediaPipe Pose skeletons.

Supports single-frame arrays of shape ``(33, 4)`` (``[x, y, z, visibility]``)
and sequence arrays of shape ``(T, 33, 4)``.

Anti-leakage rule:
    ``augment_training_samples`` MUST ONLY be invoked inside each ``GroupKFold``
    training split (``X_train``) and NEVER before splitting Train/Test.
"""

from __future__ import annotations

import math
from typing import Tuple

import numpy as np

# Exact MediaPipe Pose left/right landmark swap pairs
MIRROR_PAIRS: Tuple[Tuple[int, int], ...] = (
    (1, 4),
    (2, 5),
    (3, 6),
    (7, 8),
    (9, 10),
    (11, 12),
    (13, 14),
    (15, 16),
    (17, 18),
    (19, 20),
    (21, 22),
    (23, 24),
    (25, 26),
    (27, 28),
    (29, 30),
    (31, 32),
)

MIN_BONE_SCALE: float = 0.85
MAX_BONE_SCALE: float = 1.15


def _validate_landmarks(lm: np.ndarray) -> np.ndarray:
    arr = np.asarray(lm, dtype=np.float64)
    if arr.ndim not in (2, 3) or arr.shape[-2:] != (33, 4):
        raise ValueError(
            f"Expected landmarks shape (33, 4) or (T, 33, 4), got {arr.shape}"
        )
    return arr.copy()


def mirror_horizontal(lm: np.ndarray) -> np.ndarray:
    """Flip x -> 1.0 - x and swap MediaPipe left/right landmark pairs.

    Preserves y, z, and visibility on each swapped landmark.
    """
    out = _validate_landmarks(lm)
    out[..., 0] = 1.0 - out[..., 0]
    swapped = out.copy()
    for left_idx, right_idx in MIRROR_PAIRS:
        swapped[..., left_idx, :] = out[..., right_idx, :]
        swapped[..., right_idx, :] = out[..., left_idx, :]
    return swapped


def scale_bone_proportions(
    lm: np.ndarray,
    scale_x: float,
    scale_y: float,
) -> np.ndarray:
    """Scale skeletal coordinates around hip midpoint within ±15% ([0.85, 1.15]).

    Visibility channel ``[..., 3]`` is preserved untouched.
    """
    out = _validate_landmarks(lm)
    sx = float(np.clip(scale_x, MIN_BONE_SCALE, MAX_BONE_SCALE))
    sy = float(np.clip(scale_y, MIN_BONE_SCALE, MAX_BONE_SCALE))
    sz = 0.5 * (sx + sy)

    hip_mid = 0.5 * (out[..., 23:24, :3] + out[..., 24:25, :3])
    rel = out[..., :3] - hip_mid
    rel[..., 0] *= sx
    rel[..., 1] *= sy
    rel[..., 2] *= sz
    out[..., :3] = hip_mid + rel
    return out


def rotate_3d(
    lm: np.ndarray,
    yaw_deg: float,
    pitch_deg: float,
    roll_deg: float,
) -> np.ndarray:
    """Rotate 3D landmark coordinates (x, y, z) around torso center.

    Rotation order: R = R_z(roll) @ R_x(pitch) @ R_y(yaw).
    In MediaPipe image coordinates (x right, y down, z depth):
      - yaw rotates around vertical Y axis (synthesizes 0°/45°/90° camera views)
      - pitch tilts forward/backward around horizontal X axis
      - roll tilts camera horizon around Z axis
    Visibility channel ``[..., 3]`` is preserved untouched.
    """
    out = _validate_landmarks(lm)
    yaw = math.radians(float(yaw_deg))
    pitch = math.radians(float(pitch_deg))
    roll = math.radians(float(roll_deg))

    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    cr, sr = math.cos(roll), math.sin(roll)

    r_y = np.array(
        [[cy, 0.0, sy], [0.0, 1.0, 0.0], [-sy, 0.0, cy]],
        dtype=np.float64,
    )
    r_x = np.array(
        [[1.0, 0.0, 0.0], [0.0, cp, -sp], [0.0, sp, cp]],
        dtype=np.float64,
    )
    r_z = np.array(
        [[cr, -sr, 0.0], [sr, cr, 0.0], [0.0, 0.0, 1.0]],
        dtype=np.float64,
    )
    rot = r_z @ r_x @ r_y

    torso_center = 0.25 * (
        out[..., 11:12, :3]
        + out[..., 12:13, :3]
        + out[..., 23:24, :3]
        + out[..., 24:25, :3]
    )
    rel = out[..., :3] - torso_center
    rotated = rel @ rot.T
    out[..., :3] = torso_center + rotated
    return out


def simulate_mobile_noise(
    lm: np.ndarray,
    rng: np.random.Generator,
    pos_sigma: float = 0.012,
    vis_drop_prob: float = 0.05,
) -> np.ndarray:
    """Simulate 4.5 FPS mobile pose jitter and transient landmark occlusion."""
    out = _validate_landmarks(lm)
    if pos_sigma > 0.0:
        out[..., :3] += rng.normal(0.0, float(pos_sigma), size=out[..., :3].shape)

    vis = out[..., 3]
    if vis_drop_prob > 0.0:
        drop_mask = rng.random(size=vis.shape) < float(vis_drop_prob)
        if np.any(drop_mask):
            drop_factors = rng.uniform(0.15, 0.55, size=vis.shape)
            vis = np.where(drop_mask, vis * drop_factors, vis)
    vis = vis + rng.normal(0.0, 0.015, size=vis.shape)
    out[..., 3] = np.clip(vis, 0.0, 1.0)
    return out


def augment_training_samples(
    samples: np.ndarray,
    labels: np.ndarray,
    rng: np.random.Generator,
    copies_per_sample: int = 3,
    yaw_jitter_deg: float = 15.0,
    pitch_jitter_deg: float = 10.0,
    roll_jitter_deg: float = 10.0,
    pos_sigma: float = 0.012,
    vis_drop_prob: float = 0.05,
    allow_mirror: bool = True,
) -> Tuple[np.ndarray, np.ndarray]:
    """Generate augmented training copies strictly for a train fold.

    Returns originals concatenated with ``copies_per_sample`` augmented variants
    per input sample. Input arrays are not mutated.
    """
    src_samples = np.asarray(samples, dtype=np.float64)
    src_labels = np.asarray(labels)
    if src_samples.ndim != 3 or src_samples.shape[1:] != (33, 4):
        raise ValueError(
            f"Expected samples shape (N, 33, 4), got {src_samples.shape}"
        )
    if len(src_samples) != len(src_labels):
        raise ValueError("samples and labels must have matching length")
    if copies_per_sample <= 0:
        return src_samples.copy(), src_labels.copy()

    n = len(src_samples)
    total = n * (1 + copies_per_sample)
    aug_samples = np.empty((total, 33, 4), dtype=np.float64)
    aug_labels = np.empty((total,), dtype=src_labels.dtype)

    aug_samples[:n] = src_samples
    aug_labels[:n] = src_labels

    cursor = n
    for _ in range(copies_per_sample):
        for i in range(n):
            lm = src_samples[i]
            if allow_mirror and rng.random() < 0.5:
                lm = mirror_horizontal(lm)
            sx = float(rng.uniform(MIN_BONE_SCALE, MAX_BONE_SCALE))
            sy = float(rng.uniform(MIN_BONE_SCALE, MAX_BONE_SCALE))
            lm = scale_bone_proportions(lm, sx, sy)
            yaw = float(rng.uniform(-yaw_jitter_deg, yaw_jitter_deg))
            pitch = float(rng.uniform(-pitch_jitter_deg, pitch_jitter_deg))
            roll = float(rng.uniform(-roll_jitter_deg, roll_jitter_deg))
            lm = rotate_3d(lm, yaw, pitch, roll)
            lm = simulate_mobile_noise(
                lm,
                rng=rng,
                pos_sigma=pos_sigma,
                vis_drop_prob=vis_drop_prob,
            )
            aug_samples[cursor] = lm
            aug_labels[cursor] = src_labels[i]
            cursor += 1

    return aug_samples, aug_labels
