# [File: backend/services/nutrition_lookup.py]
import httpx
from typing import Optional

# ================================================================
# STATIC FALLBACK — tất cả 101 Food-101 classes
# Unit: per 100g  |  Source: USDA FoodData Central (SR Legacy)
# ================================================================
NUTRITION_FALLBACK_PER_100G = {
    # ── A ──────────────────────────────────────────────────────
    "apple_pie":              {"calories": 237, "protein":  2.0, "carbs": 34.0, "fat": 11.0},

    # ── B ──────────────────────────────────────────────────────
    "baby_back_ribs":         {"calories": 295, "protein": 22.0, "carbs":  3.0, "fat": 22.0},
    "baklava":                {"calories": 428, "protein":  6.0, "carbs": 48.0, "fat": 24.0},
    "beef_carpaccio":         {"calories": 160, "protein": 20.0, "carbs":  1.0, "fat":  9.0},
    "beef_tartare":           {"calories": 174, "protein": 19.0, "carbs":  2.0, "fat": 10.0},
    "beet_salad":             {"calories":  74, "protein":  2.0, "carbs": 11.0, "fat":  3.0},
    "beignets":               {"calories": 344, "protein":  6.0, "carbs": 42.0, "fat": 17.0},
    "bibimbap":               {"calories": 490, "protein": 22.0, "carbs": 70.0, "fat": 13.0},
    "bread_pudding":          {"calories": 192, "protein":  5.5, "carbs": 30.0, "fat":  6.0},
    "breakfast_burrito":      {"calories": 214, "protein": 10.0, "carbs": 22.0, "fat":  9.5},
    "bruschetta":             {"calories": 185, "protein":  5.0, "carbs": 26.0, "fat":  7.0},

    # ── C ──────────────────────────────────────────────────────
    "caesar_salad":           {"calories": 190, "protein":  8.0, "carbs":  9.0, "fat": 14.0},
    "cannoli":                {"calories": 327, "protein":  7.0, "carbs": 37.0, "fat": 17.0},
    "caprese_salad":          {"calories": 128, "protein":  7.5, "carbs":  4.0, "fat":  9.5},
    "carrot_cake":            {"calories": 415, "protein":  4.5, "carbs": 56.0, "fat": 21.0},
    "ceviche":                {"calories":  80, "protein": 14.0, "carbs":  5.0, "fat":  1.5},
    "cheese_plate":           {"calories": 370, "protein": 22.0, "carbs":  5.0, "fat": 30.0},
    "cheesecake":             {"calories": 321, "protein":  5.5, "carbs": 25.0, "fat": 22.0},
    "chicken_curry":          {"calories": 150, "protein": 12.0, "carbs":  8.0, "fat":  7.0},
    "chicken_quesadilla":     {"calories": 247, "protein": 14.0, "carbs": 22.0, "fat": 11.0},
    "chicken_wings":          {"calories": 290, "protein": 27.0, "carbs":  0.0, "fat": 20.0},
    "chocolate_cake":         {"calories": 371, "protein":  4.5, "carbs": 50.0, "fat": 17.0},
    "chocolate_mousse":       {"calories": 213, "protein":  4.5, "carbs": 23.0, "fat": 12.0},
    "churros":                {"calories": 376, "protein":  5.0, "carbs": 50.0, "fat": 18.0},
    "clam_chowder":           {"calories":  87, "protein":  5.0, "carbs": 10.0, "fat":  3.0},
    "club_sandwich":          {"calories": 295, "protein": 18.0, "carbs": 26.0, "fat": 12.0},
    "crab_cakes":             {"calories": 180, "protein": 14.0, "carbs": 10.0, "fat":  8.5},
    "creme_brulee":           {"calories": 263, "protein":  4.5, "carbs": 25.0, "fat": 16.0},
    "croque_madame":          {"calories": 264, "protein": 14.0, "carbs": 18.0, "fat": 15.0},
    "cup_cakes":              {"calories": 360, "protein":  4.0, "carbs": 51.0, "fat": 16.0},

    # ── D ──────────────────────────────────────────────────────
    "deviled_eggs":           {"calories": 145, "protein":  9.0, "carbs":  1.5, "fat": 11.0},
    "donuts":                 {"calories": 452, "protein":  5.0, "carbs": 51.0, "fat": 25.0},
    "dumplings":              {"calories": 218, "protein":  8.0, "carbs": 29.0, "fat":  8.0},

    # ── E ──────────────────────────────────────────────────────
    "edamame":                {"calories": 121, "protein": 11.0, "carbs":  9.0, "fat":  5.0},
    "eggs_benedict":          {"calories": 245, "protein": 13.0, "carbs": 14.0, "fat": 15.0},
    "escargots":              {"calories": 172, "protein": 16.0, "carbs":  2.0, "fat": 11.0},

    # ── F ──────────────────────────────────────────────────────
    "falafel":                {"calories": 333, "protein": 13.0, "carbs": 32.0, "fat": 18.0},
    "filet_mignon":           {"calories": 227, "protein": 26.0, "carbs":  0.0, "fat": 14.0},
    "fish_and_chips":         {"calories": 270, "protein": 14.0, "carbs": 25.0, "fat": 12.0},
    "foie_gras":              {"calories": 462, "protein": 11.0, "carbs":  5.0, "fat": 45.0},
    "french_fries":           {"calories": 312, "protein":  3.4, "carbs": 41.0, "fat": 15.0},
    "french_onion_soup":      {"calories":  72, "protein":  3.5, "carbs":  9.0, "fat":  2.5},
    "french_toast":           {"calories": 228, "protein":  8.5, "carbs": 27.0, "fat": 10.0},
    "fried_calamari":         {"calories": 229, "protein": 15.0, "carbs": 16.0, "fat": 11.0},
    "fried_rice":             {"calories": 163, "protein":  3.4, "carbs": 28.0, "fat":  3.5},
    "frozen_yogurt":          {"calories": 127, "protein":  3.5, "carbs": 22.0, "fat":  3.0},

    # ── G ──────────────────────────────────────────────────────
    "garlic_bread":           {"calories": 350, "protein":  8.0, "carbs": 44.0, "fat": 16.0},
    "gnocchi":                {"calories": 131, "protein":  3.5, "carbs": 26.0, "fat":  1.5},
    "greek_salad":            {"calories": 115, "protein":  3.5, "carbs":  7.0, "fat":  9.0},
    "grilled_cheese_sandwich":{"calories": 312, "protein": 13.0, "carbs": 26.0, "fat": 17.0},
    "grilled_salmon":         {"calories": 208, "protein": 20.0, "carbs":  0.0, "fat": 13.0},
    "guacamole":              {"calories": 150, "protein":  2.0, "carbs":  9.0, "fat": 13.0},
    "gyoza":                  {"calories": 219, "protein":  8.5, "carbs": 29.0, "fat":  8.0},

    # ── H ──────────────────────────────────────────────────────
    "hamburger":              {"calories": 295, "protein": 17.0, "carbs": 24.0, "fat": 14.0},
    "hot_and_sour_soup":      {"calories":  50, "protein":  4.0, "carbs":  6.0, "fat":  1.5},
    "hot_dog":                {"calories": 290, "protein": 11.0, "carbs": 23.0, "fat": 17.0},
    "huevos_rancheros":       {"calories": 183, "protein":  9.0, "carbs": 16.0, "fat":  9.0},
    "hummus":                 {"calories": 177, "protein":  8.0, "carbs": 14.0, "fat": 10.0},

    # ── I ──────────────────────────────────────────────────────
    "ice_cream":              {"calories": 207, "protein":  3.5, "carbs": 24.0, "fat": 11.0},

    # ── L ──────────────────────────────────────────────────────
    "lasagna":                {"calories": 135, "protein":  8.0, "carbs": 14.0, "fat":  5.0},
    "lobster_bisque":         {"calories":  84, "protein":  5.0, "carbs":  8.0, "fat":  3.5},
    "lobster_roll_sandwich":  {"calories": 222, "protein": 14.0, "carbs": 20.0, "fat":  9.0},

    # ── M ──────────────────────────────────────────────────────
    "macaroni_and_cheese":    {"calories": 164, "protein":  6.5, "carbs": 21.0, "fat":  6.0},
    "macarons":               {"calories": 381, "protein":  5.0, "carbs": 64.0, "fat": 12.0},
    "miso_soup":              {"calories":  40, "protein":  3.0, "carbs":  5.0, "fat":  1.0},
    "mussels":                {"calories":  86, "protein": 12.0, "carbs":  4.0, "fat":  2.0},

    # ── N ──────────────────────────────────────────────────────
    "nachos":                 {"calories": 306, "protein":  7.5, "carbs": 32.0, "fat": 17.0},

    # ── O ──────────────────────────────────────────────────────
    "omelette":               {"calories": 154, "protein": 11.0, "carbs":  1.6, "fat": 12.0},
    "onion_rings":            {"calories": 411, "protein":  5.0, "carbs": 44.0, "fat": 24.0},
    "oysters":                {"calories":  69, "protein":  8.0, "carbs":  4.0, "fat":  2.5},

    # ── P ──────────────────────────────────────────────────────
    "pad_thai":               {"calories": 215, "protein": 11.0, "carbs": 30.0, "fat":  6.0},
    "paella":                 {"calories": 169, "protein": 12.0, "carbs": 20.0, "fat":  4.0},
    "pancakes":               {"calories": 227, "protein":  6.0, "carbs": 28.0, "fat": 10.0},
    "panna_cotta":            {"calories": 168, "protein":  3.5, "carbs": 20.0, "fat":  8.5},
    "peking_duck":            {"calories": 337, "protein": 19.0, "carbs":  0.0, "fat": 29.0},
    "pho":                    {"calories":  68, "protein":  5.1, "carbs":  9.8, "fat":  1.2},
    "pizza":                  {"calories": 266, "protein": 11.0, "carbs": 33.0, "fat": 10.0},
    "pork_chop":              {"calories": 231, "protein": 25.0, "carbs":  0.0, "fat": 14.0},
    "poutine":                {"calories": 260, "protein":  8.0, "carbs": 30.0, "fat": 13.0},
    "prime_rib":              {"calories": 306, "protein": 24.0, "carbs":  0.0, "fat": 23.0},
    "pulled_pork_sandwich":   {"calories": 240, "protein": 16.0, "carbs": 22.0, "fat":  9.0},

    # ── R ──────────────────────────────────────────────────────
    "ramen":                  {"calories": 436, "protein": 21.0, "carbs": 57.0, "fat": 14.0},
    "ravioli":                {"calories": 186, "protein":  8.5, "carbs": 24.0, "fat":  6.5},
    "red_velvet_cake":        {"calories": 385, "protein":  4.0, "carbs": 55.0, "fat": 17.0},
    "risotto":                {"calories": 166, "protein":  4.5, "carbs": 25.0, "fat":  5.5},

    # ── S ──────────────────────────────────────────────────────
    "samosa":                 {"calories": 308, "protein":  6.0, "carbs": 32.0, "fat": 17.0},
    "sashimi":                {"calories": 130, "protein": 22.0, "carbs":  0.0, "fat":  4.5},
    "scallops":               {"calories":  88, "protein": 17.0, "carbs":  3.5, "fat":  0.8},
    "seaweed_salad":          {"calories":  45, "protein":  2.0, "carbs":  8.0, "fat":  0.5},
    "shrimp_and_grits":       {"calories": 158, "protein": 11.0, "carbs": 16.0, "fat":  5.5},
    "spaghetti_bolognese":    {"calories": 141, "protein":  8.0, "carbs": 16.0, "fat":  4.5},
    "spaghetti_carbonara":    {"calories": 200, "protein":  9.0, "carbs": 23.0, "fat":  8.0},
    "spring_rolls":           {"calories": 153, "protein":  3.9, "carbs": 21.0, "fat":  6.3},
    "steak":                  {"calories": 271, "protein": 26.0, "carbs":  0.0, "fat": 18.0},
    "strawberry_shortcake":   {"calories": 254, "protein":  3.5, "carbs": 38.0, "fat": 10.0},
    "sushi":                  {"calories": 150, "protein":  9.0, "carbs": 18.0, "fat":  4.0},

    # ── T ──────────────────────────────────────────────────────
    "tacos":                  {"calories": 226, "protein": 11.0, "carbs": 18.0, "fat": 12.0},
    "takoyaki":               {"calories": 211, "protein":  8.0, "carbs": 25.0, "fat":  9.0},
    "tiramisu":               {"calories": 240, "protein":  5.0, "carbs": 27.0, "fat": 13.0},
    "tuna_tartare":           {"calories": 108, "protein": 18.0, "carbs":  2.0, "fat":  3.5},

    # ── W ──────────────────────────────────────────────────────
    "waffles":                {"calories": 291, "protein":  8.0, "carbs": 37.0, "fat": 13.0},
}

