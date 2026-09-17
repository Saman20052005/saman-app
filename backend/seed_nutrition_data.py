#!/usr/bin/env python3
"""
Script to seed nutrition data for MongoDB food database
"""

import os
import sys
import certifi
from dotenv import load_dotenv
from pymongo import MongoClient

# Load environment variables
load_dotenv()

# MongoDB configuration
MONGO_URI = os.getenv("MONGO_URI") or os.getenv("MONGODB_URI") or "mongodb://localhost:27017"
DB_NAME = os.getenv("DB_NAME", "saman_fitness")

# Nutrition data for common foods
foods = [
    {
        "name": "apple_pie",
        "calories": 237,
        "protein": 1.9,
        "carbs": 34,
        "fat": 11,
        "fiber": 1.7,
        "sugar": 15,
        "description": "Bánh táo nướng truyền thống với vỏ bánh giòn và nhân táo ngọt.",
        "category": "dessert",
        "serving_size": "1 slice (1/8 of 9-inch pie)"
    },
    {
        "name": "baby_back_ribs",
        "calories": 290,
        "protein": 22,
        "carbs": 0,
        "fat": 22,
        "fiber": 0,
        "sugar": 0,
        "description": "Sườn heo nướng BBQ mềm và ngọt.",
        "category": "meat",
        "serving_size": "3 ribs (85g)"
    },
    {
        "name": "pho",
        "calories": 350,
        "protein": 20,
        "carbs": 50,
        "fat": 8,
        "fiber": 2,
        "sugar": 3,
        "description": "Phở bò Việt Nam truyền thống với bánh phở, thịt bò và nước dùng thơm.",
        "category": "soup",
        "serving_size": "1 bowl (500ml)"
    },
    {
        "name": "pizza",
        "calories": 285,
        "protein": 12,
        "carbs": 36,
        "fat": 10,
        "fiber": 2,
        "sugar": 4,
        "description": "Pizza phô mai với sốt cà chua và topping.",
        "category": "fast_food",
        "serving_size": "1 slice (107g)"
    },
    {
        "name": "hamburger",
        "calories": 354,
        "protein": 20,
        "carbs": 30,
        "fat": 17,
        "fiber": 2,
        "sugar": 6,
        "description": "Burger bò với bánh mì, rau diếp và cà chua.",
        "category": "fast_food",
        "serving_size": "1 sandwich (197g)"
    },
    {
        "name": "sushi",
        "calories": 200,
        "protein": 9,
        "carbs": 38,
        "fat": 1,
        "fiber": 2,
        "sugar": 2,
        "description": "Sushi cá hồi với cơm và rong biển.",
        "category": "japanese",
        "serving_size": "6 pieces (150g)"
    },
    {
        "name": "ramen",
        "calories": 380,
        "protein": 15,
        "carbs": 52,
        "fat": 12,
        "fiber": 3,
        "sugar": 4,
        "description": "Mì ramen Nhật Bản với nước dùng đậm đà.",
        "category": "japanese",
        "serving_size": "1 bowl (400ml)"
    },
    {
        "name": "tacos",
        "calories": 250,
        "protein": 13,
        "carbs": 25,
        "fat": 12,
        "fiber": 4,
        "sugar": 2,
        "description": "Tacos Mexico với thịt bò, rau và salsa.",
        "category": "mexican",
        "serving_size": "2 tacos (150g)"
    },
    {
        "name": "pad_thai",
        "calories": 320,
        "protein": 12,
        "carbs": 45,
        "fat": 10,
        "fiber": 3,
        "sugar": 8,
        "description": "Mì xào Thái Lan với tôm, đậu phộng và chanh.",
        "category": "thai",
        "serving_size": "1 plate (300g)"
    },
    {
        "name": "chicken_curry",
        "calories": 280,
        "protein": 25,
        "carbs": 15,
        "fat": 15,
        "fiber": 3,
        "sugar": 5,
        "description": "Cà ri gà Ấn Độ với sốt cô-cô-nút và gia vị.",
        "category": "indian",
        "serving_size": "1 cup (240ml)"
    },
    {
        "name": "lasagna",
        "calories": 377,
        "protein": 18,
        "carbs": 30,
        "fat": 20,
        "fiber": 3,
        "sugar": 6,
        "description": "Lasagna Ý với phô mai, thịt và sốt cà chua.",
        "category": "italian",
        "serving_size": "1 piece (280g)"
    },
    {
        "name": "spaghetti_bolognese",
        "calories": 420,
        "protein": 20,
        "carbs": 55,
        "fat": 15,
        "fiber": 4,
        "sugar": 8,
        "description": "Mì spaghetti Ý với sốt thịt bolognese.",
        "category": "italian",
        "serving_size": "1 plate (400g)"
    },
    {
        "name": "caesar_salad",
        "calories": 180,
        "protein": 8,
        "carbs": 12,
        "fat": 11,
        "fiber": 3,
        "sugar": 2,
        "description": "Salad Caesar với xà lách, bánh mì giòn và sốt Caesar.",
        "category": "salad",
        "serving_size": "1 bowl (150g)"
    },
    {
        "name": "greek_salad",
        "calories": 150,
        "protein": 6,
        "carbs": 10,
        "fat": 10,
        "fiber": 4,
        "sugar": 6,
        "description": "Salad Hy Lạp với dưa chuột, cà chua, ô-liu và phô mai feta.",
        "category": "salad",
        "serving_size": "1 bowl (200g)"
    },
    {
        "name": "ice_cream",
        "calories": 207,
        "protein": 3.5,
        "carbs": 24,
        "fat": 11,
        "fiber": 0.7,
        "sugar": 21,
        "description": "Kem vani mềm mịn.",
        "category": "dessert",
        "serving_size": "1/2 cup (66g)"
    },
    {
        "name": "chocolate_cake",
        "calories": 235,
        "protein": 2.5,
        "carbs": 35,
        "fat": 10,
        "fiber": 1.5,
        "sugar": 25,
        "description": "Bánh sô-cô-la bông xốp.",
        "category": "dessert",
        "serving_size": "1 slice (64g)"
    },
    {
        "name": "pancakes",
        "calories": 220,
        "protein": 6,
        "carbs": 40,
        "fat": 4,
        "fiber": 1,
        "sugar": 8,
        "description": "Bánh kếp Mỹ với si-rô cây phong.",
        "category": "breakfast",
        "serving_size": "2 pancakes (120g)"
    },
    {
        "name": "french_fries",
        "calories": 312,
        "protein": 3.4,
        "carbs": 41,
        "fat": 15,
        "fiber": 3.8,
        "sugar": 0.3,
        "description": "Khoai tây chiên giòn.",
        "category": "fast_food",
        "serving_size": "1 serving (85g)"
    },
    {
        "name": "grilled_salmon",
        "calories": 367,
        "protein": 40,
        "carbs": 0,
        "fat": 22,
        "fiber": 0,
        "sugar": 0,
        "description": "Cá hồi nướng với chanh và thảo mộc.",
        "category": "seafood",
        "serving_size": "1 fillet (170g)"
    },
    {
        "name": "shrimp_and_grits",
        "calories": 320,
        "protein": 20,
        "carbs": 35,
        "fat": 12,
        "fiber": 2,
        "sugar": 3,
        "description": "Tôm và bột ngô kiểu miền Nam nước Mỹ.",
        "category": "seafood",
        "serving_size": "1 plate (300g)"
    }
]

