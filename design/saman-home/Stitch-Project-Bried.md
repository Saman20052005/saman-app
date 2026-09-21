# Product Requirements Document (PRD) & Product Brief
## Saman — AI-Driven Personal Fitness, Nutrition & Health Companion

**Document Version:** 2.0 (Post-Weekly Consistency & Visual Polish Updates)  
**Status:** Approved / Active Specification  
**Target Platform:** Native Mobile (iOS & Android — ~390px mobile viewport)  
**Product Category:** Health & Fitness, AI Coaching, Strength & Performance  

---

### 1. Executive Summary & Vision

**Saman** is an editorial, workout-first, AI-powered personal training and nutrition companion built for dedicated lifters, strength trainees, and performance athletes. 

In contrast to conventional fitness apps that subject users to "dashboard fatigue"—fragmented data rings, noisy charts, intrusive marketing popups, and conversational chatbot gimmicks—Saman grounds its user experience in **calm athleticism**. The app acts as an intuitive, authoritative training partner that presents the single most critical decision (today’s workout) upfront, establishes seamless daily macro guardrails, tracks weekly adherence through sleek performance analytics, and weaves AI guidance organically into every touchpoint.

---

### 2. Problem Statement & User Personas

#### 2.1 The Core Problems
1. **Dashboard & Metric Fatigue:** Existing fitness tracking apps display endless disconnected widgets (steps, heart rate spikes, calories, sleep logs) without answering: *"What should I do right now?"*
2. **Gimmicky, Disconnected AI:** AI coaches are often relegated to generic chat bubbles with no contextual awareness of the user’s real-time recovery score, previous lift volume, or macro status.
3. **Rigid Workout Programs:** Traditional workout apps force static routines, leading to burnout when lifters are under-recovered or pressed for time.
4. **Distracting Commercialization:** Flashing discount banners, countdown timers, and neon gamification erode the serious, focused mindset lifters cultivate in the gym.

#### 2.2 Primary Persona: "The Intentional Athlete" (Alex, 28)
- **Profile:** Trains 4–5 days/week (hypertrophy, compound lifting, athletic conditioning); tracks caloric intake and macronutrient splits (protein/carbs/fat).
- **Core Goals:** Consistent progressive overload, balanced recovery, and clean macro adherence without spending 20 minutes manually logging every set and meal.
- **Key Frustrations:** Cluttered UIs, high cognitive load before a workout, and AI assistants that feel like novelty chatbots rather than real training partners.
- **Aesthetic Preference:** Dark obsidian interfaces, high-contrast typography, matte textures, and calm visual feedback.

---

### 3. Product Principles & Design Language

1. **Workout-First Hierarchy:**  
   The primary actionable decision—today's training session—occupies the dominant visual real estate at the top of the viewport.
2. **Contextual & Subordinate AI:**  
   Saman’s intelligence is delivered as quiet, authoritative, one-sentence coaching interventions rather than intrusive chat interruptions.
3. **Calm Athleticism (Dark Obsidian Aesthetic):**
   - **Canvas Background:** Deep obsidian (`#0c0d0e` to `#101114`).
   - **Card & Panel Surfaces:** Dark charcoal (`#16171b`) framed by hairline graphite borders (`#23252a` or `rgba(255,255,255,0.08)`).
   - **Typography Hierarchy:** Tabular, high-contrast white numbers, crisp uppercase micro-headers (`tracking-wider text-xs font-semibold`), and muted graphite secondary copy (`#9ca3af` / `#6b7280`).
   - **Disciplined Color Accents:** Strict monochrome foundation. Accents are reserved exclusively for data semantics:
     - **Saman Green (`#10b981`):** Completed workouts, active streaks, protein progress.
     - **Warm Amber (`#f59e0b`):** Carbohydrates.
     - **Muted Violet (`#a855f7`):** Dietary fats.
     - **No neon, no bright gradients, no electric blue CTAs.**
4. **Non-Intrusive Editorial Commerce:**  
   Commercial touchpoints always lead with educational value (Saman Journal) and contextual utility, strictly avoiding price tags, sale badges, or checkout carts on primary feeds.

---

### 4. Detailed Information Architecture & Screen Specifications

