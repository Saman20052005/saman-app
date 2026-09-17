"""
Canonical inference output schemas for food classification.
Treats model as black-box - downstream code only consumes these schemas.
"""

from dataclasses import dataclass
from typing import List, Optional, Dict, Any
from enum import Enum
import time


class ModelType(str, Enum):
    """Supported model types - PyTorch only architecture"""
    PYTORCH = "pytorch"
    MOCK = "mock"


@dataclass
class FoodPrediction:
    """
    Single food prediction result.
    Canonical output format for any food classification model.
    """
    class_id: int
    class_name: str
    display_name: str
    confidence: float
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        return {
            "class_id": self.class_id,
            "class_name": self.class_name,
            "display_name": self.display_name,
            "confidence": self.confidence
        }


@dataclass
class FoodClassificationResult:
    """
    Complete food classification inference result.
    This is the single canonical output schema for all food classification models.
    """
    # Primary prediction (top-1)
    top_prediction: FoodPrediction
    
    # Top-k predictions (including top-1)
    top_k_predictions: List[FoodPrediction]
    
    # Metadata
    model_type: ModelType
    inference_time_ms: float
    timestamp: float
    
    # Optional model-specific info
    model_info: Optional[Dict[str, Any]] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        return {
            "top_prediction": self.top_prediction.to_dict(),
            "top_k_predictions": [pred.to_dict() for pred in self.top_k_predictions],
            "model_type": self.model_type.value,
            "inference_time_ms": self.inference_time_ms,
            "timestamp": self.timestamp,
            "model_info": self.model_info or {}
        }
    
    @classmethod
    def create_error_result(cls, error_message: str, model_type: ModelType) -> 'FoodClassificationResult':
        """Create error result for failed inference"""
        dummy_prediction = FoodPrediction(
            class_id=-1,
            class_name="unknown",
            display_name="Unknown Food",
            confidence=0.0
        )
        
        return cls(
            top_prediction=dummy_prediction,
            top_k_predictions=[dummy_prediction],
            model_type=model_type,
            inference_time_ms=0.0,
            timestamp=time.time(),
            model_info={"error": error_message}
        )


@dataclass
class ModelMetadata:
    """Model metadata for inference tracking"""
    model_name: str
    model_version: str
    num_classes: int
    input_size: tuple
    device: str
    model_type: ModelType
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        return {
            "model_name": self.model_name,
            "model_version": self.model_version,
            "num_classes": self.num_classes,
            "input_size": self.input_size,
            "device": self.device,
            "model_type": self.model_type.value
        }


# Type aliases for backward compatibility
InferenceResult = FoodClassificationResult
Prediction = FoodPrediction
