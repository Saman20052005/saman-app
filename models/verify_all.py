#!/usr/bin/env python3
"""
Food-101 Model Verification Script
Comprehensive verification of all training artifacts and model integrity.
"""

import os
import json
import csv
import argparse
from pathlib import Path
import time

import torch
import torch.nn as nn
import torchvision.transforms as transforms
from PIL import Image
import numpy as np
import pandas as pd
from typing import Dict, List, Tuple, Optional, Any

def load_and_verify_checkpoint(checkpoint_path: str) -> Tuple[Dict, Dict]:
    """Load checkpoint and verify required keys."""
    print(f"Verifying checkpoint: {checkpoint_path}")
    
    if not os.path.exists(checkpoint_path):
        return {'status': 'FAIL', 'error': f'Checkpoint file not found: {checkpoint_path}'}, {}
    
    try:
        checkpoint = torch.load(checkpoint_path, map_location='cpu')
    except Exception as e:
        return {'status': 'FAIL', 'error': f'Failed to load checkpoint: {str(e)}'}, {}
    
    # Required keys
    required_keys = [
        'model_state_dict',
        'class_to_idx',
        'image_size',
        'normalization',
        'architecture',
        'val_acc',
        'training_epochs',
        'train_config'
    ]
    
    missing_keys = [key for key in required_keys if key not in checkpoint]
    extra_keys = [key for key in checkpoint.keys() if key not in required_keys + ['optimizer_state_dict', 'scheduler_state_dict', 'epoch', 'loss', 'preprocessing_notes']]
    
    verification_result = {
        'status': 'PASS' if not missing_keys else 'FAIL',
        'missing_keys': missing_keys,
        'extra_keys': extra_keys,
        'total_keys': len(checkpoint.keys()),
        'required_keys_found': len(required_keys) - len(missing_keys)
    }
    
    # Verify specific key contents
    details = {}
    
    # Verify class_to_idx
    if 'class_to_idx' in checkpoint:
        class_to_idx = checkpoint['class_to_idx']
        details['class_to_idx'] = {
            'num_classes': len(class_to_idx),
            'sample_classes': list(class_to_idx.keys())[:5],
            'valid_mapping': all(isinstance(k, str) and isinstance(v, int) for k, v in class_to_idx.items())
        }
    
    # Verify normalization
    if 'normalization' in checkpoint:
        norm = checkpoint['normalization']
        details['normalization'] = {
            'has_mean': 'mean' in norm,
            'has_std': 'std' in norm,
            'mean_length': len(norm.get('mean', [])),
            'std_length': len(norm.get('std', [])),
            'valid_format': isinstance(norm, dict) and 'mean' in norm and 'std' in norm
        }
    
    # Verify train_config
    if 'train_config' in checkpoint:
        config = checkpoint['train_config']
        details['train_config'] = {
            'has_lr': 'lr' in config,
            'has_optimizer': 'optimizer' in config,
            'has_batch_size': 'batch_size' in config,
            'config_keys': list(config.keys())
        }
    
    return verification_result, details

def verify_torchscript_model(model_path: str, checkpoint_info: Dict) -> Dict:
    """Verify TorchScript model can be loaded and run."""
    print(f"Verifying TorchScript model: {model_path}")
    
    if not os.path.exists(model_path):
        return {'status': 'FAIL', 'error': f'TorchScript file not found: {model_path}'}
    
    try:
        # Load model
        model = torch.jit.load(model_path, map_location='cpu')
        model.eval()
        
        # Create dummy input
        image_size = checkpoint_info.get('image_size', 224)
        dummy_input = torch.randn(1, 3, image_size, image_size)
        
        # Test forward pass
        with torch.no_grad():
            output = model(dummy_input)
        
        # Verify output shape
        expected_classes = len(checkpoint_info.get('class_to_idx', {}))
        actual_classes = output.shape[1]
        
        verification_result = {
            'status': 'PASS' if actual_classes == expected_classes else 'FAIL',
            'output_shape': list(output.shape),
            'expected_classes': expected_classes,
            'actual_classes': actual_classes,
            'forward_pass_success': True,
            'model_size_mb': os.path.getsize(model_path) / (1024 * 1024)
        }
        
        if actual_classes != expected_classes:
            verification_result['error'] = f'Output classes mismatch: expected {expected_classes}, got {actual_classes}'
        
        return verification_result
        
    except Exception as e:
        return {'status': 'FAIL', 'error': f'TorchScript verification failed: {str(e)}'}

