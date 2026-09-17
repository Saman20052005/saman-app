#!/usr/bin/env python3
"""
MongoDB Database Inspection Script
Connects to MongoDB Atlas and inspects user and food data
"""
import os
import sys
from pathlib import Path

# Add backend directory to path
backend_path = Path(__file__).parent / "backend"
sys.path.insert(0, str(backend_path))

try:
    from dotenv import load_dotenv
    from pymongo import MongoClient
    
    # Load environment variables
    load_dotenv()
    
    # MongoDB connection
    MONGO_URI = os.getenv("MONGO_URI") or os.getenv("MONGODB_URI") or "mongodb+srv://nguyenvanan.ezicpn0.mongodb.net"
    DB_NAME = os.getenv("DB_NAME", "saman_fitness")
    
    print("🔌 Connecting to MongoDB...")
    print(f"📂 Database: {DB_NAME}")
    
    # Connect to MongoDB
    client = MongoClient(MONGO_URI)
    db = client[DB_NAME]
    
    # Test connection
    client.admin.command('ping')
    print("✅ Successfully connected to MongoDB!")
    
    # Inspect users collection
    print("\n" + "="*50)
    print("👤 USERS COLLECTION INSPECTION")
    print("="*50)
    
    users_collection = db["users"]
    
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
            print(f"   Profile: {profile}")
        
        # Check health stats
        health_stats = user.get('health_stats', {})
        if health_stats:
            print(f"   Health Stats: {health_stats}")
    else:
        print("❌ User not found!")
    
    # Count total users
    total_users = users_collection.count_documents({})
    print(f"\n📊 Total users in database: {total_users}")
    
    # Inspect foods collection
    print("\n" + "="*50)
    print("🍔 FOODS COLLECTION INSPECTION")
    print("="*50)
    
    foods_collection = db["foods"]
    
    # Count total foods
    total_foods = foods_collection.count_documents({})
    print(f"\n📊 Total foods in database: {total_foods}")
    
    # Get first 5 foods
    print("\n🔍 First 5 foods:")
    foods = list(foods_collection.find().limit(5))
    
    for i, food in enumerate(foods, 1):
        print(f"\n   Food {i}:")
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
    
    collections = db.list_collection_names()
    for collection in sorted(collections):
        count = db[collection].count_documents({})
        print(f"   {collection}: {count} documents")
    
    # Check indexes
    print("\n" + "="*50)
    print("🔍 INDEXES")
    print("="*50)
    
    if "foods" in collections:
        indexes = foods_collection.list_indexes()
        print("\nFoods collection indexes:")
        for index in indexes:
            print(f"   {index['name']}: {index.get('key', {})}")
    
    if "users" in collections:
        indexes = users_collection.list_indexes()
        print("\nUsers collection indexes:")
        for index in indexes:
            print(f"   {index['name']}: {index.get('key', {})}")
    
    print("\n✅ Database inspection completed!")
    
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
finally:
    if 'client' in locals():
        client.close()
        print("\n🔌 MongoDB connection closed")
