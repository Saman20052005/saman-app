import torch
import torch.nn as nn
import torchvision.transforms as transforms
from torchvision import models
from PIL import Image
import cv2
import numpy as np
from typing import List, Tuple, Dict, Optional, Union
import logging
from pathlib import Path
import json

logger = logging.getLogger(__name__)

class PortionEstimationService:
    """
    Multi-approach portion size estimation engine:
    1. Reference object detection (plate, hand, utensil)
    2. Depth estimation using monocular vision
    3. Regression head for portion categories
    """
    
    def __init__(self, model_path: Optional[str] = None):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.depth_model = None
        self.reference_detector = None
        self.portion_regressor = None
        self.is_loaded = False
        
        # Known reference object sizes (in cm)
        self.reference_sizes = {
            'plate_25cm': 25.0,
            'plate_20cm': 20.0,
            'plate_15cm': 15.0,
            'hand': 8.0,  # average palm width
            'fork': 2.0,
            'spoon': 2.5,
            'knife': 2.0
        }
        
        # Portion size categories
        self.portion_categories = {
            'tiny': 0.5,
            'small': 0.75,
            'medium': 1.0,
            'large': 1.5,
            'extra_large': 2.0
        }
        
        if model_path:
            self.load_models(model_path)
    
    def load_models(self, model_path: str) -> bool:
        """Load all models for portion estimation"""
        try:
            # Load MiDaS for depth estimation
            self._load_depth_model()
            
            # Load reference object detector (simplified YOLO or custom model)
            self._load_reference_detector()
            
            # Load portion size regressor
            self._load_portion_regressor(model_path)
            
            self.is_loaded = True
            logger.info("Portion estimation models loaded successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to load portion models: {e}")
            self.is_loaded = False
            return False
    
    def _load_depth_model(self):
        """Load MiDaS model for monocular depth estimation"""
        try:
            # Using torch hub for MiDaS
            self.depth_model = torch.hub.load('intel-isl/MiDaS', 'MiDaS_small')
            self.depth_model.to(self.device)
            self.depth_model.eval()
            
            # MiDaS transforms
            self.depth_transform = transforms.Compose([
                transforms.Resize((384, 384)),
                transforms.ToTensor(),
                transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
            ])
            
            logger.info("MiDaS depth model loaded")
            
        except Exception as e:
            logger.warning(f"Failed to load MiDaS model: {e}")
            self.depth_model = None
    
    def _load_reference_detector(self):
        """Load reference object detection model"""
        # Simplified implementation - in production, use trained YOLO or Faster R-CNN
        self.reference_detector = ReferenceObjectDetector()
        logger.info("Reference object detector initialized")
    
    def _load_portion_regressor(self, model_path: str):
        """Load portion size regression model"""
        try:
            # Simple CNN regressor for portion size estimation
            self.portion_regressor = PortionRegressor()
            
            if Path(model_path).exists():
                checkpoint = torch.load(model_path, map_location=self.device)
                self.portion_regressor.load_state_dict(checkpoint['portion_regressor'])
                logger.info("Portion regressor weights loaded")
            
            self.portion_regressor.to(self.device)
            self.portion_regressor.eval()
            
        except Exception as e:
            logger.warning(f"Failed to load portion regressor: {e}")
            self.portion_regressor = None
    
    def estimate_portion(self, image: Image.Image, food_bbox: Optional[Tuple] = None) -> Dict:
        """
        Estimate portion size using ensemble of methods
        
        Args:
            image: PIL Image input
            food_bbox: Bounding box of food item (x1, y1, x2, y2)
            
        Returns:
            Dictionary with portion estimates and confidence
        """
        if not self.is_loaded:
            raise RuntimeError("Portion estimation models not loaded")
        
        try:
            # Convert PIL to CV2 format
            cv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
            
            # Method 1: Reference object detection
            ref_estimate = self._estimate_by_reference(cv_image, food_bbox)
            
            # Method 2: Depth estimation
            depth_estimate = self._estimate_by_depth(image, food_bbox)
            
            # Method 3: Portion regression
            regression_estimate = self._estimate_by_regression(image, food_bbox)
            
            # Ensemble combination
            final_estimate = self._combine_estimates([
                ref_estimate, depth_estimate, regression_estimate
            ])
            
            return final_estimate
            
        except Exception as e:
            logger.error(f"Portion estimation failed: {e}")
            raise
    
    def _estimate_by_reference(self, cv_image: np.ndarray, food_bbox: Optional[Tuple]) -> Dict:
        """Estimate portion using reference objects"""
        try:
            # Detect reference objects
            ref_objects = self.reference_detector.detect(cv_image)
            
            if not ref_objects:
                return {'weight_grams': 0, 'confidence': 0.0, 'method': 'reference'}
            
            # Find best reference object
            best_ref = self._select_best_reference(ref_objects, food_bbox)
            
            if not best_ref:
                return {'weight_grams': 0, 'confidence': 0.0, 'method': 'reference'}
            
            # Calculate scale and estimate weight
            scale_factor = self._calculate_scale_factor(best_ref, cv_image.shape)
            estimated_weight = self._estimate_weight_from_scale(scale_factor, food_bbox)
            
            return {
                'weight_grams': estimated_weight,
                'confidence': 0.8,  # High confidence with good reference
                'method': 'reference',
                'reference_object': best_ref['class']
            }
            
        except Exception as e:
            logger.error(f"Reference estimation failed: {e}")
            return {'weight_grams': 0, 'confidence': 0.0, 'method': 'reference'}
    
    def _estimate_by_depth(self, image: Image.Image, food_bbox: Optional[Tuple]) -> Dict:
        """Estimate portion using depth estimation"""
        if not self.depth_model:
            return {'weight_grams': 0, 'confidence': 0.0, 'method': 'depth'}
        
        try:
            # Preprocess for depth model
            input_tensor = self.depth_transform(image).unsqueeze(0).to(self.device)
            
            with torch.no_grad():
                depth_map = self.depth_model(input_tensor)
                depth_map = torch.nn.functional.interpolate(
                    depth_map.unsqueeze(1),
                    size=image.size[::-1],
                    mode="bicubic",
                    align_corners=False,
                ).squeeze()
            
            # Convert depth map to numpy
            depth_np = depth_map.cpu().numpy()
            
            # Extract depth for food region
            if food_bbox:
                x1, y1, x2, y2 = food_bbox
                food_depth = np.mean(depth_np[y1:y2, x1:x2])
            else:
                food_depth = np.mean(depth_np)
            
            # Estimate weight based on depth and size
            estimated_weight = self._depth_to_weight(food_depth, food_bbox, image.size)
            
            return {
                'weight_grams': estimated_weight,
                'confidence': 0.6,  # Medium confidence for depth
                'method': 'depth',
                'avg_depth': float(food_depth)
            }
            
        except Exception as e:
            logger.error(f"Depth estimation failed: {e}")
            return {'weight_grams': 0, 'confidence': 0.0, 'method': 'depth'}
    
    def _estimate_by_regression(self, image: Image.Image, food_bbox: Optional[Tuple]) -> Dict:
        """Estimate portion using trained regression model"""
        if not self.portion_regressor:
            return {'weight_grams': 0, 'confidence': 0.0, 'method': 'regression'}
        
        try:
            # Preprocess image
            transform = transforms.Compose([
                transforms.Resize((224, 224)),
                transforms.ToTensor(),
                transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
            ])
            
            input_tensor = transform(image).unsqueeze(0).to(self.device)
            
            with torch.no_grad():
                portion_output = self.portion_regressor(input_tensor)
            
            # Convert to weight estimate
            estimated_weight = portion_output.item() * 100  # Scale to grams
            
            return {
                'weight_grams': estimated_weight,
                'confidence': 0.7,  # Good confidence for regression
                'method': 'regression'
            }
            
        except Exception as e:
            logger.error(f"Regression estimation failed: {e}")
            return {'weight_grams': 0, 'confidence': 0.0, 'method': 'regression'}
    
    def _combine_estimates(self, estimates: List[Dict]) -> Dict:
        """Combine estimates from different methods using weighted average"""
        valid_estimates = [e for e in estimates if e['confidence'] > 0]
        
        if not valid_estimates:
            return {
                'weight_grams': 0,
                'confidence': 0.0,
                'size_category': 'unknown',
                'methods_used': []
            }
        
        # Weighted average based on confidence
        total_confidence = sum(e['confidence'] for e in valid_estimates)
        weighted_weight = sum(e['weight_grams'] * e['confidence'] for e in valid_estimates)
        
        final_weight = weighted_weight / total_confidence if total_confidence > 0 else 0
        final_confidence = min(total_confidence / len(valid_estimates), 1.0)
        
        # Determine size category
        size_category = self._weight_to_category(final_weight)
        
        return {
            'weight_grams': round(final_weight, 1),
            'confidence': round(final_confidence, 3),
            'size_category': size_category,
            'methods_used': [e['method'] for e in valid_estimates],
            'individual_estimates': estimates
        }
    
    def _weight_to_category(self, weight_grams: float) -> str:
        """Convert weight to portion category"""
        if weight_grams < 50:
            return 'tiny'
        elif weight_grams < 100:
            return 'small'
        elif weight_grams < 200:
            return 'medium'
        elif weight_grams < 350:
            return 'large'
        else:
            return 'extra_large'
    
    def _select_best_reference(self, ref_objects: List[Dict], food_bbox: Optional[Tuple]) -> Optional[Dict]:
        """Select the best reference object for scale estimation"""
        if not ref_objects:
            return None
        
        # Prioritize plates, then hands, then utensils
        priority = {'plate': 3, 'hand': 2, 'fork': 1, 'spoon': 1, 'knife': 1}
        
        # Sort by priority and confidence
        sorted_refs = sorted(
            ref_objects,
            key=lambda x: (priority.get(x['class'].split('_')[0], 0), x['confidence']),
            reverse=True
        )
        
        return sorted_refs[0] if sorted_refs else None
    
    def _calculate_scale_factor(self, ref_object: Dict, image_shape: Tuple) -> float:
        """Calculate pixels per cm from reference object"""
        ref_class = ref_object['class']
        known_size = self.reference_sizes.get(ref_class, 10.0)  # Default 10cm
        
        # Get detected size in pixels
        bbox = ref_object['bbox']
        pixel_size = max(bbox[2] - bbox[0], bbox[3] - bbox[1])  # Max dimension
        
        # Calculate scale factor
        scale_factor = known_size / pixel_size
        return scale_factor
    
    def _estimate_weight_from_scale(self, scale_factor: float, food_bbox: Optional[Tuple]) -> float:
        """Estimate weight from scale factor and food bounding box"""
        if not food_bbox:
            # Default estimation based on average food density
            return 150.0  # grams
        
        x1, y1, x2, y2 = food_bbox
        pixel_area = (x2 - x1) * (y2 - y1)
        
        # Convert to real-world area
        real_area_cm2 = pixel_area * (scale_factor ** 2)
        
        # Estimate weight assuming average food density (0.5 g/cm³)
        estimated_weight = real_area_cm2 * 0.5
        
        return max(estimated_weight, 10.0)  # Minimum 10g
    
    def _depth_to_weight(self, depth_value: float, food_bbox: Optional[Tuple], image_size: Tuple) -> float:
        """Convert depth value to weight estimate"""
        # Simplified depth-to-weight conversion
        # In production, this would use more sophisticated modeling
        
        # Normalize depth (inverse relationship)
        normalized_depth = 1.0 / (depth_value + 1e-6)
        
        # Base weight estimation
        base_weight = normalized_depth * 200  # Scale factor
        
        if food_bbox:
            x1, y1, x2, y2 = food_bbox
            area_factor = ((x2 - x1) * (y2 - y1)) / (image_size[0] * image_size[1])
            base_weight *= area_factor * 10  # Scale by relative size
        
        return max(base_weight, 10.0)  # Minimum 10g
    
    def is_model_loaded(self) -> bool:
        """Check if models are loaded and ready"""
        return self.is_loaded


