"""
Lightweight evaluation utilities for demo and academic purposes.
Supports explanation during Q&A without bloating runtime.
"""

import os
import numpy as np
from typing import List, Dict, Tuple, Optional, Any
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)


@dataclass
class EvaluationMetrics:
    """Container for evaluation metrics"""
    top1_accuracy: float
    top5_accuracy: float
    confidence_distribution: Dict[str, float]
    prediction_count: int
    avg_confidence: float


class FoodClassificationEvaluator:
    """
    Lightweight evaluator for food classification results.
    Supports offline evaluation and demo explanation without runtime dataset requirements.
    """
    
    def __init__(self):
        self.predictions = []
        self.ground_truth = []
        self.confidence_scores = []
        
    def add_prediction(self, 
                      predicted_class: str, 
                      confidence: float, 
                      top_k_predictions: List[Dict],
                      true_class: Optional[str] = None):
        """
        Add a prediction for evaluation.
        
        Args:
            predicted_class: Top-1 predicted class
            confidence: Confidence score for top-1 prediction
            top_k_predictions: List of top-k predictions with class names and confidences
            true_class: Ground truth class (optional, for accuracy calculation)
        """
        self.predictions.append({
            'predicted': predicted_class,
            'confidence': confidence,
            'top_k': top_k_predictions
        })
        
        self.confidence_scores.append(confidence)
        
        if true_class is not None:
            self.ground_truth.append(true_class)
    
    def calculate_metrics(self) -> EvaluationMetrics:
        """
        Calculate evaluation metrics from collected predictions.
        
        Returns:
            EvaluationMetrics with calculated statistics
        """
        if not self.predictions:
            return EvaluationMetrics(
                top1_accuracy=0.0,
                top5_accuracy=0.0,
                confidence_distribution={},
                prediction_count=0,
                avg_confidence=0.0
            )
        
        # Calculate confidence distribution
        confidences = np.array(self.confidence_scores)
        confidence_distribution = {
            'mean': float(np.mean(confidences)),
            'std': float(np.std(confidences)),
            'min': float(np.min(confidences)),
            'max': float(np.max(confidences)),
            'median': float(np.median(confidences))
        }
        
        # Calculate accuracy if ground truth available
        top1_accuracy = 0.0
        top5_accuracy = 0.0
        
        if len(self.ground_truth) == len(self.predictions):
            top1_correct = 0
            top5_correct = 0
            
            for pred, true in zip(self.predictions, self.ground_truth):
                # Top-1 accuracy
                if pred['predicted'] == true:
                    top1_correct += 1
                
                # Top-5 accuracy
                top5_classes = [p['class_name'] if isinstance(p, dict) else p 
                               for p in pred['top_k'][:5]]
                if true in top5_classes:
                    top5_correct += 1
            
            top1_accuracy = top1_correct / len(self.predictions)
            top5_accuracy = top5_correct / len(self.predictions)
        
        return EvaluationMetrics(
            top1_accuracy=top1_accuracy,
            top5_accuracy=top5_accuracy,
            confidence_distribution=confidence_distribution,
            prediction_count=len(self.predictions),
            avg_confidence=float(np.mean(confidences))
        )
    
    def get_confidence_summary(self) -> Dict[str, Any]:
        """
        Get confidence distribution summary for demo explanation.
        
        Returns:
            Dictionary with confidence statistics
        """
        if not self.confidence_scores:
            return {"error": "No predictions available"}
        
        confidences = np.array(self.confidence_scores)
        
        # Create confidence buckets for explanation
        buckets = {
            'high_confidence (>0.8)': np.sum(confidences > 0.8),
            'medium_confidence (0.5-0.8)': np.sum((confidences > 0.5) & (confidences <= 0.8)),
            'low_confidence (0.2-0.5)': np.sum((confidences > 0.2) & (confidences <= 0.5)),
            'very_low_confidence (<=0.2)': np.sum(confidences <= 0.2)
        }
        
        return {
            'total_predictions': len(confidences),
            'confidence_stats': {
                'mean': float(np.mean(confidences)),
                'std': float(np.std(confidences)),
                'min': float(np.min(confidences)),
                'max': float(np.max(confidences))
            },
            'confidence_buckets': buckets,
            'bucket_percentages': {
                k: f"{(v / len(confidences) * 100):.1f}%" 
                for k, v in buckets.items()
            }
        }
    
    def explain_prediction_quality(self) -> str:
        """
        Generate human-readable explanation of prediction quality.
        
        Returns:
            String explanation suitable for demo/Q&A
        """
        if not self.predictions:
            return "No predictions to evaluate"
        
        metrics = self.calculate_metrics()
        conf_summary = self.get_confidence_summary()
        
        explanation = f"""
Prediction Quality Analysis:
- Total predictions: {metrics.prediction_count}
- Average confidence: {metrics.avg_confidence:.3f}
- Confidence range: {conf_summary['confidence_stats']['min']:.3f} - {conf_summary['confidence_stats']['max']:.3f}

Confidence Distribution:
{chr(10).join([f"  - {k}: {v}" for k, v in conf_summary['bucket_percentages'].items()])}

"""
        
        if metrics.top1_accuracy > 0:
            explanation += f"""Accuracy Metrics:
- Top-1 Accuracy: {metrics.top1_accuracy:.1%}
- Top-5 Accuracy: {metrics.top5_accuracy:.1%}

"""
        
        # Add interpretation
        if metrics.avg_confidence > 0.8:
            explanation += "Interpretation: Model shows high confidence in predictions, indicating clear classification decisions."
        elif metrics.avg_confidence > 0.6:
            explanation += "Interpretation: Model shows moderate confidence, suggesting some ambiguity in predictions."
        else:
            explanation += "Interpretation: Model shows low confidence, indicating challenging or ambiguous inputs."
        
        return explanation.strip()
    
    def reset(self):
        """Reset evaluator for new evaluation session"""
        self.predictions = []
        self.ground_truth = []
        self.confidence_scores = []