# Đảm bảo tất cả 101 class đều có trong fallback
assert len(NUTRITION_FALLBACK_PER_100G) == 101, (
    f"Expected 101 entries, got {len(NUTRITION_FALLBACK_PER_100G)}"
)

_DEFAULT_NUTRITION = {"calories": 200, "protein": 10.0, "carbs": 25.0, "fat": 8.0}


class NutritionLookup:
    OPENFOODFACTS_URL = "https://world.openfoodfacts.org/cgi/search.pl"
    USDA_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"
    USDA_API_KEY = "DEMO_KEY"

    async def lookup(self, food_label: str, grams: float = 100.0) -> dict:
        """
        Tra cứu macro theo label từ Food101.
        Thứ tự ưu tiên: OpenFoodFacts → USDA → Static fallback
        """
        query = food_label.replace("_", " ")
        ratio = grams / 100.0

        nutrition = (
            await self._try_openfoodfacts(query)
            or await self._try_usda(query)
            or self._static_fallback(food_label)
        )

        return {
            "calories": round(nutrition["calories"] * ratio, 1),
            "protein":  round(nutrition["protein"] * ratio, 1),
            "carbs":    round(nutrition["carbs"] * ratio, 1),
            "fat":      round(nutrition["fat"] * ratio, 1),
            "per_100g": {
                "calories": nutrition["calories"],
                "protein":  nutrition["protein"],
                "carbs":    nutrition["carbs"],
                "fat":      nutrition["fat"],
            },
            "source":   nutrition.get("_source", "fallback"),
        }

    async def _try_openfoodfacts(self, query: str) -> Optional[dict]:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(self.OPENFOODFACTS_URL, params={
                    "search_terms":  query,
                    "search_simple": 1,
                    "action":        "process",
                    "json":          1,
                    "page_size":     3,
                    "fields":        "product_name,nutriments,nutrition_grades",
                })

            data = resp.json()
            products = data.get("products", []) if isinstance(data, dict) else []
            if not products:
                return None

            for p in products:
                n = p.get("nutriments", {})
                cal = n.get("energy-kcal_100g") or n.get("energy-kcal")
                if cal and float(cal) > 0:
                    return {
                        "calories": float(cal),
                        "protein":  float(n.get("proteins_100g") or 0),
                        "carbs":    float(n.get("carbohydrates_100g") or 0),
                        "fat":      float(n.get("fat_100g") or 0),
                        "_source":  "openfoodfacts",
                    }
            return None
        except Exception as e:
            print(f"[NutritionLookup] OpenFoodFacts error: {e}")
            return None

    async def _try_usda(self, query: str) -> Optional[dict]:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(self.USDA_URL, params={
                    "query":    query,
                    "api_key":  self.USDA_API_KEY,
                    "pageSize": 1,
                    "dataType": "SR Legacy,Foundation",
                })

            data = resp.json()
            foods = data.get("foods", []) if isinstance(data, dict) else []
            if not foods:
                return None

            nutrients = {
                n["nutrientName"]: n["value"]
                for n in foods[0].get("foodNutrients", [])
            }

            cal = (
                nutrients.get("Energy (Atwater General Factors)")
                or nutrients.get("Energy (Atwater Specific Factors)")
                or nutrients.get("Energy")
            )

            # Nếu > 900 khả năng là kJ → convert sang kcal
            if cal and cal > 900:
                cal = cal / 4.184

            if not cal:
                return None

            return {
                "calories": float(cal),
                "protein":  float(nutrients.get("Protein", 0)),
                "carbs":    float(nutrients.get("Carbohydrate, by difference", 0)),
                "fat":      float(nutrients.get("Total lipid (fat)", 0)),
                "_source":  "usda",
            }
        except Exception as e:
            print(f"[NutritionLookup] USDA error: {e}")
            return None

    def _static_fallback(self, food_label: str) -> dict:
        base = NUTRITION_FALLBACK_PER_100G.get(food_label, _DEFAULT_NUTRITION)
        return {**base, "_source": "fallback"}
