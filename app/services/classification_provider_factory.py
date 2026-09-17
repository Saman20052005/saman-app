"""
Classification Provider Factory for switching between different food classification implementations.
Supports mock and pytorch providers via configuration. TensorFlow is no longer supported.
"""

import os
from typing import Optional
from enum import Enum
import logging

# Conditional imports to support mock mode without dependencies
try:
    from .food_classification_service import FoodClassificationService
    _PYTORCH_AVAILABLE = True
except ImportError:
    FoodClassificationService = None
    _PYTORCH_AVAILABLE = False

from .mock_food_classification_service import MockFoodClassificationService, MockMode

logger = logging.getLogger(__name__)


class ClassificationProvider(str, Enum):
    """Supported classification providers - PyTorch only architecture"""
    MOCK = "mock"
    PYTORCH = "pytorch"


class ClassificationProviderFactory:
    """
    Factory for creating food classification service instances based on configuration.
    Provides abstraction layer between ensemble and specific classification implementations.
    """
    
    @staticmethod
    def get_provider() -> ClassificationProvider:
        """Get classification provider from environment configuration"""
        provider_str = os.getenv("FOOD_CLASSIFIER_PROVIDER", "mock").lower()
        
        if provider_str == ClassificationProvider.MOCK.value:
            return ClassificationProvider.MOCK
        elif provider_str == ClassificationProvider.PYTORCH.value:
            return ClassificationProvider.PYTORCH
        else:
            # Explicitly reject TensorFlow with clear error
            if provider_str == "tensorflow":
                logger.error("TensorFlow provider is no longer supported. Please use 'pytorch' or 'mock'")
            else:
                logger.warning(f"Invalid provider '{provider_str}', defaulting to mock")
            return ClassificationProvider.MOCK
    
    @staticmethod
    def create_service(
        model_path: Optional[str] = None,
        mock_mode: Optional[MockMode] = None
    ):
        """
        Create classification service instance based on provider configuration.
        Implements safe fallback strategy for all failure scenarios.
        
        Args:
            model_path: Optional path to model weights (for pytorch)
            mock_mode: Mock mode when provider is mock
            
        Returns:
            Classification service instance
        """
        provider = ClassificationProviderFactory.get_provider()
        
        logger.info(f"🏭 Creating classification service - Provider: {provider.value}")
        
        if provider == ClassificationProvider.MOCK:
            # Determine mock mode from environment
            mock_mode_str = os.getenv("MOCK_CLASSIFIER_MODE", "normal").lower()
            if mock_mode is None:
                try:
                    mock_mode = MockMode(mock_mode_str)
                except ValueError:
                    logger.warning(f"⚠️ Invalid mock mode '{mock_mode_str}', defaulting to normal")
                    mock_mode = MockMode.NORMAL
            
            logger.info(f"🎭 Creating MockFoodClassificationService with mode: {mock_mode.value}")
            return MockFoodClassificationService(mock_mode=mock_mode)
        
        elif provider == ClassificationProvider.PYTORCH:
            if not _PYTORCH_AVAILABLE:
                logger.error(f"❌ PyTorch provider requested but torch is not available, falling back to mock")
                logger.info(f"🔄 Fallback: Using MockFoodClassificationService")
                return MockFoodClassificationService()
            
            logger.info(f"🔥 Creating FoodClassificationService (PyTorch) with model_path: {model_path}")
            
            # Try to create real PyTorch service with fallback
            try:
                from .food_classification_service import FoodClassificationService
                service = FoodClassificationService(model_path=model_path)
                logger.info("✅ PyTorch service created (lazy load — model loads on first inference)")
                return service
            except Exception as e:
                logger.error(f"❌ PyTorch service creation failed: {e}, falling back to mock")
                logger.info(f"🔄 Fallback: Using MockFoodClassificationService")
                return MockFoodClassificationService()
        
        else:
            # Fallback to mock
            logger.warning(f"⚠️ Unknown provider '{provider}', falling back to mock")
            logger.info(f"🔄 Fallback: Using MockFoodClassificationService")
            return MockFoodClassificationService()
    
    @staticmethod
    def get_provider_info() -> dict:
        """Get information about current provider configuration"""
        provider = ClassificationProviderFactory.get_provider()
        
        return {
            'current_provider': provider.value,
            'supported_providers': [ClassificationProvider.MOCK.value, ClassificationProvider.PYTORCH.value],
            'pytorch_available': _PYTORCH_AVAILABLE,
            'architecture': 'PyTorch-only',
            'tensorflow_deprecated': True
        }


# Convenience function for backward compatibility
def create_classification_service(
    model_path: Optional[str] = None,
    mock_mode: Optional[MockMode] = None
):
    """
    Convenience function to create classification service.
    This is the main entry point for creating classification services.
    """
    return ClassificationProviderFactory.create_service(model_path, mock_mode)