def verify_labels_file(labels_path: str, checkpoint_info: Dict) -> Dict:
    """Verify labels.txt matches checkpoint class_to_idx."""
    print(f"Verifying labels file: {labels_path}")
    
    if not os.path.exists(labels_path):
        return {'status': 'FAIL', 'error': f'Labels file not found: {labels_path}'}
    
    try:
        # Read labels
        with open(labels_path, 'r') as f:
            labels = [line.strip() for line in f if line.strip()]
        
        # Check against checkpoint
        class_to_idx = checkpoint_info.get('class_to_idx', {})
        idx_to_class = {v: k for k, v in class_to_idx.items()}
        
        # Verify ordering
        expected_labels = [idx_to_class[i] for i in range(len(idx_to_class))]
        
        matches = labels == expected_labels
        missing_labels = set(expected_labels) - set(labels)
        extra_labels = set(labels) - set(expected_labels)
        
        verification_result = {
            'status': 'PASS' if matches else 'FAIL',
            'num_labels': len(labels),
            'expected_classes': len(expected_labels),
            'labels_match_checkpoint': matches,
            'missing_labels': list(missing_labels),
            'extra_labels': list(extra_labels),
            'sample_labels': labels[:5]
        }
        
        if not matches:
            verification_result['error'] = f'Labels file does not match checkpoint class mapping'
        
        return verification_result
        
    except Exception as e:
        return {'status': 'FAIL', 'error': f'Labels verification failed: {str(e)}'}

def verify_macro_csv(macro_path: str, checkpoint_info: Dict) -> Dict:
    """Verify macro CSV covers required classes."""
    print(f"Verifying macro CSV: {macro_path}")
    
    if not os.path.exists(macro_path):
        return {'status': 'FAIL', 'error': f'Macro CSV not found: {macro_path}'}
    
    try:
        # Load CSV
        df = pd.read_csv(macro_path)
        
        # Check required columns
        required_columns = ['class', 'protein_g', 'fat_g', 'carb_g', 'serving_size_g']
        missing_columns = [col for col in required_columns if col not in df.columns]
        
        if missing_columns:
            return {
                'status': 'FAIL',
                'error': f'Missing required columns: {missing_columns}',
                'found_columns': list(df.columns)
            }
        
        # Check class coverage
        checkpoint_classes = set(checkpoint_info.get('class_to_idx', {}).keys())
        csv_classes = set(df['class'].tolist())
        
        covered_classes = checkpoint_classes & csv_classes
        missing_classes = checkpoint_classes - csv_classes
        extra_classes = csv_classes - checkpoint_classes
        
        coverage_percentage = (len(covered_classes) / len(checkpoint_classes)) * 100 if checkpoint_classes else 0
        
        # Check data validity
        invalid_protein = df[df['protein_g'] < 0].shape[0]
        invalid_fat = df[df['fat_g'] < 0].shape[0]
        invalid_carb = df[df['carb_g'] < 0].shape[0]
        invalid_serving = df[df['serving_size_g'] <= 0].shape[0]
        
        verification_result = {
            'status': 'PASS' if coverage_percentage >= 95 else 'FAIL',
            'total_rows': len(df),
            'checkpoint_classes': len(checkpoint_classes),
            'csv_classes': len(csv_classes),
            'covered_classes': len(covered_classes),
            'missing_classes': list(missing_classes),
            'extra_classes': list(extra_classes),
            'coverage_percentage': coverage_percentage,
            'data_quality': {
                'invalid_protein_rows': invalid_protein,
                'invalid_fat_rows': invalid_fat,
                'invalid_carb_rows': invalid_carb,
                'invalid_serving_rows': invalid_serving
            },
            'sample_macro_data': df.head(3).to_dict('records') if len(df) > 0 else []
        }
        
        if coverage_percentage < 95:
            verification_result['error'] = f'Coverage {coverage_percentage:.1f}% below 95% threshold'
        
        return verification_result
        
    except Exception as e:
        return {'status': 'FAIL', 'error': f'Macro CSV verification failed: {str(e)}'}

