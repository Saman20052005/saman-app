# [File: routers/chat.py]
from typing import Optional, Dict, List, Any
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
import os
import logging

# 🔥 IMPORT REPOSITORY (Thay vì gọi DB trực tiếp)
from backend.app.repositories.user_repository import UserRepository

# Import Auth
from backend.auth_utils import verify_token

router = APIRouter(prefix="/api/chat", tags=["AI Chat"])

# Khởi tạo Repo
user_repo = UserRepository()

# 🔑 KEY CỦA BẠN (Nên đưa vào biến môi trường nếu có thể)
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

def get_ai_reply(prompt: str) -> str:
    """Hàm wrapper để gọi AI: Thử Gemini trước, fallback sang OpenAI."""
    # 1. Thử Gemini
    if GEMINI_API_KEY:
        try:
            import google.generativeai as genai
            genai.configure(api_key=GEMINI_API_KEY)
            model = genai.GenerativeModel('gemini-1.5-flash')
            response = model.generate_content(prompt)
            return response.text
        except Exception as e:
            logging.error(f"Gemini Error: {e}")

    # 2. Thử OpenAI
    if OPENAI_API_KEY:
        try:
            from openai import OpenAI
            client = OpenAI(api_key=OPENAI_API_KEY)
            response = client.chat.completions.create(
                model="gpt-4o-mini",  # Hoặc gpt-3.5-turbo
                messages=[{"role": "user", "content": prompt}],
                max_tokens=300
            )
            return response.choices[0].message.content
        except Exception as e:
            logging.error(f"OpenAI Error: {e}")

    return "Lỗi: Không tìm thấy API Key hoặc Model AI không khả dụng (Cần cấu hình GEMINI_API_KEY hoặc OPENAI_API_KEY)."

class ChatRequest(BaseModel):
    message: str
    context: Optional[Dict] = None
    history: Optional[List] = None

@router.post("")
async def chat_with_ai(request: ChatRequest, email: str = Depends(verify_token)):
    try:
        # 🔥 Lấy thông tin User để truyền vào Prompt
        user = user_repo.get_by_email(email)
        
        user_context_str = ""
        if user and "profile" in user and user["profile"]:
            p = user["profile"]
            stats = user.get("health_stats", {})
            user_context_str = f"""
            HỒ SƠ NGƯỜI DÙNG:
            - Tên: {user.get('full_name', 'Bạn')}
            - Cân nặng: {p.get('weight')}kg
            - Mục tiêu: {p.get('goal', 'sống khỏe')}
            - TDEE: {stats.get('tdee', 'chưa tính')} kcal
            """
        
        # Xây dựng prompt
        full_prompt = f"{user_context_str}\nUSER HỎI: {request.message}\nTRẢ LỜI NGẮN GỌN & THÂN THIỆN:"
        
        reply = get_ai_reply(full_prompt)
        
        return {
            "reply": reply,
            "status": "success" if not reply.startswith("Lỗi:") else "error"
        }

    except Exception as e:
        logging.error(f"Chat Route Error: {e}")
        return {
            "reply": f"Lỗi hệ thống: {str(e)}", 
            "status": "error"
        }