#!/bin/bash

# Endpoint Testing Script for Health AI Backend
# Tests all critical endpoints and returns HTTP status codes

set -e

BASE_URL="http://127.0.0.1:8000"
FAILED_TESTS=0
TOTAL_TESTS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🚀 Starting Health AI Backend Endpoint Tests"
echo "=========================================="

# Function to test endpoint
test_endpoint() {
    local method=$1
    local endpoint=$2
    local data=$3
    local expected_status=$4
    local description=$5
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -n "Testing $method $endpoint... "
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" "$BASE_URL$endpoint")
    elif [ "$method" = "POST" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$BASE_URL$endpoint")
    elif [ "$method" = "PUT" ]; then
        response=$(curl -s -w "\n%{http_code}" -X PUT \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$BASE_URL$endpoint")
    fi
    
    # Extract status code (last line)
    status_code=$(echo "$response" | tail -n1)
    # Extract body (everything except last line)
    body=$(echo "$response" | sed '$d')
    
    if [ "$status_code" = "$expected_status" ]; then
        echo -e "${GREEN}✅ PASS${NC} ($status_code)"
        if [ -n "$description" ]; then
            echo "   $description"
        fi
    else
        echo -e "${RED}❌ FAIL${NC} (expected $expected_status, got $status_code)"
        echo "   Response: $body"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo ""
}

# Function to test endpoint with auth token
test_endpoint_with_auth() {
    local method=$1
    local endpoint=$2
    local data=$3
    local expected_status=$4
    local description=$5
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -n "Testing $method $endpoint (with auth)... "
    
    # Get auth token first (mock token for testing)
    auth_response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"email":"test@example.com","password":"testpassword"}' \
        "$BASE_URL/api/auth/login")
    
    # Extract token (simplified - in real scenario would parse JSON)
    token="mock_token_for_testing"
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Bearer $token" \
            "$BASE_URL$endpoint")
    elif [ "$method" = "POST" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -d "$data" \
            "$BASE_URL$endpoint")
    elif [ "$method" = "PUT" ]; then
        response=$(curl -s -w "\n%{http_code}" -X PUT \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -d "$data" \
            "$BASE_URL$endpoint")
    fi
    
    # Extract status code (last line)
    status_code=$(echo "$response" | tail -n1)
    # Extract body (everything except last line)
    body=$(echo "$response" | sed '$d')
    
    if [ "$status_code" = "$expected_status" ]; then
        echo -e "${GREEN}✅ PASS${NC} ($status_code)"
        if [ -n "$description" ]; then
            echo "   $description"
        fi
    else
        echo -e "${RED}❌ FAIL${NC} (expected $expected_status, got $status_code)"
        echo "   Response: $body"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo ""
}

# Wait for server to be ready
echo "⏳ Waiting for server to be ready..."
for i in {1..30}; do
    if curl -s "$BASE_URL/" > /dev/null 2>&1; then
        echo "✅ Server is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}❌ Server not ready after 30 seconds${NC}"
        exit 1
    fi
    sleep 1
done

echo ""
echo "🧪 Running Endpoint Tests"
echo "========================"

# Basic health checks
test_endpoint "GET" "/" "" "200" "Root endpoint"
test_endpoint "GET" "/docs" "" "200" "API documentation"
test_endpoint "GET" "/api/health" "" "200" "Health status endpoint"

# Auth endpoints
test_endpoint "POST" "/api/auth/login" '{"email":"test@example.com","password":"testpassword"}' "200" "Login endpoint"
test_endpoint "POST" "/api/auth/register" '{"email":"new@example.com","password":"newpassword","full_name":"Test User"}' "200" "Register endpoint"

# Nutrition endpoints
test_endpoint "GET" "/api/nutrition/2026-03-03" "" "401" "Nutrition by date (requires auth)"
test_endpoint_with_auth "GET" "/api/nutrition/2026-03-03" "" "200" "Nutrition by date (with auth)"
test_endpoint_with_auth "POST" "/api/nutrition/generate-plan" '{"target_calories":2000}' "200" "Generate nutrition plan"
test_endpoint_with_auth "GET" "/api/nutrition/foods/search?q=apple" "" "200" "Search foods"
test_endpoint_with_auth "POST" "/api/nutrition/logs" '{"date":"2026-03-03","meal_type":"breakfast","foods":[],"total_calories":500}' "200" "Create nutrition log"
test_endpoint_with_auth "POST" "/api/nutrition/water" '{"date":"2026-03-03","amount_ml":250}' "200" "Log water intake"

# Workout endpoints
test_endpoint_with_auth "GET" "/api/workouts/plans" "" "200" "Get workout plans"
test_endpoint_with_auth "GET" "/api/workouts/streak" "" "200" "Get workout streak"
test_endpoint_with_auth "POST" "/api/workouts/sessions" '{"plan_id":"plan_1","start_time":"2026-03-03T10:00:00"}' "200" "Log workout session"
test_endpoint_with_auth "POST" "/api/workouts/plans" '{"name":"Test Plan","description":"Test","exercises":[],"duration_minutes":30,"difficulty":"beginner","target_muscles":["full_body"]}' "200" "Create workout plan"

# User endpoints
test_endpoint_with_auth "GET" "/api/user/profile" "" "200" "Get user profile"
test_endpoint_with_auth "PUT" "/api/user/update-profile" '{"full_name":"Updated Name","age":25,"gender":"male","height":175.0,"weight":70.0,"activity_level":"moderate","goal":"maintain"}' "200" "Update user profile"

# Chat endpoint
test_endpoint_with_auth "POST" "/api/chat" '{"message":"Hello"}' "200" "Chat with AI"

# Food analysis endpoints
test_endpoint_with_auth "POST" "/api/food/analyze" "" "200" "Food analysis (requires file upload - simplified test)"

# Reports
test_endpoint_with_auth "GET" "/api/nutrition/report/weekly?date=2026-03-03" "" "200" "Weekly nutrition report"
test_endpoint_with_auth "GET" "/api/workouts/report/weekly?date=2026-03-03" "" "200" "Weekly workout report"

echo ""
echo "📊 Test Results"
echo "=============="
echo "Total tests: $TOTAL_TESTS"
echo "Passed: $((TOTAL_TESTS - FAILED_TESTS))"
echo "Failed: $FAILED_TESTS"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ $FAILED_TESTS test(s) failed${NC}"
    exit 1
fi