def verify_training_artifacts(training_dir: str) -> Dict:
    """Verify training artifacts exist and are valid."""
    print(f"Verifying training artifacts in: {training_dir}")
    
    training_dir = Path(training_dir)
    
    # Expected files
    expected_files = {
        'training_curve.csv': 'Training metrics CSV',
        'confusion_matrix.png': 'Confusion matrix image',
        'confusion_matrix.npy': 'Confusion matrix numpy array',
        'per_class_counts.csv': 'Per-class image counts'
    }
    
    artifact_results = {}
    
    for filename, description in expected_files.items():
        file_path = training_dir / filename
        
        if not file_path.exists():
            artifact_results[filename] = {
                'status': 'FAIL',
                'error': f'File not found: {filename}',
                'description': description
            }
            continue
        
        try:
            if filename.endswith('.csv'):
                # Verify CSV
                df = pd.read_csv(file_path)
                artifact_results[filename] = {
                    'status': 'PASS',
                    'rows': len(df),
                    'columns': list(df.columns),
                    'description': description
                }
            elif filename.endswith('.npy'):
                # Verify numpy array
                array = np.load(file_path)
                artifact_results[filename] = {
                    'status': 'PASS',
                    'shape': list(array.shape),
                    'dtype': str(array.dtype),
                    'description': description
                }
            elif filename.endswith('.png'):
                # Verify image file
                from PIL import Image
                img = Image.open(file_path)
                artifact_results[filename] = {
                    'status': 'PASS',
                    'size': img.size,
                    'mode': img.mode,
                    'description': description
                }
            else:
                artifact_results[filename] = {
                    'status': 'PASS',
                    'size_bytes': file_path.stat().st_size,
                    'description': description
                }
                
        except Exception as e:
            artifact_results[filename] = {
                'status': 'FAIL',
                'error': f'Failed to verify {filename}: {str(e)}',
                'description': description
            }
    
    # Overall status
    failed_count = sum(1 for result in artifact_results.values() if result['status'] == 'FAIL')
    overall_status = 'PASS' if failed_count == 0 else 'FAIL'
    
    return {
        'status': overall_status,
        'failed_count': failed_count,
        'total_files': len(expected_files),
        'artifacts': artifact_results
    }

def perform_dummy_inference(checkpoint_path: str, checkpoint_info: Dict) -> Dict:
    """Perform dummy inference to verify model works end-to-end."""
    print("Performing dummy inference test...")
    
    try:
        # Load model
        checkpoint = torch.load(checkpoint_path, map_location='cpu')
        
        # Reconstruct model
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
            return {'status': 'FAIL', 'error': f'Unknown architecture: {architecture}'}
        
        model.load_state_dict(checkpoint['model_state_dict'])
        model.eval()
        
        # Create dummy input
        image_size = checkpoint['image_size']
        dummy_input = torch.randn(1, 3, image_size, image_size)
        
        # Run inference
        with torch.no_grad():
            output = model(dummy_input)
            probabilities = torch.nn.functional.softmax(output, dim=1)
            top_prob, top_class = torch.topk(probabilities, 1)
        
        # Verify results
        idx_to_class = {v: k for k, v in checkpoint['class_to_idx'].items()}
        predicted_class = idx_to_class[top_class.item()]
        confidence = top_prob.item()
        
        return {
            'status': 'PASS',
            'predicted_class': predicted_class,
            'confidence': confidence,
            'output_shape': list(output.shape),
            'top_probability': confidence,
            'inference_success': True
        }
        
    except Exception as e:
        return {'status': 'FAIL', 'error': f'Dummy inference failed: {str(e)}'}

