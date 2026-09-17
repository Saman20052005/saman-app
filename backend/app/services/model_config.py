import os
from pathlib import Path
from typing import Dict, Optional, List
import json
import logging
from dataclasses import dataclass, asdict
from dotenv import load_dotenv

logger = logging.getLogger(__name__)

@dataclass
class ModelConfig:
    """Configuration for ML models"""
    model_name: str
    model_path: Optional[str] = None
    model_url: Optional[str] = None
    num_classes: int = 101
    input_size: tuple = (224, 224)
    device: str = "auto"
    confidence_threshold: float = 0.5
    batch_size: int = 1
    max_image_size: int = 1024
    supported_formats: List[str] = None
    
    def __post_init__(self):
        if self.supported_formats is None:
            self.supported_formats = ["JPEG", "JPG", "PNG", "WEBP"]
        
        if self.device == "auto":
            try:
                import torch
                self.device = "cuda" if torch.cuda.is_available() else "cpu"
            except ImportError:
                logger.warning("PyTorch not available, defaulting to CPU device")
                self.device = "cpu"

@dataclass
class FoodAnalysisConfig:
    """Complete configuration for food analysis system"""
    
    # Model configurations
    classification: ModelConfig
    portion_estimation: ModelConfig
    
    # Database configuration
    mongo_uri: str
    db_name: str
    nutrition_collection: str = "foods"
    
    # Service configuration
    max_concurrent_requests: int = 10
    request_timeout: float = 30.0
    cache_ttl: int = 3600  # seconds
    
    # Confidence thresholds
    classification_threshold: float = 0.3
    portion_threshold: float = 0.2
    overall_threshold: float = 0.4
    
    # Performance settings
    enable_batch_processing: bool = True
    max_batch_size: int = 8
    enable_gpu: bool = True
    
    # Logging and monitoring
    log_level: str = "INFO"
    enable_metrics: bool = True
    metrics_port: int = 8001
    
    # Model paths
    model_base_path: str = "models"
    
    def __post_init__(self):
        # Ensure model base path exists
        Path(self.model_base_path).mkdir(parents=True, exist_ok=True)

