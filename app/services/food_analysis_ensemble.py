from typing import List, Dict, Optional, Tuple, Any
import logging
from PIL import Image
import numpy as np
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed

# Conditional imports to support mock mode without dependencies
try:
    from .classification_provider_factory import create_classification_service
    _FACTORY_AVAILABLE = True
except ImportError:
    create_classification_service = None
    _FACTORY_AVAILABLE = False

try:
    from .portion_estimation_service import PortionEstimationService
    _PORTION_AVAILABLE = True
except ImportError:
    PortionEstimationService = None
    _PORTION_AVAILABLE = False

from .nutrition_mapping_service import NutritionMappingService

logger = logging.getLogger(__name__)

class FoodAnalysisEnsemble:
    """
    Ensemble service that combines food classification, portion estimation, and nutrition mapping
    Provides unified interface for food analysis with confidence scoring and error handling
    """
    
    def __init__(self, 
                 classification_model_path: Optional[str] = None,
                 portion_model_path: Optional[str] = None,
                 mongo_uri: Optional[str] = None,
                 db_name: Optional[str] = None):
        
        # Initialize services using provider factory with fallbacks
        if create_classification_service:
            self.classifier = create_classification_service(model_path=classification_model_path)
        else:
            logger.warning("Classification provider factory not available, using mock")
            from .mock_food_classification_service import MockFoodClassificationService, MockMode
            self.classifier = MockFoodClassificationService(MockMode.NORMAL)
        
        if PortionEstimationService:
            self.portion_estimator = PortionEstimationService(portion_model_path)
        else:
            logger.warning("Portion estimation service not available, using mock")
            self.portion_estimator = type('MockPortionService', (), {
                'is_model_loaded': lambda self: True,
                'estimate_portion': lambda self, img: {'weight_grams': 150.0, 'confidence': 0.5, 'size_category': 'medium', 'methods_used': ['mock']}
            })()
        
        self.nutrition_mapper = NutritionMappingService(mongo_uri, db_name)
        
        # Configuration
        self.confidence_thresholds = {
            'classification': 0.3,
            'portion': 0.2,
            'overall': 0.4
        }
        
        # Ensemble weights for different methods
        self.ensemble_weights = {
            'classification': 0.4,
            'portion_reference': 0.3,
            'portion_depth': 0.2,
            'portion_regression': 0.1
        }
        
        # Performance tracking
        self.performance_stats = {
            'total_requests': 0,
            'successful_requests': 0,
            'average_processing_time': 0.0
        }
        
        logger.info("Food Analysis Ensemble initialized with classification provider: " + 
                   type(self.classifier).__name__)
    
    def analyze_image(self, image: Image.Image, top_k: int = 5, include_nutrition: bool = True) -> Dict:
        """
        Analyze food image and return comprehensive results.
        
        Args:
            image: PIL Image input
            top_k: Number of top food predictions to consider
            include_nutrition: Whether to include nutrition analysis
            
        Returns:
            Dictionary containing analysis results
        """
        request_id = str(uuid.uuid4())[:8]  # Short ID for logging
        start_time = time.time()
        
        logger.info(f"🍽️ Starting food analysis {request_id} - top_k: {top_k}, include_nutrition: {include_nutrition}")
        
        try:
            # Step 1: Classify food
            classification_start = time.time()
            classification_results = self._classify_food(image, top_k)
            classification_time = (time.time() - classification_start) * 1000
            logger.info(f"🔍 Classification {request_id} completed in {classification_time:.1f}ms - {len(classification_results)} items")
            
            if not classification_results:
                return self._create_error_result(request_id, "No food items detected")
            
            # Step 2: Estimate portions
            portion_start = time.time()
            portion_results = self._estimate_portions(image, classification_results)
            portion_time = (time.time() - portion_start) * 1000
            logger.info(f"⚖️ Portion estimation {request_id} completed in {portion_time:.1f}ms")
            
            # Step 3: Calculate nutrition
            nutrition_start = time.time()
            nutrition_results = self._calculate_nutrition(portion_results) if include_nutrition else []
            nutrition_time = (time.time() - nutrition_start) * 1000
            logger.info(f"🥗 Nutrition calculation {request_id} completed in {nutrition_time:.1f}ms")
            
            # Step 4: Build final result
            result = self._build_result(
                request_id, classification_results, portion_results, nutrition_results
            )
            
            # Step 5: Calculate overall confidence
            result['overall_confidence'] = self._calculate_overall_confidence(portion_results)
            
            # Add timing breakdown
            total_time = (time.time() - start_time) * 1000
            result['processing_time_ms'] = total_time
            result['timing_breakdown'] = {
                'classification_ms': classification_time,
                'portion_estimation_ms': portion_time,
                'nutrition_calculation_ms': nutrition_time,
                'total_ms': total_time
            }
            
            # Add system info for evaluation
            result['system_info'] = self._get_system_info()
            
            self._update_performance_stats(True, total_time)
            
            logger.info(f"✅ Food analysis {request_id} completed successfully in {total_time:.1f}ms - "
                       f"overall_confidence: {result['overall_confidence']:.3f}")
            
            return result
            
        except Exception as e:
            error_time = (time.time() - start_time) * 1000
            logger.error(f"❌ Food analysis {request_id} failed after {error_time:.1f}ms: {e}")
            self._update_performance_stats(False, error_time)
            return self._create_error_result(request_id, str(e))
    
    def _get_system_info(self) -> Dict:
        """Get system information for evaluation and debugging"""
        return {
            'provider_info': {
                'classifier_type': type(self.classifier).__name__,
                'has_canonical_method': hasattr(self.classifier, 'predict_canonical'),
                'is_model_loaded': getattr(self.classifier, 'is_model_loaded', lambda: False)()
            },
            'ensemble_config': {
                'confidence_thresholds': self.confidence_thresholds,
                'ensemble_weights': self.ensemble_weights
            },
            'performance_stats': self.performance_stats
        }
    
    def _classify_food(self, image: Image.Image, top_k: int) -> List[Dict]:
        """Perform food classification using provider abstraction"""
        try:
            if not self.classifier.is_model_loaded():
                logger.warning("Food classification model not loaded")
                return []
            
            # Use canonical prediction method if available, otherwise fallback to legacy
            if hasattr(self.classifier, 'predict_canonical'):
                classification_result = self.classifier.predict_canonical(image, top_k)
                
                if classification_result.model_info and "error" in classification_result.model_info:
                    logger.error(f"Classification failed: {classification_result.model_info['error']}")
                    return []
                
                # Convert canonical predictions to existing format for backward compatibility
                filtered_predictions = []
                for pred in classification_result.top_k_predictions:
                    if pred.confidence >= self.confidence_thresholds['classification']:
                        filtered_predictions.append({
                            'class_name': pred.class_name,
                            'display_name': pred.display_name,
                            'confidence': pred.confidence,
                            'class_id': pred.class_id
                        })
            else:
                # Fallback to legacy predict method
                predictions = self.classifier.predict(image, top_k)
                
                # Filter by confidence threshold
                filtered_predictions = [
                    pred for pred in predictions 
                    if pred['confidence'] >= self.confidence_thresholds['classification']
                ]
            
            logger.info(f"Classification: {len(filtered_predictions)} items above threshold")
            return filtered_predictions
            
        except Exception as e:
            logger.error(f"Food classification failed: {e}")
            return []
    
    def _estimate_portions(self, image: Image.Image, classification_results: List[Dict]) -> List[Dict]:
        """Estimate portion sizes for classified food items"""
        food_items = []
        
        try:
            if not self.portion_estimator.is_model_loaded():
                logger.warning("Portion estimation model not loaded, using default portions")
                # Create food items with default portions
                for pred in classification_results:
                    food_items.append({
                        'name': pred['class_name'],
                        'display_name': pred['display_name'],
                        'confidence': pred['confidence'],
                        'portion_estimate': {
                            'weight_grams': 150.0,  # Default portion
                            'confidence': 0.5,
                            'size_category': 'medium',
                            'methods_used': ['default']
                        }
                    })
                return food_items
            
            # Perform portion estimation
            portion_result = self.portion_estimator.estimate_portion(image)
            
            # Combine classification with portion estimation
            for pred in classification_results:
                food_item = {
                    'name': pred['class_name'],
                    'display_name': pred['display_name'],
                    'confidence': pred['confidence'],
                    'portion_estimate': portion_result
                }
                food_items.append(food_item)
            
            logger.info(f"Portion estimation completed for {len(food_items)} items")
            return food_items
            
        except Exception as e:
            logger.error(f"Portion estimation failed: {e}")
            # Return items with default portions
            for pred in classification_results:
                food_items.append({
                    'name': pred['class_name'],
                    'display_name': pred['display_name'],
                    'confidence': pred['confidence'],
                    'portion_estimate': {
                        'weight_grams': 150.0,
                        'confidence': 0.3,
                        'size_category': 'medium',
                        'methods_used': ['fallback']
                    }
                })
            return food_items
    
    def _calculate_nutrition(self, food_items: List[Dict]) -> List[Dict]:
        """Calculate nutrition for each food item"""
        try:
            for item in food_items:
                nutrition = self.nutrition_mapper.calculate_nutrition(
                    item['name'], 
                    item['portion_estimate']
                )
                item['nutrition'] = nutrition
            
            logger.info(f"Nutrition calculation completed for {len(food_items)} items")
            return food_items
            
        except Exception as e:
            logger.error(f"Nutrition calculation failed: {e}")
            # Add empty nutrition to all items
            for item in food_items:
                item['nutrition'] = self.nutrition_mapper._create_empty_nutrition_response()
            return food_items
    
    def _create_final_result(self, 
                           food_items: List[Dict], 
                           request_id: str, 
                           start_time: float,
                           user_id: Optional[str] = None) -> Dict:
        """Create final analysis result"""
        processing_time = time.time() - start_time
        
        # Calculate overall confidence
        overall_confidence = self._calculate_overall_confidence(food_items)
        
        # Create nutrition summary
        nutrition_summary = None
        if food_items and 'nutrition' in food_items[0]:
            nutrition_summary = self.nutrition_mapper.get_nutrition_summary(food_items)
        
        result = {
            'request_id': request_id,
            'food_items': food_items,
            'overall_confidence': overall_confidence,
            'processing_time_ms': round(processing_time * 1000, 1),
            'nutrition_summary': nutrition_summary,
            'metadata': {
                'user_id': user_id,
                'timestamp': time.time(),
                'model_versions': self._get_model_versions(),
                'thresholds_used': self.confidence_thresholds
            },
            'status': 'success'
        }
        
        return result
    
    def _build_result(self, request_id: str, classification_results: List[Dict], 
                     portion_results: List[Dict], nutrition_results: List[Dict]) -> Dict:
        """Build final analysis result"""
        food_items = []
        
        for i, (class_result, portion_result) in enumerate(zip(classification_results, portion_results)):
            nutrition = nutrition_results[i] if i < len(nutrition_results) else {}
            
            food_item = {
                "id": f"{request_id}_{i}",
                "name": class_result.get("display_name", class_result.get("class_name", "Unknown")),
                "confidence": class_result.get("confidence", 0.0),
                "class_id": class_result.get("class_id", -1),
                "portion_estimate": portion_result,
                "nutrition": nutrition
            }
            food_items.append(food_item)
        
        return {
            "request_id": request_id,
            "status": "success",
            "food_items": food_items,
            "total_items": len(food_items)
        }

    def _calculate_overall_confidence(self, food_items: List[Dict]) -> float:
        """Calculate overall confidence for the analysis"""
        if not food_items:
            return 0.0
        
        # Weighted average of classification and portion confidence
        total_confidence = 0.0
        total_weight = 0.0
        
        for item in food_items:
            class_conf = item.get('confidence', 0.0)
            portion_conf = item.get('portion_estimate', {}).get('confidence', 0.0)
            nutrition_conf = item.get('nutrition', {}).get('confidence', 0.0)
            
            # Weighted combination
            item_confidence = (
                class_conf * 0.4 + 
                portion_conf * 0.4 + 
                nutrition_conf * 0.2
            )
            
            total_confidence += item_confidence
            total_weight += 1.0
        
        overall_confidence = total_confidence / total_weight if total_weight > 0 else 0.0
        return round(overall_confidence, 3)
    
    def _get_model_versions(self) -> Dict:
        """Get version information for all models"""
        classification_info = None
        
        if hasattr(self.classifier, 'get_model_info'):
            classification_info = self.classifier.get_model_info()
        elif hasattr(self.classifier, 'predict_canonical'):
            # Try to get info from a canonical prediction result
            try:
                from PIL import Image
                dummy_img = Image.new('RGB', (224, 224), color='white')
                result = self.classifier.predict_canonical(dummy_img, 1)
                classification_info = result.model_info
            except Exception as e:
                logger.warning(f"Could not get classification model info: {e}")
                classification_info = {"error": "Could not retrieve model info"}
        else:
            classification_info = {"model_type": "unknown"}
        
        return {
            'classification': classification_info,
            'portion_estimation': {
                'is_loaded': self.portion_estimator.is_model_loaded(),
                'methods_available': ['reference', 'depth', 'regression']
            },
            'nutrition_mapping': {
                'database_connected': self.nutrition_mapper.foods_collection is not None,
                'fallback_available': True
            },
            'provider_info': {
                'classifier_type': type(self.classifier).__name__,
                'has_canonical_method': hasattr(self.classifier, 'predict_canonical')
            }
        }
    
    def _update_performance_stats(self, success: bool, processing_time: float):
        """Update performance statistics"""
        self.performance_stats['total_requests'] += 1
        
        if success:
            self.performance_stats['successful_requests'] += 1
        
        # Update average processing time
        total_time = (
            self.performance_stats['average_processing_time'] * 
            (self.performance_stats['total_requests'] - 1) + 
            processing_time
        )
        self.performance_stats['average_processing_time'] = (
            total_time / self.performance_stats['total_requests']
        )
    
    def _create_empty_result(self, request_id: str, message: str) -> Dict:
        """Create empty result for no food detected"""
        return {
            'request_id': request_id,
            'food_items': [],
            'overall_confidence': 0.0,
            'processing_time_ms': 0.0,
            'nutrition_summary': self.nutrition_mapper._create_empty_summary(),
            'metadata': {
                'message': message,
                'timestamp': time.time()
            },
            'status': 'no_food_detected'
        }
    
    def _create_error_result(self, request_id: str, error_message: str) -> Dict:
        """Create error result"""
        return {
            'request_id': request_id,
            'food_items': [],
            'overall_confidence': 0.0,
            'processing_time_ms': 0.0,
            'nutrition_summary': self.nutrition_mapper._create_empty_summary(),
            'metadata': {
                'error': error_message,
                'timestamp': time.time()
            },
            'status': 'error'
        }
    
    def analyze_batch(self, images: List[Image.Image], max_workers: int = 4) -> List[Dict]:
        """
        Analyze multiple images in parallel
        
        Args:
            images: List of PIL Images to analyze
            max_workers: Maximum number of parallel workers
            
        Returns:
            List of analysis results
        """
        results = []
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Submit all analysis tasks
            future_to_image = {
                executor.submit(self.analyze_image, image): i 
                for i, image in enumerate(images)
            }
            
            # Collect results as they complete
            for future in as_completed(future_to_image):
                image_index = future_to_image[future]
                try:
                    result = future.result()
                    result['image_index'] = image_index
                    results.append(result)
                except Exception as e:
                    logger.error(f"Batch analysis failed for image {image_index}: {e}")
                    error_result = self._create_error_result(
                        str(uuid.uuid4()), 
                        str(e)
                    )
                    error_result['image_index'] = image_index
                    results.append(error_result)
        
        # Sort by original image order
        results.sort(key=lambda x: x['image_index'])
        return results
    
    def get_performance_stats(self) -> Dict:
        """Get current performance statistics"""
        stats = self.performance_stats.copy()
        
        if stats['total_requests'] > 0:
            stats['success_rate'] = stats['successful_requests'] / stats['total_requests']
        else:
            stats['success_rate'] = 0.0
        
        return stats
    
    def update_confidence_thresholds(self, 
                                    classification: Optional[float] = None,
                                    portion: Optional[float] = None,
                                    overall: Optional[float] = None):
        """Update confidence thresholds"""
        if classification is not None:
            self.confidence_thresholds['classification'] = classification
        if portion is not None:
            self.confidence_thresholds['portion'] = portion
        if overall is not None:
            self.confidence_thresholds['overall'] = overall
        
        logger.info(f"Updated confidence thresholds: {self.confidence_thresholds}")
    
    def health_check(self) -> Dict:
        """Perform health check on all services"""
        health_status = {
            'overall': 'healthy',
            'services': {},
            'timestamp': time.time()
        }
        
        # Check classification service
        if self.classifier.is_model_loaded():
            health_status['services']['classification'] = 'healthy'
        else:
            health_status['services']['classification'] = 'unhealthy'
            health_status['overall'] = 'degraded'
        
        # Check portion estimation service
        if self.portion_estimator.is_model_loaded():
            health_status['services']['portion_estimation'] = 'healthy'
        else:
            health_status['services']['portion_estimation'] = 'unhealthy'
            health_status['overall'] = 'degraded'
        
        # Check nutrition mapping service
        if self.nutrition_mapper.foods_collection is not None:
            health_status['services']['nutrition_mapping'] = 'healthy'
        else:
            health_status['services']['nutrition_mapping'] = 'degraded'
            health_status['overall'] = 'degraded'
        
        return health_status
    
    def close(self):
        """Close all services and connections"""
        try:
            self.nutrition_mapper.close()
            logger.info("Food Analysis Ensemble closed")
        except Exception as e:
            logger.error(f"Error closing ensemble: {e}")
