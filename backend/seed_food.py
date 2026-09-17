import requests
import time
from pymongo import MongoClient
import certifi # 👈 QUAN TRỌNG: Để fix lỗi SSL trên Mac

# --- CẤU HÌNH PRODUCTION ---
# 👇 Dán link MongoDB Atlas của bạn vào đây (Link thật)
MONGO_URI = "mongodb+srv://health_ai_user:tj4oqxasH2obPX7Z@nguyenvanan.ezicpn0.mongodb.net/?appName=NguyenVanAn"

DB_NAME = "saman_fitness" 
COLLECTION_NAME = "foods"
TARGET_PER_GROUP = 1000 # Số lượng món mỗi nhóm

# Import Thresholds từ constants (để tự động gắn Tags ngay khi Seed)
try:
    from backend.app.core.constants import Thresholds, FoodTag
except ImportError:
    # Fallback phòng hờ
    class Thresholds:
        HIGH_CARB = 40.0
        HIGH_FAT = 20.0
        HIGH_PROTEIN = 15.0
    class FoodTag:
        HIGH_CARB = "HIGH_CARB"
        HIGH_FAT = "HIGH_FAT"
        HIGH_PROTEIN = "HIGH_PROTEIN"

GROUP_TAGS = {
    "Protein": ["meats", "seafood", "fishes", "chicken", "beef", "eggs"],
    "Carb": ["rice", "noodles", "pasta", "breads", "potatoes", "cereals"],
    "Fat": ["oils", "nuts", "butter", "cheeses"],
    "Vitamin": ["fruits", "vegetables", "salads", "legumes"]
}

def get_db_collection():
    # 🔥 THÊM tlsCAFile=certifi.where() ĐỂ FIX LỖI SSL
    client = MongoClient(MONGO_URI, tlsCAFile=certifi.where())
    db = client[DB_NAME]
    return db[COLLECTION_NAME]

def normalize_text(text):
    return text.lower().strip() if text else ""

def generate_tags_for_food(nutri):
    tags = []
    p = float(nutri.get("proteins_100g", 0) or 0)
    c = float(nutri.get("carbohydrates_100g", 0) or 0)
    f = float(nutri.get("fat_100g", 0) or 0)
    
    if p >= Thresholds.HIGH_PROTEIN: tags.append(FoodTag.HIGH_PROTEIN)
    if c >= Thresholds.HIGH_CARB: tags.append(FoodTag.HIGH_CARB)
    if f >= Thresholds.HIGH_FAT: tags.append(FoodTag.HIGH_FAT)
    return tags

def seed_data():
    collection = get_db_collection()
    
    print("⚙️ Đang tạo index trên Cloud...")
    collection.create_index("name")
    collection.create_index("group")
    collection.create_index("tags") 
    
    existing_names = set()
    # Tải danh sách tên đã có để tránh trùng (nếu chạy lại)
    for doc in collection.find({}, {"name": 1}):
        if "name" in doc: existing_names.add(normalize_text(doc["name"]))
    print(f"✅ Đã biết {len(existing_names)} món trên Cloud.")

    for group_name, tags in GROUP_TAGS.items():
        current_count = collection.count_documents({"group": group_name})
        print(f"\n🚀 GROUP: {group_name} (Hiện có: {current_count})")
        
        page = 1
        tag_index = 0
        
        while current_count < TARGET_PER_GROUP:
            current_tag = tags[tag_index % len(tags)]
            url = "https://world.openfoodfacts.org/cgi/search.pl"
            params = {
                "action": "process",
                "tagtype_0": "categories",
                "tag_contains_0": "contains",
                "tag_0": current_tag,
                "page_size": 50,
                "page": page,
                "json": 1,
                "fields": "product_name,product_name_vi,nutriments,code"
            }

            try:
                print(f"   ...Page {page} tag '{current_tag}'...")
                resp = requests.get(url, params=params, timeout=30)
                data = resp.json()
                products = data.get("products", [])

                if not products:
                    tag_index += 1
                    page = 1
                    if tag_index >= len(tags): break
                    continue

                new_items = []
                for p in products:
                    name_vi = p.get("product_name_vi")
                    name_en = p.get("product_name")
                    final_name = name_vi if (name_vi and len(name_vi) > 0) else name_en
                    
                    if not final_name: continue
                    if normalize_text(final_name) in existing_names: continue

                    nutri = p.get("nutriments", {})
                    calories = nutri.get("energy-kcal_100g", 0)
                    if not calories:
                        kj = nutri.get("energy-kj_100g", 0)
                        if kj: calories = int(kj / 4.184)

                    if not calories or calories <= 0: continue

                    # Generate Tags & Insert
                    food_tags = generate_tags_for_food(nutri)
                    item = {
                        "name": final_name,
                        "group": group_name,
                        "calories": int(calories),
                        "protein": float(nutri.get("proteins_100g", 0) or 0),
                        "carbs": float(nutri.get("carbohydrates_100g", 0) or 0),
                        "fat": float(nutri.get("fat_100g", 0) or 0),
                        "unit": "g",
                        "standard_serving": 100,
                        "tags": food_tags, # Có luôn Tags
                        "is_verified": False
                    }
                    
                    new_items.append(item)
                    existing_names.add(normalize_text(final_name))

                if new_items:
                    collection.insert_many(new_items)
                    current_count += len(new_items)
                    print(f"      -> +{len(new_items)} món. Tổng: {current_count}")
                
                page += 1
                time.sleep(1)

            except Exception as e:
                print(f"   ❌ Lỗi: {e}. Skip page.")
                page += 1
                time.sleep(5)

    print("\n✅ SEEDING PRODUCTION HOÀN TẤT!")

if __name__ == "__main__":
    seed_data()