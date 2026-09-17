# Import torch guard first
from .torch_guard import USE_PYTORCH, torch_available, models_available, initialize_torch
import logging
import os
from typing import Optional, List, Dict

# No torch imports at module level - will be lazy loaded
from PIL import Image
import numpy as np
from pathlib import Path
import json
import time

from ..schemas.inference_schemas import (
    FoodClassificationResult, 
    FoodPrediction, 
    ModelType,
    ModelMetadata
)

logger = logging.getLogger(__name__)

class FoodClassificationService:
    """
    EfficientNet-B0 based food classification model with lazy loading
    Fine-tuned on food dataset for 101 food categories
    """
    
    def __init__(self, model_path: Optional[str] = None, num_classes: int = 101):
        """
        Initialize FoodClassificationService with lazy PyTorch model loading.
        
        Args:
            model_path: Path to .pth/.pt model file
            num_classes: Number of classes (should be 101 for Food-101)
        """
        self.num_classes = num_classes
        self.model_path = model_path or os.getenv("MODEL_PATH", "models/placeholder_model.pt")
        self.device = os.getenv("FOOD_MODEL_DEVICE", "cpu")
        
        # Lazy-loaded components
        self._model = None
        self._transforms = None
        self._label_registry = None
        self._torch_initialized = False
        
        logger.info(f"FoodClassificationService initialized (lazy loading) with model: {self.model_path}")
    
    def _ensure_torch(self):
        """Ensure PyTorch is imported and initialized"""
        if not self._torch_initialized:
            try:
                import torch
                import torch.nn as nn
                import torchvision.transforms as transforms
                from torchvision import models
                
                # Store in instance for later use
                self._torch = torch
                self._torchvision_models = models
                self._torchvision_transforms = transforms
                self._torch_initialized = True
                
                logger.info("✅ PyTorch modules lazy-loaded successfully")
            except ImportError as e:
                logger.error(f"❌ PyTorch lazy import failed: {e}")
                raise
    
    def _ensure_model(self):
        """Ensure model is loaded"""
        if self._model is None:
            self._ensure_torch()
            
            try:
                # Create EfficientNet-B4 model
                model = self._torchvision_models.efficientnet_b4(weights=None)
                
                # Modify classifier for 101 food classes
                in_features = model.classifier[1].in_features
                model.classifier[1] = self._torch.nn.Linear(in_features, self.num_classes)
                
                # Load weights if model file exists
                if os.path.exists(self.model_path):
                    logger.info(f"Loading model weights from {self.model_path}")
                    state_dict = self._torch.load(self.model_path, map_location='cpu')
                    # Handle strict=True for loading
                    model.load_state_dict(state_dict, strict=True)
                else:
                    logger.warning(f"Model file not found at {self.model_path}, using random weights")
                
                # Setup device and move model
                self.device = self._torch.device("cpu")
                model.to(self.device)
                model.eval()
                
                # Tối ưu RAM cho Render free tier
                import gc
                gc.collect()
                self._torch.set_grad_enabled(False)
                
                self._model = model
                logger.info(f"Model loaded successfully on {self.device}")
                
            except Exception as e:
                logger.error(f"Model loading failed: {e}")
                raise
    
    def _ensure_transforms(self):
        """Ensure transforms are initialized"""
        if self._transforms is None:
            self._ensure_torch()
            self._transforms = self._torchvision_transforms.Compose([
                self._torchvision_transforms.Resize((224, 224)),
                self._torchvision_transforms.ToTensor(),
                self._torchvision_transforms.Normalize(
                    mean=[0.485, 0.456, 0.406], 
                    std=[0.229, 0.224, 0.225]
                )
            ])
            logger.info("✅ Transforms initialized")
    
    def _ensure_label_registry(self):
        """Ensure label registry is loaded"""
        if self._label_registry is None:
            try:
                from ..ml.registry.food_label_registry import get_label_registry
                self._label_registry = get_label_registry()
                logger.info("✅ Label registry loaded")
            except ImportError:
                # Fallback to basic labels
                self._label_registry = type('MockRegistry', (), {
                    'is_valid': True,
                    'labels': [f'food_{i}' for i in range(self.num_classes)],
                    'get_label_info': lambda idx: {'name': f'food_{idx}', 'macro': 'unknown'}
                })()
                logger.warning("⚠️ Using mock label registry")
    
    def predict(self, image: Image.Image, top_k: int = 5) -> List[Dict]:
        """
        Predict food class with confidence scores
        
        Args:
            image: PIL Image input
            top_k: Number of top predictions to return
            
        Returns:
            List of predictions with class names and confidence scores
        """
        result = self.predict_canonical(image, top_k)
        return [pred.to_dict() for pred in result.top_k_predictions]
    
    def predict_canonical(self, image: Image.Image, top_k: int = 5) -> FoodClassificationResult:
        """
        Predict food class with canonical output schema using lazy-loaded PyTorch model.
        
        Args:
            image: PIL Image input
            top_k: Number of top predictions to return
            
        Returns:
            FoodClassificationResult with canonical schema
        """
        try:
            # Ensure all components are loaded
            self._ensure_model()
            self._ensure_transforms()
            self._ensure_label_registry()
            
            # Preprocess image
            input_tensor = self._transforms(image).unsqueeze(0).to(self.device)
            
            # Run inference
            with self._torch.no_grad():
                outputs = self._model(input_tensor)
                probabilities = self._torch.nn.functional.softmax(outputs[0], dim=0)
            
            # Get top-k predictions
            top_probs, top_indices = self._torch.topk(probabilities, min(top_k, len(probabilities)))
            
            # Convert to canonical format
            predictions = []
            for i in range(len(top_probs)):
                class_id = int(top_indices[i].cpu().numpy())
                confidence = float(top_probs[i].cpu().numpy())
                
                # Get label info
                if hasattr(self._label_registry, 'get_label_info'):
                    label_info = self._label_registry.get_label_info(class_id)
                    class_name = label_info.get('name', f'food_{class_id}')
                    display_name = self._format_display_name(class_name)
                else:
                    class_name = f'food_{class_id}'
                    display_name = self._format_display_name(class_name)
                
                prediction = FoodPrediction(
                    class_id=class_id,
                    class_name=class_name,
                    display_name=display_name,
                    confidence=confidence
                )
                predictions.append(prediction)
            
            # Create model metadata
            model_metadata = ModelMetadata(
                model_name="efficientnet_b0_food101",
                model_version="lazy_load_v1",
                num_classes=self.num_classes,
                input_size=(224, 224),
                device=str(self.device),
                model_type=ModelType.PYTORCH
            )
            
            canonical_result = FoodClassificationResult(
                top_prediction=predictions[0],
                top_k_predictions=predictions,
                model_type=ModelType.PYTORCH,
                inference_time_ms=0,  # Could measure with time.time()
                timestamp=time.time(),
                model_info={
                    **model_metadata.to_dict(),
                    "dataset": "food101",
                    "loader_version": "lazy_load_1.0.0",
                    "labels_info": getattr(self._label_registry, 'get_labels_info', lambda: {})()
                }
            )
            
            logger.info(f"Lazy-loaded PyTorch prediction completed: {canonical_result.top_prediction.class_name} "
                       f"(confidence: {canonical_result.top_prediction.confidence:.3f})")
            
            return canonical_result
            
        except Exception as e:
            logger.error(f"Lazy-loaded PyTorch prediction failed: {e}")
            return FoodClassificationResult.create_error_result(
                f"Prediction failed: {e}", 
                ModelType.PYTORCH
            )
    
    def _format_display_name(self, class_name: str) -> str:
        """Convert class_name to human readable format"""
        return class_name.replace('_', ' ').title()
    
    def is_model_loaded(self) -> bool:
        """Check if model is loaded and ready for inference"""
        return self._model is not None
    
    def get_model_info(self) -> Dict:
        """Get model information"""
        return {
            'model_type': 'pytorch',
            'is_loaded': self.is_model_loaded(),
            'model_path': self.model_path,
            'device': str(self.device) if self._torch_initialized else 'not_initialized',
            'num_classes': self.num_classes,
            'torch_initialized': self._torch_initialized
        }
