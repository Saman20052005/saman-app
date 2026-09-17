# Food-101 Mobile Model Training Pipeline

Production-ready pipeline for training Food-101 classification models with macro nutrient estimation for mobile deployment.

## Overview

This pipeline provides:
- **Dataset validation and reproducible splitting**
- **Transfer learning with EfficientNet-B0/MobileNetV2**
- **TorchScript export for mobile deployment**
- **Macro nutrient estimation from food predictions**
- **Comprehensive verification and reporting**

## Quick Start (Google Colab)

### 1. Setup Environment

```bash
# Mount Google Drive
from google.colab import drive
drive.mount('/content/drive')

# Install dependencies
!pip install torch torchvision tqdm pandas matplotlib seaborn scikit-learn pillow

# Create working directory
!mkdir -p /content/food101_pipeline
%cd /content/food101_pipeline
```

### 2. Upload Dataset and Scripts

```bash
# Upload Food-101 dataset to /content/food-101
# Upload all Python scripts to /content/food101_pipeline
# Upload labels_to_macro.csv template
```

### 3. Dataset Validation

```bash
# Validate dataset and create splits
python validate_dataset.py \
    --dataset_path /content/food-101/images \
    --output_dir /content/dataset_analysis \
    --train_ratio 0.8 \
    --val_ratio 0.1 \
    --test_ratio 0.1 \
    --seed 42
```

### 4. Training

```bash
# Train EfficientNet-B0 model (recommended)
python train.py \
    --data_path /content/food-101 \
    --split_dir /content/dataset_analysis \
    --output_dir /content/training_output \
    --model efficientnet_b0 \
    --image_size 224 \
    --batch_size 32 \
    --epochs 30 \
    --lr 1e-3 \
    --freeze_epochs 3 \
    --num_workers 4

# Alternative: Train MobileNetV2 (smaller, faster)
python train.py \
    --data_path /content/food-101 \
    --split_dir /content/dataset_analysis \
    --output_dir /content/training_output \
    --model mobilenet_v2 \
    --image_size 224 \
    --batch_size 64 \
    --epochs 30 \
    --lr 1e-3 \
    --freeze_epochs 3 \
    --num_workers 4
```

### 5. Export for Mobile

```bash
# Export TorchScript model
python export_torchscript.py \
    --checkpoint /content/training_output/food101_model_fullinfo.pth \
    --output_dir /content/exports \
    --method trace \
    --quantize \
    --benchmark
```

### 6. Verification

```bash
# Verify all artifacts
python verify_all.py \
    --checkpoint /content/training_output/food101_model_fullinfo.pth \
    --torchscript_model /content/exports/food101_mobile_trace.pt \
    --labels_file /content/training_output/labels.txt \
    --macro_csv /content/labels_to_macro.csv \
    --training_dir /content/training_output \
    --output /content/verify_report.json
```

### 7. Inference Testing

```bash
# Test inference on sample images
python inference.py \
    --model_path /content/exports/food101_mobile_trace.pt \
    --macro_csv /content/labels_to_macro.csv \
    --image_dir /content/sample_images \
    --output /content/test_inference.json \
    --top_k 5 \
    --serving_size 100.0
```

### 8. Save to Drive

```bash
# Copy results to Google Drive
!cp -r /content/training_output /content/drive/MyDrive/food101_results/
!cp -r /content/exports /content/drive/MyDrive/food101_results/
!cp -r /content/dataset_analysis /content/drive/MyDrive/food101_results/
!cp /content/verify_report.json /content/drive/MyDrive/food101_results/
```

## File Structure

```
food101_pipeline/
├── validate_dataset.py      # Dataset validation and splitting
├── train.py                 # Training script with transfer learning
├── inference.py             # Inference with macro estimation
├── export_torchscript.py    # Mobile export and quantization
├── verify_all.py           # Comprehensive verification
├── labels_to_macro.csv     # Macro nutrient mapping template
├── README.md               # This file
└── teammate_checklist_vi.txt # Vietnamese checklist
```

## Expected Outputs

### Training Outputs (`/training_output/`)
- `food101_model_fullinfo.pth` - Complete checkpoint with metadata
- `labels.txt` - Class names ordered by index
- `training_curve.csv` - Training metrics per epoch
- `confusion_matrix.png/.npy` - Confusion matrix visualization
- `per_class_counts.csv` - Image count per class

