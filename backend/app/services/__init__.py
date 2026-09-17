"""
Food Analysis Services

This module provides comprehensive food analysis capabilities including:
- Food classification using EfficientNet-B3
- Portion size estimation using multiple approaches
- Nutrition mapping and macro calculations
- Ensemble service combining all predictions

Main Classes:
- FoodClassificationService: Deep learning-based food recognition
- PortionEstimationService: Multi-method portion size estimation
- NutritionMappingService: Nutrition database integration
- FoodAnalysisEnsemble: Unified analysis pipeline

Usage:
    from backend.app.services import FoodAnalysisEnsemble
    
    ensemble = FoodAnalysisEnsemble()
    result = ensemble.analyze_image(image)
"""

# Conditional imports to support mock mode without torch
try:
    from .food_classification_service import FoodClassificationService
    _PYTORCH_AVAILABLE = True
except ImportError:
    FoodClassificationService = None
    _PYTORCH_AVAILABLE = False

try:
    from .portion_estimation_service import PortionEstimationService
    _TORCH_VISION_AVAILABLE = True
except ImportError:
    PortionEstimationService = None
    _TORCH_VISION_AVAILABLE = False

from .nutrition_mapping_service import NutritionMappingService
from .food_analysis_ensemble import FoodAnalysisEnsemble
from .model_config import ConfigManager, get_config, update_config, save_config
from .mock_food_classification_service import MockFoodClassificationService
from .classification_provider_factory import create_classification_service

__all__ = [
    'FoodClassificationService',
    'PortionEstimationService', 
    'NutritionMappingService',
    'FoodAnalysisEnsemble',
    'ConfigManager',
    'get_config',
    'update_config',
    'save_config',
    'MockFoodClassificationService',
    'create_classification_service'
]