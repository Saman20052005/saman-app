# Food Analysis System Architecture

## Overview

The Food Image → Macro Nutrient Analysis system is a **PyTorch-only** architecture that provides end-to-end food classification, portion estimation, and nutrition mapping. The system is designed with provider abstraction, enabling seamless switching between mock and real models through configuration.

## Architecture Principles

- **PyTorch-only**: No TensorFlow dependencies in runtime
- **Provider Abstraction**: Classification services are abstracted behind a factory pattern
- **Safe Fallbacks**: Automatic fallback to mock provider on any failure
- **Canonical Schema**: All providers return the same `FoodClassificationResult` schema
- **Configuration-driven**: Model switching requires only environment variable changes

## Core Components

### 1. Classification Provider Factory
**Location**: `app/services/classification_provider_factory.py`

**Purpose**: Abstracts classification service creation and provider selection.

**Supported Providers**:
- `mock`: MockFoodClassificationService (deterministic predictions)
- `pytorch`: FoodClassificationService (real EfficientNet-B3 model)

**Configuration**:
```bash
FOOD_CLASSIFIER_PROVIDER=mock|pytorch
```

### 2. PyTorch Model Loader
**Location**: `app/ml/loaders/food101_pytorch_loader.py`

**Purpose**: Robust loading of EfficientNet-B3 Food-101 models.

**Features**:
- Safe model loading with multiple checkpoint formats
- Device auto-selection (CPU/CUDA)
- Model-label compatibility validation
- Model versioning via hash calculation

### 3. Label Registry
**Location**: `app/ml/registry/food_label_registry.py`

**Purpose**: Validates and manages Food-101 labels with stable class_id mapping.

**Features**:
- Food-101 canonical label validation
- Checksum verification for label file integrity
- Stable class_id ↔ class_name mapping
- Support for custom label sets with warnings

### 4. Food Analysis Ensemble
**Location**: `app/services/food_analysis_ensemble.py`

**Purpose**: Orchestrates the complete food analysis pipeline.

**Pipeline**:
1. Food Classification (via provider factory)
2. Portion Estimation (PyTorch models)
3. Nutrition Mapping (MongoDB + fallback)

### 5. Mock Services
**Location**: `app/services/mock_food_classification_service.py`

**Purpose**: Provides deterministic mock predictions for development/testing.

**Features**:
- Food-101 style predictions (101 classes)
- Multiple modes: normal, low_confidence, unknown, empty
- Deterministic predictions based on image hash
- Complete metadata and traceability

## Model Artifacts

### Expected Structure
```
app/ml_artifacts/
├── food_classification_model.pth  # Real PyTorch model (when available)
└── labels.txt                     # Food-101 labels (101 lines)
```

### Model Loading
- **Real Model**: EfficientNet-B3 fine-tuned on Food-101
- **Input**: 224×224 RGB images
- **Output**: Softmax probabilities for 101 food classes
- **Preprocessing**: ImageNet normalization

## API Endpoints

### Primary Food Analysis
- **Endpoint**: `/api/food/analyze`
- **Method**: POST
- **Input**: Image file
- **Output**: Complete food analysis with nutrition

### Legacy Nutrition Routes
- **Endpoint**: `/api/nutrition/analyze-image`
- **Method**: POST
- **Input**: Image file
- **Output**: Food classification + nutrition lookup

## Configuration

### Environment Variables
```bash
# Provider Selection
FOOD_CLASSIFIER_PROVIDER=mock          # Options: mock, pytorch

# Mock Configuration
MOCK_CLASSIFIER_MODE=normal            # Options: normal, low_confidence, unknown, empty

# PyTorch Model Configuration
FOOD_MODEL_PATH=app/ml_artifacts/food_classification_model.pth
FOOD_LABELS_PATH=app/ml_artifacts/labels.txt
FOOD_MODEL_DEVICE=auto                 # Options: auto, cpu, cuda

# Database
MONGO_URI=mongodb://localhost:27017
DB_NAME=saman_fitness
```

## Deployment Modes

### Development Mode
```bash
FOOD_CLASSIFIER_PROVIDER=mock
MOCK_CLASSIFIER_MODE=normal
```
- Uses mock predictions
- No model files required
- Fast startup, deterministic results

### Production Mode
```bash
FOOD_CLASSIFIER_PROVIDER=pytorch
FOOD_MODEL_PATH=app/ml_artifacts/food_classification_model.pth
FOOD_LABELS_PATH=app/ml_artifacts/labels.txt
FOOD_MODEL_DEVICE=cuda
```
- Uses real PyTorch model
- Automatic fallback to mock on failures
- GPU acceleration when available

## Error Handling & Safety

### Fallback Strategy
1. **Missing Dependencies**: Falls back to mock if PyTorch unavailable
2. **Model Load Failure**: Falls back to mock if model invalid
3. **Runtime Errors**: Returns error results without crashing
4. **Invalid Configuration**: Defaults to mock with clear logging

### Safety Guarantees
- **No API failures**: System always responds, even with mock data
- **Graceful degradation**: Real model → mock → error response
- **Clear logging**: All fallbacks are logged with reasons
- **Schema stability**: Response format never changes

## Migration Path

### From TensorFlow to PyTorch (Complete)
✅ TensorFlow services removed
✅ TensorFlow dependencies removed
✅ TensorFlow artifacts cleaned
✅ Provider selection hardened
✅ Documentation updated

### Future Model Updates
1. Place new `food_classification_model.pth` in `app/ml_artifacts/`
2. Ensure `labels.txt` has 101 Food-101 labels
3. Set `FOOD_CLASSIFIER_PROVIDER=pytorch`
4. No code changes required

## Performance Characteristics

### Mock Provider
- **Inference Time**: ~1-5ms
- **Memory**: Minimal
- **Accuracy**: Deterministic mock predictions

### PyTorch Provider
- **Inference Time**: ~20-50ms (CPU), ~5-15ms (GPU)
- **Memory**: ~500MB model + overhead
- **Accuracy**: Real Food-101 model performance

## Monitoring & Debugging

### Model Information
```python
from app.services.classification_provider_factory import get_provider_info

info = get_provider_info()
# Returns: current_provider, supported_providers, pytorch_available, architecture
```

### Service Status
```python
from app.services.food_analysis_ensemble import FoodAnalysisEnsemble

ensemble = FoodAnalysisEnsemble()
versions = ensemble._get_model_versions()
# Returns: classification, portion_estimation, nutrition_mapping, provider_info
```

## Security Considerations

- **Model Access**: Model files are loaded from local filesystem only
- **Input Validation**: All images are validated before processing
- **Memory Management**: Models are loaded once and reused
- **Error Isolation**: Provider failures don't crash the application

## Extensibility

The architecture supports easy extension:

1. **New Models**: Implement new providers following the canonical schema
2. **Additional Preprocessing**: Extend transforms in model loader
3. **Custom Label Sets**: Use label registry with custom labels.txt
4. **New Nutrition Sources**: Extend nutrition mapping service

## Compliance

- **PyTorch-only**: No TensorFlow runtime dependencies
- **API Stability**: Response schemas are versioned and stable
- **Configuration-driven**: No code changes for model switching
- **Safe Fallbacks**: System remains operational under all failure modes
