"""18-feature invariant geometric extractor for MediaPipe 33-landmark skeletons.

Designed for exact 1-to-1 numeric parity (< 1e-6) between Python and pure Dart
using only elementary math primitives (``atan2``, ``hypot``/``sqrt``, ``abs``,
``min``, ``max``).

Dart Port Specification (exact formulas)
----------------------------------------
Given ``landmarks`` as 33 points ``lm[i] = [x, y, z, vis]`` (MediaPipe Pose):

1. Midpoints & torso scale:
   - ``shoulder_mid_x = 0.5 * (lm[11].x + lm[12].x)``
   - ``shoulder_mid_y = 0.5 * (lm[11].y + lm[12].y)``
   - ``hip_mid_x      = 0.5 * (lm[23].x + lm[24].x)``
   - ``hip_mid_y      = 0.5 * (lm[23].y + lm[24].y)``
   - ``elbow_mid_y    = 0.5 * (lm[13].y + lm[14].y)``
   - ``wrist_mid_y    = 0.5 * (lm[15].y + lm[16].y)``
   - ``knee_mid_y     = 0.5 * (lm[25].y + lm[26].y)``
   - ``torso_len      = max(hypot(shoulder_mid_x - hip_mid_x, shoulder_mid_y - hip_mid_y), 1e-3)``

2. Normalized 2D joint angle ``angleNorm(a, b, c)`` (vertex at ``b``, in ``[0, 1]``):
   - ``v1x = a.x - b.x; v1y = a.y - b.y``
   - ``v2x = c.x - b.x; v2y = c.y - b.y``
   - ``n1 = hypot(v1x, v1y); n2 = hypot(v2x, v2y)``
   - If ``n1 < 1e-6 || n2 < 1e-6``, return ``0.0``
   - ``dot = v1x * v2x + v1y * v2y``
   - ``cross = abs(v1x * v2y - v1y * v2x)``
   - ``angle_deg = atan2(cross, dot) * (180.0 / pi)``
   - Return ``angle_deg / 180.0``

3. Exact 18 features (in ``FEATURE_NAMES`` order):
   0.  ``left_elbow_angle_deg``    = ``angleNorm(11, 13, 15)``
   1.  ``right_elbow_angle_deg``   = ``angleNorm(12, 14, 16)``
   2.  ``active_elbow_angle_norm`` = visibility-weighted average of (0) and (1):
       ``wL = (vis11 + vis13 + vis15) / 3.0``, ``wR = (vis12 + vis14 + vis16) / 3.0``
       If ``wL + wR > 1e-6``: ``(wL * f0 + wR * f1) / (wL + wR)`` else ``0.5 * (f0 + f1)``
   3.  ``left_shoulder_angle_deg`` = ``angleNorm(23, 11, 13)``
   4.  ``right_shoulder_angle_deg``= ``angleNorm(24, 12, 14)``
   5.  ``left_hip_angle_deg``      = ``angleNorm(11, 23, 25)``
   6.  ``right_hip_angle_deg``     = ``angleNorm(12, 24, 26)``
   7.  ``left_knee_angle_deg``     = ``angleNorm(23, 25, 27)``
   8.  ``right_knee_angle_deg``    = ``angleNorm(24, 26, 28)``
   9.  ``wrist_rel_shoulder_y``    = ``clamp((wrist_mid_y - shoulder_mid_y) / torso_len, -2.5, 2.5)``
   10. ``elbow_rel_shoulder_y``    = ``clamp((elbow_mid_y - shoulder_mid_y) / torso_len, -2.5, 2.5)``
   11. ``hip_rel_knee_y``          = ``clamp((hip_mid_y - knee_mid_y) / torso_len, -2.5, 2.5)``
   12. ``shoulder_to_torso_ratio`` = ``clamp(abs(lm[11].x - lm[12].x) / torso_len, 0.0, 2.5)``
   13. ``hip_to_torso_ratio``      = ``clamp(abs(lm[23].x - lm[24].x) / torso_len, 0.0, 2.5)``
   14. ``shoulder_z_diff``         = ``clamp(abs(lm[11].z - lm[12].z), 0.0, 2.5)``
   15. ``torso_lean_norm``         = ``atan2(abs(shoulder_mid_x - hip_mid_x), abs(hip_mid_y - shoulder_mid_y)) * (180.0 / pi) / 90.0``
       (returns ``0.0`` if both ``abs(dx) < 1e-9`` and ``abs(dy) < 1e-9``)
   16. ``upper_vis_mean``          = ``clamp(mean(vis[11,12,13,14,15,16,23,24]), 0.0, 1.0)``
   17. ``bilateral_vis_asym``      = ``clamp(abs(mean(vis[11,13,15,23]) - mean(vis[12,14,16,24])), 0.0, 1.0)``
"""

