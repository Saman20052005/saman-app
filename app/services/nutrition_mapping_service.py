from typing import Dict, List, Optional, Tuple
import logging
from pymongo import MongoClient
import os
from dotenv import load_dotenv
import json
from pathlib import Path

logger = logging.getLogger(__name__)

class NutritionMappingService:
    """
    Maps food items to nutrition data and calculates macros based on portion estimates
    Uses USDA FoodData Central schema for nutrition information
    """
    
    def __init__(self, mongo_uri: Optional[str] = None, db_name: Optional[str] = None):
        load_dotenv()
        
        # MongoDB connection
        self.mongo_uri = mongo_uri or os.getenv("MONGO_URI", "mongodb://localhost:27017")
        self.db_name = db_name or os.getenv("DB_NAME", "saman_fitness")
        
        # Initialize collections
        self.client = None
        self.foods_collection = None
        self.nutrition_collection = None
        
        # Nutrition calculation constants
        self.MACRO_MULTIPLIERS = {
            'protein': 4.0,  # calories per gram
            'carbohydrates': 4.0,
            'fat': 9.0,
            'alcohol': 7.0
        }
        
        # Load nutrition database
        self._load_nutrition_database()
    
    def _load_nutrition_database(self):
        """Load nutrition database from MongoDB or fallback to local data"""
        try:
            self.client = MongoClient(self.mongo_uri)
            db = self.client[self.db_name]
            self.foods_collection = db["foods"]
            self.nutrition_collection = db["nutrition_plans"]
            
            # Test connection
            self.client.admin.command('ping')
            logger.info("Connected to nutrition database")
            
        except Exception as e:
            logger.warning(f"Failed to connect to MongoDB: {e}")
            self._load_fallback_nutrition_data()
    
    def _load_fallback_nutrition_data(self):
        """Load fallback nutrition data from local files"""
        try:
            # Load basic nutrition data
            fallback_path = Path(__file__).parent.parent.parent / "data" / "nutrition_fallback.json"
            if fallback_path.exists():
                with open(fallback_path, 'r') as f:
                    self.fallback_nutrition = json.load(f)
                logger.info("Loaded fallback nutrition data")
            else:
                self.fallback_nutrition = self._create_minimal_nutrition_data()
                logger.warning("Using minimal nutrition data")
                
        except Exception as e:
            logger.error(f"Failed to load fallback nutrition data: {e}")
            self.fallback_nutrition = self._create_minimal_nutrition_data()
    
    def _create_minimal_nutrition_data(self) -> Dict:
        """Create minimal nutrition data for common foods"""
        return {
            'apple_pie': {
                'calories_100g': 296,
                'protein_100g': 1.9,
                'fat_100g': 11.0,
                'carbs_100g': 42.5,
                'fiber_100g': 1.9,
                'sugar_100g': 21.5
            },
            'chicken_curry': {
                'calories_100g': 240,
                'protein_100g': 18.0,
                'fat_100g': 15.0,
                'carbs_100g': 12.0,
                'fiber_100g': 2.0,
                'sugar_100g': 3.0
            },
            'pizza': {
                'calories_100g': 285,
                'protein_100g': 12.4,
                'fat_100g': 10.8,
                'carbs_100g': 36.2,
                'fiber_100g': 2.3,
                'sugar_100g': 4.1
            },
            'salad': {
                'calories_100g': 35,
                'protein_100g': 2.0,
                'fat_100g': 0.5,
                'carbs_100g': 7.0,
                'fiber_100g': 3.0,
                'sugar_100g': 3.5
            },
            'rice': {
                'calories_100g': 130,
                'protein_100g': 2.7,
                'fat_100g': 0.3,
                'carbs_100g': 28.0,
                'fiber_100g': 0.4,
                'sugar_100g': 0.1
            }
        }
    
    def calculate_nutrition(self, food_class: str, portion_estimate: Dict) -> Dict:
        """
        Calculate nutrition information based on food class and portion estimate
        
        Args:
            food_class: Food classification result
            portion_estimate: Portion estimation result with weight_grams
            
        Returns:
            Dictionary with calculated nutrition values
        """
        try:
            # Get base nutrition data for 100g
            base_nutrition = self._get_base_nutrition(food_class)
            
            if not base_nutrition:
                logger.warning(f"No nutrition data found for {food_class}")
                return self._create_empty_nutrition_response()
            
            # Calculate portion multiplier
            weight_grams = portion_estimate.get('weight_grams', 100)
            portion_multiplier = weight_grams / 100.0
            
            # Calculate nutrition for actual portion
            calculated_nutrition = self._calculate_portion_nutrition(
                base_nutrition, portion_multiplier
            )
            
            # Add confidence and metadata
            result = {
                **calculated_nutrition,
                'portion_info': {
                    'weight_grams': weight_grams,
                    'portion_multiplier': portion_multiplier,
                    'size_category': portion_estimate.get('size_category', 'unknown')
                },
                'confidence': self._calculate_nutrition_confidence(
                    base_nutrition, portion_estimate
                ),
                'data_source': self._get_data_source(food_class)
            }
            
            return result
            
        except Exception as e:
            logger.error(f"Nutrition calculation failed: {e}")
            return self._create_empty_nutrition_response()
    
    def _get_base_nutrition(self, food_class: str) -> Optional[Dict]:
        """Get base nutrition data for food class"""
        # Try MongoDB first
        if self.foods_collection:
            try:
                food_data = self.foods_collection.find_one({"food_class": food_class})
                if food_data and 'nutrition_per_100g' in food_data:
                    return food_data['nutrition_per_100g']
            except Exception as e:
                logger.warning(f"MongoDB lookup failed: {e}")
        
        # Fallback to local data
        return self.fallback_nutrition.get(food_class)
    
    def _calculate_portion_nutrition(self, base_nutrition: Dict, multiplier: float) -> Dict:
        """Calculate nutrition for specific portion size"""
        nutrition = {}
        
        # Calculate macros
        for macro in ['calories', 'protein', 'fat', 'carbohydrates', 'fiber', 'sugar']:
            base_key = f"{macro}_100g" if macro != 'calories' else 'calories_100g'
            if base_key in base_nutrition:
                nutrition[macro] = round(base_nutrition[base_key] * multiplier, 1)
            else:
                nutrition[macro] = 0.0
        
        # Calculate calories from macros (for verification)
        calculated_calories = (
            nutrition.get('protein', 0) * self.MACRO_MULTIPLIERS['protein'] +
            nutrition.get('carbohydrates', 0) * self.MACRO_MULTIPLIERS['carbohydrates'] +
            nutrition.get('fat', 0) * self.MACRO_MULTIPLIERS['fat']
        )
        
        nutrition['calories_from_macros'] = round(calculated_calories, 1)
        
        # Add macro percentages
        total_calories = nutrition.get('calories', 0)
        if total_calories > 0:
            nutrition['protein_percentage'] = round(
                (nutrition.get('protein', 0) * self.MACRO_MULTIPLIERS['protein']) / total_calories * 100, 1
            )
            nutrition['carbs_percentage'] = round(
                (nutrition.get('carbohydrates', 0) * self.MACRO_MULTIPLIERS['carbohydrates']) / total_calories * 100, 1
            )
            nutrition['fat_percentage'] = round(
                (nutrition.get('fat', 0) * self.MACRO_MULTIPLIERS['fat']) / total_calories * 100, 1
            )
        else:
            nutrition['protein_percentage'] = 0
            nutrition['carbs_percentage'] = 0
            nutrition['fat_percentage'] = 0
        
        return nutrition
    
    def _calculate_nutrition_confidence(self, base_nutrition: Dict, portion_estimate: Dict) -> float:
        """Calculate overall confidence for nutrition calculation"""
        # Base confidence from nutrition data quality
        data_confidence = 0.9 if 'usda_source' in base_nutrition else 0.7
        
        # Portion estimation confidence
        portion_confidence = portion_estimate.get('confidence', 0.5)
        
        # Combined confidence (weighted average)
        overall_confidence = (data_confidence * 0.6 + portion_confidence * 0.4)
        
        return round(min(overall_confidence, 1.0), 3)
    
    def _get_data_source(self, food_class: str) -> str:
        """Get data source for nutrition information"""
        if self.foods_collection:
            try:
                food_data = self.foods_collection.find_one({"food_class": food_class})
                if food_data:
                    return food_data.get('data_source', 'database')
            except:
                pass
        
        return 'fallback'
    
    def _create_empty_nutrition_response(self) -> Dict:
        """Create empty nutrition response for unknown foods"""
        return {
            'calories': 0,
            'protein': 0,
            'fat': 0,
            'carbohydrates': 0,
            'fiber': 0,
            'sugar': 0,
            'calories_from_macros': 0,
            'protein_percentage': 0,
            'carbs_percentage': 0,
            'fat_percentage': 0,
            'portion_info': {
                'weight_grams': 0,
                'portion_multiplier': 0,
                'size_category': 'unknown'
            },
            'confidence': 0.0,
            'data_source': 'unknown'
        }
    
    def get_nutrition_summary(self, food_items: List[Dict]) -> Dict:
        """
        Calculate total nutrition for multiple food items
        
        Args:
            food_items: List of food items with nutrition data
            
        Returns:
            Summary with total nutrition values
        """
        try:
            total_nutrition = {
                'calories': 0,
                'protein': 0,
                'fat': 0,
                'carbohydrates': 0,
                'fiber': 0,
                'sugar': 0,
                'item_count': len(food_items),
                'food_items': []
            }
            
            for item in food_items:
                nutrition = item.get('nutrition', {})
                food_name = item.get('display_name', 'Unknown')
                
                # Add to totals
                for macro in ['calories', 'protein', 'fat', 'carbohydrates', 'fiber', 'sugar']:
                    total_nutrition[macro] += nutrition.get(macro, 0)
                
                # Add item summary
                total_nutrition['food_items'].append({
                    'name': food_name,
                    'calories': nutrition.get('calories', 0),
                    'weight_grams': nutrition.get('portion_info', {}).get('weight_grams', 0)
                })
            
            # Calculate percentages
            total_calories = total_nutrition['calories']
            if total_calories > 0:
                total_nutrition['protein_percentage'] = round(
                    (total_nutrition['protein'] * self.MACRO_MULTIPLIERS['protein']) / total_calories * 100, 1
                )
                total_nutrition['carbs_percentage'] = round(
                    (total_nutrition['carbohydrates'] * self.MACRO_MULTIPLIERS['carbohydrates']) / total_calories * 100, 1
                )
                total_nutrition['fat_percentage'] = round(
                    (total_nutrition['fat'] * self.MACRO_MULTIPLIERS['fat']) / total_calories * 100, 1
                )
            else:
                total_nutrition['protein_percentage'] = 0
                total_nutrition['carbs_percentage'] = 0
                total_nutrition['fat_percentage'] = 0
            
            return total_nutrition
            
        except Exception as e:
            logger.error(f"Nutrition summary calculation failed: {e}")
            return self._create_empty_summary()
    
    def _create_empty_summary(self) -> Dict:
        """Create empty nutrition summary"""
        return {
            'calories': 0,
            'protein': 0,
            'fat': 0,
            'carbohydrates': 0,
            'fiber': 0,
            'sugar': 0,
            'protein_percentage': 0,
            'carbs_percentage': 0,
            'fat_percentage': 0,
            'item_count': 0,
            'food_items': []
        }
    
    def add_nutrition_data(self, food_class: str, nutrition_data: Dict, data_source: str = 'manual'):
        """
        Add new nutrition data to database
        
        Args:
            food_class: Food classification name
            nutrition_data: Nutrition information per 100g
            data_source: Source of nutrition data
        """
        try:
            if self.foods_collection:
                food_document = {
                    'food_class': food_class,
                    'nutrition_per_100g': nutrition_data,
                    'data_source': data_source,
                    'created_at': '2024-01-01T00:00:00Z',  # Simplified timestamp
                    'updated_at': '2024-01-01T00:00:00Z'
                }
                
                # Update or insert
                self.foods_collection.replace_one(
                    {'food_class': food_class},
                    food_document,
                    upsert=True
                )
                
                logger.info(f"Added nutrition data for {food_class}")
            else:
                # Add to fallback data
                self.fallback_nutrition[food_class] = nutrition_data
                logger.info(f"Added nutrition data to fallback for {food_class}")
                
        except Exception as e:
            logger.error(f"Failed to add nutrition data: {e}")
    
    def search_similar_foods(self, food_class: str, limit: int = 5) -> List[Dict]:
        """
        Search for similar foods based on name similarity
        
        Args:
            food_class: Food class to search for
            limit: Maximum number of results
            
        Returns:
            List of similar foods with nutrition data
        """
        try:
            similar_foods = []
            
            # Simple string matching (in production, use fuzzy matching)
            search_terms = food_class.lower().replace('_', ' ').split()
            
            if self.foods_collection:
                # Search in MongoDB
                cursor = self.foods_collection.find({})
                for food_doc in cursor:
                    food_name = food_doc.get('food_class', '').lower().replace('_', ' ')
                    
                    # Calculate similarity score (simplified)
                    similarity = self._calculate_similarity(food_class.lower(), food_name)
                    
                    if similarity > 0.3:  # Threshold for similarity
                        similar_foods.append({
                            'food_class': food_doc.get('food_class'),
                            'nutrition': food_doc.get('nutrition_per_100g', {}),
                            'similarity': similarity,
                            'data_source': food_doc.get('data_source', 'database')
                        })
            
            # Search in fallback data
            for fallback_class, nutrition in self.fallback_nutrition.items():
                if fallback_class != food_class:
                    similarity = self._calculate_similarity(food_class.lower(), fallback_class.lower())
                    
                    if similarity > 0.3:
                        similar_foods.append({
                            'food_class': fallback_class,
                            'nutrition': nutrition,
                            'similarity': similarity,
                            'data_source': 'fallback'
                        })
            
            # Sort by similarity and limit results
            similar_foods.sort(key=lambda x: x['similarity'], reverse=True)
            return similar_foods[:limit]
            
        except Exception as e:
            logger.error(f"Similar food search failed: {e}")
            return []
    
    def _calculate_similarity(self, str1: str, str2: str) -> float:
        """Calculate similarity between two strings (simplified Jaccard similarity)"""
        words1 = set(str1.replace('_', ' ').split())
        words2 = set(str2.replace('_', ' ').split())
        
        intersection = words1.intersection(words2)
        union = words1.union(words2)
        
        if not union:
            return 0.0
        
        return len(intersection) / len(union)
    
    def close(self):
        """Close database connection"""
        if self.client:
            self.client.close()