### Export Outputs (`/exports/`)
- `food101_mobile_trace.pt` - TorchScript model for mobile
- `food101_mobile_trace_quantized.pt` - Quantized model (smaller)
- `export_report.json` - Export performance metrics

### Analysis Outputs (`/dataset_analysis/`)
- `train.txt`, `val.txt`, `test.txt` - Reproducible data splits
- `per_class_counts.csv` - Class distribution
- `dataset_summary.json` - Dataset statistics
- `corrupt_images.csv` - Invalid images (if any)
- `duplicates.csv` - Duplicate images (if any)

## Model Performance Targets

- **Validation Top-1 Accuracy**: ≥ 60% (target ≥ 65%)
- **TorchScript Compatibility**: 100% forward pass success
- **Macro Coverage**: ≥ 95% of classes have macro data
- **Model Size**: < 50MB (unquantized), < 25MB (quantized)
- **Inference Time**: < 100ms on mobile CPU

## Configuration Options

### Training Parameters
- `--model`: efficientnet_b0 (default) or mobilenet_v2
- `--image_size`: 224 (default) or 329 for better accuracy
- `--batch_size`: 32 (default), adjust based on GPU memory
- `--epochs`: 30 (default), may need more for convergence
- `--lr`: 1e-3 (default), learning rate
- `--freeze_epochs`: 3 (default), backbone freeze epochs

### Export Options
- `--method`: trace (default) or script
- `--quantize`: Apply dynamic quantization for smaller size
- `--benchmark`: Performance benchmarking

### Inference Parameters
- `--top_k`: Number of top predictions (default: 5)
- `--serving_size`: Serving size for macro calculations (default: 100g)

## Troubleshooting

### Common Issues

1. **CUDA Out of Memory**
   ```bash
   # Reduce batch size
   python train.py --batch_size 16 ...
   ```

2. **Dataset Path Issues**
   ```bash
   # Verify dataset structure
   ls /content/food-101/images/
   # Should show class directories: apple_pie/, baby_back_ribs/, etc.
   ```

3. **Macro CSV Missing Classes**
   ```bash
   # Check verification report for missing classes
   cat verify_report.json | grep "missing_classes"
   ```

4. **TorchScript Export Fails**
   ```bash
   # Try scripting instead of tracing
   python export_torchscript.py --method script ...
   ```

### Performance Improvements

- **Higher Accuracy**: Use `--image_size 329` with EfficientNet-B0
- **Faster Training**: Use MobileNetV2 with larger batch size
- **Better Generalization**: Increase `--freeze_epochs` to 5
- **Mobile Optimization**: Use quantized model for deployment

## Advanced Usage

### Resume Training
```bash
python train.py --resume /content/training_output/checkpoints/checkpoint_epoch_15.pth ...
```

### Custom Learning Rate Schedule
```bash
# Modify train.py to use ReduceLROnPlateau
scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='max', patience=3)
```

### Data Augmentation
```bash
# Modify train.py transforms for stronger augmentation
transforms.RandomResizedCrop(image_size, scale=(0.8, 1.0)),
transforms.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.3, hue=0.2),
```

## Mobile Deployment

### Android Integration
```java
// Load TorchScript model
Module module = Module.load(assetFilePath(context, "food101_mobile_trace.pt"));

// Prepare input tensor
Tensor inputTensor = TensorImageUtils.bitmapToFloat32Tensor(
    bitmap, 
    TensorImageUtils.TORCHVISION_NORM_MEAN_RGB,
    TensorImageUtils.TORCHVISION_NORM_STD_RGB
);

// Run inference
Tensor output = module.forward(IValue.from(inputTensor)).toTensor();
```

### iOS Integration (CoreML)
```bash
# Convert to CoreML (requires additional tools)
pip install coremltools
python convert_to_coreml.py --model food101_mobile_trace.pt
```

## Citation

If you use this pipeline, please cite:
```
@inproceedings{bossard14,
  title = {Food-101 -- Mining Discriminative Components with Random Forests},
  author = {Bossard, Lukas and Guillaumin, Matthieu and Van Gool, Luc},
  booktitle = {European Conference on Computer Vision},
  year = {2014}
}
```

## License

This pipeline is provided for research and development purposes. Please ensure compliance with the original Food-101 dataset license terms.
