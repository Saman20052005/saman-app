# Product Requirements Document (PRD) & Executive Product Brief
## Saman — AI-Driven Personal Fitness, Nutrition & Health Companion

**Document Version:** 3.2 (Comprehensive Production Specification)  
**Status:** Approved / Active Production Baseline  
**Target Platform:** Native Mobile (iOS & Android — ~390px mobile viewport)  
**Product Category:** Contextual AI Coaching, Strength & Performance, Health & Nutrition  

---

### 1. Executive Summary & Vision

**Saman** is an editorial, workout-first, AI-driven personal training, nutrition, and health companion engineered specifically for dedicated strength trainees, lifters, and performance athletes.

Unlike legacy fitness applications that suffer from **dashboard fatigue**—overwhelming users with metric rings, disconnected charts, aggressive gamification, and intrusive upsells—Saman grounds its entire user experience in **calm athleticism**. 

The app functions as an intuitive, authoritative in-gym training partner that:
1. **Presents the primary daily decision upfront** through today’s programmed workout session.
2. **Maintains disciplined daily nutrition guardrails** via flat macro tracking with semantic color discipline.
3. **Embeds conversational coaching organically** through **Saman Coach**—a quiet, context-aware companion that understands fatigue, analyzes meals from photos, presents clean structured recommendations, and manages user state without technical AI jargon.
4. **Houses a personal coach workspace** via an integrated full-height drawer with quick access to recent conversations, weekly reviews, nutrition check-ins, reminders, and user preferences.

---

### 2. Problem Statement & User Personas

#### 2.1 The Core Problems
1. **Dashboard & Metric Fatigue:** Existing fitness tracking apps display endless disconnected widgets (steps, heart rate spikes, calories, sleep logs) without answering: *"What should I do right now?"*
2. **Gimmicky, Disconnected AI:** AI coaches are typically relegated to generic chat bubbles with no contextual awareness of the user’s real-time recovery score, previous lift volume, or macro status.
3. **Technical AI Jargon & Telemetry Exposure:** Most AI fitness apps leak backend telemetry, LLM status messages ("Stop generating", "Telemetry Synced"), and robot-like status dots, breaking athletic immersion.
4. **Distracting Commercialization:** Flashing discount banners, countdown timers, and neon gamification erode the serious, focused mindset lifters cultivate in the gym.

#### 2.2 Primary Persona: "The Intentional Athlete" (Alex, 28)
- **Profile:** Trains 4–5 days/week (hypertrophy, compound lifting, functional conditioning); tracks caloric intake and macronutrient splits (protein/carbs/fat).
- **Core Goals:** Consistent progressive overload, balanced recovery, and clean macro adherence without spending 20 minutes manually logging every set and meal.
- **Key Frustrations:** Cluttered UIs, high cognitive load before a workout, and AI assistants that feel like novelty chatbots rather than real training partners.
- **Aesthetic Preference:** Dark obsidian interfaces, high-contrast typography, matte textures, and calm visual feedback.

---

### 3. Product Principles & Design Language

1. **Workout-First Hierarchy:**  
   The primary actionable decision—today's training session—occupies the dominant visual real estate at the top of the Home viewport.
2. **Contextual & Subordinate AI ("Calm Coach"):**  
   Saman’s intelligence is delivered as quiet, authoritative, one-sentence coaching interventions and natural conversation rather than intrusive chat interruptions. Saman speaks when spoken to or when high-value proactive nudges are warranted.
3. **Calm Athleticism (Dark Obsidian Aesthetic):**
   - **Canvas Background:** Deep obsidian (`#0c0d0e` to `#121316`).
   - **Card & Panel Surfaces:** Dark charcoal (`#16171b` / `#1b1b1f`) framed by hairline graphite borders (`#23252a` or `rgba(255,255,255,0.08)`).
   - **Typography Hierarchy:** Tabular, high-contrast white numbers, clean title-case headers (`font-medium`), and muted graphite secondary copy (`#9ca3af` / `#6b7280`). Monospace is strictly reserved for data timestamps where necessary.
   - **Disciplined Color Accents:** Strict monochrome foundation. Accents are reserved exclusively for data semantics:
     - **Saman Green (`#10b981`):** Completed workouts, active streaks, protein progress, active reminder indicator dot.
     - **Warm Amber (`#f59e0b`):** Carbohydrates.
     - **Muted Violet (`#a855f7`):** Dietary fats.
     - **Strict Negatives:** No neon, no electric blue CTAs, no decorative gradients, no heavy glassmorphism.
