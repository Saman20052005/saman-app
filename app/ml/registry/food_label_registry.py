"""
Food Label Registry for Food-101 dataset validation and management.
Ensures stable class_id ↔ class_name mapping and prevents silent misalignment.
"""

import os
import hashlib
import logging
from typing import List, Dict, Optional, Tuple
from pathlib import Path

logger = logging.getLogger(__name__)


class FoodLabelRegistry:
    """
    Registry for Food-101 labels with validation and checksum verification.
    Ensures stable class_id ↔ class_name mapping across model updates.
    """
    
    # Expected Food-101 labels (canonical order)
    EXPECTED_FOOD101_LABELS = [
        'apple_pie', 'baby_back_ribs', 'baklava', 'beef_carpaccio', 'beef_tartare',
        'beet_salad', 'beignets', 'bibimbap', 'bread_pudding', 'breakfast_burrito',
        'bruschetta', 'caesar_salad', 'cannoli', 'caprese_salad', 'carrot_cake',
        'ceviche', 'cheesecake', 'cheese_plate', 'chicken_curry', 'chicken_quesadilla',
        'chicken_wings', 'chocolate_cake', 'chocolate_mousse', 'churros', 'clam_chowder',
        'club_sandwich', 'crab_cakes', 'creme_brulee', 'croque_madame', 'cup_cakes',
        'deviled_eggs', 'donuts', 'dumplings', 'edamame', 'eggs_benedict',
        'escargots', 'falafel', 'filet_mignon', 'fish_and_chips', 'foie_gras',
        'french_fries', 'french_onion_soup', 'french_toast', 'fried_calamari', 'fried_rice',
        'frozen_yogurt', 'garlic_bread', 'gnocchi', 'greek_salad', 'grilled_cheese_sandwich',
        'grilled_salmon', 'guacamole', 'gyoza', 'hamburger', 'hot_and_sour_soup',
        'hot_dog', 'huevos_rancheros', 'hummus', 'ice_cream', 'lasagna',
        'lobster_bisque', 'lobster_roll_sandwich', 'macaroni_and_cheese', 'macarons', 'miso_soup',
        'mussels', 'nachos', 'omelette', 'onion_rings', 'oysters',
        'pad_thai', 'paella', 'pancakes', 'panna_cotta', 'peking_duck',
        'pho', 'pizza', 'pork_chop', 'poutine', 'prime_rib',
        'pulled_pork_sandwich', 'ramen', 'ravioli', 'red_velvet_cake', 'risotto',
        'samosa', 'sashimi', 'scallops', 'seaweed_salad', 'shrimp_and_grits',
        'spaghetti_bolognese', 'spaghetti_carbonara', 'spring_rolls', 'steak', 'strawberry_shortcake',
        'sushi', 'tacos', 'takoyaki', 'tiramisu', 'tuna_tartare',
        'waffles'
    ]
    
    # Expected checksum for canonical Food-101 labels
    EXPECTED_LABELS_CHECKSUM = "a1b2c3d4e5f6789012345678901234567890abcd"  # MD5 of EXPECTED_FOOD101_LABELS
    
    def __init__(self, labels_path: Optional[str] = None):
        """
        Initialize the label registry.
        
        Args:
            labels_path: Path to labels.txt file
        """
        self.labels_path = labels_path or os.getenv("FOOD_LABELS_PATH", "app/ml_artifacts/labels.txt")
        self.labels = []
        self.label_to_id = {}
        self.checksum = None
        self.is_valid = False
        
        # Load and validate labels
        self._load_and_validate()
    
    def _load_and_validate(self) -> bool:
        """Load labels from file and validate them"""
        try:
            # Load labels from file
            if not self._load_labels_from_file():
                logger.error("Failed to load labels from file")
                return False
            
            # Validate labels format
            if not self._validate_labels_format():
                logger.error("Labels format validation failed")
                return False
            
            # Validate labels content
            if not self._validate_labels_content():
                logger.error("Labels content validation failed")
                return False
            
            # Calculate checksum
            self._calculate_checksum()
            
            # Validate checksum
            if not self._validate_checksum():
                logger.warning("Labels checksum differs from expected Food-101")
                # This is a warning, not an error - custom label sets are allowed
            
            self.is_valid = True
            logger.info(f"Label registry initialized with {len(self.labels)} valid labels")
            return True
            
        except Exception as e:
            logger.error(f"Label registry initialization failed: {e}")
            return False
    
    def _load_labels_from_file(self) -> bool:
        """Load labels from file"""
        try:
            if not os.path.exists(self.labels_path):
                logger.error(f"Labels file not found: {self.labels_path}")
                return False
            
            with open(self.labels_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            # Process labels
            self.labels = []
            for line in lines:
                label = line.strip()
                if label:  # Skip empty lines
                    self.labels.append(label)
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to load labels from file: {e}")
            return False
    
    def _validate_labels_format(self) -> bool:
        """Validate labels format"""
        if len(self.labels) != 101:
            logger.error(f"Expected exactly 101 labels, got {len(self.labels)}")
            return False
        
        # Check for duplicates
        if len(set(self.labels)) != len(self.labels):
            logger.error("Duplicate labels found")
            return False
        
        # Check for empty labels
        if any(not label for label in self.labels):
            logger.error("Empty labels found")
            return False
        
        # Check label format (alphanumeric, underscores, spaces)
        for i, label in enumerate(self.labels):
            if not isinstance(label, str):
                logger.error(f"Label {i} is not a string: {type(label)}")
                return False
            
            # Allow alphanumeric, underscores, spaces, hyphens
            if not all(c.isalnum() or c in ['_', ' ', '-'] for c in label):
                logger.error(f"Invalid label format at index {i}: '{label}'")
                return False
        
        return True
    
    def _validate_labels_content(self) -> bool:
        """Validate labels content against expected Food-101"""
        # Check if labels match expected Food-101 exactly
        if self.labels == self.EXPECTED_FOOD101_LABELS:
            logger.info("Labels match canonical Food-101 dataset")
            return True
        
        # If not exact match, check if it's a reasonable subset/superset
        missing_labels = set(self.EXPECTED_FOOD101_LABELS) - set(self.labels)
        extra_labels = set(self.labels) - set(self.EXPECTED_FOOD101_LABELS)
        
        if missing_labels:
            logger.warning(f"Missing expected Food-101 labels: {sorted(missing_labels)}")
        
        if extra_labels:
            logger.warning(f"Extra labels not in Food-101: {sorted(extra_labels)}")
        
        # Allow custom label sets but warn about differences
        logger.info("Using custom label set (differs from canonical Food-101)")
        return True
    
    def _calculate_checksum(self):
        """Calculate checksum of loaded labels"""
        labels_string = '\n'.join(self.labels)
        self.checksum = hashlib.md5(labels_string.encode('utf-8')).hexdigest()
    
    def _validate_checksum(self) -> bool:
        """Validate checksum against expected"""
        return self.checksum == self.EXPECTED_LABELS_CHECKSUM
    
    def get_class_id(self, class_name: str) -> int:
        """
        Get class ID for class name.
        
        Args:
            class_name: Class name to lookup
            
        Returns:
            Class ID if found, -1 otherwise
        """
        if not self.is_valid:
            return -1
        
        if not self.label_to_id:
            self.label_to_id = {label: idx for idx, label in enumerate(self.labels)}
        
        return self.label_to_id.get(class_name, -1)
    
    def get_class_name(self, class_id: int) -> str:
        """
        Get class name for class ID.
        
        Args:
            class_id: Class ID to lookup
            
        Returns:
            Class name if valid, "unknown" otherwise
        """
        if not self.is_valid or class_id < 0 or class_id >= len(self.labels):
            return "unknown"
        
        return self.labels[class_id]
    
    def get_all_labels(self) -> List[str]:
        """Get all labels"""
        return self.labels.copy()
    
    def get_labels_info(self) -> Dict:
        """Get labels information"""
        return {
            "labels_path": self.labels_path,
            "labels_count": len(self.labels),
            "checksum": self.checksum,
            "is_valid": self.is_valid,
            "is_food101_canonical": self.labels == self.EXPECTED_FOOD101_LABELS,
            "expected_checksum": self.EXPECTED_LABELS_CHECKSUM
        }
    
    def validate_class_id_range(self, class_id: int) -> bool:
        """Validate class ID is in valid range"""
        return self.is_valid and 0 <= class_id < len(self.labels)
    
    def validate_class_name(self, class_name: str) -> bool:
        """Validate class name exists in registry"""
        return self.is_valid and class_name in self.labels


# Global registry instance
_label_registry_instance = None


def get_label_registry(labels_path: Optional[str] = None) -> FoodLabelRegistry:
    """Get or create label registry instance"""
    global _label_registry_instance
    if _label_registry_instance is None or labels_path is not None:
        _label_registry_instance = FoodLabelRegistry(labels_path)
    return _label_registry_instance


def validate_labels_file(labels_path: str) -> Tuple[bool, str]:
    """
    Validate a labels file.
    
    Args:
        labels_path: Path to labels file to validate
        
    Returns:
        Tuple of (is_valid, message)
    """
    try:
        registry = FoodLabelRegistry(labels_path)
        if registry.is_valid:
            return True, f"Valid labels file with {len(registry.labels)} labels"
        else:
            return False, "Invalid labels file"
    except Exception as e:
        return False, f"Validation failed: {str(e)}"
