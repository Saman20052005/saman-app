# [File: backend/services/food_classifier.py]
import io
import logging
import os
from pathlib import Path

# PIL được import ở module level vì nhẹ (~5MB), torch thì không
from PIL import Image

logger = logging.getLogger(__name__)

# ================================================================
# CLASS LIST — 101 classes, thứ tự ALPHABETICAL (ImageFolder mặc định)
# Sẽ được REPLACE bằng class_mapping.json khi model train xong
# ================================================================
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

CONFIDENCE_THRESHOLD = 0.40


class FoodClassifier:
    """
    Singleton classifier với lazy torch loading.
    torch/torchvision KHÔNG được import ở module level — chỉ load khi cần thiết
    để tránh OOM crash trên Render free tier 512MB.
    """
    _instance = None

    @classmethod
    def get_instance(cls, model_path: str = "models/checkpoint.pth"):
        if cls._instance is None:
            cls._instance = cls(model_path=model_path)
        return cls._instance

    def __init__(self, model_path: str = "models/checkpoint.pth"):
        # FIX: default path đổi sang checkpoint.pth cho khớp với HuggingFace
        self.model_path = model_path
        self.ready = False
        self.classes = list(FOOD101_CLASSES_ALPHA)
        self.model = None
        self.device = None
        self._transform = None  # lazy init sau khi torch được load

        self._load_class_mapping(model_path)

        if Path(model_path).exists():
            try:
                self._load_model(model_path)
                self.ready = True
                logger.info("[FoodClassifier] ✅ Model loaded: %s", model_path)
            except Exception as e:
                logger.warning("[FoodClassifier] ⚠️ Model load failed, mock mode: %s", e)
        else:
            logger.info("[FoodClassifier] ℹ️ No model at %s — running mock mode", model_path)

    def _load_class_mapping(self, model_path: str):
        """Load class_mapping.json nếu có — ưu tiên hơn alphabetical list."""
        import json
        mapping_path = Path(model_path).parent / "class_mapping.json"
        if mapping_path.exists():
            with open(mapping_path) as f:
                idx_to_class = json.load(f)
            self.classes = [idx_to_class[str(i)] for i in range(len(idx_to_class))]
            logger.info("[FoodClassifier] Loaded class mapping: %d classes", len(self.classes))

    def _load_model(self, model_path: str):
        """
        Load model với lazy torch import.
        torch chỉ được import tại đây — không phải ở module level.
        Giúp tiết kiệm ~200MB RAM trong suốt thời gian startup trước request đầu tiên.
        """
        # FIX: lazy import — torch chỉ load khi method này được gọi
        import torch
        import torch.nn as nn
        from torchvision import models, transforms

        self.device = torch.device("cpu")  # Render free tier không có GPU

        model = models.efficientnet_b4(weights=None)
        model.classifier[1] = nn.Linear(model.classifier[1].in_features, 101)

        state = torch.load(model_path, map_location=self.device)
        # Handle cả 3 format: raw state_dict, wrapped {"model_state_dict": ...}, hoặc {"model": ...}
        if isinstance(state, dict):
            if "model_state_dict" in state:
                state = state["model_state_dict"]
            elif "model" in state:
                state = state["model"]

        model.load_state_dict(state, strict=True)  # strict=True để phát hiện lỗi sớm
        
        # Xóa state dict khỏi RAM ngay sau khi load xong
        del state
        import gc
        gc.collect()
        
        # Convert model sang half precision để tiết kiệm ~40MB
        # model.half()  # float32 → float16 - XÓA vì gây numerical instability trên CPU
        
        model.to(self.device)
        model.eval()
        torch.set_grad_enabled(False)

        self.model = model

        # Build transform sau khi torch đã được import
        self._transform = transforms.Compose([
            transforms.Resize(256),
            transforms.CenterCrop(224),
            transforms.ToTensor(),
            transforms.Normalize(
                mean=[0.485, 0.456, 0.406],
                std=[0.229, 0.224, 0.225],
            ),
        ])

    def predict(self, image_bytes: bytes) -> dict:
        if not self.ready:
            return self._mock_predict()
        return self._real_predict(image_bytes)

    def _real_predict(self, image_bytes: bytes) -> dict:
        import torch  # đã được import trước đó, không tốn thêm RAM
        with torch.no_grad():
            img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
            tensor = self._transform(img).unsqueeze(0).to(self.device)
            # tensor = tensor.half()  # XÓA vì model không còn dùng half precision
            probs = torch.softmax(self.model(tensor), dim=1)[0]

            top3_probs, top3_idx = torch.topk(probs, 3)
            top3 = [
                {
                    "label": self.classes[idx.item()],
                    "food_name": self.classes[idx.item()].replace("_", " ").title(),
                    "confidence": round(prob.item(), 3),
                }
                for prob, idx in zip(top3_probs, top3_idx)
            ]
            best = top3[0]
            return {
                "label":          best["label"],
                "food_name":      best["food_name"],
                "confidence":     best["confidence"],
                "low_confidence": best["confidence"] < CONFIDENCE_THRESHOLD,
                "top3":           top3,
                "mock":           False,
            }

    def _mock_predict(self) -> dict:
        """Trả kết quả giả để test pipeline không cần model."""
        return {
            "label":          "pizza",
            "food_name":      "Pizza",
            "confidence":     0.85,
            "low_confidence": False,
            "top3": [
                {"label": "pizza",     "food_name": "Pizza",     "confidence": 0.85},
                {"label": "flatbread", "food_name": "Flatbread", "confidence": 0.09},
                {"label": "focaccia",  "food_name": "Focaccia",  "confidence": 0.04},
            ],
            "mock": True,
        }
