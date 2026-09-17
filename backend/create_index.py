from pymongo import MongoClient
import os

# Kết nối DB (Sử dụng đúng tên DB trong file database.py của bạn)
MONGO_URI = "mongodb://localhost:27017"
DB_NAME = "health_ai_db" # <--- Kiểm tra kỹ tên này!

def create_indexes():
    try:
        client = MongoClient(MONGO_URI)
        db = client[DB_NAME]
        foods = db["foods"]
        
        print(f"🔌 Đang kết nối tới DB: {DB_NAME}...")
        
        # 1. Tạo Text Index cho trường 'name' (Để tìm kiếm "phở" ra "Phở bò")
        print("⏳ Đang tạo Text Index cho 'name'...")
        foods.create_index([("name", "text")])
        
        # 2. (Tuỳ chọn) Tạo Index cho 'group' nếu sau này bạn muốn lọc theo nhóm (Protein, Carb...)
        print("⏳ Đang tạo Index cho 'group'...")
        foods.create_index("group")

        print("✅ ĐÃ TẠO INDEX THÀNH CÔNG! Database đã sẵn sàng.")
        
    except Exception as e:
        print(f"❌ Lỗi: {e}")

if __name__ == "__main__":
    create_indexes()