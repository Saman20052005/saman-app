# [File: check_db.py]
from pymongo import MongoClient
import certifi

# Thay bằng URI thật của bạn
MONGO_URI = "mongodb://localhost:27017"
DB_NAME = "saman_fitness" 
COLLECTION_NAME = "foods"

def check():
    try:
        client = MongoClient(MONGO_URI, tlsCAFile=certifi.where())
        db = client[DB_NAME]
        collection = db[COLLECTION_NAME]
        
        count = collection.count_documents({})
        
        print(f"📡 Đang kết nối tới DB: {DB_NAME}")
        print(f"📊 Tổng số món ăn tìm thấy: {count}")
        
        if count > 0:
            sample = collection.find_one()
            print("📝 Mẫu dữ liệu đầu tiên:")
            print(f"   - Tên: {sample.get('name')}")
            print(f"   - Tags: {sample.get('tags')}")
        else:
            print("⚠️ Database đang RỖNG!")

    except Exception as e:
        print(f"❌ Lỗi: {e}")

if __name__ == "__main__":
    check()