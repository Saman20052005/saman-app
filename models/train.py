#!/usr/bin/env python3
"""
Food-101 Training Script with EfficientNet-B0 and MobileNetV2
Production-ready training with transfer learning, AMP, and comprehensive logging.
"""

import os
import json
import csv
import argparse
import time
from pathlib import Path
from datetime import datetime

import torch
import torch.nn as nn
import torch.optim as optim
from torch.cuda.amp import GradScaler, autocast
from torch.utils.tensorboard import SummaryWriter
import torchvision
import torchvision.transforms as transforms
from torchvision import datasets, models
from torch.utils.data import DataLoader, random_split

import numpy as np
import pandas as pd
from PIL import Image
from tqdm import tqdm
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import confusion_matrix, classification_report
import random

def set_seed(seed=42):
    """Set random seeds for reproducibility."""
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False

def get_model(model_name, num_classes, pretrained=True):
    """Get model architecture."""
    if model_name == 'efficientnet_b0':
        model = models.efficientnet_b0(pretrained=pretrained)
        model.classifier[1] = nn.Linear(model.classifier[1].in_features, num_classes)
    elif model_name == 'mobilenet_v2':
        model = models.mobilenet_v2(pretrained=pretrained)
        model.classifier[1] = nn.Linear(model.classifier[1].in_features, num_classes)
    else:
        raise ValueError(f"Unsupported model: {model_name}")
    
    return model

def get_transforms(image_size=224, is_training=True):
    """Get data transforms."""
    normalize = transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    
    if is_training:
        return transforms.Compose([
            transforms.RandomResizedCrop(image_size),
            transforms.RandomHorizontalFlip(p=0.5),
            transforms.RandomRotation(degrees=15),
            transforms.ColorJitter(brightness=0.2, contrast=0.2, saturation=0.2, hue=0.1),
            transforms.ToTensor(),
            normalize,
        ])
    else:
        return transforms.Compose([
            transforms.Resize(int(image_size * 1.14)),
            transforms.CenterCrop(image_size),
            transforms.ToTensor(),
            normalize,
        ])

def load_split_files(split_dir):
    """Load train/val/test split files."""
    split_dir = Path(split_dir)
    
    def read_split(filename):
        with open(split_dir / filename, 'r') as f:
            return [line.strip() for line in f if line.strip()]
    
    return {
        'train': read_split('train.txt'),
        'val': read_split('val.txt'),
        'test': read_split('test.txt')
    }

class Food101Dataset(torch.utils.data.Dataset):
    """Custom dataset for Food-101 with file paths."""
    
    def __init__(self, file_paths, transform=None, class_to_idx=None):
        self.file_paths = file_paths
        self.transform = transform
        self.class_to_idx = class_to_idx or self._create_class_mapping()
        
    def _create_class_mapping(self):
        """Create class to index mapping from file paths."""
        classes = set()
        for path in self.file_paths:
            class_name = Path(path).parent.name
            classes.add(class_name)
        return {cls: idx for idx, cls in enumerate(sorted(classes))}
    
    def __len__(self):
        return len(self.file_paths)
    
    def __getitem__(self, idx):
        img_path = self.file_paths[idx]
        
        # Load image
        image = Image.open(img_path).convert('RGB')
        
        # Get class label
        class_name = Path(img_path).parent.name
        label = self.class_to_idx[class_name]
        
        # Apply transforms
        if self.transform:
            image = self.transform(image)
        
        return image, label

