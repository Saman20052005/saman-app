"""Regression coverage for food-classifier fallback and mock result schema."""

from pathlib import Path

from PIL import Image

from backend.app.schemas.inference_schemas import FoodClassificationResult, ModelType
from backend.app.services.classification_provider_factory import create_classification_service
from backend.app.services.mock_food_classification_service import MockFoodClassificationService


def test_missing_pytorch_weights_fall_back_to_mock(monkeypatch, tmp_path):
    """A requested PyTorch provider must safely use mock when weights are absent."""
    missing_weights = Path(tmp_path) / "missing_food_model.pth"
    assert not missing_weights.exists()

    monkeypatch.setenv("FOOD_CLASSIFIER_PROVIDER", "pytorch")
    service = create_classification_service(model_path=str(missing_weights))

    assert isinstance(service, MockFoodClassificationService)

    # Inference should return a result without bubbling an exception to the API.
    result = service.predict_canonical(Image.new("RGB", (16, 16), color="gray"))
    assert isinstance(result, FoodClassificationResult)
    assert result.model_type is ModelType.MOCK


def test_mock_provider_returns_canonical_schema_for_noise_image(monkeypatch):
    """Arbitrary pixel data should still produce a valid canonical mock result."""
    monkeypatch.setenv("FOOD_CLASSIFIER_PROVIDER", "mock")
    service = create_classification_service()

    # A noise image represents validly decoded but meaningless image content.
    noise = Image.effect_noise((32, 32), 100).convert("RGB")
    result = service.predict_canonical(noise)

    assert isinstance(result, FoodClassificationResult)
    assert result.model_type is ModelType.MOCK
    assert result.top_prediction in result.top_k_predictions
    assert result.to_dict()["model_type"] == "mock"
    assert result.to_dict()["top_prediction"]["class_name"]


def test_ensemble_lazy_load_failure_falls_back_to_mock_predict(monkeypatch, tmp_path):
    """If a lazy-loaded PyTorch classifier fails during inference, ensemble must fall back to mock."""
    import backend.app.services.food_analysis_ensemble as ensemble_mod
    from backend.app.services.food_analysis_ensemble import FoodAnalysisEnsemble
    from backend.app.services.food_classification_service import FoodClassificationService

    monkeypatch.setattr(ensemble_mod, "NutritionMappingService", lambda *args, **kwargs: None)
    ensemble = FoodAnalysisEnsemble(classification_model_path=str(Path(tmp_path) / "missing.pth"))
    # Force a lazy-loaded PyTorch classifier with missing weights onto the ensemble
    ensemble.classifier = FoodClassificationService(model_path=str(Path(tmp_path) / "missing.pth"))
    monkeypatch.setattr(
        ensemble.classifier,
        "_ensure_model",
        lambda: (_ for _ in ()).throw(RuntimeError("PyTorch lazy load failed")),
    )

    predictions = ensemble._classify_food(Image.new("RGB", (32, 32), color="white"), top_k=3)
    assert len(predictions) > 0
    assert isinstance(ensemble.classifier, MockFoodClassificationService)
    assert "class_name" in predictions[0]
    assert "confidence" in predictions[0]

