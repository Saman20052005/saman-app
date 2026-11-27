"""Phase 5 Multi-Exercise ML Research Pipeline (isolated in ml_research/phase5_multi_exercise).

Provides geometric 3D landmark augmentation, 18 invariant geometric features
(1-to-1 compatible with pure Dart inference), and leakage-proof GroupKFold
training + lightweight JSON weight export for:
  - view_angle_model: frontal / oblique45 / side90
  - 5 exercise phase models: pull-up, lat-pulldown, squat, push-up, bicep-curl
    with phases: top_idle / transition / bottom_peak
"""

from .augmentation import (
    MIRROR_PAIRS,
    augment_training_samples,
    mirror_horizontal,
    rotate_3d,
    scale_bone_proportions,
    simulate_mobile_noise,
)
from .feature_extractor import (
    EXERCISES,
    FEATURE_NAMES,
    PHASE_LABELS,
    VIEW_ANGLE_LABELS,
    extract_features,
    extract_features_batch,
)

__all__ = [
    "EXERCISES",
    "FEATURE_NAMES",
    "MIRROR_PAIRS",
    "PHASE_LABELS",
    "VIEW_ANGLE_LABELS",
    "augment_training_samples",
    "extract_features",
    "extract_features_batch",
    "mirror_horizontal",
    "rotate_3d",
    "scale_bone_proportions",
    "simulate_mobile_noise",
]