def generate_verification_report(results: Dict, output_path: str):
    """Generate comprehensive verification report."""
    
    # Count passes and fails
    total_checks = 0
    passed_checks = 0
    
    for check_name, check_result in results.items():
        if isinstance(check_result, dict) and 'status' in check_result:
            total_checks += 1
            if check_result['status'] == 'PASS':
                passed_checks += 1
    
    success_rate = (passed_checks / total_checks) * 100 if total_checks > 0 else 0
    
    # Create summary
    summary = {
        'verification_timestamp': time.time(),
        'overall_status': 'PASS' if success_rate >= 90 else 'FAIL',
        'success_rate': success_rate,
        'total_checks': total_checks,
        'passed_checks': passed_checks,
        'failed_checks': total_checks - passed_checks,
        'remediation_suggestions': []
    }
    
    # Add remediation suggestions
    if results.get('checkpoint', {}).get('status') == 'FAIL':
        summary['remediation_suggestions'].append('Re-train model with proper checkpoint saving')
    
    if results.get('torchscript_model', {}).get('status') == 'FAIL':
        summary['remediation_suggestions'].append('Re-export model using export_torchscript.py')
    
    if results.get('labels_file', {}).get('status') == 'FAIL':
        summary['remediation_suggestions'].append('Regenerate labels.txt from checkpoint class_to_idx')
    
    if results.get('macro_csv', {}).get('status') == 'FAIL':
        coverage = results['macro_csv'].get('coverage_percentage', 0)
        if coverage < 95:
            summary['remediation_suggestions'].append(f'Add macro data for {results["macro_csv"]["missing_classes"]} classes')
    
    if results.get('dummy_inference', {}).get('status') == 'FAIL':
        summary['remediation_suggestions'].append('Check model architecture and checkpoint integrity')
    
    # Combine with detailed results
    full_report = {
        'summary': summary,
        'detailed_results': results
    }
    
    # Save report
    with open(output_path, 'w') as f:
        json.dump(full_report, f, indent=2)
    
    return summary

def main():
    parser = argparse.ArgumentParser(description='Verify Food-101 model artifacts')
    parser.add_argument('--checkpoint', type=str, required=True,
                        help='Path to model checkpoint (.pth)')
    parser.add_argument('--torchscript_model', type=str, default=None,
                        help='Path to TorchScript model (.pt)')
    parser.add_argument('--labels_file', type=str, default=None,
                        help='Path to labels.txt file')
    parser.add_argument('--macro_csv', type=str, default=None,
                        help='Path to labels_to_macro.csv file')
    parser.add_argument('--training_dir', type=str, default=None,
                        help='Path to training output directory')
    parser.add_argument('--output', type=str, default='verify_report.json',
                        help='Output verification report')
    
    args = parser.parse_args()
    
    print("Starting comprehensive verification of Food-101 artifacts...")
    print("="*60)
    
    results = {}
    
    # Verify checkpoint
    checkpoint_result, checkpoint_details = load_and_verify_checkpoint(args.checkpoint)
    results['checkpoint'] = checkpoint_result
    results['checkpoint_details'] = checkpoint_details
    
    if checkpoint_result['status'] == 'FAIL':
        print("❌ Checkpoint verification failed - cannot continue with other checks")
        summary = generate_verification_report(results, args.output)
        print(f"\nVerification completed with errors. Report saved to {args.output}")
        return
    
    checkpoint_info = checkpoint_details
    
    # Verify TorchScript model (if provided)
    if args.torchscript_model:
        results['torchscript_model'] = verify_torchscript_model(args.torchscript_model, checkpoint_info)
    
    # Verify labels file (if provided)
    if args.labels_file:
        results['labels_file'] = verify_labels_file(args.labels_file, checkpoint_info)
    
    # Verify macro CSV (if provided)
    if args.macro_csv:
        results['macro_csv'] = verify_macro_csv(args.macro_csv, checkpoint_info)
    
    # Verify training artifacts (if provided)
    if args.training_dir:
        results['training_artifacts'] = verify_training_artifacts(args.training_dir)
    
    # Perform dummy inference
    results['dummy_inference'] = perform_dummy_inference(args.checkpoint, checkpoint_info)
    
    # Generate report
    summary = generate_verification_report(results, args.output)
    
    # Print summary
    print("\n" + "="*60)
    print("VERIFICATION SUMMARY")
    print("="*60)
    print(f"Overall Status: {summary['overall_status']}")
    print(f"Success Rate: {summary['success_rate']:.1f}% ({summary['passed_checks']}/{summary['total_checks']})")
    
    if summary['remediation_suggestions']:
        print("\nRemediation Suggestions:")
        for i, suggestion in enumerate(summary['remediation_suggestions'], 1):
            print(f"  {i}. {suggestion}")
    
    # Print individual check results
    print("\nIndividual Check Results:")
    for check_name, check_result in results.items():
        if isinstance(check_result, dict) and 'status' in check_result:
            status_icon = "✅" if check_result['status'] == 'PASS' else "❌"
            print(f"  {status_icon} {check_name}: {check_result['status']}")
            if 'error' in check_result:
                print(f"    Error: {check_result['error']}")
    
    print(f"\nDetailed report saved to: {args.output}")

if __name__ == '__main__':
    main()
