#!/usr/bin/env python3
"""
Simple MongoDB Database Inspection using Backend Connection
"""
import sys
from pathlib import Path

# Add backend directory to path
backend_path = Path(__file__).parent / "backend"
sys.path.insert(0, str(backend_path))

try:
    from backend.app.database import users_collection, foods_collection, nutrition_collection, db
    from pymongo import MongoClient
    
    print("🔌 Using existing backend database connection...")
    
    if users_collection is None or foods_collection is None:
        print("❌ Database collections not available - check backend connection")
        sys.exit(1)
    
    print("✅ Database connection established!")
    
    # Inspect users collection
    print("\n" + "="*50)
    print("👤 USERS COLLECTION INSPECTION")
    print("="*50)
    
    # Find specific user
    target_email = "ann2552988@gmail.com"
    print(f"\n🔍 Searching for user: {target_email}")
    user = users_collection.find_one({"email": target_email})
    
    if user:
        print("✅ User found!")
        print(f"   Email: {user.get('email')}")
        print(f"   Full Name: {user.get('full_name')}")
        print(f"   Created: {user.get('created_at')}")
        
        # Check profile data
        profile = user.get('profile', {})
        if profile:
            print(f"   Profile Data:")
            for key, value in profile.items():
                print(f"     {key}: {value}")
        
        # Check health stats
        health_stats = user.get('health_stats', {})
        if health_stats:
            print(f"   Health Stats:")
            for key, value in health_stats.items():
                print(f"     {key}: {value}")
    else:
        print("❌ User not found!")
    
    # Count total users
    total_users = users_collection.count_documents({})
    print(f"\n📊 Total users in database: {total_users}")
    
    # Show all users (limited)
    print("\n👥 All users (max 10):")
    all_users = list(users_collection.find().limit(10))
    for i, user in enumerate(all_users, 1):
        print(f"   {i}. {user.get('email')} - {user.get('full_name', 'No name')}")
    
    # Inspect foods collection
    print("\n" + "="*50)
    print("🍔 FOODS COLLECTION INSPECTION")
    print("="*50)
    
    # Count total foods
    total_foods = foods_collection.count_documents({})
    print(f"\n📊 Total foods in database: {total_foods}")
    
    # Get first 5 foods
    print("\n🔍 First 5 foods:")
    foods = list(foods_collection.find().limit(5))
    
    for i, food in enumerate(foods, 1):
        print(f"\n   Food {i}:")
        print(f"     ID: {food.get('_id')}")
        print(f"     Name: {food.get('name')}")
        print(f"     Calories: {food.get('calories')}")
        print(f"     Protein: {food.get('protein')}")
        print(f"     Carbs: {food.get('carbs')}")
        print(f"     Fat: {food.get('fat')}")
        print(f"     Tags: {food.get('tags', [])}")
        print(f"     Group: {food.get('group', 'N/A')}")
    
    # Check collections
    print("\n" + "="*50)
    print("📚 ALL COLLECTIONS")
    print("="*50)
    
    if db is not None:
        collections = db.list_collection_names()
        for collection in sorted(collections):
            count = db[collection].count_documents({})
            print(f"   {collection}: {count} documents")
    else:
        print("❌ Database not available")
    
    print("\n✅ Database inspection completed!")
    
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