def connect_to_mongodb():
    """Connect to MongoDB using environment variables"""
    try:
        # Print connection info (hide password)
        safe_uri = MONGO_URI.split("@")[-1] if "@" in MONGO_URI else MONGO_URI
        print(f"🔌 Connecting to MongoDB: {safe_uri}")
        print(f"📂 Database Name: {DB_NAME}")
        
        # Connect with SSL for cloud, without SSL for localhost
        if "localhost" in MONGO_URI or "127.0.0.1" in MONGO_URI:
            print("⚠️  Detected Localhost. Disabling SSL.")
            client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        else:
            print("☁️  Detected Cloud DB. Enabling SSL.")
            client = MongoClient(MONGO_URI, tlsCAFile=certifi.where(), serverSelectionTimeoutMS=5000)
        
        # Test connection
        client.admin.command('ping')
        print("✅ Successfully connected to MongoDB!")
        
        return client[DB_NAME]
        
    except Exception as e:
        print(f"❌ MongoDB Connection Error: {e}")
        raise

def seed_nutrition_data():
    """Seed nutrition data to MongoDB"""
    try:
        # Connect to database
        db = connect_to_mongodb()
        foods_collection = db["foods"]
        
        print(f"\n📦 Seeding {len(foods)} food items...")
        
        # Insert foods with upsert (update if exists, insert if not)
        inserted_count = 0
        updated_count = 0
        
        for food in foods:
            # Check if food already exists
            existing = foods_collection.find_one({"name": food["name"]})
            
            if existing:
                # Update existing food
                foods_collection.update_one(
                    {"name": food["name"]},
                    {"$set": food}
                )
                updated_count += 1
                print(f"  📝 Updated: {food['name']}")
            else:
                # Insert new food
                foods_collection.insert_one(food)
                inserted_count += 1
                print(f"  ➕ Added: {food['name']}")
        
        print(f"\n✅ Seeding completed!")
        print(f"   - New foods added: {inserted_count}")
        print(f"   - Existing foods updated: {updated_count}")
        print(f"   - Total foods in database: {foods_collection.count_documents({})}")
        
        # Show sample data
        print(f"\n📋 Sample data:")
        sample = foods_collection.find_one()
        if sample:
            print(f"   Example: {sample['name']} - {sample['calories']} cal")
        
    except Exception as e:
        print(f"❌ Error seeding data: {e}")
        raise

def main():
    """Main function"""
    print("=" * 50)
    print("NUTRITION DATA SEEDING SCRIPT")
    print("=" * 50)
    
    try:
        seed_nutrition_data()
        print("\n🎉 All operations completed successfully!")
        
    except KeyboardInterrupt:
        print("\n⚠️  Operation cancelled by user")
        sys.exit(1)
        
    except Exception as e:
        print(f"\n❌ Script failed: {e}")
        sys.exit(1)
    
    finally:
        print("=" * 50)

if __name__ == "__main__":
    main()
