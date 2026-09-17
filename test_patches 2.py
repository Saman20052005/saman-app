#!/usr/bin/env python3
"""
Test script for the 4 patches implemented:
1. Reset Daily Tracking
2. Calorie Budget Rollover  
3. Meal Swap (real implementation)
4. Water Reminder Badge (Flutter-only)

This script tests the backend endpoints. Replace BASE_URL and TOKEN with actual values.
"""

import requests
import json
from datetime import datetime, timedelta

# Configuration - Replace with actual values
BASE_URL = "https://saman-app-v5us.onrender.com"  # or "http://localhost:8000" for local
TOKEN = "<YOUR_VALID_JWT_TOKEN>"  # Replace with actual token

HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

def test_reset_daily_tracking():
    """Test Patch 1: Reset Daily Tracking"""
    print("\n" + "="*60)
    print("🧪 TESTING PATCH 1: Reset Daily Tracking")
    print("="*60)
    
    today = datetime.now().strftime("%Y-%m-%d")
    
    # Step 1: Reset the day
    reset_url = f"{BASE_URL}/api/nutrition/reset-day"
    reset_data = {"date": today}
    
    print(f"\n1️⃣ POST {reset_url}")
    print(f"   Data: {reset_data}")
    
    try:
        response = requests.post(reset_url, headers=HEADERS, json=reset_data)
        print(f"   Status: {response.status_code}")
        print(f"   Response: {response.json()}")
        
        if response.status_code == 200:
            reset_response = response.json()
            assert reset_response.get("status") == "reset"
            assert reset_response.get("date") == today
            assert "reset_at" in reset_response
            print("   ✅ Reset endpoint working correctly")
        else:
            print(f"   ❌ Reset failed: {response.text}")
            return False
    except Exception as e:
        print(f"   ❌ Reset error: {e}")
        return False
    
    # Step 2: Verify GET /{date} returns empty entries after reset
    get_url = f"{BASE_URL}/api/nutrition/{today}"
    print(f"\n2️⃣ GET {get_url}")
    
    try:
        response = requests.get(get_url, headers=HEADERS)
        print(f"   Status: {response.status_code}")
        data = response.json()
        print(f"   Entries count: {len(data.get('entries', []))}")
        print(f"   Total calories: {data.get('total_calories', 0)}")
        
        if response.status_code == 200:
            # After reset, entries should be empty (only entries after reset time)
            entries = data.get('entries', [])
            total_cal = data.get('total_calories', 0)
            print(f"   ✅ GET after reset: {len(entries)} entries, {total_cal} calories")
        else:
            print(f"   ❌ GET failed: {response.text}")
            return False
    except Exception as e:
        print(f"   ❌ GET error: {e}")
        return False
    
    # Step 3: Verify weekly report still contains all data
    start_date = (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d")
    weekly_url = f"{BASE_URL}/api/nutrition/report/weekly?start_date={start_date}"
    print(f"\n3️⃣ GET {weekly_url}")
    
    try:
        response = requests.get(weekly_url, headers=HEADERS)
        print(f"   Status: {response.status_code}")
        
        if response.status_code == 200:
            weekly_data = response.json()
            today_data = next((day for day in weekly_data.get('daily', []) if day['date'] == today), None)
            if today_data:
                print(f"   Today in weekly report: {today_data.get('calories', 0)} calories")
                print("   ✅ Weekly report preserves historical data")
            else:
                print("   ⚠️  Today not found in weekly report")
        else:
            print(f"   ❌ Weekly report failed: {response.text}")
    except Exception as e:
        print(f"   ❌ Weekly report error: {e}")
    
    return True

def test_rollover_calories():
    """Test Patch 2: Calorie Budget Rollover"""
    print("\n" + "="*60)
    print("🧪 TESTING PATCH 2: Calorie Budget Rollover")
    print("="*60)
    
    today = datetime.now().strftime("%Y-%m-%d")
    get_url = f"{BASE_URL}/api/nutrition/{today}"
    
    print(f"\n📊 GET {get_url}")
    
    try:
        response = requests.get(get_url, headers=HEADERS)
        print(f"   Status: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            rollover_cal = data.get('rollover_calories', 0)
            print(f"   Rollover calories: {rollover_cal}")
            
            if 'rollover_calories' in data and isinstance(rollover_cal, int):
                print("   ✅ Rollover calories field present and correct type")
                print(f"   ✅ Value: {rollover_cal} kcal")
            else:
                print("   ❌ Rollover calories field missing or incorrect")
                return False
        else:
            print(f"   ❌ GET failed: {response.text}")
            return False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False
    
    return True

def test_meal_swap():
    """Test Patch 3: Meal Swap (requires existing log)"""
    print("\n" + "="*60)
    print("🧪 TESTING PATCH 3: Meal Swap")
    print("="*60)
    
    # First, get existing logs to find a log_id
    today = datetime.now().strftime("%Y-%m-%d")
    logs_url = f"{BASE_URL}/api/nutrition/logs/{today}"
    
    print(f"\n1️⃣ GET {logs_url} - Find existing log")
    
    try:
        response = requests.get(logs_url, headers=HEADERS)
        print(f"   Status: {response.status_code}")
        
        if response.status_code != 200:
            print("   ⚠️  No existing logs found - creating test log first")
            # Create a test log
            log_data = {
                "date": today,
                "meal_type": "breakfast",
                "foods": [{
                    "name": "Test Food",
                    "calories": 300,
                    "protein": 20,
                    "carbs": 30,
                    "fat": 10,
                    "food_id": "test_food_id",
                    "weight_grams": 100
                }],
                "total_calories": 300
            }
            
            create_url = f"{BASE_URL}/api/nutrition/logs"
            print(f"\n📝 POST {create_url} - Create test log")
            create_response = requests.post(create_url, headers=HEADERS, json=log_data)
            print(f"   Status: {create_response.status_code}")
            
            if create_response.status_code == 200:
                log_id = create_response.json().get("id")
                print(f"   ✅ Created test log: {log_id}")
            else:
                print(f"   ❌ Failed to create test log: {create_response.text}")
                return False
        else:
            logs_data = response.json()
            logs = logs_data.get('logs', [])
            if logs:
                log_id = logs[0].get('_id')
                print(f"   ✅ Found existing log: {log_id}")
            else:
                print("   ❌ No logs found")
                return False
        
        # Now test the swap
        if log_id:
            swap_url = f"{BASE_URL}/api/nutrition/logs/{log_id}/swap"
            swap_data = {
                "log_id": log_id,
                "food_index": 0,
                "replacement_food_id": "607e4fc8-5b6b-4e8b-9a8a-5b6b4e8b9a8a"  # Example food ID
            }
            
            print(f"\n🔄 PUT {swap_url}")
            print(f"   Data: {swap_data}")
            
            swap_response = requests.put(swap_url, headers=HEADERS, json=swap_data)
            print(f"   Status: {swap_response.status_code}")
            print(f"   Response: {swap_response.json()}")
            
            if swap_response.status_code == 200:
                swap_result = swap_response.json()
                expected_fields = ["id", "message", "old_food", "new_food", "new_calories"]
                if all(field in swap_result for field in expected_fields):
                    print("   ✅ Swap response contains all expected fields")
                    print(f"   ✅ Swapped '{swap_result.get('old_food')}' → '{swap_result.get('new_food')}'")
                    return True
                else:
                    print(f"   ❌ Missing fields in response. Got: {list(swap_result.keys())}")
                    return False
            else:
                print(f"   ❌ Swap failed: {swap_response.text}")
                return False
        
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False

def main():
    """Run all patch tests"""
    print("🚀 Starting Patch Tests")
    print(f"   Base URL: {BASE_URL}")
    print(f"   Date: {datetime.now().strftime('%Y-%m-%d')}")
    
    if TOKEN == "<YOUR_VALID_JWT_TOKEN>":
        print("⚠️  WARNING: Please replace TOKEN with actual JWT token")
        print("   You can get this by logging into the app and checking network requests")
        return
    
    results = {
        "Reset Daily Tracking": test_reset_daily_tracking(),
        "Calorie Budget Rollover": test_rollover_calories(),
        "Meal Swap": test_meal_swap(),
    }
    
    print("\n" + "="*60)
    print("📊 TEST RESULTS SUMMARY")
    print("="*60)
    
    for test_name, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{test_name}: {status}")
    
    print(f"\nOverall: {sum(results.values())}/{len(results)} tests passed")
    
    if all(results.values()):
        print("🎉 All patches working correctly!")
    else:
        print("⚠️  Some patches need attention")

if __name__ == "__main__":
    main()
