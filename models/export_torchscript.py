#!/usr/bin/env python3
"""
TorchScript Export and Quantization Utilities for Food-101 Models
Exports trained models to TorchScript format and applies quantization for mobile deployment.
"""

import os
import argparse
import time
from pathlib import Path
import json

import torch
import torch.nn as nn
import torchvision.transforms as transforms
from PIL import Image
import numpy as np
from typing import Dict, Tuple, Optional

def load_model_from_checkpoint(checkpoint_path: str, device: torch.device) -> Tuple[nn.Module, Dict]:
    """Load model from checkpoint and return model with metadata."""
    print(f"Loading checkpoint from {checkpoint_path}")
    
    checkpoint = torch.load(checkpoint_path, map_location=device)
    
    # Reconstruct model architecture
    architecture = checkpoint['architecture']
    num_classes = len(checkpoint['class_to_idx'])
    
    if architecture == 'efficientnet_b0':
        from torchvision import models
        model = models.efficientnet_b0(pretrained=False)
        model.classifier[1] = nn.Linear(model.classifier[1].in_features, num_classes)
    elif architecture == 'mobilenet_v2':
        from torchvision import models
        model = models.mobilenet_v2(pretrained=False)
        model.classifier[1] = nn.Linear(model.classifier[1].in_features, num_classes)
    else:
        raise ValueError(f"Unsupported architecture: {architecture}")
    
    # Load state dict
    model.load_state_dict(checkpoint['model_state_dict'])
    model = model.to(device)
    model.eval()
    
    return model, checkpoint

def create_dummy_input(image_size: int, batch_size: int = 1) -> torch.Tensor:
    """Create dummy input for tracing."""
    return torch.randn(batch_size, 3, image_size, image_size)

def export_torchscript_trace(
    model: nn.Module, 
    checkpoint_info: Dict,
    output_path: str,
    device: torch.device,
    batch_size: int = 1
) -> str:
    """Export model using TorchScript tracing."""
    print("Exporting model with TorchScript tracing...")
    
    # Create dummy input
    dummy_input = create_dummy_input(checkpoint_info['image_size'], batch_size)
    dummy_input = dummy_input.to(device)
    
    # Trace the model
    with torch.no_grad():
        traced_model = torch.jit.trace(model, dummy_input)
    
    # Save traced model
    traced_model.save(output_path)
    
    # Verify the traced model
    print("Verifying traced model...")
    try:
        with torch.no_grad():
            original_output = model(dummy_input)
            traced_output = traced_model(dummy_input)
            
            # Check if outputs are close
            if torch.allclose(original_output, traced_output, atol=1e-5):
                print("✓ Traced model verification passed")
            else:
                print("⚠ Traced model outputs differ from original")
                print(f"  Max difference: {torch.max(torch.abs(original_output - traced_output)):.6f}")
    except Exception as e:
        print(f"⚠ Traced model verification failed: {e}")
    
    return output_path

def export_torchscript_script(
    model: nn.Module,
    checkpoint_info: Dict,
    output_path: str,
    device: torch.device
) -> str:
    """Export model using TorchScript scripting."""
    print("Exporting model with TorchScript scripting...")
    
    # Script the model
    scripted_model = torch.jit.script(model)
    
    # Save scripted model
    scripted_model.save(output_path)
    
    # Verify the scripted model
    print("Verifying scripted model...")
    try:
        dummy_input = create_dummy_input(checkpoint_info['image_size'])
        dummy_input = dummy_input.to(device)
        
        with torch.no_grad():
            original_output = model(dummy_input)
            scripted_output = scripted_model(dummy_input)
            
            # Check if outputs are close
            if torch.allclose(original_output, scripted_output, atol=1e-5):
                print("✓ Scripted model verification passed")
            else:
                print("⚠ Scripted model outputs differ from original")
                print(f"  Max difference: {torch.max(torch.abs(original_output - scripted_output)):.6f}")
    except Exception as e:
        print(f"⚠ Scripted model verification failed: {e}")
    
    return output_path

