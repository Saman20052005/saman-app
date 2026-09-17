from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form
from fastapi.responses import JSONResponse
import io
import logging
import os
import time
from typing import Optional, List

from PIL import Image

from backend.services.food_classifier import FoodClassifier
from backend.services.nutrition_lookup import NutritionLookup
from backend.auth_utils import verify_token

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/food", tags=["Food Analysis"])

# Mock inference pipeline — classifier + nutrition lookup
_nutrition_lookup = NutritionLookup()


def get_classifier() -> FoodClassifier:
    model_path = os.getenv("FOOD_MODEL_PATH", "models/best_model.pth")
    return FoodClassifier.get_instance(model_path=model_path)


@router.post("/analyze")
async def analyze_food_image(
    image: UploadFile = File(...),
    grams: float = Form(default=100.0),
    email: str = Depends(verify_token),
):
    """
    Nhận ảnh món ăn → trả food label + macro (calories/protein/carbs/fat).
    Dùng Food101 model + USDA/OpenFoodFacts lookup. Mock mode khi chưa có model.
    """
    if image.content_type and image.content_type not in (
        "image/jpeg", "image/png", "image/webp", "image/jpg"
    ) and not image.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Only JPEG/PNG/WEBP supported")

    image_bytes = await image.read()

    if len(image_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Image too large (max 10MB)")

    if len(image_bytes) < 1000:
        raise HTTPException(status_code=400, detail="Image too small or corrupted")

    classifier = get_classifier()
    try:
        result = classifier.predict(image_bytes)
    except Exception as e:
        logger.exception("Classification error: %s", e)
        raise HTTPException(status_code=500, detail=f"Classification error: {str(e)}")

    food_label = result["label"]
    confidence = result["confidence"]

    try:
        nutrition = await _nutrition_lookup.lookup(food_label, grams)
    except Exception as e:
        logger.warning("Nutrition lookup failed: %s", e)
        nutrition = {
            "calories": 0, "protein": 0, "carbs": 0, "fat": 0,
            "source": "error", "per_100g": {},
        }

    food_name = result.get("food_name") or food_label.replace("_", " ").title()
    return {
        "food_name":        food_name,
        "food_label":       food_label,
        "detected_food_name": food_name,  # frontend AIAnalysisResult compatibility
        "confidence":       confidence,
        "low_confidence":   result.get("low_confidence", False),
        "grams":            grams,
        "nutrition": {
            "calories": nutrition["calories"],
            "protein":  nutrition["protein"],
            "carbs":    nutrition["carbs"],
            "fat":      nutrition["fat"],
        },
        "per_100g":         nutrition.get("per_100g", {}),
        "nutrition_source": nutrition.get("source", "unknown"),
        "top3_predictions": result.get("top3", []),
        "mock":             result.get("mock", False),
        "user_email":       email,
        "temp_id":          "",  # frontend compatibility
        "image_url":        "",
    }


@router.get("/health")
async def food_health():
    """Health check for food analysis — classifier ready or mock_mode."""
    classifier = get_classifier()
    return {
        "status":      "ready" if classifier.ready else "mock_mode",
        "model":       "efficientnet_b4" if classifier.ready else "none",
        "num_classes": len(classifier.classes),
    }


# ----- Legacy endpoints (vẫn dùng FoodAnalysisEnsemble nếu có) -----
try:
    from backend.app.services import FoodAnalysisEnsemble, get_config, update_config
    from backend.app.services.model_config import config_manager
    _LEGACY_AVAILABLE = True
except ImportError:
    _LEGACY_AVAILABLE = False
    FoodAnalysisEnsemble = get_config = update_config = None
    config_manager = None

food_analyzer = None

def get_food_analyzer():
    """Legacy ensemble — dùng cho /analyze-batch, /models/info, etc."""
    global food_analyzer
    if not _LEGACY_AVAILABLE:
        raise RuntimeError("FoodAnalysisEnsemble not available")
    if food_analyzer is None:
        config = get_config()
        model_paths = config_manager.get_model_paths() if config_manager else {}
        food_analyzer = FoodAnalysisEnsemble(
            classification_model_path=model_paths.get("classification"),
            portion_model_path=model_paths.get("portion_estimation"),
            mongo_uri=config.mongo_uri,
            db_name=config.db_name,
        )
    return food_analyzer

@router.post("/analyze-batch")
async def analyze_food_images_batch(
    images: List[UploadFile] = File(...),
    user_id: Optional[str] = Form(None),
    top_k: int = Form(3),
    include_nutrition: bool = Form(True),
    email: str = Depends(verify_token)
):
    """
    Analyze multiple food images in parallel
    
    Args:
        images: List of food image files
        user_id: Optional user ID for personalization
        top_k: Number of top food predictions per image
        include_nutrition: Whether to include nutrition calculations
        email: User email (from authentication)
    
    Returns:
        List of analysis results
    """
    try:
        # Validate number of images
        if len(images) > 8:
            raise HTTPException(status_code=400, detail="Too many images (max 8)")
        
        # Validate all images
        pil_images = []
        for img_file in images:
            if not img_file.content_type.startswith('image/'):
                raise HTTPException(status_code=400, detail=f"File {img_file.filename} is not an image")
            
            if img_file.size and img_file.size > 10 * 1024 * 1024:
                raise HTTPException(status_code=413, detail=f"Image {img_file.filename} too large")
            
            image_data = await img_file.read()
            try:
                pil_image = Image.open(io.BytesIO(image_data))
                if pil_image.mode != 'RGB':
                    pil_image = pil_image.convert('RGB')
                pil_images.append(pil_image)
            except Exception as e:
                raise HTTPException(status_code=422, detail=f"Invalid image {img_file.filename}: {str(e)}")
        
        # Get analyzer and perform batch analysis
        analyzer = get_food_analyzer()
        results = analyzer.analyze_batch(
            images=pil_images,
            max_workers=4
        )
        
        # Add user email to all results
        for result in results:
            result['user_email'] = email
        
        return {
            'results': results,
            'total_images': len(images),
            'processing_time_ms': sum(r.get('processing_time_ms', 0) for r in results)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Batch food analysis failed: {e}")
        raise HTTPException(status_code=500, detail=f"Batch analysis failed: {str(e)}")

@router.get("/models/info")
async def get_model_info():
    """Get information about loaded models"""
    try:
        analyzer = get_food_analyzer()
        
        # Get model versions
        model_info = analyzer._get_model_versions()
        
        # Add configuration info
        config = get_config()
        model_info['configuration'] = {
            'classification_threshold': config.classification_threshold,
            'portion_threshold': config.portion_threshold,
            'overall_threshold': config.overall_threshold,
            'max_concurrent_requests': config.max_concurrent_requests,
            'enable_batch_processing': config.enable_batch_processing
        }
        
        return model_info
        
    except Exception as e:
        logger.error(f"Failed to get model info: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get model info: {str(e)}")

@router.post("/models/reload")
async def reload_models():
    """Reload all models (admin only)"""
    try:
        global food_analyzer
        food_analyzer = None
        
        # Create new analyzer instance
        analyzer = get_food_analyzer()
        
        return {
            'message': 'Models reloaded successfully',
            'health': analyzer.health_check(),
            'timestamp': time.time()
        }
        
    except Exception as e:
        logger.error(f"Failed to reload models: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to reload models: {str(e)}")

@router.get("/performance/stats")
async def get_performance_stats():
    """Get performance statistics"""
    try:
        analyzer = get_food_analyzer()
        stats = analyzer.get_performance_stats()
        
        return stats
        
    except Exception as e:
        logger.error(f"Failed to get performance stats: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get performance stats: {str(e)}")

@router.post("/config/update")
async def update_configuration(
    classification_threshold: Optional[float] = Form(None),
    portion_threshold: Optional[float] = Form(None),
    overall_threshold: Optional[float] = Form(None)
):
    """Update configuration thresholds (admin only)"""
    try:
        config_updates = {}
        
        if classification_threshold is not None:
            config_updates['classification_threshold'] = classification_threshold
        if portion_threshold is not None:
            config_updates['portion_threshold'] = portion_threshold
        if overall_threshold is not None:
            config_updates['overall_threshold'] = overall_threshold
        
        if not config_updates:
            raise HTTPException(status_code=400, detail="No configuration updates provided")
        
        # Update global configuration
        update_config(**config_updates)
        
        # Update analyzer thresholds
        analyzer = get_food_analyzer()
        analyzer.update_confidence_thresholds(
            classification=classification_threshold,
            portion=portion_threshold,
            overall=overall_threshold
        )
        
        return {
            'message': 'Configuration updated successfully',
            'updates': config_updates,
            'current_config': get_config().__dict__,
            'timestamp': time.time()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update configuration: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to update configuration: {str(e)}")

@router.get("/nutrition/search")
async def search_similar_foods(
    food_name: str,
    limit: int = 5
):
    """Search for similar foods in nutrition database"""
    try:
        analyzer = get_food_analyzer()
        similar_foods = analyzer.nutrition_mapper.search_similar_foods(food_name, limit)
        
        return {
            'query': food_name,
            'results': similar_foods,
            'count': len(similar_foods)
        }
        
    except Exception as e:
        logger.error(f"Food search failed: {e}")
        raise HTTPException(status_code=500, detail=f"Food search failed: {str(e)}")
