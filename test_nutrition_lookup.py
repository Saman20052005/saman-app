# test_nutrition_lookup.py — chạy local, không cần model
import asyncio
import sys
import os

# Add the backend directory to the Python path
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)
sys.path.insert(0, os.path.join(current_dir, 'app', 'services'))

# Import directly to avoid __init__.py issues
import nutrition_lookup

async def test():
    lookup = nutrition_lookup.NutritionLookup()
    test_labels = ["pizza", "sushi", "hamburger", "pho", "fried_rice"]
    
    print("Testing NutritionLookup with OpenFoodFacts API...")
    print("=" * 50)
    
    for label in test_labels:
        print(f"\n🔍 Looking up: {label}")
        result = await lookup.lookup(label, grams=100)
        
        if "error" in result:
            print(f"❌ {label}: {result['error']}")
        else:
            print(f"✅ {label}:")
            print(f"   Product: {result.get('product_name', 'N/A')}")
            print(f"   Calories: {result.get('calories', 0)} kcal")
            print(f"   Protein: {result.get('protein', 0)}g")
            print(f"   Carbs: {result.get('carbs', 0)}g")
            print(f"   Fat: {result.get('fat', 0)}g")
            print(f"   Source: {result.get('source', 'N/A')}")
            
            # Show original per 100g values for comparison
            original = result.get('original_per_100g', {})
            if original:
                print(f"   Original (per 100g):")
                print(f"     Calories: {original.get('calories', 0)} kcal")
                print(f"     Protein: {original.get('protein', 0)}g")
                print(f"     Carbs: {original.get('carbs', 0)}g")
                print(f"     Fat: {original.get('fat', 0)}g")

if __name__ == "__main__":
    asyncio.run(test())
