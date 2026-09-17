#!/usr/bin/env python3
"""
Create placeholder model for deployment
This creates a small EfficientNet-B0 model with random weights for testing
"""
import os
import sys

def create_placeholder():
    """Create placeholder model file"""
    try:
        import torch
        from torchvision import models
        
        print("Creating placeholder model...")
        
        # Create EfficientNet-B0 model
        model = models.efficientnet_b0(weights=None)
        
        # Modify classifier for 101 food classes
        in_features = model.classifier[1].in_features
        model.classifier[1] = torch.nn.Linear(in_features, 101)
        
        # Create models directory if it doesn't exist
        os.makedirs("models", exist_ok=True)
        
        # Save model state dict
        model_path = "models/placeholder_model.pt"
        torch.save(model.state_dict(), model_path)
        
        print(f"✅ Placeholder model saved to {model_path}")
        print(f"Model size: {os.path.getsize(model_path) / 1024 / 1024:.1f} MB")
        
        return True
        
    except ImportError as e:
        print(f"❌ PyTorch not available: {e}")
        return False
    except Exception as e:
        print(f"❌ Error creating placeholder: {e}")
        return False

if __name__ == "__main__":
    success = create_placeholder()
    sys.exit(0 if success else 1)