def calculate_metrics(model, dataloader, device, num_classes):
    """Calculate comprehensive metrics."""
    model.eval()
    all_preds = []
    all_labels = []
    correct_top1 = 0
    correct_top3 = 0
    total = 0
    
    with torch.no_grad():
        for images, labels in tqdm(dataloader, desc='Calculating metrics'):
            images, labels = images.to(device), labels.to(device)
            
            outputs = model(images)
            _, predicted = torch.max(outputs, 1)
            _, top3_pred = torch.topk(outputs, 3, dim=1)
            
            total += labels.size(0)
            correct_top1 += (predicted == labels).sum().item()
            correct_top3 += torch.sum(torch.any(top3_pred == labels.view(-1, 1), dim=1)).item()
            
            all_preds.extend(predicted.cpu().numpy())
            all_labels.extend(labels.cpu().numpy())
    
    top1_acc = 100 * correct_top1 / total
    top3_acc = 100 * correct_top3 / total
    
    # Confusion matrix
    cm = confusion_matrix(all_labels, all_preds)
    
    # Per-class metrics
    report = classification_report(all_labels, all_preds, 
                                  target_names=[f'class_{i}' for i in range(num_classes)],
                                  output_dict=True)
    
    return top1_acc, top3_acc, cm, report

def plot_confusion_matrix(cm, class_names, save_path):
    """Plot and save confusion matrix."""
    plt.figure(figsize=(20, 16))
    sns.heatmap(cm, annot=False, cmap='Blues', xticklabels=class_names, yticklabels=class_names)
    plt.title('Confusion Matrix')
    plt.xlabel('Predicted')
    plt.ylabel('Actual')
    plt.tight_layout()
    plt.savefig(save_path, dpi=150, bbox_inches='tight')
    plt.close()

def save_checkpoint(model, optimizer, scheduler, epoch, loss, acc, config, save_path, is_best=False):
    """Save model checkpoint with all required metadata."""
    checkpoint = {
        'epoch': epoch,
        'model_state_dict': model.state_dict(),
        'optimizer_state_dict': optimizer.state_dict(),
        'scheduler_state_dict': scheduler.state_dict() if scheduler else None,
        'loss': loss,
        'val_acc': acc,
        'class_to_idx': config['class_to_idx'],
        'image_size': config['image_size'],
        'normalization': config['normalization'],
        'architecture': config['architecture'],
        'training_epochs': epoch + 1,
        'train_config': config['train_config'],
        'preprocessing_notes': 'ImageNet normalization, random crops and flips for training'
    }
    
    torch.save(checkpoint, save_path)
    
    if is_best:
        best_path = save_path.parent / 'best_model.pth'
        torch.save(checkpoint, best_path)

def train_epoch(model, dataloader, criterion, optimizer, scaler, device, scheduler=None):
    """Train for one epoch."""
    model.train()
    running_loss = 0.0
    correct = 0
    total = 0
    
    pbar = tqdm(dataloader, desc='Training')
    for images, labels in pbar:
        images, labels = images.to(device), labels.to(device)
        
        optimizer.zero_grad()
        
        with autocast():
            outputs = model(images)
            loss = criterion(outputs, labels)
        
        scaler.scale(loss).backward()
        scaler.step(optimizer)
        scaler.update()
        
        running_loss += loss.item()
        _, predicted = torch.max(outputs, 1)
        total += labels.size(0)
        correct += (predicted == labels).sum().item()
        
        # Update progress bar
        current_acc = 100 * correct / total
        pbar.set_postfix({'loss': running_loss/total, 'acc': f'{current_acc:.2f}%'})
    
    if scheduler:
        scheduler.step()
    
    epoch_loss = running_loss / len(dataloader)
    epoch_acc = 100 * correct / total
    
    return epoch_loss, epoch_acc

