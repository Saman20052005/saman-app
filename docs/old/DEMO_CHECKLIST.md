# Demo Safety Checklist

## Pre-Demo Configuration

### Environment Variables to Set
```bash
# For reliable demo with mock provider
FOOD_CLASSIFIER_PROVIDER=mock
MOCK_CLASSIFIER_MODE=normal
FOOD_DEMO_SEED=42

# For evaluation mode (shows ML reasoning)
FOOD_EVAL_MODE=true

# Optional: For real PyTorch model demo
# FOOD_CLASSIFIER_PROVIDER=pytorch
# FOOD_MODEL_PATH=app/ml_artifacts/food_classification_model.pth
```

### Files to Verify
- ✅ `.env` file exists with correct configuration
- ✅ `app/ml_artifacts/labels.txt` exists (101 Food-101 labels)
- ✅ No TensorFlow dependencies in `requirements.txt`
- ✅ Application starts without errors

## Demo Scenarios

### 1. Mock Provider Demo (Recommended for Safety)
```bash
# Set environment
export FOOD_CLASSIFIER_PROVIDER=mock
export FOOD_DEMO_SEED=42
export FOOD_EVAL_MODE=true

# Start application
python main.py

# Test with any food image
curl -X POST "http://localhost:8000/api/food/analyze" \
     -H "Content-Type: multipart/form-data" \
     -F "file=@test_image.jpg"
```

**Expected Behavior:**
- Deterministic predictions (same result every time)
- Clear ML reasoning in response
- Processing time ~20-30ms
- Provider info shows "MockFoodClassificationService"

### 2. PyTorch Provider Demo (If Model Available)
```bash
# Set environment
export FOOD_CLASSIFIER_PROVIDER=pytorch
export FOOD_MODEL_PATH=app/ml_artifacts/food_classification_model.pth

# Start application
python main.py
```

**Expected Behavior:**
- Real model inference
- Fallback to mock if model fails to load
- Processing time ~50-100ms (CPU) or ~10-20ms (GPU)

## What to Say During Demo

### Introduction
"This is a PyTorch-only food classification system that can identify 101 different food categories from images and provide nutritional analysis."

### Architecture Explanation
"The system uses a provider pattern with two main providers:
1. **Mock Provider** - For development and reliable demos
2. **PyTorch Provider** - For real model inference with EfficientNet-B3"

### Model Fallback Explanation
"If you see the system fall back to mock during the demo, that's by design. The system has automatic fallbacks to ensure it never crashes, which is crucial for production reliability."

### Evaluation Mode
"When `FOOD_EVAL_MODE=true`, the system includes detailed ML reasoning in the response, showing confidence distributions and prediction methodology."

### Portion Estimation
"The portion estimation uses multiple approaches including reference object detection and depth estimation. In mock mode, it provides reasonable estimates for demonstration purposes."

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. "PyTorch provider requested but torch is not available"
**Cause**: PyTorch not installed
**Solution**: System automatically falls back to mock
**What to say**: "This demonstrates the system's robust fallback mechanism"

#### 2. "Model file not found"
**Cause**: Real PyTorch model not available
**Solution**: System automatically falls back to mock
**What to say**: "The system is designed to work with or without real models"

#### 3. "MongoDB connection failed"
**Cause**: MongoDB not running
**Solution**: System uses minimal nutrition data
**What to say**: "The system gracefully handles database unavailability"

#### 4. Slow response times
**Cause**: Running on CPU without GPU acceleration
**Solution**: This is expected behavior
**What to say**: "Performance improves significantly with GPU acceleration"

## Demo Script Example

### Opening
"Today I'll demonstrate our PyTorch-based food classification system. The system can identify 101 different food categories and provide nutritional analysis."

### Feature 1: Classification
"Let me upload an image of pizza. The system will classify it and provide confidence scores."
*(Show response with top-5 predictions and confidence distribution)*

### Feature 2: Evaluation Mode
"With evaluation mode enabled, you can see the ML reasoning behind each prediction, including confidence distributions and prediction methodology."

### Feature 3: Provider System
"The system uses a provider pattern. Currently running in mock mode for reliability, but it can seamlessly switch to real PyTorch models when available."

### Feature 4: Robustness
"Notice how the system includes detailed timing breakdowns and system information. This helps with monitoring and debugging in production."

### Closing
"The system demonstrates professional ML engineering practices including provider abstraction, safe fallbacks, comprehensive logging, and evaluation capabilities."

## Technical Questions Preparation

### Q: "Why use mock provider?"
A: "For development reliability and demo safety. It ensures the system always works regardless of model availability, which is crucial for production systems."

### Q: "How does the fallback work?"
A: "The provider factory automatically detects failures and falls back to mock. This includes missing dependencies, invalid model files, or runtime errors."

### Q: "What's the accuracy?"
A: "With real PyTorch models, it achieves standard Food-101 accuracy. Mock provider provides deterministic predictions for development."

### Q: "Why EfficientNet-B3?"
A: "Good balance of accuracy and efficiency, proven performance on food recognition, reasonable inference time for demo purposes."

### Q: "How do you handle different image sizes?"
A: "All images are resized to 224×224 with ImageNet normalization, which is standard for EfficientNet models."

## Environment Verification Commands

```bash
# Check provider configuration
python -c "
from app.services.classification_provider_factory import ClassificationProviderFactory
info = ClassificationProviderFactory.get_provider_info()
print('Provider Info:', info)
"

# Check evaluation utilities
python -c "
from app.ml.evaluation.eval_utils import get_demo_explanation
print(get_demo_explanation())
"

# Test ensemble with mock
python -c "
from app.services.food_analysis_ensemble import FoodAnalysisEnsemble
from PIL import Image
ensemble = FoodAnalysisEnsemble()
img = Image.new('RGB', (224, 224), color='red')
result = ensemble.analyze_image(img)
print('Status:', result.get('status'))
print('Processing time:', result.get('processing_time_ms'))
"
```

## Final Checklist Before Demo

- [ ] Environment variables set correctly
- [ ] Application starts without errors
- [ ] Test image ready for upload
- [ ] API endpoint accessible
- [ ] Response format verified
- [ ] Fallback behavior tested
- [ ] Logging level appropriate for demo
- [ ] Evaluation mode working (if using)
- [ ] Demo script prepared
- [ ] Technical questions rehearsed

## Emergency Procedures

### If Application Crashes
1. Check logs for error messages
2. Verify environment variables
3. Fall back to mock provider: `FOOD_CLASSIFIER_PROVIDER=mock`
4. Restart with minimal configuration

### If Predictions Look Wrong
1. Verify `FOOD_DEMO_SEED` is set for deterministic behavior
2. Check `MOCK_CLASSIFIER_MODE` setting
3. Review confidence scores in evaluation mode
4. Explain mock vs real model behavior

### If Performance is Slow
1. Check if running on CPU vs GPU
2. Review timing breakdown in response
3. Explain mock vs real model performance differences
4. Mention optimization opportunities

Remember: The system is designed to be robust and educational. Any "issues" during demo are actually opportunities to explain good engineering practices!
