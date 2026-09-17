#!/usr/bin/env bash
# Verify sau khi fix — 4 curl test. Chạy: export BASE=... TOKEN=... DATE=... rồi ./verify_nutrition_curl.sh

set -e
BASE="${BASE:-https://saman-app-v5us.onrender.com}"
TOKEN="${TOKEN:-}"
DATE="${DATE:-2026-03-15}"

if [ -z "$TOKEN" ]; then
  echo "Set TOKEN (và tùy chọn BASE, DATE) rồi chạy lại."
  echo "Ví dụ: export TOKEN='eyJ...' BASE='http://127.0.0.1:8000' DATE='2026-03-15'"
  exit 1
fi

echo "=== Test 1: GET plan (expect: 200, có plan hoặc meals) ==="
curl -s "$BASE/api/nutrition/$DATE" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool || true

echo ""
echo "=== Test 2: POST generate-plan (expect: 200, plan.meals) ==="
curl -s -X POST "$BASE/api/nutrition/generate-plan" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"target_calories":2000,"goal":"maintain","dietary_preferences":[],"allergies":[]}' \
  | python3 -m json.tool || true

echo ""
echo "=== Test 3: POST log-story (expect: 200, log_id) ==="
curl -s -X POST "$BASE/api/nutrition/log-story" \
  -H "Authorization: Bearer $TOKEN" \
  -F "meal_type=lunch" \
  -F "food_name=Pizza" \
  -F "calories=266" \
  -F "protein=11" \
  -F "carbs=33" \
  -F "fat=10" \
  -F "grams=100" \
  -F "logged_at=$DATE" \
  | python3 -m json.tool || true

echo ""
echo "=== Test 4: GET log-story (expect: date, stories, total) ==="
curl -s "$BASE/api/nutrition/log-story/$DATE" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -m json.tool || true