def validate_epoch(model, dataloader, criterion, device):
    """Validate for one epoch."""
    model.eval()
    running_loss = 0.0
    correct = 0
    total = 0
    
    with torch.no_grad():
        for images, labels in tqdm(dataloader, desc='Validation'):
            images, labels = images.to(device), labels.to(device)
            
            outputs = model(images)
            loss = criterion(outputs, labels)
            
            running_loss += loss.item()
            _, predicted = torch.max(outputs, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()
    
    epoch_loss = running_loss / len(dataloader)
    epoch_acc = 100 * correct / total
    
    return epoch_loss, epoch_acc

def main():
    parser = argparse.ArgumentParser(description='Train Food-101 model')
    parser.add_argument('--data_path', type=str, required=True,
                        help='Path to Food-101 dataset root')
    parser.add_argument('--split_dir', type=str, required=True,
                        help='Path to split files directory')
    parser.add_argument('--output_dir', type=str, default='./training_output',
                        help='Output directory for checkpoints and logs')
    parser.add_argument('--model', type=str, default='efficientnet_b0',
                        choices=['efficientnet_b0', 'mobilenet_v2'],
                        help='Model architecture')
    parser.add_argument('--image_size', type=int, default=224,
                        help='Input image size')
    parser.add_argument('--batch_size', type=int, default=32,
                        help='Batch size')
    parser.add_argument('--epochs', type=int, default=30,
                        help='Number of training epochs')
    parser.add_argument('--lr', type=float, default=1e-3,
                        help='Learning rate')
    parser.add_argument('--weight_decay', type=float, default=1e-4,
                        help='Weight decay')
    parser.add_argument('--freeze_epochs', type=int, default=3,
                        help='Number of epochs to freeze backbone')
    parser.add_argument('--num_workers', type=int, default=4,
                        help='Number of data loader workers')
    parser.add_argument('--seed', type=int, default=42,
                        help='Random seed')
    parser.add_argument('--resume', type=str, default=None,
                        help='Path to checkpoint to resume from')
    parser.add_argument('--device', type=str, default='auto',
                        help='Device to use (auto/cpu/cuda)')
    
    args = parser.parse_args()
    
    # Set seed
    set_seed(args.seed)
    
    # Setup device
    if args.device == 'auto':
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    else:
        device = torch.device(args.device)
    
    print(f"Using device: {device}")
    
    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(exist_ok=True)
    checkpoints_dir = output_dir / 'checkpoints'
    checkpoints_dir.mkdir(exist_ok=True)
    
    # Load split files
    splits = load_split_files(args.split_dir)
    
    # Create datasets
    train_transform = get_transforms(args.image_size, is_training=True)
    val_transform = get_transforms(args.image_size, is_training=False)
    
    # Create class mapping from training data
    temp_dataset = Food101Dataset(splits['train'], transform=None)
    class_to_idx = temp_dataset.class_to_idx
    idx_to_class = {v: k for k, v in class_to_idx.items()}
    num_classes = len(class_to_idx)
    
    print(f"Found {num_classes} classes")
    
    train_dataset = Food101Dataset(splits['train'], transform=train_transform, class_to_idx=class_to_idx)
    val_dataset = Food101Dataset(splits['val'], transform=val_transform, class_to_idx=class_to_idx)
    test_dataset = Food101Dataset(splits['test'], transform=val_transform, class_to_idx=class_to_idx)
    
    # Create data loaders
    train_loader = DataLoader(train_dataset, batch_size=args.batch_size, shuffle=True,
                             num_workers=args.num_workers, pin_memory=True, persistent_workers=True)
    val_loader = DataLoader(val_dataset, batch_size=args.batch_size, shuffle=False,
                           num_workers=args.num_workers, pin_memory=True)
    test_loader = DataLoader(test_dataset, batch_size=args.batch_size, shuffle=False,
                            num_workers=args.num_workers, pin_memory=True)
    
    print(f"Train/Val/Test samples: {len(train_dataset)}/{len(val_dataset)}/{len(test_dataset)}")
    
    # Create model
    model = get_model(args.model, num_classes, pretrained=True)
    model = model.to(device)
    
    # Loss and optimizer
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    
    # AMP scaler
    scaler = GradScaler()
    
    # Training config
    config = {
        'class_to_idx': class_to_idx,
        'image_size': args.image_size,
        'normalization': {'mean': [0.485, 0.456, 0.406], 'std': [0.229, 0.224, 0.225]},
        'architecture': args.model,
        'train_config': {
            'lr': args.lr,
            'optimizer': 'AdamW',
            'batch_size': args.batch_size,
            'scheduler': 'CosineAnnealingLR',
            'weight_decay': args.weight_decay,
            'freeze_epochs': args.freeze_epochs
        }
    }
    
    # Resume from checkpoint if specified
    start_epoch = 0
    best_acc = 0.0
    if args.resume:
        checkpoint = torch.load(args.resume, map_location=device)
        model.load_state_dict(checkpoint['model_state_dict'])
        optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
        scheduler.load_state_dict(checkpoint['scheduler_state_dict'])
        start_epoch = checkpoint['epoch'] + 1
        best_acc = checkpoint['val_acc']
        print(f"Resumed from epoch {start_epoch}, best acc: {best_acc:.2f}%")
    
    # Training loop
    training_log = []
    writer = SummaryWriter(log_dir=str(output_dir / 'tensorboard'))
    
    # Freeze backbone for initial epochs
    if args.freeze_epochs > 0 and start_epoch < args.freeze_epochs:
        print(f"Freezing backbone for {args.freeze_epochs} epochs")
        for name, param in model.named_parameters():
            if 'classifier' not in name and 'fc' not in name:
                param.requires_grad = False
    
    for epoch in range(start_epoch, args.epochs):
        print(f"\nEpoch {epoch+1}/{args.epochs}")
        
        # Unfreeze after freeze_epochs
        if epoch == args.freeze_epochs:
            print("Unfreezing backbone for fine-tuning")
            for param in model.parameters():
                param.requires_grad = True
        
        # Train
        train_loss, train_acc = train_epoch(model, train_loader, criterion, optimizer, scaler, device, scheduler)
        
        # Validate
        val_loss, val_acc = validate_epoch(model, val_loader, criterion, device)
        
        # Log metrics
        training_log.append({
            'epoch': epoch + 1,
            'train_loss': train_loss,
            'train_acc': train_acc,
            'val_loss': val_loss,
            'val_acc': val_acc,
            'lr': optimizer.param_groups[0]['lr']
        })
        
        writer.add_scalar('Loss/Train', train_loss, epoch)
        writer.add_scalar('Loss/Val', val_loss, epoch)
        writer.add_scalar('Accuracy/Train', train_acc, epoch)
        writer.add_scalar('Accuracy/Val', val_acc, epoch)
        writer.add_scalar('Learning_Rate', optimizer.param_groups[0]['lr'], epoch)
        
        print(f"Train Loss: {train_loss:.4f}, Train Acc: {train_acc:.2f}%")
        print(f"Val Loss: {val_loss:.4f}, Val Acc: {val_acc:.2f}%")
        
        # Save checkpoint
        is_best = val_acc > best_acc
        if is_best:
            best_acc = val_acc
        
        checkpoint_path = checkpoints_dir / f'checkpoint_epoch_{epoch+1}.pth'
        save_checkpoint(model, optimizer, scheduler, epoch, val_loss, val_acc, config, checkpoint_path, is_best)
    
    # Final evaluation on test set
    print("\nFinal evaluation on test set...")
    top1_acc, top3_acc, cm, report = calculate_metrics(model, test_loader, device, num_classes)
    
    print(f"Test Top-1 Accuracy: {top1_acc:.2f}%")
    print(f"Test Top-3 Accuracy: {top3_acc:.2f}%")
    
    # Save final model with full info
    final_checkpoint_path = output_dir / 'food101_model_fullinfo.pth'
    save_checkpoint(model, optimizer, scheduler, args.epochs-1, 0, best_acc, config, final_checkpoint_path)
    
    # Save training log
    training_df = pd.DataFrame(training_log)
    training_df.to_csv(output_dir / 'training_curve.csv', index=False)
    
    # Save confusion matrix
    plot_confusion_matrix(cm, list(idx_to_class.values()), output_dir / 'confusion_matrix.png')
    np.save(output_dir / 'confusion_matrix.npy', cm)
    
    # Save labels file
    with open(output_dir / 'labels.txt', 'w') as f:
        for i in range(num_classes):
            f.write(f"{idx_to_class[i]}\n")
    
    print(f"\nTraining completed! Best validation accuracy: {best_acc:.2f}%")
    print(f"Results saved to: {output_dir}")

if __name__ == '__main__':
    main()