class DemoExplanationHelper:
    """
    Helper class for generating explanations during demo and Q&A.
    """
    
    @staticmethod
    def explain_model_architecture() -> str:
        """Generate explanation of model architecture for demo"""
        return """
Model Architecture:
- Base Model: EfficientNet-B3 (pre-trained on ImageNet)
- Fine-tuned on: Food-101 dataset (101 food categories)
- Input Size: 224×224 RGB images
- Output: Softmax probabilities for 101 food classes
- Parameters: ~12M (EfficientNet-B3) + classifier head

Training Process:
1. Started with ImageNet-pretrained weights
2. Modified final layer for 101 food classes
3. Fine-tuned on Food-101 dataset
4. Used transfer learning for better generalization

Why EfficientNet-B3:
- Good balance of accuracy and efficiency
- Proven performance on food recognition tasks
- Reasonable inference time for demo purposes
        """.strip()
    
    @staticmethod
    def explain_provider_system() -> str:
        """Generate explanation of provider system for demo"""
        return """
Provider System Architecture:
- Mock Provider: Deterministic predictions for development/demo
- PyTorch Provider: Real model inference for production
- Factory Pattern: Automatic provider selection via config
- Safe Fallback: Always operational, never crashes

Configuration:
- FOOD_CLASSIFIER_PROVIDER=mock|pytorch
- Automatic fallback to mock on failures
- Zero-code model switching via environment variables

Benefits:
- Development can proceed without real models
- Demo always works regardless of model availability
- Production can easily switch between providers
- Clear separation of concerns
        """.strip()
    
    @staticmethod
    def explain_evaluation_approach() -> str:
        """Generate explanation of evaluation approach for demo"""
        return """
Evaluation Approach:
- Top-1 Accuracy: Correct prediction in #1 position
- Top-5 Accuracy: Correct prediction in top 5 positions
- Confidence Analysis: Distribution of prediction confidence
- Error Analysis: Common failure patterns and edge cases

Demo Evaluation:
- Real-time confidence tracking
- Prediction quality explanation
- Model behavior under different conditions
- Comparison between mock and real predictions

Academic Rigor:
- Standard ML evaluation metrics
- Confidence calibration analysis
- Error case investigation
- Performance benchmarking
        """.strip()


def create_demo_evaluator() -> FoodClassificationEvaluator:
    """Create evaluator instance for demo purposes"""
    return FoodClassificationEvaluator()


def get_demo_explanation() -> str:
    """Get comprehensive demo explanation"""
    helper = DemoExplanationHelper()
    
    explanation = f"""
{helper.explain_model_architecture()}

{helper.explain_provider_system()}

{helper.explain_evaluation_approach()}
"""
    
    return explanation.strip()
