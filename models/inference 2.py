#!/usr/bin/env python3
"""
Food-101 Inference Script with Macro Nutrient Estimation
Loads trained model and performs inference with macro nutrient calculations.
"""

import os
import json
import csv
import argparse
from pathlib import Path
import time

import torch
import torch.nn.functional as F
import torchvision.transforms as transforms
from PIL import Image
import numpy as np
import pandas as pd
from typing import Dict, List, Tuple, Optional

def load_model(checkpoint_path: str, device: torch.device) -> torch.nn.Module:
    """Load trained model from checkpoint."""
    print(f"Loading model from {checkpoint_path}")
    
    checkpoint = torch.load(checkpoint_path, map_location=device)
    
    # Reconstruct model architecture
    architecture = checkpoint['architecture']
    num_classes = len(checkpoint['class_to_idx'])
    
    if architecture == 'efficientnet_b0':
        from torchvision import models
        model = models.efficientnet_b0(pretrained=False)
        model.classifier[1] = torch.nn.Linear(model.classifier[1].in_features, num_classes)
    elif architecture == 'mobilenet_v2':
        from torchvision import models
        model = models.mobilenet_v2(pretrained=False)
        model.classifier[1] = torch.nn.Linear(model.classifier[1].in_features, num_classes)
    else:
        raise ValueError(f"Unsupported architecture: {architecture}")
    
    # Load state dict
    model.load_state_dict(checkpoint['model_state_dict'])
    model = model.to(device)
    model.eval()
    
    return model, checkpoint

def load_torchscript_model(model_path: str, device: torch.device) -> torch.nn.Module:
    """Load TorchScript model."""
    print(f"Loading TorchScript model from {model_path}")
    model = torch.jit.load(model_path, map_location=device)
    model = model.to(device)
    model.eval()
    return model

def load_macro_mapping(macro_csv_path: str) -> pd.DataFrame:
    """Load macro nutrient mapping from CSV."""
    print(f"Loading macro mapping from {macro_csv_path}")
    
    df = pd.read_csv(macro_csv_path)
    
    # Validate required columns
    required_cols = ['class', 'protein_g', 'fat_g', 'carb_g', 'serving_size_g']
    missing_cols = [col for col in required_cols if col not in df.columns]
    if missing_cols:
        raise ValueError(f"Missing required columns in macro CSV: {missing_cols}")
    
    return df

def get_transforms(image_size: int, normalization: Dict) -> transforms.Compose:
    """Get inference transforms."""
    normalize = transforms.Normalize(
        mean=normalization['mean'], 
        std=normalization['std']
    )
    
    return transforms.Compose([
        transforms.Resize(int(image_size * 1.14)),
        transforms.CenterCrop(image_size),
        transforms.ToTensor(),
        normalize,
    ])

def preprocess_image(image_path: str, transform: transforms.Compose) -> torch.Tensor:
    """Preprocess single image for inference."""
    image = Image.open(image_path).convert('RGB')
    tensor = transform(image).unsqueeze(0)  # Add batch dimension
    return tensor

def predict_with_probabilities(
    model: torch.nn.Module, 
    image_tensor: torch.Tensor, 
    device: torch.device,
    top_k: int = 5
) -> Tuple[List[str], List[float], List[int]]:
    """Get top-k predictions with probabilities."""
    image_tensor = image_tensor.to(device)
    
    with torch.no_grad():
        outputs = model(image_tensor)
        probabilities = F.softmax(outputs, dim=1)
        
        # Get top-k predictions
        top_probs, top_indices = torch.topk(probabilities, min(top_k, outputs.size(1)))
        
        top_probs = top_probs.cpu().numpy().flatten()
        top_indices = top_indices.cpu().numpy().flatten()
    
    return top_probs, top_indices

