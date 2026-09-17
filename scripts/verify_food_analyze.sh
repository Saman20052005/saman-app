#!/usr/bin/env bash
# Ngày 2 — Verify POST /api/food/analyze và GET /api/food/health
# Chạy: export BASE=... TOKEN=... [IMAGE_PATH=path/to/image.jpg]
set -e
BASE="${BASE:-http://127.0.0.1:8000}"
TOKEN="${TOKEN:-}"
IMAGE_PATH="${IMAGE_PATH:-}"

if [ -z "$TOKEN" ]; then
  echo "Set TOKEN (và tùy chọn BASE, IMAGE_PATH)."
  echo "Ví dụ: export TOKEN='eyJ...' BASE='https://saman-app-v5us.onrender.com'"
  exit 1
fi

echo "=== GET /api/food/health (expect: mock_mode khi chưa có model) ==="
curl -s "$BASE/api/food/health" | python3 -m json.tool

echo ""
echo "=== POST /api/food/analyze (form key phải là 'image' để khớp frontend) ==="
if [ -n "$IMAGE_PATH" ] && [ -f "$IMAGE_PATH" ]; then
  curl -s -X POST "$BASE/api/food/analyze" \
    -H "Authorization: Bearer $TOKEN" \
    -F "image=@$IMAGE_PATH" \
    -F "grams=150" | python3 -m json.tool
else
  echo "Tạo ảnh 1x1 pixel để test (mock mode không cần ảnh thật)..."
  python3 -c "
from PIL import Image
import io
buf = io.BytesIO()
Image.new('RGB', (1, 1), color='red').save(buf, format='JPEG')
with open('/tmp/test_food.jpg', 'wb') as f:
    f.write(buf.getvalue())
print('Saved /tmp/test_food.jpg')
"
  curl -s -X POST "$BASE/api/food/analyze" \
    -H "Authorization: Bearer $TOKEN" \
    -F "image=@/tmp/test_food.jpg" \
    -F "grams=150" | python3 -m json.tool
fi
