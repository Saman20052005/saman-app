"""
Mock Food Classification Service for development and testing.
Produces deterministic, realistic Food-101 style predictions without requiring real models.
"""

import os
import logging
import time
import hashlib
import random
from typing import List, Dict, Optional, Any
from enum import Enum
from PIL import Image
import io

from ..schemas.inference_schemas import (
    FoodClassificationResult, 
    FoodPrediction, 
    ModelType,
    ModelMetadata
)

logger = logging.getLogger(__name__)


class MockMode(str, Enum):
    """Mock classification behavior modes"""
    NORMAL = "normal"
    LOW_CONFIDENCE = "low_confidence"
    UNKNOWN = "unknown"
    EMPTY = "empty"


class MockFoodClassificationService:
    """
    Mock food classification service that mimics Food-101 model behavior.
    Produces deterministic predictions based on image content hash.
    """
    
    def __init__(self, mock_mode: MockMode = MockMode.NORMAL):
        """
        Initialize mock classification service.
        
        Args:
            mock_mode: Mode for mock predictions (normal, low_confidence, unknown, empty)
        """
        self.mock_mode = mock_mode
        self.eval_mode = os.getenv("FOOD_EVAL_MODE", "false").lower() == "true"
        self.demo_seed = os.getenv("FOOD_DEMO_SEED")
        
        # Controlled list of labels guaranteed to exist in the database/fallback
        self.food_101_labels = [
            'apple_pie', 'chicken_curry', 'pizza', 'salad', 'rice'
        ]
        
        # Popular foods for higher probability in mock mode
        self.popular_foods = [
            'pizza', 'salad', 'chicken_curry'
        ]
        
        logger.info(f"MockFoodClassificationService initialized with mode: {mock_mode}, eval_mode: {self.eval_mode}, demo_seed: {self.demo_seed}")
    
    def _get_image_hash(self, image: Image.Image) -> str:
        """Generate deterministic hash from image for consistent predictions"""
        # Convert image to bytes and hash
        img_bytes = io.BytesIO()
        image.save(img_bytes, format='PNG')
        img_bytes = img_bytes.getvalue()
        
        # Base hash from image content
        base_hash = hashlib.md5(img_bytes).hexdigest()
        
        # Apply demo seed if provided for deterministic demo behavior
        if self.demo_seed:
            combined = f"{base_hash}_{self.demo_seed}"
            return hashlib.md5(combined.encode()).hexdigest()
        
        return base_hash
    
    def _generate_deterministic_predictions(self, image: Image.Image, top_k: int = 5) -> List[FoodPrediction]:
        """Generate deterministic predictions based on image hash"""
        
        if self.mock_mode == MockMode.EMPTY:
            return []
        
        # Use hash to seed random for deterministic behavior
        image_hash = self._get_image_hash(image)
        seed = int(image_hash[:8], 16)
        random.seed(seed)
        
        if self.mock_mode == MockMode.UNKNOWN:
            # Always return unknown food
            return [FoodPrediction(
                class_id=0,
                class_name="unknown_food",
                display_name="Unknown Food",
                confidence=0.824
            )]
        
        # Select random foods based on hash
        available_foods = self.food_101_labels.copy()
        random.shuffle(available_foods)
        
        # Generate predictions
        predictions = []
        for i in range(min(top_k, len(available_foods))):
            class_name = available_foods[i]
            class_id = self.food_101_labels.index(class_name)
            
            # Generate confidence based on mode
            if self.mock_mode == MockMode.LOW_CONFIDENCE:
                confidence = random.uniform(0.15, 0.45)
            else:  # NORMAL mode
                # Popular foods get higher confidence
                if class_name in self.popular_foods:
                    confidence = random.uniform(0.75, 0.92)
                else:
                    confidence = random.uniform(0.45, 0.85)
            
            predictions.append(FoodPrediction(
                class_id=class_id,
                class_name=class_name,
                display_name=class_name.replace('_', ' ').title(),
                confidence=confidence
            ))
        
        # Sort by confidence (highest first)
        predictions.sort(key=lambda x: x.confidence, reverse=True)
        
        return predictions
    
    def predict(self, image: Image.Image, top_k: int = 5) -> List[Dict]:
        """
        Mock predict method for backward compatibility.
        
        Args:
            image: PIL Image input
            top_k: Number of top predictions to return
            
        Returns:
            List of prediction dictionaries
        """
        result = self.predict_canonical(image, top_k)
        return [pred.to_dict() for pred in result.top_k_predictions]
    
    def predict_canonical(self, image: Image.Image, top_k: int = 5) -> FoodClassificationResult:
        """
        Generate mock food classification predictions in canonical format.
        
        Args:
            image: PIL Image input
            top_k: Number of top predictions to return
            
        Returns:
            FoodClassificationResult with canonical schema
        """
        start_time = time.time()
        
        try:
            # Generate deterministic predictions
            predictions = self._generate_deterministic_predictions(image, top_k)
            
            if not predictions:
                # Handle empty mode
                result = FoodClassificationResult.create_error_result(
                    "No food detected", 
                    ModelType.MOCK
                )
                result.model_info.update({
                    "mock_mode": self.mock_mode.value,
                    "eval_mode": self.eval_mode,
                    "demo_seed": self.demo_seed
                })
                return result
            
            # Create model metadata
            model_metadata = ModelMetadata(
                model_name="mock_food101",
                model_version="v0",
                num_classes=len(self.food_101_labels),
                input_size=(224, 224),
                device="cpu",
                model_type=ModelType.MOCK
            )
            
            inference_time = (time.time() - start_time) * 1000
            
            # Base model info
            model_info = model_metadata.to_dict()
            model_info.update({
                "dataset": "food101_simulated",
                "mock_mode": self.mock_mode.value,
                "deterministic": True,
                "eval_mode": self.eval_mode,
                "demo_seed": self.demo_seed
            })
            
            # Add evaluation mode enhancements
            if self.eval_mode:
                # Add confidence distribution summary
                confidences = [pred.confidence for pred in predictions]
                model_info["confidence_distribution"] = {
                    "mean": sum(confidences) / len(confidences),
                    "min": min(confidences),
                    "max": max(confidences),
                    "top_k_confidences": confidences[:top_k]
                }
                
                # Add prediction reasoning
                model_info["prediction_reasoning"] = {
                    "method": "deterministic_hash_based",
                    "seed_source": "image_content" + (f"_{self.demo_seed}" if self.demo_seed else ""),
                    "mock_mode_behavior": self._get_mode_explanation()
                }
            
            result = FoodClassificationResult(
                top_prediction=predictions[0],
                top_k_predictions=predictions,
                model_type=ModelType.MOCK,
                inference_time_ms=inference_time,
                timestamp=time.time(),
                model_info=model_info
            )
            
            logger.info(f"Mock prediction completed: {result.top_prediction.class_name} "
                       f"(confidence: {result.top_prediction.confidence:.3f}) "
                       f"eval_mode: {self.eval_mode}")
            
            return result
            
        except Exception as e:
            logger.error(f"Mock prediction failed: {e}")
            return FoodClassificationResult.create_error_result(
                f"Mock prediction failed: {e}", 
                ModelType.MOCK
            )
    
    def _get_mode_explanation(self) -> str:
        """Get explanation of current mock mode behavior"""
        explanations = {
            MockMode.NORMAL: "Realistic confidence distribution (0.45-0.92)",
            MockMode.LOW_CONFIDENCE: "Low confidence predictions (0.15-0.45)",
            MockMode.UNKNOWN: "Always returns 'unknown_food'",
            MockMode.EMPTY: "Returns no food detected"
        }
        return explanations.get(self.mock_mode, "Unknown mode")
    
    def is_model_loaded(self) -> bool:
        """Mock service is always loaded"""
        return True
    
    def get_model_info(self) -> Dict:
        """Get mock model information"""
        return {
            'model_type': 'mock',
            'model_name': 'mock_food101',
            'model_version': 'v0',
            'num_classes': len(self.food_101_labels),
            'input_size': (224, 224),
            'device': 'mock',
            'is_loaded': self.is_loaded,
            'mock_mode': self.mock_mode.value,
            'dataset': 'food101_simulated'
        }