4. **Non-Intrusive Editorial Commerce:**  
   Commercial touchpoints always lead with educational value (Saman Journal) and contextual utility, strictly avoiding price tags, sale badges, or checkout carts on primary feeds.
5. **Human Coaching Over System Mechanics:**  
   UI surfaces never expose raw technical terms ("AI Model", "Telemetry", "Token Generation", "Offline Error Code"). Failures and recovery states are framed naturally as a calm coach temporarily pausing or asking for clarity.

---

### 4. Global Architecture & App Shell Navigation

The app uses a persistent 5-tab bottom navigation bar engineered with 20×20 px line icons and micro-indicators:
1. **Home:** Minimalist rounded house outline with an active off-white focal dot.
2. **Workout:** Athletic barbell/dumbbell glyph with visible center grip and dual weight plates.
3. **Saman (Center Anchor):** Proprietary geometric uppercase **"S"** monogram crafted from two tapered arcs with a central negative-space break. Replaces generic sparkle/AI icons to represent brand strength, companion memory, and intelligence.
4. **Nutrition:** Modern line-art fork and knife dining utensils.
5. **Profile:** Clean contoured person silhouette.

---

### 5. Detailed Screen Specifications

#### 5.1 Home Screen Architecture (Primary Surface)
- **A. Greeting & Companion Bar:** Dynamic user greeting (`"Hello, Saman"`) paired with notification bell and profile action.
  - **Saman Contextual Line:** Live-generated heuristic guidance derived from sleep HRV, acute training strain, and scheduled workout volume (e.g., *"Leg volume is high today — fuel up 60m before training"*).
- **B. Workout Recommendation Carousel:**
  - Snap-to-card track peeking into adjacent cards (`snap-x snap-mandatory`).
  - **Dominant Card:** Moody editorial lifting visual, recovery rationale badge (*"Best match for your recovery"*), workout title (*"Leg Day & Posterior Chain"*), specifications (*"45 min · 5 compound exercises · Target RPE 8.5"*), exercise chips, and high-contrast solid CTA button (*"Start Workout →"*).
  - **Secondary Alternatives:** *Upper Strength* (40 min), *Full Body Express* (25 min), and *Active Recovery* (20 min) with minimal *"View workout →"* action.
- **C. Sporty Quick-Action Dock:**
  - Zero-friction touchpoints: `+ Log Meal` (photo/barcode), `▷ Quick Start` (unplanned lifting timer), `💧 Water` (+250ml log), and `✎ Note` (RPE & soreness check-in).
- **D. Daily Targets Module:**
  - Flat, unboxed nutrition command center.
  - Full-width caloric bar: `1,850 / 2,500 kcal · 74%`.
  - 3-column macro split with dedicated color semantics: Protein (`#10b981`), Carbs (`#f59e0b`), Fat (`#a855f7`).
  - Integrated hydration tracker: `1.8L / 2.5L`.
- **E. Weekly Consistency Performance Module:**
  - Trend header: `WEEKLY CONSISTENCY` + `3 / 4 sessions`.
  - Integrated 3-column summary: Sessions (`3/4`), Completion (`75%`), Streak (`3d`).
  - Dual-line visual trend: Restrained emerald spline representing actual completed sessions vs. subtle dashed off-white spline representing the programmed target across Mon–Sun.
  - Next session link: `NEXT SESSION · Upper Hypertrophy` with understated `View progress →`.
- **F. Saman Picks (Contextual Surface):**
  - Card 1: **Saman Journal** (Restrained athletic recovery guide with dark gym photography).
  - Card 2: **Saman Shop** (Curated training essentials—matte straps, shaker bottle—strictly free of prices, sales badges, or checkout carts).

---

#### 5.2 Saman Coach Conversational Ecosystem (Saman Tab)

The **Saman** tab houses an intelligent, multi-state conversational coaching system designed for long-term athlete collaboration.