def apply_dynamic_quantization(model_path: str, output_path: str) -> str:
    """Apply dynamic quantization to TorchScript model."""
    print(f"Applying dynamic quantization to {model_path}")
    
    # Load TorchScript model
    model = torch.jit.load(model_path, map_location='cpu')
    
    # Apply dynamic quantization (only works on CPU)
    quantized_model = torch.quantization.quantize_dynamic(
        model.cpu(), 
        {nn.Linear, nn.Conv2d},  # Layers to quantize
        dtype=torch.qint8
    )
    
    # Save quantized model
    quantized_model.save(output_path)
    
    # Compare model sizes
    original_size = os.path.getsize(model_path) / (1024 * 1024)  # MB
    quantized_size = os.path.getsize(output_path) / (1024 * 1024)  # MB
    compression_ratio = original_size / quantized_size
    
    print(f"Original model size: {original_size:.2f} MB")
    print(f"Quantized model size: {quantized_size:.2f} MB")
    print(f"Compression ratio: {compression_ratio:.2f}x")
    
    return output_path

def benchmark_model_performance(
    model_path: str,
    checkpoint_info: Dict,
    device: torch.device,
    num_iterations: int = 100
) -> Dict:
    """Benchmark model performance."""
    print(f"Benchmarking model performance with {num_iterations} iterations...")
    
    # Load model
    if model_path.endswith('.pt'):
        model = torch.jit.load(model_path, map_location=device)
    else:
        model, _ = load_model_from_checkpoint(model_path, device)
    
    model.eval()
    
    # Create dummy input
    dummy_input = create_dummy_input(checkpoint_info['image_size'])
    dummy_input = dummy_input.to(device)
    
    # Warmup
    with torch.no_grad():
        for _ in range(10):
            _ = model(dummy_input)
    
    # Benchmark
    if device.type == 'cuda':
        torch.cuda.synchronize()
    
    start_time = time.time()
    with torch.no_grad():
        for _ in range(num_iterations):
            _ = model(dummy_input)
    
    if device.type == 'cuda':
        torch.cuda.synchronize()
    
    end_time = time.time()
    
    avg_time = (end_time - start_time) / num_iterations
    throughput = 1.0 / avg_time
    
    results = {
        'avg_inference_time_ms': avg_time * 1000,
        'throughput_fps': throughput,
        'device': str(device),
        'num_iterations': num_iterations
    }
    
    print(f"Average inference time: {results['avg_inference_time_ms']:.2f} ms")
    print(f"Throughput: {results['throughput_fps']:.1f} FPS")
    
    return results

def test_quantized_model_accuracy(
    original_model_path: str,
    quantized_model_path: str,
    checkpoint_info: Dict,
    device: torch.device,
    num_samples: int = 100
) -> Dict:
    """Test accuracy difference between original and quantized models."""
    print(f"Testing quantized model accuracy with {num_samples} samples...")
    
    # Load models
    original_model = torch.jit.load(original_model_path, map_location=device)
    quantized_model = torch.jit.load(quantized_model_path, map_location='cpu')  # Quantized models run on CPU
    
    original_model.eval()
    quantized_model.eval()
    
    # Test on random samples
    max_diff = 0.0
    avg_diff = 0.0
    
    for i in range(num_samples):
        # Create random input
        dummy_input = create_dummy_input(checkpoint_info['image_size'])
        
        # Get outputs
        with torch.no_grad():
            if device.type == 'cuda':
                original_output = original_model(dummy_input.to(device)).cpu()
            else:
                original_output = original_model(dummy_input)
            
            quantized_output = quantized_model(dummy_input)
        
        # Calculate difference
        diff = torch.max(torch.abs(original_output - quantized_output)).item()
        max_diff = max(max_diff, diff)
        avg_diff += diff
    
    avg_diff /= num_samples
    
    results = {
        'max_output_difference': max_diff,
        'avg_output_difference': avg_diff,
        'num_samples': num_samples
    }
    
    print(f"Max output difference: {results['max_output_difference']:.6f}")
    print(f"Average output difference: {results['avg_output_difference']:.6f}")
    
    return results

def save_export_report(
    checkpoint_info: Dict,
    export_results: Dict,
    output_path: str
):
    """Save export report as JSON."""
    report = {
        'export_timestamp': time.time(),
        'model_info': {
            'architecture': checkpoint_info['architecture'],
            'image_size': checkpoint_info['image_size'],
            'num_classes': len(checkpoint_info['class_to_idx']),
            'val_acc': checkpoint_info.get('val_acc', 'Unknown')
        },
        'export_results': export_results
    }
    
    with open(output_path, 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"Export report saved to {output_path}")

