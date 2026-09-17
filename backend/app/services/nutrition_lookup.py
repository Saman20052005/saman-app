import asyncio
import aiohttp
import logging
from typing import Dict, Any, Optional
import ssl

logger = logging.getLogger(__name__)

class NutritionLookup:
    def __init__(self):
        self.openfoodfacts_base_url = "https://world.openfoodfacts.org/api/v2"
        self.usda_base_url = "https://api.nal.usda.gov/fdc/v1"
        # Note: You'll need to get an API key from USDA for production use
        
        # Add User-Agent headers to prevent 403 errors
        self.HEADERS = {
            "User-Agent": "SamanFitnessApp/1.0 (nutrition lookup; contact@yourapp.com)"
        }
        
    async def lookup(self, label: str, grams: float = 100) -> Dict[str, Any]:
        """
        Look up nutrition information for a food item using OpenFoodFacts
        Returns nutrition data per 100g and adjusted for the specified grams
        """
        try:
            # First try OpenFoodFacts
            result = await self._lookup_openfoodfacts(label, grams)
            if result:
                return result
                
            # Fallback to USDA (would need API key)
            # result = await self._lookup_usda(label, grams)
            
            return {"error": "Food not found", "label": label}
            
        except Exception as e:
            logger.error(f"Error looking up nutrition for {label}: {str(e)}")
            return {"error": str(e), "label": label}
    
    async def _lookup_openfoodfacts(self, label: str, grams: float) -> Optional[Dict[str, Any]]:
        """Search OpenFoodFacts for nutrition data"""
        url = f"{self.openfoodfacts_base_url}/search"
        params = {
            "search_terms": label,
            "search_simple": 1,
            "action": "process",
            "json": 1,
            "page_size": 5
        }
        
        # Create SSL context that bypasses verification for testing
        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE
        
        connector = aiohttp.TCPConnector(ssl=ssl_context)
        
        async with aiohttp.ClientSession(connector=connector, headers=self.HEADERS) as session:
            async with session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    
                    if data.get("products") and len(data["products"]) > 0:
                        # Get the first product
                        product = data["products"][0]
                        
                        # Extract nutrition data per 100g
                        nutriments = product.get("nutriments", {})
                        
                        nutrition_data = {
                            "source": "openfoodfacts",
                            "label": label,
                            "product_name": product.get("product_name", label),
                            "grams": grams,
                            "calories": self._get_nutrient_value(nutriments, "energy-kcal_100g", grams),
                            "protein": self._get_nutrient_value(nutriments, "proteins_100g", grams),
                            "carbs": self._get_nutrient_value(nutriments, "carbohydrates_100g", grams),
                            "fat": self._get_nutrient_value(nutriments, "fat_100g", grams),
                            "fiber": self._get_nutrient_value(nutriments, "fiber_100g", grams),
                            "sugar": self._get_nutrient_value(nutriments, "sugars_100g", grams),
                            "sodium": self._get_nutrient_value(nutriments, "sodium_100g", grams),
                            "saturated_fat": self._get_nutrient_value(nutriments, "saturated-fat_100g", grams),
                            "original_per_100g": {
                                "calories": nutriments.get("energy-kcal_100g", 0),
                                "protein": nutriments.get("proteins_100g", 0),
                                "carbs": nutriments.get("carbohydrates_100g", 0),
                                "fat": nutriments.get("fat_100g", 0),
                                "fiber": nutriments.get("fiber_100g", 0),
                                "sugar": nutriments.get("sugars_100g", 0),
                                "sodium": nutriments.get("sodium_100g", 0),
                                "saturated_fat": nutriments.get("saturated-fat_100g", 0)
                            }
                        }
                        
                        return nutrition_data
        
        return None
    
    def _get_nutrient_value(self, nutriments: Dict, key: str, target_grams: float) -> float:
        """Get nutrient value adjusted for target grams from per 100g value"""
        per_100g_value = nutriments.get(key, 0)
        if per_100g_value and target_grams != 100:
            return round((per_100g_value * target_grams) / 100, 2)
        return per_100g_value or 0
    
    async def _lookup_usda(self, label: str, grams: float) -> Optional[Dict[str, Any]]:
        """Search USDA database (requires API key)"""
        # This would require an API key from USDA
        # Implementation placeholder for future use
        # When implementing, use headers=self.HEADERS in the request
        return None