```
┌─────────────────────────────────────────────────────────────┐
│ [≡ Menu]          [S] Saman Coach             [✎ Edit] [🔔] │
├─────────────────────────────────────────────────────────────┤
│ CONVERSATION FEED / ACTIVE WORKSPACE                        │
│                                                             │
│ [State-Dependent Renderings]:                               │
│ - Empty State (Greeting, Suggested Queries)                 │
│ - Active Conversation (User bubble, Saman response)         │
│ - Food Photo Analysis Loading (Scanning card)               │
│ - Food Photo Result (Image preview, macro chips, CTAs)      │
│ - Reminder / Proactive Nudge (Contextual rest reminder)     │
│ - Long Response / Table (Markdown, metrics table, CTAs)     │
│ - Typing State (Restrained pulsing wave indicator)         │
│ - Recoverable Error State (Calm retry button)               │
│ - Food Photo Failure State (Reshoot guide + manual log)     │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ COMPOSER DOCK (Standardized Across All States)              │
│ [ + Tool / Photo ] [ Type a message...        ] [ ↑ Send ]  │
├─────────────────────────────────────────────────────────────┤
│ BOTTOM NAVIGATION:  [🏠 Home] [🏋️ Workout] [S Saman] [🥗 Nutri] [👤 Profile] │
└─────────────────────────────────────────────────────────────┘
```

##### 5.2.1 Core Conversational States:
1. **Empty / New Conversation State:**
   - Calm, uncluttered introduction with the geometric `S` monogram badge and title-case **Saman**.
   - Lightweight query chips for rapid athlete check-ins: *"Check recovery status"*, *"Review today's nutrition"*, *"Adjust leg day volume"*.
   - Completely clean composer input without pre-filled draft text.
2. **Active Conversation State:**
   - High-contrast, right-aligned user speech bubbles in subtle charcoal.
   - Clean left-aligned Saman responses prefaced with the `S` monogram badge, title-case **Saman**, and lightweight timestamp (`09:42`).
   - Contextual coaching feedback with natural emphasis on training load (e.g., *RPE 8*, *24g short on protein*).
3. **Food Photo Analysis Loading State:**
   - Triggered immediately when a meal photo is attached.
   - Shows thumbnail of user's meal paired with a quiet, unobtrusive scanning state: *"Analyzing meal..."* with estimated progress.
   - No complex neural network telemetry or synthetic bounding boxes.
4. **Food Photo Result State:**
   - High-fidelity meal photograph thumbnail (`{{DATA:IMAGE:IMAGE_24}}`).
   - Breakdown of detected items: Grilled chicken breast, Jasmine rice, Steamed broccoli & edamame.
   - Caloric & Macro Summary Pill: `680 kcal · 58g Protein · 72g Carbs · 14g Fat`.
   - Dual-Action Controls: Primary `Log to Daily Targets →` (Saman Green) and secondary `Adjust portions`.
5. **Reminder / Proactive Nudge State:**
   - Unobtrusive coaching notification at the top of the chat: *"Hydration reminder — 700ml remaining before your 7:00 PM session"*.
   - Includes quick acknowledgment chips: *"Logged 500ml"*, *"Snooze 30m"*.
   - Free of aggressive alarm bells or banner clutter.
6. **Long Response / Markdown / Table State:**
   - For in-depth periodization reviews, weekly nutrition breakdowns, and program changes.
   - Soft title-case conversational headings: **Training**, **Nutrition**, **Tomorrow**.
   - **Simplified Mobile Metric Table:**
     | Metric | Today | Target |
     |---|---|---|
     | Calories | 2,280 | 2,400 |
     | Protein | 156g | 180g |
     | Workout | Complete | Planned |
     | Recovery | Moderate | — |
   - Dual Action Hierarchy: Primary `Adjust tomorrow's workout →` (emerald tinted) and secondary `Plan breakfast →`.
7. **Loading & Typing State:**
   - Replaces artificial "Stop generating" text and console logs with a quiet, elegant typing rhythm (three pulsing off-white dots).
8. **Recoverable Error State:**
   - Expressed with personal coach humility: *"I hit a brief snag pulling your latest Garmin HRV data. Let's try that again."*
   - Clear, monochrome `Retry` button paired with a fallback manual prompt.
9. **Food Photo Failure State:**
   - Friendly coach guidance when lighting or composition obscures a dish: *"Couldn't quite identify this plate cleanly. Try snapping from directly above with more light, or quick-log the meal manually."*
   - Two clear recovery options: `Retake photo` or `Manual meal entry`.

---

#### 5.3 Saman Coach Full-Height Drawer (Personal Coach Workspace)

Accessed via the top-left hamburger menu (`[≡]`) on the Saman Coach chat bar.