def main():
    parser = argparse.ArgumentParser(description='Export Food-101 model to TorchScript')
    parser.add_argument('--checkpoint', type=str, required=True,
                        help='Path to model checkpoint (.pth)')
    parser.add_argument('--output_dir', type=str, default='./exports',
                        help='Output directory for exported models')
    parser.add_argument('--method', type=str, default='trace',
                        choices=['trace', 'script', 'both'],
                        help='Export method')
    parser.add_argument('--quantize', action='store_true',
                        help='Apply dynamic quantization')
    parser.add_argument('--benchmark', action='store_true',
                        help='Benchmark model performance')
    parser.add_argument('--device', type=str, default='auto',
                        help='Device to use (auto/cpu/cuda)')
    parser.add_argument('--batch_size', type=int, default=1,
                        help='Batch size for tracing')
    parser.add_argument('--benchmark_iterations', type=int, default=100,
                        help='Number of iterations for benchmarking')
    
    args = parser.parse_args()
    
    # Setup device
    if args.device == 'auto':
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    else:
        device = torch.device(args.device)
    
    print(f"Using device: {device}")
    
    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(exist_ok=True)
    
    # Load model and checkpoint info
    model, checkpoint_info = load_model_from_checkpoint(args.checkpoint, device)
    
    export_results = {}
    
    # Export to TorchScript
    if args.method in ['trace', 'both']:
        trace_path = output_dir / 'food101_mobile_trace.pt'
        export_torchscript_trace(
            model, checkpoint_info, str(trace_path), device, args.batch_size
        )
        export_results['traced_model'] = str(trace_path)
        
        # Benchmark traced model
        if args.benchmark:
            benchmark_results = benchmark_model_performance(
                str(trace_path), checkpoint_info, device, args.benchmark_iterations
            )
            export_results['traced_model_benchmark'] = benchmark_results
    
    if args.method in ['script', 'both']:
        script_path = output_dir / 'food101_mobile_script.pt'
        export_torchscript_script(
            model, checkpoint_info, str(script_path), device
        )
        export_results['scripted_model'] = str(script_path)
        
        # Benchmark scripted model
        if args.benchmark:
            benchmark_results = benchmark_model_performance(
                str(script_path), checkpoint_info, device, args.benchmark_iterations
            )
            export_results['scripted_model_benchmark'] = benchmark_results
    
    # Apply quantization
    if args.quantize:
        print("\nApplying dynamic quantization...")
        
        # Choose which model to quantize (prefer traced if available)
        if 'traced_model' in export_results:
            base_model_path = export_results['traced_model']
            quantized_path = output_dir / 'food101_mobile_trace_quantized.pt'
        else:
            base_model_path = export_results['scripted_model']
            quantized_path = output_dir / 'food101_mobile_script_quantized.pt'
        
        apply_dynamic_quantization(base_model_path, str(quantized_path))
        export_results['quantized_model'] = str(quantized_path)
        
        # Test quantized model accuracy
        accuracy_results = test_quantized_model_accuracy(
            base_model_path, str(quantized_path), checkpoint_info, device
        )
        export_results['quantized_model_accuracy_test'] = accuracy_results
        
        # Benchmark quantized model
        if args.benchmark:
            benchmark_results = benchmark_model_performance(
                str(quantized_path), checkpoint_info, torch.device('cpu'), args.benchmark_iterations
            )
            export_results['quantized_model_benchmark'] = benchmark_results
    
    # Save export report
    report_path = output_dir / 'export_report.json'
    save_export_report(checkpoint_info, export_results, str(report_path))
    
    print(f"\nExport completed! Results saved to {output_dir}")
    print("Files created:")
    for key, path in export_results.items():
        if not key.endswith('_benchmark') and not key.endswith('_test'):
            print(f"  - {path}")
    
    print(f"\nFor mobile deployment, use:")
    if 'traced_model' in export_results:
        print(f"  Standard: {export_results['traced_model']}")
    if 'quantized_model' in export_results:
        print(f"  Quantized: {export_results['quantized_model']} (smaller size, CPU only)")

if __name__ == '__main__':
    main()