#### 4.1 Global Persistent Frame (Shell Navigation)
The app uses a 5-tab persistent bottom navigation bar engineered with 20×20 px line icons and micro-indicators:
1. **Home (Active):** Minimalist rounded house outline with an active off-white focal dot.
2. **Workout:** Athletic barbell/dumbbell glyph with visible center grip and dual weight plates.
3. **Saman (Center Anchor):** Proprietary geometric uppercase **"S"** monogram crafted from two tapered arcs with a central negative-space break. Replaces generic sparkle/AI icons to represent brand strength and intelligence.
4. **Nutrition:** Modern line-art fork and knife dining utensils.
5. **Profile:** Clean contoured person silhouette.

---

#### 4.2 Home Screen Architecture (Primary Surface)

```
┌─────────────────────────────────────────────────────────────┐
│ [Profile / Greeting] "Hello, Saman"               [🔔] [⚙️]  │
│ [AI Coaching Line] "Leg volume is high today — fuel up..."  │
├─────────────────────────────────────────────────────────────┤
│ WORKOUT RECOMMENDATION CAROUSEL (Snap Swipable Track)       │
│ ┌───────────────────────────┐ ┌───────────────────────────┐ │
│ │ Recommended for Today     │ │ Upper Strength            │ │
│ │ Leg Day & Posterior Chain │ │ 40 min · Push & Pull      │ │
│ │ 45 min · RPE 8.5          │ │ View workout →            │ │
│ │ [Start Workout →]         │ │                           │ │
│ └───────────────────────────┘ └───────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│ SPORTY QUICK-ACTION DOCK                                    │
│ [ + Log Meal ]   [ ▷ Quick Start ]   [ 💧 Water ]   [ ✎ Note ]│
├─────────────────────────────────────────────────────────────┤
│ DAILY TARGETS (Unified Nutrition Panel)                     │
│ Calories: 1,850 / 2,500 kcal (74%)                          │
│ [ Protein: 145g ]   [ Carbs: 180g ]   [ Fat: 52g ]          │
│ Hydration: 1.8L / 2.5L                                      │
├─────────────────────────────────────────────────────────────┤
│ WEEKLY CONSISTENCY (Performance Chart Panel)                │
│ Header: [📈] WEEKLY CONSISTENCY           3 / 4 sessions    │
│ Metrics: Sessions (3/4) | Completion (75%) | Streak (3d)    │
│ Dual Line Chart: Actual Activity vs. Planned Target         │
│ Footer: Next: Upper Hypertrophy · View progress →           │
├─────────────────────────────────────────────────────────────┤
│ SAMAN PICKS (Editorial & Curated Ecosystem)                 │
│ ┌───────────────────────────┐ ┌───────────────────────────┐ │
│ │ SAMAN JOURNAL             │ │ SAMAN SHOP                │ │
│ │ Recover better after Leg..│ │ Recovery essentials...    │ │
│ │ Read guide →              │ │ Explore picks →           │ │
│ └───────────────────────────┘ └───────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│ BOTTOM NAVIGATION:  [🏠 Home] [🏋️ Workout] [S Saman] [🥗 Nutri] [👤 Profile] │
└─────────────────────────────────────────────────────────────┘
```

##### Detailed Component Breakdowns:
- **A. Greeting & Companion Bar:**  
  - Dynamic user greeting paired with quick profile switches and notifications.
  - **Saman Contextual Line:** Live-generated heuristic guidance derived from sleep HRV, acute training strain, and scheduled workout volume (e.g., *"Leg volume is high today — fuel up 60m before training"*).
- **B. Workout Recommendation Carousel:**  
  - **Snap-to-Card Track:** Full primary card peeking into the next card (`w-[88%]` vs `w-[72%]`).
  - **Dominant Card:** Moody editorial lifting visual, recovery rationale badge (*"Best match for your recovery"*), workout title (*"Leg Day & Posterior Chain"*), specifications (*"45 min · 5 compound exercises · Target RPE 8.5"*), exercise chips (*Squat (4×8)*, *RDL (3×10)*, *Bulgarian Split*), and high-contrast solid CTA button (*"Start Workout →"*).
  - **Secondary Alternatives:** *Upper Strength* (40 min), *Full Body Express* (25 min), and *Active Recovery* (20 min) with minimal *"View workout →"* action.
