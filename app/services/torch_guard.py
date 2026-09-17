"""
PyTorch Import Guard for safe deployment
Controls PyTorch loading based on environment variables
"""

import os
import logging

logger = logging.getLogger(__name__)

# Environment-controlled PyTorch loading
USE_PYTORCH = os.getenv("USE_PYTORCH", "false").lower() == "true"
FALLBACK_TO_MOCK = os.getenv("FALLBACK_TO_MOCK", "true").lower() == "true"
MODEL_DIR = os.getenv("MODEL_DIR", "/opt/render/project/src/models")

# Global torch reference
torch = None

def initialize_torch():
    """Initialize PyTorch if enabled and available"""
    global torch, USE_PYTORCH
    
    if not USE_PYTORCH:
        logger.info("PyTorch disabled by environment (USE_PYTORCH=false)")
        return False
    
    try:
        import torch
        logger.info(f"✅ PyTorch imported successfully: {torch.__version__}")
        
        # Test basic functionality
        if torch.cuda.is_available():
            logger.info("✅ CUDA available")
        else:
            logger.info("✅ PyTorch CPU-only mode")
        
        return True
        
    except ImportError as e:
        logger.error(f"❌ PyTorch import failed: {e}")
        if FALLBACK_TO_MOCK:
            logger.info("🔄 Falling back to mock mode")
            USE_PYTORCH = False
            return False
        else:
            raise e
    except Exception as e:
        logger.error(f"❌ PyTorch initialization failed: {e}")
        if FALLBACK_TO_MOCK:
            logger.info("🔄 Falling back to mock mode")
            USE_PYTORCH = False
            return False
        else:
            raise e

def check_model_files():
    """Check if model files exist in MODEL_DIR"""
    import os
    from pathlib import Path
    
    model_dir = Path(MODEL_DIR)
    if not model_dir.exists():
        logger.warning(f"Model directory does not exist: {model_dir}")
        return False
    
    # Check for common model files
    model_files = [
        "food_classification_model.pth",
        "portion_estimation_regressor.pth", 
        "food_classification_efficientnet_b3.pth"
    ]
    
    existing_files = []
    for file in model_files:
        file_path = model_dir / file
        if file_path.exists():
            existing_files.append(file)
            logger.info(f"✅ Model file found: {file_path}")
        else:
            logger.warning(f"⚠️ Model file missing: {file_path}")
    
    return len(existing_files) > 0

# Initialize on import
torch_available = initialize_torch()
models_available = check_model_files() if torch_available else False

if USE_PYTORCH and not torch_available:
    logger.error("❌ PyTorch required but not available")
elif USE_PYTORCH and not models_available:
    logger.warning("⚠️ PyTorch available but model files missing")
elif not USE_PYTORCH:
    logger.info("ℹ️ Running in mock mode (PyTorch disabled)")