class ReferenceObjectDetector:
    """Simplified reference object detector"""
    
    def __init__(self):
        # In production, load trained object detection model
        pass
    
    def detect(self, image: np.ndarray) -> List[Dict]:
        """Detect reference objects in image"""
        # Simplified implementation - returns mock detections
        # In production, use YOLO, Faster R-CNN, or similar
        
        detections = []
        
        # Mock detection for demo
        # In real implementation, this would use actual object detection
        h, w = image.shape[:2]
        
        # Simulate plate detection (center of image)
        if w > 200 and h > 200:
            detections.append({
                'class': 'plate_25cm',
                'confidence': 0.85,
                'bbox': [w//4, h//4, 3*w//4, 3*h//4]
            })
        
        return detections


class PortionRegressor(nn.Module):
    """CNN for portion size regression"""
    
    def __init__(self):
        super(PortionRegressor, self).__init__()
        
        # Simple CNN architecture
        self.features = nn.Sequential(
            nn.Conv2d(3, 32, 3, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2),
            nn.Conv2d(32, 64, 3, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2),
            nn.Conv2d(64, 128, 3, padding=1),
            nn.ReLU(),
            nn.AdaptiveAvgPool2d((1, 1))
        )
        
        self.regressor = nn.Sequential(
            nn.Dropout(0.5),
            nn.Linear(128, 64),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(64, 1),
            nn.Sigmoid()  # Output normalized portion size
        )
    
    def forward(self, x):
        x = self.features(x)
        x = x.view(x.size(0), -1)
        x = self.regressor(x)
        return x
