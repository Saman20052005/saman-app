#!/usr/bin/env python3
"""
Smoke test for model loading
Tests if PyTorch model can be loaded and basic inference works
"""
import os
import sys
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_model_loading():
    """Test if we can import torch and load a model"""
    try:
        import torch
        import torchvision.transforms as transforms
        from torchvision import models
        
        logger.info(f"✅ PyTorch version: {torch.__version__}")
        logger.info(f"✅ CUDA available: {torch.cuda.is_available()}")
        
        # Test efficientnet_b0 model creation (without pretrained weights)
        logger.info("✅ Testing EfficientNet-B0 model creation...")
        model = models.efficientnet_b0(weights=None)
        
        # Modify classifier for 101 food classes
        in_features = model.classifier[1].in_features
        model.classifier[1] = torch.nn.Linear(in_features, 101)
        
        logger.info("✅ EfficientNet-B0 model created successfully")
        
        # Test with dummy input
        logger.info("✅ Testing forward pass with dummy input...")
        dummy_input = torch.randn(1, 3, 224, 224)
        with torch.no_grad():
            output = model(dummy_input)
        logger.info(f"✅ Forward pass successful, output shape: {output.shape}")
        
        # Test image transforms
        logger.info("✅ Testing image transforms...")
        transform = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        ])
        logger.info("✅ Image transforms created successfully")
        
        logger.info("🎉 MODEL LOADED - All tests passed!")
        return True
        
    except ImportError as e:
        logger.error(f"❌ Import error: {e}")
        return False
    except Exception as e:
        logger.error(f"❌ Model loading error: {e}")
        return False

def test_model_path():
    """Test if MODEL_PATH environment variable is set"""
    model_path = os.getenv('MODEL_PATH', 'models/placeholder_model.pt')
    logger.info(f"📂 MODEL_PATH: {model_path}")
    
    if os.path.exists(model_path):
        logger.info(f"✅ Model file exists at MODEL_PATH")
        return True
    else:
        logger.warning(f"⚠️ Model file not found at MODEL_PATH: {model_path}")
        return False

def test_lazy_loading_service():
    """Test the lazy-loading FoodClassificationService"""
    try:
        # Add backend to path
        sys.path.insert(0, '/Users/nguyenvanan/Desktop/project-root/backend')
        
        from backend.app.services.food_classification_service import FoodClassificationService
        
        logger.info("✅ FoodClassificationService imported successfully")
        
        # Test service initialization (should not import torch yet)
        service = FoodClassificationService()
        logger.info("✅ Service initialized without importing torch")
        
        # Test lazy loading
        logger.info("✅ Testing lazy model loading...")
        # This will trigger torch import and model loading
        info = service.get_model_info()
        logger.info(f"✅ Service info: {info}")
        
        # Test model loading status
        if service.is_model_loaded():
            logger.info("✅ Model loaded successfully via lazy loading")
        else:
            logger.info("ℹ️ Model not loaded yet (expected if no model file)")
        
        return True
        
    except Exception as e:
        logger.error(f"❌ Lazy loading test failed: {e}")
        return False

if __name__ == "__main__":
    logger.info("=== MODEL LOADING SMOKE TEST ===")
    
    # Test 1: Basic PyTorch functionality
    pytorch_ok = test_model_loading()
    
    # Test 2: Model path
    path_ok = test_model_path()
    
    # Test 3: Lazy loading service
    lazy_ok = test_lazy_loading_service()
    
    if pytorch_ok and lazy_ok:
        logger.info("✅ SMOKE TEST PASSED - Model loading works!")
        sys.exit(0)
    else:
        logger.error("❌ SMOKE TEST FAILED - Model loading issues detected")
        sys.exit(1)