- **C. Sporty Quick-Action Dock:**  
  - Zero-friction touchpoints: `+ Log Meal` (photo/barcode), `▷ Quick Start` (unplanned lifting timer), `💧 Water` (+250ml log), and `✎ Training Note` (RPE & soreness logging).
- **D. Daily Targets Module:**  
  - Flat, unboxed nutrition command center.
  - Full-width caloric bar: `1,850 / 2,500 kcal · 74%`.
  - 3-column macro split with dedicated color semantics: Protein (`#10b981`), Carbs (`#f59e0b`), Fat (`#a855f7`).
  - Integrated hydration tracker: `1.8L / 2.5L`.
- **E. Weekly Consistency Performance Module:**  
  - Metric Header: Trend icon + `WEEKLY CONSISTENCY` + `3 / 4 sessions`.
  - Integrated 3-Column Summary: `Sessions: 3 / 4` | `Completion: 75%` (Saman Green) | `Streak: 3 days`.
  - Dual-Line Visual Trend: Restrained emerald spline representing actual completed sessions vs. subtle dashed off-white spline representing the programmed target, mapped across a 7-day horizontal axis (Mon–Sun) with today's date highlighted.
  - Next Session Link: `NEXT SESSION · Upper Hypertrophy` with understated `View progress →` text link.
- **F. Saman Picks (Contextual Surface):**  
  - Modular, secondary snap-carousel above bottom nav.
  - **Card 1 (Saman Journal):** Restrained athletic recovery guide with dark gym photography.
  - **Card 2 (Saman Shop):** Curated training essentials (matte lifting straps, shaker bottle) governed by strict commerce guardrails: no prices, no discounts, and no checkout clutter.

---

### 5. Technical Requirements & Integrations

1. **Biometric Data Ingestion:**
   - Real-time synchronization via Apple HealthKit, Android Health Connect, and Whoop/Oura Web APIs.
   - Core ingestion signals: Heart Rate Variability (HRV), Resting Heart Rate (RHR), Sleep Stage Breakdown, and Active Caloric Expenditure.
2. **AI Recommendation & Load Engine:**
   - Dynamic recommendation model factoring in the Acute:Chronic Workload Ratio (ACWR) to suggest workout intensity and rest days.
   - Rule-based safeguard against overtraining (RPE auto-downshifting when HRV is 1.5 standard deviations below 30-day baseline).
3. **Local-First & Offline Resilience:**
   - SQLite client caching ensuring that workouts, active rest timers, and exercise logging function flawlessly in dead-zone gym basements.
   - Background data synchronization with zero screen blocking.

---

### 6. Product Success Metrics & KPIs

| Metric | Target | Strategic Objective |
|---|---|---|
| **Workout Start Rate from Home** | > 65% DAU | Validates that workout-first hierarchy converts intent into action |
| **Weekly Adherence (≥4 Sessions)** | > 72% cohort | Validates efficacy of Weekly Consistency trend visualization |
| **Quick Action Engagement** | ≥ 2.8 logs/user/day | Confirms low friction for real-time meal, water, and note entries |
| **Editorial Guide Click-Through** | > 22% read rate | Proves high content relevance without annoying users |
| **D30 User Retention** | > 58% | Validates long-term utility of the companion experience |

---

### 7. Product Roadmap & Phased Rollout

- **Phase 1 (MVP — Current Release):**  
  Mobile Home experience featuring the workout-first carousel, quick-action dock, Daily Targets macro system, Weekly Consistency line chart, Saman Picks ecosystem, and proprietary 5-tab navigation.
- **Phase 2 (Active Workout Execution):**  
  Dedicated in-gym set/rep/weight logger with automatic plate calculator, auto-adjusting rest timers, and live RPE tracking.
- **Phase 3 (Saman Companion Coaching Tab):**  
  Dedicated conversation interface for long-term periodization reviews, exercise form analysis, and adaptive macro adjustments.
- **Phase 4 (Computer Vision Nutrition):**  
  Camera-based multi-item meal detection and automated macronutrient estimation linked directly to Daily Targets.
