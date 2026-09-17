"""
PyTorch Food-101 Model Loader  [app/ml/loaders/food101_pytorch_loader.py]

FIX LOG:
  - EfficientNet-B3 → B4  (khớp với best_model.pth đã train)
  - Default model_path  → "models/best_model.pth"  (khớp với food_classifier.py)
  - Transform: Resize(256) + CenterCrop(224) thay vì Resize(224,224) trực tiếp
    (best practice cho EfficientNet — tránh squash tỉ lệ ảnh)
  - Warmup: chạy 2 lần để JIT cache ổn định hơn trên CPU
"""

import hashlib
import logging
import os
import time
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

import torch
import torch.nn as nn
import torchvision.transforms as transforms
from PIL import Image
from torchvision import models

logger = logging.getLogger(__name__)

# Class list alphabetical — đồng bộ với food_classifier.py
FOOD101_CLASSES_ALPHA = [
    "apple_pie", "baby_back_ribs", "baklava", "beef_carpaccio",
    "beef_tartare", "beet_salad", "beignets", "bibimbap",
    "bread_pudding", "breakfast_burrito", "bruschetta", "caesar_salad",
    "cannoli", "caprese_salad", "carrot_cake", "ceviche", "cheesecake",
    "cheese_plate", "chicken_curry", "chicken_quesadilla", "chicken_wings",
    "chocolate_cake", "chocolate_mousse", "churros", "clam_chowder",
    "club_sandwich", "crab_cakes", "creme_brulee", "croque_madame",
    "cup_cakes", "deviled_eggs", "donuts", "dumplings", "edamame",
    "eggs_benedict", "escargots", "falafel", "filet_mignon",
    "fish_and_chips", "foie_gras", "french_fries", "french_onion_soup",
    "french_toast", "fried_calamari", "fried_rice", "frozen_yogurt",
    "garlic_bread", "gnocchi", "greek_salad", "grilled_cheese_sandwich",
    "grilled_salmon", "guacamole", "gyoza", "hamburger",
    "hot_and_sour_soup", "hot_dog", "huevos_rancheros", "hummus",
    "ice_cream", "lasagna", "lobster_bisque", "lobster_roll_sandwich",
    "macaroni_and_cheese", "macarons", "miso_soup", "mussels",
    "nachos", "omelette", "onion_rings", "oysters", "pad_thai",
    "paella", "pancakes", "panna_cotta", "peking_duck", "pho",
    "pizza", "pork_chop", "poutine", "prime_rib",
    "pulled_pork_sandwich", "ramen", "ravioli", "red_velvet_cake",
    "risotto", "samosa", "sashimi", "scallops", "seaweed_salad",
    "shrimp_and_grits", "spaghetti_bolognese", "spaghetti_carbonara",
    "spring_rolls", "steak", "strawberry_shortcake", "sushi",
    "tacos", "takoyaki", "tiramisu", "tuna_tartare", "waffles",
]