def calculate_weighted_macros(
    top_probs: np.ndarray, 
    top_indices: np.ndarray, 
    idx_to_class: Dict[int, str],
    macro_df: pd.DataFrame,
    serving_size: float = 100.0
) -> Dict[str, float]:
    """Calculate weighted macro nutrient estimates."""
    
    # Initialize macro totals
    total_protein = 0.0
    total_fat = 0.0
    total_carb = 0.0
    
    # Classes with macro data
    classes_with_macros = []
    missing_macro_classes = []
    
    for prob, idx in zip(top_probs, top_indices):
        class_name = idx_to_class[idx]
        
        # Look up macro data
        macro_row = macro_df[macro_df['class'] == class_name]
        
        if not macro_row.empty:
            row = macro_row.iloc[0]
            
            # Normalize to serving size
            factor = serving_size / row['serving_size_g']
            
            total_protein += prob * row['protein_g'] * factor
            total_fat += prob * row['fat_g'] * factor
            total_carb += prob * row['carb_g'] * factor
            
            classes_with_macros.append({
                'class': class_name,
                'probability': float(prob),
                'protein_g': float(row['protein_g'] * factor),
                'fat_g': float(row['fat_g'] * factor),
                'carb_g': float(row['carb_g'] * factor),
                'source_url': row.get('source_url', '')
            })
        else:
            missing_macro_classes.append(class_name)
    
    macro_estimate = {
        'protein_g': float(total_protein),
        'fat_g': float(total_fat),
        'carb_g': float(total_carb),
        'calories': float((total_protein * 4) + (total_carb * 4) + (total_fat * 9)),  # Standard caloric values
        'serving_size_g': serving_size,
        'classes_with_macros': classes_with_macros,
        'missing_macro_classes': missing_macro_classes
    }
    
    return macro_estimate

def infer_single_image(
    model: torch.nn.Module,
    image_path: str,
    checkpoint_info: Dict,
    macro_df: pd.DataFrame,
    device: torch.device,
    top_k: int = 5,
    serving_size: float = 100.0
) -> Dict:
    """Perform inference on a single image."""
    
    # Setup transforms
    transform = get_transforms(checkpoint_info['image_size'], checkpoint_info['normalization'])
    
    # Preprocess image
    image_tensor = preprocess_image(image_path, transform)
    
    # Get predictions
    top_probs, top_indices = predict_with_probabilities(model, image_tensor, device, top_k)
    
    # Convert indices to class names
    idx_to_class = {v: k for k, v in checkpoint_info['class_to_idx'].items()}
    top_classes = [idx_to_class[idx] for idx in top_indices]
    
    # Calculate weighted macros
    macro_estimate = calculate_weighted_macros(
        top_probs, top_indices, idx_to_class, macro_df, serving_size
    )
    
    # Prepare result
    result = {
        'image_path': image_path,
        'timestamp': time.time(),
        'model_info': {
            'architecture': checkpoint_info['architecture'],
            'image_size': checkpoint_info['image_size'],
            'val_acc': checkpoint_info.get('val_acc', 'Unknown')
        },
        'predictions': [
            {
                'class': top_classes[i],
                'probability': float(top_probs[i]),
                'rank': i + 1
            }
            for i in range(len(top_classes))
        ],
        'macro_estimate': macro_estimate,
        'serving_size_g': serving_size
    }
    
    return result

def batch_inference(
    model: torch.nn.Module,
    image_paths: List[str],
    checkpoint_info: Dict,
    macro_df: pd.DataFrame,
    device: torch.device,
    top_k: int = 5,
    serving_size: float = 100.0
) -> List[Dict]:
    """Perform batch inference on multiple images."""
    results = []
    
    print(f"Processing {len(image_paths)} images...")
    for i, image_path in enumerate(image_paths):
        print(f"Processing {i+1}/{len(image_paths)}: {image_path}")
        
        try:
            result = infer_single_image(
                model, image_path, checkpoint_info, macro_df, device, top_k, serving_size
            )
            results.append(result)
        except Exception as e:
            print(f"Error processing {image_path}: {str(e)}")
            results.append({
                'image_path': image_path,
                'error': str(e),
                'timestamp': time.time()
            })
    
    return results

def save_results(results: List[Dict], output_path: str):
    """Save inference results to JSON file."""
    with open(output_path, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"Results saved to {output_path}")