class ConfigManager:
    """Manages configuration for food analysis system"""
    
    def __init__(self, config_file: Optional[str] = None):
        load_dotenv()
        
        self.config_file = config_file or "food_analysis_config.json"
        self.config: Optional[FoodAnalysisConfig] = None
        
        # Load configuration
        self.load_config()
    
    def load_config(self) -> FoodAnalysisConfig:
        """Load configuration from file or environment variables"""
        try:
            # Try to load from file first
            if Path(self.config_file).exists():
                self.config = self._load_from_file()
                logger.info(f"Loaded configuration from {self.config_file}")
            else:
                self.config = self._load_from_environment()
                logger.info("Loaded configuration from environment variables")
            
            # Validate configuration
            self._validate_config()
            
            return self.config
            
        except Exception as e:
            logger.error(f"Failed to load configuration: {e}")
            # Fallback to default configuration
            self.config = self._get_default_config()
            logger.warning("Using default configuration")
            return self.config
    
    def _load_from_file(self) -> FoodAnalysisConfig:
        """Load configuration from JSON file"""
        with open(self.config_file, 'r') as f:
            config_dict = json.load(f)
        
        # Convert to FoodAnalysisConfig
        classification_config = ModelConfig(**config_dict['classification'])
        portion_config = ModelConfig(**config_dict['portion_estimation'])
        
        return FoodAnalysisConfig(
            classification=classification_config,
            portion_estimation=portion_config,
            **{k: v for k, v in config_dict.items() 
               if k not in ['classification', 'portion_estimation']}
        )
    
    def _load_from_environment(self) -> FoodAnalysisConfig:
        """Load configuration from environment variables"""
        
        # Classification model config
        classification_config = ModelConfig(
            model_name=os.getenv("CLASSIFICATION_MODEL_NAME", "efficientnet_b3"),
            model_path=os.getenv("CLASSIFICATION_MODEL_PATH"),
            model_url=os.getenv("CLASSIFICATION_MODEL_URL"),
            num_classes=int(os.getenv("CLASSIFICATION_NUM_CLASSES", "101")),
            input_size=self._parse_tuple(os.getenv("CLASSIFICATION_INPUT_SIZE", "300,300")),
            device=os.getenv("CLASSIFICATION_DEVICE", "auto"),
            confidence_threshold=float(os.getenv("CLASSIFICATION_THRESHOLD", "0.3")),
            batch_size=int(os.getenv("CLASSIFICATION_BATCH_SIZE", "1")),
            max_image_size=int(os.getenv("MAX_IMAGE_SIZE", "1024"))
        )
        
        # Portion estimation config
        portion_config = ModelConfig(
            model_name=os.getenv("PORTION_MODEL_NAME", "portion_regressor"),
            model_path=os.getenv("PORTION_MODEL_PATH"),
            model_url=os.getenv("PORTION_MODEL_URL"),
            num_classes=int(os.getenv("PORTION_NUM_CLASSES", "1")),
            input_size=self._parse_tuple(os.getenv("PORTION_INPUT_SIZE", "224,224")),
            device=os.getenv("PORTION_DEVICE", "auto"),
            confidence_threshold=float(os.getenv("PORTION_THRESHOLD", "0.2")),
            batch_size=int(os.getenv("PORTION_BATCH_SIZE", "1"))
        )
        
        return FoodAnalysisConfig(
            classification=classification_config,
            portion_estimation=portion_config,
            mongo_uri=os.getenv("MONGO_URI", "mongodb://localhost:27017"),
            db_name=os.getenv("DB_NAME", "saman_fitness"),
            nutrition_collection=os.getenv("NUTRITION_COLLECTION", "foods"),
            max_concurrent_requests=int(os.getenv("MAX_CONCURRENT_REQUESTS", "10")),
            request_timeout=float(os.getenv("REQUEST_TIMEOUT", "30.0")),
            cache_ttl=int(os.getenv("CACHE_TTL", "3600")),
            classification_threshold=float(os.getenv("CLASSIFICATION_THRESHOLD", "0.3")),
            portion_threshold=float(os.getenv("PORTION_THRESHOLD", "0.2")),
            overall_threshold=float(os.getenv("OVERALL_THRESHOLD", "0.4")),
            enable_batch_processing=os.getenv("ENABLE_BATCH_PROCESSING", "true").lower() == "true",
            max_batch_size=int(os.getenv("MAX_BATCH_SIZE", "8")),
            enable_gpu=os.getenv("ENABLE_GPU", "true").lower() == "true",
            log_level=os.getenv("LOG_LEVEL", "INFO"),
            enable_metrics=os.getenv("ENABLE_METRICS", "true").lower() == "true",
            metrics_port=int(os.getenv("METRICS_PORT", "8001")),
            model_base_path=os.getenv("MODEL_BASE_PATH", "models")
        )
    
    def _get_default_config(self) -> FoodAnalysisConfig:
        """Get default configuration"""
        
        classification_config = ModelConfig(
            model_name="efficientnet_b3",
            model_path=None,
            num_classes=101,
            input_size=(300, 300),
            device="auto",
            confidence_threshold=0.3
        )
        
        portion_config = ModelConfig(
            model_name="portion_regressor",
            model_path=None,
            num_classes=1,
            input_size=(224, 224),
            device="auto",
            confidence_threshold=0.2
        )
        
        return FoodAnalysisConfig(
            classification=classification_config,
            portion_estimation=portion_config,
            mongo_uri="mongodb://localhost:27017",
            db_name="saman_fitness",
            nutrition_collection="foods",
            max_concurrent_requests=10,
            request_timeout=30.0,
            cache_ttl=3600,
            classification_threshold=0.3,
            portion_threshold=0.2,
            overall_threshold=0.4,
            enable_batch_processing=True,
            max_batch_size=8,
            enable_gpu=True,
            log_level="INFO",
            enable_metrics=True,
            metrics_port=8001,
            model_base_path="models"
        )
    
    def _parse_tuple(self, tuple_str: str) -> tuple:
        """Parse tuple string like "300,300" to tuple"""
        try:
            return tuple(map(int, tuple_str.split(',')))
        except:
            return (224, 224)  # Default
    
    def _validate_config(self):
        """Validate configuration values"""
        if not self.config:
            raise ValueError("Configuration not loaded")
        
        # Validate confidence thresholds
        if not (0 <= self.config.classification_threshold <= 1):
            raise ValueError("Classification threshold must be between 0 and 1")
        
        if not (0 <= self.config.portion_threshold <= 1):
            raise ValueError("Portion threshold must be between 0 and 1")
        
        if not (0 <= self.config.overall_threshold <= 1):
            raise ValueError("Overall threshold must be between 0 and 1")
        
        # Validate numeric values
        if self.config.max_concurrent_requests <= 0:
            raise ValueError("Max concurrent requests must be positive")
        
        if self.config.request_timeout <= 0:
            raise ValueError("Request timeout must be positive")
        
        # Validate model paths
        if self.config.classification.model_path:
            path = Path(self.config.classification.model_path)
            if not path.exists():
                logger.warning(f"Classification model path does not exist: {path}")
        
        if self.config.portion_estimation.model_path:
            path = Path(self.config.portion_estimation.model_path)
            if not path.exists():
                logger.warning(f"Portion model path does not exist: {path}")
    
    def save_config(self, config_file: Optional[str] = None):
        """Save current configuration to file"""
        if not self.config:
            raise ValueError("No configuration to save")
        
        save_path = config_file or self.config_file
        
        try:
            # Convert to dictionary
            config_dict = asdict(self.config)
            
            # Save to file
            with open(save_path, 'w') as f:
                json.dump(config_dict, f, indent=2)
            
            logger.info(f"Configuration saved to {save_path}")
            
        except Exception as e:
            logger.error(f"Failed to save configuration: {e}")
            raise
    
    def update_config(self, **kwargs):
        """Update configuration values"""
        if not self.config:
            self.load_config()
        
        for key, value in kwargs.items():
            if hasattr(self.config, key):
                setattr(self.config, key, value)
                logger.info(f"Updated config: {key} = {value}")
            else:
                logger.warning(f"Unknown configuration key: {key}")
        
        # Re-validate after update
        self._validate_config()
    
    def get_model_paths(self) -> Dict[str, Optional[str]]:
        """Get absolute paths for all models"""
        if not self.config:
            return {}
        
        base_path = Path(self.config.model_base_path)
        
        paths = {
            'classification': None,
            'portion_estimation': None
        }
        
        if self.config.classification.model_path:
            paths['classification'] = str(base_path / self.config.classification.model_path)
        
        if self.config.portion_estimation.model_path:
            paths['portion_estimation'] = str(base_path / self.config.portion_estimation.model_path)
        
        return paths
    
    def create_directories(self):
        """Create necessary directories"""
        if not self.config:
            return
        
        # Create model base directory
        Path(self.config.model_base_path).mkdir(parents=True, exist_ok=True)
        
        # Create log directory
        Path("logs").mkdir(exist_ok=True)
        
        # Create cache directory
        Path("cache").mkdir(exist_ok=True)
        
        logger.info("Created necessary directories")
    
    def get_environment_info(self) -> Dict:
        """Get environment information for debugging"""
        info = {}
        try:
            import torch
            info['torch_version'] = torch.__version__
            info['cuda_available'] = torch.cuda.is_available()
            if torch.cuda.is_available():
                info['cuda_device_count'] = torch.cuda.device_count()
                info['cuda_device_name'] = torch.cuda.get_device_name(0)
        except ImportError:
            info['torch_version'] = 'Not installed'
            info['cuda_available'] = False
        
        try:
            import sys
            info['python_version'] = sys.version
        except Exception:
            info['python_version'] = 'Unknown'
        
        return info
    
    def get_config_info(self) -> Dict:
        """Get current configuration information"""
        if self.config:
            info.update({
                'config_file': self.config_file,
                'model_base_path': self.config.model_base_path,
                'enable_gpu': self.config.enable_gpu,
                'log_level': self.config.log_level
            })
        
        return info

# Global configuration instance
config_manager = ConfigManager()

def get_config() -> FoodAnalysisConfig:
    """Get global configuration"""
    return config_manager.config

def update_config(**kwargs):
    """Update global configuration"""
    config_manager.update_config(**kwargs)

def save_config(config_file: Optional[str] = None):
    """Save global configuration"""
    config_manager.save_config(config_file)
