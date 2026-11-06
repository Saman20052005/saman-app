"""Run the real lib/main.dart build with browser-only HTTP test responses.

No production code/provider/auth override is injected. Login, profile gate,
Nutrition repository/provider and navigation all execute normally. Every API
request is fulfilled in memory; no user account or real database is touched.
Never reads cookies, storage, credentials or request authorization headers.
"""
import base64
import json
import re
import secrets
import sys
import time
from datetime import date, timedelta
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright


def main():
    base, target = sys.argv[1:3]
    output = Path(target)
    output.mkdir(parents=True, exist_ok=True)
    calls, errors = [], []
    today = date.today().isoformat()
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    profile = {
        "user_id": "nutrition-ui-test", "full_name": "Nutrition UI Test",
        "email": "nutrition-ui@example.invalid",
        "profile": {"age": 28, "gender": "male", "height": 178, "weight": 75,
                    "activity_level": "moderate", "activity_canonical": "moderate", "goal": "gain_muscle"},
        "health_stats": {"daily_calories": 2300, "target_protein": 160,
                         "target_carbs": 240, "target_fat": 65, "water_target_ml": 2000},
    }
    entries = [
        {"log_id": "browser-lunch", "food_name": "Grilled chicken & quinoa bowl", "meal_type": "lunch",
         "calories": 640, "protein": 48, "carbs": 62, "fat": 22},
        {"log_id": "browser-breakfast", "food_name": "Avocado toast & eggs", "meal_type": "breakfast",
         "calories": 640, "protein": 38, "carbs": 80, "fat": 19},
    ]
    # Deliberately synthetic, unsigned test value. Never sent to a real server.
    encode = lambda value: base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    synthetic_session = encode({"alg": "none", "typ": "JWT"}) + "." + encode({
        "sub": "nutrition-ui-test", "exp": int(time.time()) + 3600,
    }) + ".test-only"

    def response_for(path):
        if path == "/api/auth/login":
            return {"access_token": synthetic_session, "token_type": "bearer"}
        if path == "/api/user/profile":
            return profile
        if re.fullmatch(r"/api/nutrition/\d{4}-\d{2}-\d{2}", path):
            selected = path.rsplit("/", 1)[1]
            populated = selected != yesterday
            return {"date": selected, "meals": [], "entries": entries if populated else [],
                    "total_calories": 1280 if populated else 0,
                    "total_protein": 86 if populated else 0, "total_carbs": 142 if populated else 0,
                    "total_fat": 41 if populated else 0, "current_water": 750, "water_target": 2000,
                    "macro_targets": {"calories": 2300, "protein": 160, "carbs": 240, "fat": 65}}
        if "summary" in path or "stats" in path or "streak" in path:
            return {"total_sessions": 0, "total_calories": 0, "streak": 0, "days": [], "sessions": []}
        return []

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="msedge", headless=True)
        context = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2)
        page = context.new_page()
        page.on("pageerror", lambda error: errors.append(str(error)))

        def intercept(route):
            request = route.request
            parsed = urlparse(request.url)
            if parsed.path.startswith("/api/"):
                calls.append({"method": request.method, "path": parsed.path})
                payload = response_for(parsed.path)
                if parsed.path == "/api/nutrition/generate-plan":
                    # Match the existing empty-day auto-generation contract.
                    selected = (request.post_data_json or {}).get("date", yesterday)
                    payload = response_for("/api/nutrition/" + selected)
                route.fulfill(status=200, content_type="application/json",
                              headers={"Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "*"},
                              body=json.dumps(payload))
            else:
                route.continue_()

        page.route("**/*", intercept)
        try:
            page.goto(base, wait_until="domcontentloaded")
            page.wait_for_selector("flt-glass-pane", state="attached", timeout=60000)
            page.evaluate("document.querySelector('flt-semantics-placeholder')?.click()")
            page.wait_for_timeout(3500)
            page.screenshot(path=str(output / "full-app-login.png"))
            inputs = page.locator("input")
            if inputs.count() < 2:
                raise RuntimeError("Login inputs are not available through Flutter semantics")
            inputs.nth(0).fill("nutrition-ui@example.invalid")
            inputs.nth(1).fill(secrets.token_urlsafe(18))
            page.get_by_role("button", name="Log In", exact=True).click()
            nutrition_tab = page.get_by_role("button", name=re.compile(r"^Nutrition(?: Nutrition)?$"))
            nutrition_tab.wait_for(timeout=30000)
            nutrition_tab.click()
            page.get_by_role("button", name="Report", exact=True).wait_for(timeout=15000)
            page.wait_for_timeout(800)
            page.screenshot(path=str(output / "full-app-nutrition-populated.png"))
            # First visible meal card body in the fixed 390x844 evidence viewport.
            page.mouse.click(200, 700)
            page.get_by_role("button", name="Close meal details", exact=True).wait_for(timeout=10000)
            page.wait_for_timeout(300)
            page.screenshot(path=str(output / "full-app-meal-details.png"))
            page.get_by_role("button", name="Close meal details", exact=True).click()
            page.wait_for_timeout(400)
            page.get_by_role("button", name="Previous day", exact=True).click()
            page.mouse.move(380, 400)
            page.wait_for_timeout(800)
            page.get_by_text("Your day, on a plate", exact=False).first.wait_for(state="attached", timeout=15000)
            page.screenshot(path=str(output / "full-app-nutrition-empty.png"))
            page.get_by_role("button", name="Next day", exact=True).click()
            page.wait_for_timeout(800)
            page.get_by_role("button", name="Log meal", exact=True).click()
            page.wait_for_timeout(600)
            page.screenshot(path=str(output / "full-app-log-meal.png"))
            page.get_by_role("button", name="Đóng", exact=True).first.click()
            page.wait_for_timeout(500)
            page.get_by_role("button", name="Scan food", exact=True).click()
            page.get_by_text("Ghi Nhận Dinh Dưỡng", exact=True).first.wait_for(timeout=10000)
            page.screenshot(path=str(output / "full-app-scan-food.png"))
            page.mouse.click(4, 4)
            page.wait_for_timeout(500)
            page.get_by_role("button", name="Report", exact=True).click()
            page.wait_for_timeout(500)
            page.screenshot(path=str(output / "full-app-report-route.png"))
        except Exception:
            page.screenshot(path=str(output / "full-app-diagnostic.png"))
            # Only visible semantics and input metadata, never input values.
            (output / "full-app-diagnostic.json").write_text(json.dumps({
                "semantics": page.locator("flt-semantics-host").inner_text() if page.locator("flt-semantics-host").count() else "",
                "inputs": page.locator("input").evaluate_all("es => es.map(e => ({type:e.type, label:e.getAttribute('aria-label'), placeholder:e.placeholder}))"),
                "calls": calls, "page_errors": errors,
            }, ensure_ascii=False, indent=2), encoding="utf-8")
            raise
        finally:
            (output / "full-app-results.json").write_text(json.dumps({
                "entrypoint": "lib/main.dart", "base_url": base,
                "data_source": "browser-intercepted HTTP test responses; no real account/data writes",
                "today": today, "calls": calls, "page_errors": errors,
            }, ensure_ascii=False, indent=2), encoding="utf-8")
            browser.close()


if __name__ == "__main__":
    main()