from __future__ import annotations

import math
from typing import Sequence, Tuple

import numpy as np

FEATURE_NAMES: Tuple[str, ...] = (
    "left_elbow_angle_deg",
    "right_elbow_angle_deg",
    "active_elbow_angle_norm",
    "left_shoulder_angle_deg",
    "right_shoulder_angle_deg",
    "left_hip_angle_deg",
    "right_hip_angle_deg",
    "left_knee_angle_deg",
    "right_knee_angle_deg",
    "wrist_rel_shoulder_y",
    "elbow_rel_shoulder_y",
    "hip_rel_knee_y",
    "shoulder_to_torso_ratio",
    "hip_to_torso_ratio",
    "shoulder_z_diff",
    "torso_lean_norm",
    "upper_vis_mean",
    "bilateral_vis_asym",
)

VIEW_ANGLE_LABELS: Tuple[str, ...] = ("frontal", "oblique45", "side90")
PHASE_LABELS: Tuple[str, ...] = ("top_idle", "transition", "bottom_peak")
EXERCISES: Tuple[str, ...] = (
    "pull-up",
    "lat-pulldown",
    "squat",
    "push-up",
    "bicep-curl",
)

_UPPER_BODY_INDICES: Tuple[int, ...] = (11, 12, 13, 14, 15, 16, 23, 24)
_LEFT_UPPER_INDICES: Tuple[int, ...] = (11, 13, 15, 23)
_RIGHT_UPPER_INDICES: Tuple[int, ...] = (12, 14, 16, 24)
_RAD_TO_DEG: float = 180.0 / math.pi


def _clamp(val: float, lo: float, hi: float) -> float:
    if not math.isfinite(val):
        return lo
    if val < lo:
        return lo
    if val > hi:
        return hi
    return val


def _angle_2d_norm(
    ax: float,
    ay: float,
    bx: float,
    by: float,
    cx: float,
    cy: float,
) -> float:
    """Compute interior 2D angle at vertex b, normalized to [0.0, 1.0] (deg / 180)."""
    v1x = ax - bx
    v1y = ay - by
    v2x = cx - bx
    v2y = cy - by
    n1 = math.hypot(v1x, v1y)
    n2 = math.hypot(v2x, v2y)
    if n1 < 1e-6 or n2 < 1e-6:
        return 0.0
    dot = v1x * v2x + v1y * v2y
    cross = abs(v1x * v2y - v1y * v2x)
    angle_deg = math.atan2(cross, dot) * _RAD_TO_DEG
    return _clamp(angle_deg / 180.0, 0.0, 1.0)