class Food101PyTorchLoader:
    """
    Loader cho EfficientNet-B4 Food-101.
    Designed để dùng trong FoodAnalysisEnsemble (legacy pipeline).
    Cho pipeline chính, dùng FoodClassifier singleton thay thế.
    """

    def __init__(
        self,
        model_path: Optional[str] = None,
        labels_path: Optional[str] = None,   # optional — fallback về FOOD101_CLASSES_ALPHA
        device: str = "auto",
    ):
        # Path mặc định đồng bộ với food_classifier.py + Render env var
        self.model_path = model_path or os.getenv(
            "FOOD_MODEL_PATH", "models/best_model.pth"
        )
        self.labels_path = labels_path  # None → dùng hardcoded list
        self.device = self._select_device(device)

        self.model: Optional[nn.Module] = None
        self.labels: list = list(FOOD101_CLASSES_ALPHA)
        self.transform: Optional[transforms.Compose] = None
        self.is_loaded = False

        self.model_metadata: Dict[str, Any] = {
            "model_type":   "pytorch",
            "architecture": "efficientnet_b4",   # B4, bukan B3
            "num_classes":  101,
            "device":       self.device,
        }

        self._setup_transforms()
        logger.info(f"[Food101PyTorchLoader] device={self.device}")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def load_model(self) -> bool:
        """Load model + labels. Returns True nếu thành công."""
        try:
            self._load_labels_if_file()
            if not self._load_model_weights():
                return False
            if not self._validate_output_shape():
                return False
            self._warmup()
            self.is_loaded = True
            logger.info(f"[Food101PyTorchLoader] Model ready — {self.model_metadata}")
            return True
        except Exception as e:
            logger.error(f"[Food101PyTorchLoader] load_model failed: {e}")
            return False

    def predict(
        self, image: Image.Image, top_k: int = 5
    ) -> Tuple[bool, Optional[Dict]]:
        """
        Run inference.

        Returns:
            (True, result_dict) hoặc (False, {"error": "..."})
        """
        if not self.is_loaded:
            return False, {"error": "Model not loaded"}

        try:
            t0 = time.time()
            tensor = self.transform(image).unsqueeze(0).to(self.device)

            with torch.no_grad():
                logits = self.model(tensor)
                probs = torch.nn.functional.softmax(logits[0], dim=0)

            k = min(top_k, len(self.labels))
            top_probs, top_idx = torch.topk(probs, k)

            predictions = [
                {
                    "class_id":    idx.item(),
                    "class_name":  self.labels[idx.item()],
                    "display_name": self.labels[idx.item()].replace("_", " ").title(),
                    "confidence":  round(prob.item(), 4),
                }
                for prob, idx in zip(top_probs, top_idx)
            ]

            return True, {
                "predictions":       predictions,
                "inference_time_ms": round((time.time() - t0) * 1000, 1),
                "model_metadata":    self.model_metadata.copy(),
            }

        except Exception as e:
            logger.error(f"[Food101PyTorchLoader] predict failed: {e}")
            return False, {"error": str(e)}

    def get_model_info(self) -> Dict[str, Any]:
        return {
            **self.model_metadata,
            "is_loaded":    self.is_loaded,
            "model_path":   self.model_path,
            "labels_count": len(self.labels),
        }

    def get_labels(self) -> list:
        return self.labels.copy()

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _select_device(self, device: str) -> str:
        if device == "auto":
            return "cuda" if torch.cuda.is_available() else "cpu"
        if device == "cuda" and not torch.cuda.is_available():
            logger.warning("CUDA requested but not available — falling back to CPU")
            return "cpu"
        return device

    def _setup_transforms(self):
        """
        EfficientNet best practice: Resize → CenterCrop (giữ aspect ratio)
        thay vì Resize trực tiếp về 224×224 (squash).
        """
        self.transform = transforms.Compose([
            transforms.Resize(256),
            transforms.CenterCrop(224),
            transforms.ToTensor(),
            transforms.Normalize(
                mean=[0.485, 0.456, 0.406],
                std=[0.229, 0.224, 0.225],
            ),
        ])

    def _load_labels_if_file(self):
        """Load labels.txt nếu được cung cấp, không thì dùng hardcoded list."""
        if not self.labels_path:
            return  # dùng FOOD101_CLASSES_ALPHA

        path = Path(self.labels_path)
        if not path.exists():
            logger.warning(f"labels_path={self.labels_path} not found — using hardcoded list")
            return

        lines = [l.strip() for l in path.read_text().splitlines() if l.strip()]
        if len(lines) != 101:
            logger.warning(f"labels.txt has {len(lines)} entries (expected 101) — using hardcoded list")
            return

        self.labels = lines
        logger.info(f"Loaded {len(self.labels)} labels from {self.labels_path}")

    def _load_model_weights(self) -> bool:
        """Build EfficientNet-B4 và load state_dict."""
        if not Path(self.model_path).exists():
            logger.error(f"Model file not found: {self.model_path}")
            return False

        try:
            # ── Architecture: EfficientNet-B4 (khớp với training) ──────
            model = models.efficientnet_b4(weights=None)
            model.classifier[1] = nn.Linear(
                model.classifier[1].in_features, 101
            )

            # ── Load weights (hỗ trợ cả raw state_dict và wrapped dict) ─
            ckpt = torch.load(self.model_path, map_location=self.device)
            if isinstance(ckpt, dict):
                state = (
                    ckpt.get("model_state_dict")
                    or ckpt.get("state_dict")
                    or ckpt
                )
            else:
                state = ckpt

            model.load_state_dict(state, strict=False)
            model.to(self.device)
            model.eval()

            self.model = model
            self.model_metadata["model_hash"] = self._file_hash()
            self.model_metadata["loaded_at"] = time.time()
            return True

        except Exception as e:
            logger.error(f"_load_model_weights failed: {e}")
            return False

    def _validate_output_shape(self) -> bool:
        """Chạy dummy forward để xác nhận output = 101 classes."""
        try:
            dummy = torch.randn(1, 3, 224, 224).to(self.device)
            with torch.no_grad():
                out = self.model(dummy)
            if out.shape[1] != len(self.labels):
                logger.error(
                    f"Output classes={out.shape[1]} != labels={len(self.labels)}"
                )
                return False
            return True
        except Exception as e:
            logger.error(f"_validate_output_shape failed: {e}")
            return False

    def _warmup(self, runs: int = 2):
        """
        Warmup 2 lần — lần đầu JIT compile, lần hai cache ổn định.
        Non-critical: lỗi warmup không block load.
        """
        try:
            dummy = torch.randn(1, 3, 224, 224).to(self.device)
            for _ in range(runs):
                with torch.no_grad():
                    self.model(dummy)
            logger.info(f"Warmup done ({runs} runs)")
        except Exception as e:
            logger.warning(f"Warmup failed (non-critical): {e}")

    def _file_hash(self) -> str:
        try:
            data = Path(self.model_path).read_bytes()
            return hashlib.md5(data).hexdigest()[:12]
        except Exception:
            return "unknown"
