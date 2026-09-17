#!/usr/bin/env python3
"""
Food-101 Dataset Validation and Split Script
Validates dataset structure, detects issues, and creates reproducible train/val/test splits.
"""

import os
import json
import csv
import hashlib
import argparse
from pathlib import Path
from collections import Counter, defaultdict
from PIL import Image
import numpy as np
from tqdm import tqdm
import random

def compute_image_hash(image_path):
    """Compute MD5 hash of image file."""
    hash_md5 = hashlib.md5()
    with open(image_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()

def validate_image(image_path):
    """Check if image is valid and readable."""
    try:
        with Image.open(image_path) as img:
            img.verify()
        return True, None
    except Exception as e:
        return False, str(e)

def scan_dataset(dataset_path):
    """Scan dataset and return statistics."""
    dataset_path = Path(dataset_path)
    if not dataset_path.exists():
        raise FileNotFoundError(f"Dataset path not found: {dataset_path}")
    
    print(f"Scanning dataset: {dataset_path}")
    
    # Find all image files
    image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.webp'}
    all_images = []
    
    for ext in image_extensions:
        all_images.extend(dataset_path.rglob(f"*{ext}"))
        all_images.extend(dataset_path.rglob(f"*{ext.upper()}"))
    
    print(f"Found {len(all_images)} image files")
    
    # Extract class names from directory structure
    class_to_images = defaultdict(list)
    corrupt_images = []
    zero_byte_files = []
    image_hashes = {}
    duplicates = []
    
    print("Validating images and computing hashes...")
    for img_path in tqdm(all_images):
        # Check for zero-byte files
        if img_path.stat().st_size == 0:
            zero_byte_files.append(str(img_path))
            continue
        
        # Validate image
        is_valid, error = validate_image(img_path)
        if not is_valid:
            corrupt_images.append({'path': str(img_path), 'error': error})
            continue
        
        # Extract class name (assuming structure: dataset_path/class_name/image.jpg)
        relative_path = img_path.relative_to(dataset_path)
        if len(relative_path.parts) >= 2:
            class_name = relative_path.parts[0]
            class_to_images[class_name].append(img_path)
        
        # Compute hash for duplicate detection
        img_hash = compute_image_hash(img_path)
        if img_hash in image_hashes:
            duplicates.append({
                'original': image_hashes[img_hash],
                'duplicate': str(img_path),
                'hash': img_hash
            })
        else:
            image_hashes[img_hash] = str(img_path)
    
    return {
        'class_to_images': dict(class_to_images),
        'corrupt_images': corrupt_images,
        'zero_byte_files': zero_byte_files,
        'duplicates': duplicates,
        'total_images': len(all_images)
    }

def create_splits(class_to_images, output_dir, train_ratio=0.8, val_ratio=0.1, test_ratio=0.1, seed=42):
    """Create reproducible train/val/test splits."""
    random.seed(seed)
    np.random.seed(seed)
    
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True)
    
    train_files = []
    val_files = []
    test_files = []
    
    print("Creating splits...")
    for class_name, images in tqdm(class_to_images.items()):
        random.shuffle(images)
        n_images = len(images)
        
        n_train = int(n_images * train_ratio)
        n_val = int(n_images * val_ratio)
        n_test = n_images - n_train - n_val
        
        train_files.extend(images[:n_train])
        val_files.extend(images[n_train:n_train + n_val])
        test_files.extend(images[n_train + n_val:])
    
    # Save split files
    def save_split(files, filename):
        with open(output_dir / filename, 'w') as f:
            for img_path in files:
                f.write(f"{img_path}\n")
    
    save_split(train_files, 'train.txt')
    save_split(val_files, 'val.txt')
    save_split(test_files, 'test.txt')
    
    return len(train_files), len(val_files), len(test_files)

def save_per_class_counts(class_to_images, output_path):
    """Save per-class image counts to CSV."""
    output_path = Path(output_path)
    
    with open(output_path, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['class_name', 'count'])
        for class_name, images in sorted(class_to_images.items()):
            writer.writerow([class_name, len(images)])