def extract_features(landmarks: Sequence[Sequence[float]] | np.ndarray) -> np.ndarray:
    """Extract the 18 invariant geometric features from a single (33, 4) pose.

    Returns a 1-D ``np.ndarray`` of shape ``(18,)`` and dtype ``np.float64``.
    """
    lm = np.asarray(landmarks, dtype=np.float64)
    if lm.shape != (33, 4):
        raise ValueError(f"Expected landmarks shape (33, 4), got {lm.shape}")

    def pt(idx: int) -> Tuple[float, float, float, float]:
        x = float(lm[idx, 0]) if math.isfinite(float(lm[idx, 0])) else 0.0
        y = float(lm[idx, 1]) if math.isfinite(float(lm[idx, 1])) else 0.0
        z = float(lm[idx, 2]) if math.isfinite(float(lm[idx, 2])) else 0.0
        v = _clamp(float(lm[idx, 3]), 0.0, 1.0)
        return x, y, z, v

    p11 = pt(11)
    p12 = pt(12)
    p13 = pt(13)
    p14 = pt(14)
    p15 = pt(15)
    p16 = pt(16)
    p23 = pt(23)
    p24 = pt(24)
    p25 = pt(25)
    p26 = pt(26)
    p27 = pt(27)
    p28 = pt(28)

    # Midpoints & torso scale
    shoulder_mid_x = 0.5 * (p11[0] + p12[0])
    shoulder_mid_y = 0.5 * (p11[1] + p12[1])
    hip_mid_x = 0.5 * (p23[0] + p24[0])
    hip_mid_y = 0.5 * (p23[1] + p24[1])
    elbow_mid_y = 0.5 * (p13[1] + p14[1])
    wrist_mid_y = 0.5 * (p15[1] + p16[1])
    knee_mid_y = 0.5 * (p25[1] + p26[1])

    torso_len = max(
        math.hypot(shoulder_mid_x - hip_mid_x, shoulder_mid_y - hip_mid_y),
        1e-3,
    )

    # 1-9: Joint angles normalized by 180°
    left_elbow = _angle_2d_norm(p11[0], p11[1], p13[0], p13[1], p15[0], p15[1])
    right_elbow = _angle_2d_norm(p12[0], p12[1], p14[0], p14[1], p16[0], p16[1])

    w_left = (p11[3] + p13[3] + p15[3]) / 3.0
    w_right = (p12[3] + p14[3] + p16[3]) / 3.0
    if (w_left + w_right) > 1e-6:
        active_elbow = (w_left * left_elbow + w_right * right_elbow) / (w_left + w_right)
    else:
        active_elbow = 0.5 * (left_elbow + right_elbow)

    left_shoulder = _angle_2d_norm(p23[0], p23[1], p11[0], p11[1], p13[0], p13[1])
    right_shoulder = _angle_2d_norm(p24[0], p24[1], p12[0], p12[1], p14[0], p14[1])
    left_hip = _angle_2d_norm(p11[0], p11[1], p23[0], p23[1], p25[0], p25[1])
    right_hip = _angle_2d_norm(p12[0], p12[1], p24[0], p24[1], p26[0], p26[1])
    left_knee = _angle_2d_norm(p23[0], p23[1], p25[0], p25[1], p27[0], p27[1])
    right_knee = _angle_2d_norm(p24[0], p24[1], p26[0], p26[1], p28[0], p28[1])

    # 10-12: Torso-normalized vertical relative positions
    wrist_rel_shoulder_y = _clamp((wrist_mid_y - shoulder_mid_y) / torso_len, -2.5, 2.5)
    elbow_rel_shoulder_y = _clamp((elbow_mid_y - shoulder_mid_y) / torso_len, -2.5, 2.5)
    hip_rel_knee_y = _clamp((hip_mid_y - knee_mid_y) / torso_len, -2.5, 2.5)

    # 13-15: Camera view-angle discriminators
    shoulder_to_torso_ratio = _clamp(abs(p11[0] - p12[0]) / torso_len, 0.0, 2.5)
    hip_to_torso_ratio = _clamp(abs(p23[0] - p24[0]) / torso_len, 0.0, 2.5)
    shoulder_z_diff = _clamp(abs(p11[2] - p12[2]), 0.0, 2.5)

    # 16: Torso lean relative to vertical axis, normalized by 90°
    dx = abs(shoulder_mid_x - hip_mid_x)
    dy = abs(hip_mid_y - shoulder_mid_y)
    if dx < 1e-9 and dy < 1e-9:
        torso_lean_norm = 0.0
    else:
        torso_lean_norm = _clamp((math.atan2(dx, dy) * _RAD_TO_DEG) / 90.0, 0.0, 1.0)

    # 17-18: Upper-body visibility summary & bilateral asymmetry
    vis_map = {
        11: p11[3],
        12: p12[3],
        13: p13[3],
        14: p14[3],
        15: p15[3],
        16: p16[3],
        23: p23[3],
        24: p24[3],
    }
    upper_vis_mean = _clamp(
        sum(vis_map[i] for i in _UPPER_BODY_INDICES) / len(_UPPER_BODY_INDICES),
        0.0,
        1.0,
    )
    left_vis_mean = sum(vis_map[i] for i in _LEFT_UPPER_INDICES) / len(_LEFT_UPPER_INDICES)
    right_vis_mean = sum(vis_map[i] for i in _RIGHT_UPPER_INDICES) / len(_RIGHT_UPPER_INDICES)
    bilateral_vis_asym = _clamp(abs(left_vis_mean - right_vis_mean), 0.0, 1.0)

    return np.array(
        [
            left_elbow,
            right_elbow,
            active_elbow,
            left_shoulder,
            right_shoulder,
            left_hip,
            right_hip,
            left_knee,
            right_knee,
            wrist_rel_shoulder_y,
            elbow_rel_shoulder_y,
            hip_rel_knee_y,
            shoulder_to_torso_ratio,
            hip_to_torso_ratio,
            shoulder_z_diff,
            torso_lean_norm,
            upper_vis_mean,
            bilateral_vis_asym,
        ],
        dtype=np.float64,
    )


def extract_features_batch(samples: np.ndarray) -> np.ndarray:
    """Extract 18 features for a batch of poses of shape ``(N, 33, 4)``."""
    arr = np.asarray(samples, dtype=np.float64)
    if arr.ndim != 3 or arr.shape[1:] != (33, 4):
        raise ValueError(f"Expected shape (N, 33, 4), got {arr.shape}")
    out = np.empty((len(arr), len(FEATURE_NAMES)), dtype=np.float64)
    for i in range(len(arr)):
        out[i] = extract_features(arr[i])
    return out