- **Overlay Specs:** Full-height mobile overlay (~80% screen width) layered above the current conversation, with the remaining ~20% visible beneath a dark translucent scrim (`bg-black/60`).
- **Lightweight Identity Cue:** Single restrained text line directly below top app bar: `Saman · Your personal coach` in muted secondary gray.
- **Primary Action:** `+ New conversation` full-width charcoal pill button at the top.
- **Recent Conversations List:**
  - Title: **Recent** (title case, muted).
  - 4 high-value recent chat items with timestamps:
    - *Upper body form check* (Yesterday) — in active selected state.
    - *Post-workout meal plan* (Mon).
    - *Lower-back adjustment* (Sun).
    - *Macro review* (Last week).
  - Link: `View all conversations →`.
- **Coach Tools Section:**
  - Title: **Coach tools**.
  - Three monochrome utility rows with subtle chevrons:
    - 📅 **Weekly review**
    - 🍴 **Nutrition review**
    - 🏋️ **Workout analysis**
- **Utility Rows:**
  - **Reminders:** Displays `2 active` with a semantic Saman Green indicator dot and navigation chevron.
  - **Saman preferences:** Consolidates coaching tone, response style, and proactive nudges into a single settings entry point.
- **Clean Footer:** Zero redundant version codes or marketing badges, leaving generous breathing room above the bottom tab bar.

---

### 6. Technical Specifications & Integrations

1. **Biometric & Wearable Ingestion Engine:**
   - Continuous background sync via Apple HealthKit, Health Connect (Android), and Whoop / Oura Cloud APIs.
   - Core ingestion parameters: Heart Rate Variability (HRV rmssd), Resting Heart Rate (RHR), Sleep Stage Architecture (Deep/REM/Light), and Active Workout Strain.
2. **Context-Aware Coaching Engine (CACE):**
   - Acute:Chronic Workload Ratio (ACWR) dynamic calculation to automatically throttle workout intensity recommendations.
   - Intelligent Prompt Context Builder that injects:
     - Today's completed sets & RPE.
     - Remaining macro targets from Daily Targets.
     - Subjective soreness check-ins.
3. **Computer Vision Meal Estimator:**
   - Multi-item segmentation pipeline for food imagery.
   - Outputs macronutrient ranges and caloric approximations with confidence scores.
   - Graceful fallback to user adjustment or manual override.
4. **Local-First Caching & Resilience:**
   - SQLite client database on-device for full offline workout logging and meal history.
   - Offline message queueing for Saman Coach with automatic sync upon reconnecting to gym Wi-Fi or cellular networks.

---

### 7. Product Success Metrics & KPIs

| Metric | Target | Strategic Objective |
|---|---|---|
| **Workout Start Rate from Home** | > 65% DAU | Validates that workout-first hierarchy drives gym execution |
| **Weekly Adherence (≥4 Sessions)** | > 72% active cohort | Measures long-term habit formation via Weekly Consistency tracking |
| **Saman Coach DAU Engagement** | > 48% DAU | Validates that athletes treat Saman as a true partner rather than a gimmick |
| **Food Photo Log Conversion** | > 80% completion | Proves low friction of camera-based meal logging into Daily Targets |
| **Quick Action Logs** | ≥ 2.8 entries/user/day | Ensures frictionless real-time capture of hydration, meals, and notes |
| **D30 User Retention** | > 58% | Validates core product utility and retention against top fitness benchmarks |

---

### 8. Phased Product Roadmap

- **Phase 1 (MVP — Delivered):**  
  Mobile Home experience (Workout carousel, Quick-Action dock, Daily Targets macro strip, Weekly Consistency line chart, Saman Picks editorial ecosystem) and global 5-tab app shell.
- **Phase 2 (Saman Coach & Conversational Intelligence — Current Milestone):**  
  Full multi-state coaching chat interface (Empty, Active, Food Analysis Loading, Food Result, Reminder/Nudge, Long Response/Table, Typing, Recoverable Error, Photo Failure) and Full-Height Workspace Drawer.
- **Phase 3 (Active In-Gym Workout Tracker):**  
  Set-by-set compound lifting execution mode with automatic barbell plate math, rest countdown timers, and live RPE capture.
- **Phase 4 (Deep Wearable & Recovery Periodization):**  
  Automated multi-week deload recommendations, HRV-driven workout downshifting, and personalized micronutrient optimization.