def main():
    parser = argparse.ArgumentParser(description='Food-101 inference with macro estimation')
    parser.add_argument('--model_path', type=str, required=True,
                        help='Path to model checkpoint (.pth) or TorchScript (.pt)')
    parser.add_argument('--macro_csv', type=str, required=True,
                        help='Path to macro nutrient CSV file')
    parser.add_argument('--image_path', type=str, default=None,
                        help='Single image path for inference')
    parser.add_argument('--image_dir', type=str, default=None,
                        help='Directory containing images for batch inference')
    parser.add_argument('--output', type=str, default='inference_results.json',
                        help='Output JSON file')
    parser.add_argument('--top_k', type=int, default=5,
                        help='Number of top predictions to return')
    parser.add_argument('--serving_size', type=float, default=100.0,
                        help='Serving size in grams for macro calculations')
    parser.add_argument('--device', type=str, default='auto',
                        help='Device to use (auto/cpu/cuda)')
    
    args = parser.parse_args()
    
    # Validate inputs
    if not args.image_path and not args.image_dir:
        raise ValueError("Either --image_path or --image_dir must be specified")
    
    # Setup device
    if args.device == 'auto':
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    else:
        device = torch.device(args.device)
    
    print(f"Using device: {device}")
    
    # Load model
    if args.model_path.endswith('.pt'):
        model = load_torchscript_model(args.model_path, device)
        # For TorchScript, we need to load the original checkpoint for metadata
        checkpoint_path = args.model_path.replace('.pt', '_fullinfo.pth')
        if os.path.exists(checkpoint_path):
            _, checkpoint_info = load_model(checkpoint_path, device)
        else:
            raise FileNotFoundError(f"Cannot find checkpoint file for metadata: {checkpoint_path}")
    else:
        model, checkpoint_info = load_model(args.model_path, device)
    
    # Load macro mapping
    macro_df = load_macro_mapping(args.macro_csv)
    
    # Collect image paths
    image_paths = []
    if args.image_path:
        if os.path.exists(args.image_path):
            image_paths.append(args.image_path)
        else:
            raise FileNotFoundError(f"Image not found: {args.image_path}")
    
    if args.image_dir:
        image_dir = Path(args.image_dir)
        if not image_dir.exists():
            raise FileNotFoundError(f"Directory not found: {args.image_dir}")
        
        # Find all image files
        image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.webp'}
        for ext in image_extensions:
            image_paths.extend(str(p) for p in image_dir.rglob(f"*{ext}"))
            image_paths.extend(str(p) for p in image_dir.rglob(f"*{ext.upper()}"))
    
    if not image_paths:
        raise ValueError("No valid images found")
    
    print(f"Found {len(image_paths)} images to process")
    
    # Perform inference
    results = batch_inference(
        model, image_paths, checkpoint_info, macro_df, device,
        args.top_k, args.serving_size
    )
    
    # Save results
    save_results(results, args.output)
    
    # Print summary
    successful_results = [r for r in results if 'error' not in r]
    failed_results = [r for r in results if 'error' in r]
    
    print(f"\nInference Summary:")
    print(f"Total images: {len(results)}")
    print(f"Successful: {len(successful_results)}")
    print(f"Failed: {len(failed_results)}")
    
    if successful_results:
        avg_confidence = np.mean([r['predictions'][0]['probability'] for r in successful_results])
        print(f"Average top-1 confidence: {avg_confidence:.3f}")
        
        # Show example result
        example = successful_results[0]
        print(f"\nExample prediction for {example['image_path']}:")
        print(f"Top-1: {example['predictions'][0]['class']} ({example['predictions'][0]['probability']:.3f})")
        if example['macro_estimate']['classes_with_macros']:
            macros = example['macro_estimate']
            print(f"Estimated macros ({macros['serving_size_g']}g serving):")
            print(f"  Protein: {macros['protein_g']:.1f}g")
            print(f"  Fat: {macros['fat_g']:.1f}g") 
            print(f"  Carbs: {macros['carb_g']:.1f}g")
            print(f"  Calories: {macros['calories']:.0f} kcal")

if __name__ == '__main__':
    main()
