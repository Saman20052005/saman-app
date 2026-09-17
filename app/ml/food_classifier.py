import io
from pathlib import Path

import torch
import torch.nn as nn
from PIL import Image
from torchvision import models, transforms


FOOD101_CLASSES = [
    "apple_pie", "baby_back_ribs", "baklava", "beef_carpaccio",
    "beef_tartare", "beet_salad", "beignets", "bibimbap", "bread_pudding",
    "breakfast_burrito", "bruschetta", "caesar_salad", "cannoli",
    "caprese_salad", "carrot_cake", "ceviche", "cheesecake", "cheese_plate",
    "chicken_curry", "chicken_quesadilla", "chicken_wings", "chocolate_cake",
    "chocolate_mousse", "churros", "clam_chowder", "club_sandwich",
    "crab_cakes", "creme_brulee", "croque_madame", "cup_cakes",
    "deviled_eggs", "donuts", "dumplings", "edamame", "eggs_benedict",
    "escargots", "falafel", "filet_mignon", "fish_and_chips", "foie_gras",
    "french_fries", "french_onion_soup", "french_toast", "fried_calamari",
    "fried_rice", "frozen_yogurt", "garlic_bread", "gnocchi",
    "greek_salad", "grilled_cheese_sandwich", "grilled_salmon", "guacamole",
    "gyoza", "hamburger", "hot_and_sour_soup", "hot_dog", "huevos_rancheros",
    "hummus", "ice_cream", "lasagna", "lobster_bisque", "lobster_roll_sandwich",
    "macaroni_and_cheese", "macarons", "miso_soup", "mussels", "nachos",
    "omelette", "onion_rings", "oysters", "pad_thai", "paella",
    "pancakes", "panna_cotta", "peking_duck", "pho", "pizza",
    "pork_chop", "poutine", "prime_rib", "pulled_pork_sandwich", "ramen",
    "ravioli", "red_velvet_cake", "risotto", "samosa", "sashimi",
    "scallops", "seaweed_salad", "shrimp_and_grits", "spaghetti_bolognese",
    "spaghetti_carbonara", "spring_rolls", "steak", "strawberry_shortcake",
    "sushi", "tacos", "takoyaki", "tiramisu", "tuna_tartare", "waffles"
]

CONFIDENCE_THRESHOLD = 0.40


class FoodClassifier:
    _instance = None

    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self, model_path: str = "models/checkpoint.pth"):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.model = self._load_model(model_path)
        self.transform = self._build_transform()
        print(f"[FoodClassifier] Loaded on {self.device}")

    def _resolve_model_path(self, model_path: str) -> Path:
        p = Path(model_path)
        if p.is_absolute():
            return p

        project_root = Path(__file__).resolve().parents[3]
        candidate = project_root / p
        if candidate.exists():
            return candidate

        backend_root = Path(__file__).resolve().parents[2]
        candidate2 = backend_root / p
        return candidate2

    def _load_model(self, model_path: str) -> nn.Module:
        model = models.efficientnet_b4(weights=None)

        model.classifier = nn.Sequential(
            nn.Dropout(p=0.4, inplace=True),
            nn.Linear(model.classifier[1].in_features, 101),
        )

        resolved_path = self._resolve_model_path(model_path)
        if not resolved_path.exists():
            raise FileNotFoundError(f"Model file not found: {resolved_path}")

        state_dict = torch.load(str(resolved_path), map_location=self.device)
        if isinstance(state_dict, dict) and "model_state_dict" in state_dict:
            state_dict = state_dict["model_state_dict"]

        model.load_state_dict(state_dict)
        model = model.float()
        model.to(self.device)
        model.eval()
        return model

    def _build_transform(self):
        return transforms.Compose(
            [
                transforms.Resize(256),
                transforms.CenterCrop(224),
                transforms.ToTensor(),
                transforms.Normalize(
                    mean=[0.485, 0.456, 0.406],
                    std=[0.229, 0.224, 0.225],
                ),
            ]
        )

    @torch.no_grad()
    def predict(self, image_bytes: bytes) -> dict:
        img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        tensor = self.transform(img).unsqueeze(0).to(self.device)

        logits = self.model(tensor)
        probs = torch.softmax(logits, dim=1)[0]

        top3_probs, top3_idx = torch.topk(probs, 3)
        top3 = [
            {
                "label": FOOD101_CLASSES[idx.item()],
                "food_name": FOOD101_CLASSES[idx.item()].replace("_", " ").title(),
                "confidence": round(prob.item(), 3),
            }
            for prob, idx in zip(top3_probs, top3_idx)
        ]

        best = top3[0]
        low_confidence = best["confidence"] < CONFIDENCE_THRESHOLD

        return {
            "label": best["label"],
            "food_name": best["food_name"],
            "confidence": best["confidence"],
            "low_confidence": low_confidence,
            "top3": top3,
        }
