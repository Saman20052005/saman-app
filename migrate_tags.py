# [File: migrate_tags.py]
from pymongo import MongoClient
import certifi  # <--- THÊM DÒNG NÀY

# Import logic ngưỡng
try:
    from backend.app.core.constants import Thresholds, FoodTag
except ImportError:
    class Thresholds:
        HIGH_CARB = 40.0
        HIGH_FAT = 20.0
        HIGH_PROTEIN = 15.0
    class FoodTag:
        HIGH_CARB = "HIGH_CARB"
        HIGH_FAT = "HIGH_FAT"
        HIGH_PROTEIN = "HIGH_PROTEIN"

# 👇 Thay dòng này bằng link Production của bạn
# MONGO_URI = "mongodb://localhost:27017" 
# Lưu ý: Đừng để lộ password khi chụp ảnh màn hình
MONGO_URI = "mongodb://localhost:27017"

DB_NAME = "saman_fitness" 
COLLECTION_NAME = "foods"

def generate_tags(p, c, f):
    tags = []
    if p >= Thresholds.HIGH_PROTEIN: tags.append(FoodTag.HIGH_PROTEIN)
    if c >= Thresholds.HIGH_CARB: tags.append(FoodTag.HIGH_CARB)
    if f >= Thresholds.HIGH_FAT: tags.append(FoodTag.HIGH_FAT)
    return tags

def migrate():
    # 🔥 FIX LỖI SSL: Thêm tlsCAFile=certifi.where()
    client = MongoClient(MONGO_URI, tlsCAFile=certifi.where())
    
    db = client[DB_NAME]
    collection = db[COLLECTION_NAME]

    print("⏳ Đang quét toàn bộ món ăn để cập nhật Tags (Production)...")
    
    cursor = collection.find({})
    count = 0
    updated = 0

    from pymongo import UpdateOne
    bulk_ops = []

    for doc in cursor:
        count += 1
        p = float(doc.get("protein", 0) or 0)
        c = float(doc.get("carbs", 0) or 0)
        f = float(doc.get("fat", 0) or 0)
        
        new_tags = generate_tags(p, c, f)
        
        old_tags = doc.get("tags")
        if old_tags != new_tags:
            bulk_ops.append(
                UpdateOne({"_id": doc["_id"]}, {"$set": {"tags": new_tags}})
            )
            updated += 1
        
        if len(bulk_ops) >= 500:
            collection.bulk_write(bulk_ops)
            bulk_ops = []
            print(f"   -> Đã xử lý {count} món...")

    if bulk_ops:
        collection.bulk_write(bulk_ops)

    print(f"✅ HOÀN TẤT! Đã cập nhật Tags cho {updated} món ăn cũ trên Cloud.")

if __name__ == "__main__":
    migrate()