def save_summary_report(stats, output_path):
    """Save dataset summary as JSON."""
    class_counts = [len(images) for images in stats['class_to_images'].values()]
    
    summary = {
        'total_images': stats['total_images'],
        'classes': len(stats['class_to_images']),
        'avg_per_class': np.mean(class_counts) if class_counts else 0,
        'min_per_class': min(class_counts) if class_counts else 0,
        'max_per_class': max(class_counts) if class_counts else 0,
        'corrupt_images': len(stats['corrupt_images']),
        'zero_byte_files': len(stats['zero_byte_files']),
        'duplicates': len(stats['duplicates'])
    }
    
    with open(output_path, 'w') as f:
        json.dump(summary, f, indent=2)

def save_detailed_reports(stats, output_dir):
    """Save detailed reports for corrupt files and duplicates."""
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True)
    
    # Save corrupt images report
    if stats['corrupt_images']:
        with open(output_dir / 'corrupt_images.csv', 'w', newline='') as csvfile:
            writer = csv.writer(csvfile)
            writer.writerow(['path', 'error'])
            for item in stats['corrupt_images']:
                writer.writerow([item['path'], item['error']])
    
    # Save zero-byte files report
    if stats['zero_byte_files']:
        with open(output_dir / 'zero_byte_files.txt', 'w') as f:
            for path in stats['zero_byte_files']:
                f.write(f"{path}\n")
    
    # Save duplicates report
    if stats['duplicates']:
        with open(output_dir / 'duplicates.csv', 'w', newline='') as csvfile:
            writer = csv.writer(csvfile)
            writer.writerow(['original', 'duplicate', 'hash'])
            for item in stats['duplicates']:
                writer.writerow([item['original'], item['duplicate'], item['hash']])

def main():
    parser = argparse.ArgumentParser(description='Validate and split Food-101 dataset')
    parser.add_argument('--dataset_path', type=str, required=True,
                        help='Path to Food-101 dataset directory')
    parser.add_argument('--output_dir', type=str, default='./dataset_analysis',
                        help='Output directory for analysis results')
    parser.add_argument('--train_ratio', type=float, default=0.8,
                        help='Training set ratio (default: 0.8)')
    parser.add_argument('--val_ratio', type=float, default=0.1,
                        help='Validation set ratio (default: 0.1)')
    parser.add_argument('--test_ratio', type=float, default=0.1,
                        help='Test set ratio (default: 0.1)')
    parser.add_argument('--seed', type=int, default=42,
                        help='Random seed for reproducibility (default: 42)')
    
    args = parser.parse_args()
    
    # Validate ratios
    if abs(args.train_ratio + args.val_ratio + args.test_ratio - 1.0) > 1e-6:
        raise ValueError("Train, val, and test ratios must sum to 1.0")
    
    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(exist_ok=True)
    
    # Scan dataset
    stats = scan_dataset(args.dataset_path)
    
    # Save per-class counts
    save_per_class_counts(stats['class_to_images'], output_dir / 'per_class_counts.csv')
    
    # Save summary report
    save_summary_report(stats, output_dir / 'dataset_summary.json')
    
    # Save detailed reports
    save_detailed_reports(stats, output_dir)
    
    # Create train/val/test splits
    train_count, val_count, test_count = create_splits(
        stats['class_to_images'], 
        output_dir,
        args.train_ratio,
        args.val_ratio,
        args.test_ratio,
        args.seed
    )
    
    # Print summary
    print("\n" + "="*50)
    print("DATASET VALIDATION COMPLETE")
    print("="*50)
    print(f"Total images found: {stats['total_images']}")
    print(f"Valid classes: {len(stats['class_to_images'])}")
    print(f"Corrupt images: {len(stats['corrupt_images'])}")
    print(f"Zero-byte files: {len(stats['zero_byte_files'])}")
    print(f"Duplicate images: {len(stats['duplicates'])}")
    print(f"Train/Val/Test split: {train_count}/{val_count}/{test_count}")
    print(f"\nResults saved to: {output_dir}")
    print("- per_class_counts.csv: Image count per class")
    print("- dataset_summary.json: Overall statistics")
    print("- train.txt, val.txt, test.txt: Data splits")
    print("- corrupt_images.csv: List of corrupt images (if any)")
    print("- zero_byte_files.txt: List of zero-byte files (if any)")
    print("- duplicates.csv: List of duplicate images (if any)")

if __name__ == '__main__':
    main()
