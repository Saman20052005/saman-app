# SAMAN Fitness & Nutrition — Product Requirements Document (PRD)

**Document Version:** 2.0  
**Status:** Approved for Engineering Handoff  
**Target Platform:** iOS & Android (Mobile Web / Native, ~390px viewport)  
**Design Direction:** *Calm Athleticism* (Dark Obsidian `#0C0D0E`, Hairline Graphite `#26282F`, Emerald Accent `#10B981`)  
**Scope:** Habit Journeys, Points Economy & AI Analysis Credits, In-App Feedback Patterns  

---

## 1. Executive Summary & Product Vision

### 1.1 Problem Statement
Traditional fitness and nutrition apps often rely on aggressive, hyperactive gamification—such as flashing streak warnings, neon alarms, casino-style coin animations, and heavy modal popups. This creates friction, fatigue, and eventual churn among serious, health-conscious users when they miss a single day.

### 1.2 Product Vision
**SAMAN** introduces a stoic, mature, and distraction-free wellness experience anchored in **Calm Athleticism**. Inspired by the editorial restraint of *Nike Training Club* and the functional prioritization of *Fitbod*, SAMAN guides users through structured daily commitments without shame, visual clutter, or unnecessary cognitive load.

### 1.3 Key Principles
1. **Calm, High-Contrast Obsidian Surfaces:** Monochromatic dark canvas (`#0C0D0E`), elevated charcoal cards (`#16171B`), and 1px graphite dividers (`#26282F`).
2. **Restrained Color Telemetry:** Emerald (`#10B981`) is reserved exclusively for completed states, streaks, and optimal recovery.
3. **No-Guilt Habit Architecture:** Rest days and missed days are handled with supportive, constructive tone rather than punitive streak resets.
4. **Transparent Points & AI Credit Economy:** Clear dual-currency delineation between activity loyalty points and functional AI photo-analysis credits.

---

## 2. Core User Personas & Flows

### 2.1 Target Persona: The Disciplined Striver (Alex, 29)
- **Goal:** Build long-term consistency in strength training and high-protein nutrition.
- **Pain Points:** Overwhelmed by cluttered fitness apps with endless popups, confusing tier locks, and aggressive notifications.
- **Needs:** Fast daily check-in, clear feedback on habits, zero-clutter wallet to exchange points for AI meal analysis.

### 2.2 End-to-End User Flow
```
[Home / Profile]
       │
       ▼
[Screen 1: Create Journey] ──► Select Focus (Workout / Nutrition / Both)
       │                    ──► Set Commitment (7 / 14 / 21 / 30 Days)
       │                    ──► Enable Daily Reminder (e.g., 8:00 PM)
       ▼
[Screen 2: My Journey]      ──► View Progress (e.g., Day 7 of 21, 6 completed)
       │                    ──► Check Off Real Tasks (via Workout/Nutrition logs)
       │                    ──► Claim Daily Reward (+20 pts)
       │                    ──► Track Journey Calendar (Completed, Rest, Upcoming)
       ▼
[Screen 3: Points & AI]     ──► Monitor Balance (240 pts, 3 AI credits)
       │                    ──► Select Exchange Pack (1 AI credit = 100 pts)
       │                    ──► Review Confirmation Bottom Sheet (Before/After)
       ▼
[In-App Feedback]           ──► Non-blocking snackbars, AI analysis loaders, error states
```

---

## 3. Screen Specifications & Functional Requirements

### 3.1 Screen 1: Create Journey (`Screen 1: Create Journey`)
**Purpose:** Help the user make a simple, achievable commitment without medical claims or onboarding friction.

#### Key UI Elements & Layout:
- **Top Bar:** Back button, title `"Create Journey"`, subtitle `"A small habit, lasting change."`.
- **Focus Selector (`What do you want to focus on?`):**
  - Three full-width interactive rows: `Workout`, `Nutrition`, `Both`.
  - Selected state: Subtle emerald border (`#10B981`), emerald radio/check indicator, slight dark-tint background.
  - Default selection in prototype: `Both`.
- **Duration Selector (`How long to commit?`):**
  - Segmented control options: `7 days`, `14 days`, `21 days`, `30 days`.
  - Default selection: `21 days`.
  - Helper copy below selector: `"3 weeks to build a habit."`.
- **Daily Reminder Section:**
  - Row 1: `"Daily reminder"` with toggle switch (iOS style).
  - Row 2 (conditional upon toggle on): `"Reminder time"` displaying `8:00 PM` with chevron right.
  - Quiet footer note: `"You can adjust reminders anytime."`.
- **Primary CTA:**
  - Sticky bottom action: Solid off-white (`#F9FAFB`) button with dark text (`#0C0D0E`), height 52px, label `"Start Journey"`.
- **Explicit Exclusions:**
  - No complex questionnaire, no body-fat promises, no nested summary cards, and no points-per-day marketing clutter during setup.

---

### 3.2 Screen 2: My Journey (`Screen 2: My Journey`)
**Purpose:** Serve as the central hub for daily habit execution, progress tracking, and reward redemption.

#### Key UI Elements & Layout:
- **Header:** Back button, title `"My Journey"`, subtitle `"Personal progress & daily discipline"`, and discreet tune/filter icon.
- **Active Journey Hero Card:**
  - Tag: `"21-Day Journey"`.
  - Title: `"Better Every Day"`, subtitle `"Workout & Nutrition"`.
  - Streak Highlight: Restrained flame icon with `"4 streak"`.
  - Horizontal Progress Bar: 6 of 21 days completed (~29% fill).
  - Status Indicators: `"6 of 21 days completed"` (left) and `"Today · Day 7"` (right).
- **Today's Tasks (`Today · 1 of 2 tasks`):**
  - **Task 1 (Nutrition):** `"Log meal"`, secondary line `"1,850 kcal logged"`, right status badge `"Completed"` with emerald check circle. Read-only state driven by app logging.
  - **Task 2 (Workout):** `"Complete workout"`, secondary line `"Upper Body Strength · 50 min"`, right action `"Start >"`. Entire row tappable to launch workout.
  - *Rule:* Tasks cannot be manually checked via arbitrary checkboxes; they must reflect actual in-app logging.
- **Daily Reward Integration:**
  - Pending State (1/2 tasks): Inline quiet row `"Complete today's tasks to earn 20 pts."` with `20 pts` counter.
  - Ready State (2/2 tasks): Full-width prominent button `"Claim 20 pts"`.
  - Claimed State: Non-interactive confirmation row `"Claimed 20 pts today"`.
- **Journey Calendar (21-Day Matrix):**
  - Compact 3-week calendar grid (days 1 to 21).
  - Day States:
    - *Completed:* Emerald fill / emerald tick (Days 1, 2, 4, 5).
    - *Rest Day:* Leaf / seedling icon (Day 6, Day 13, Day 20).
    - *Missed Day:* Subtle dash symbol (Day 3).
    - *Today (Active):* Distinct emerald ring outline with center dot (Day 7).
    - *Upcoming:* Muted dark numerals (Days 8 to 21).
  - Legend: Completed (`•`), Today (`○`), Rest (`🌱`), Upcoming (`•`).
- **Point Wallet Entry Card:**
  - Tappable navigation row: Wallet icon, label `"Point Wallet"`, balance `"240 pts · 3 AI credits"`, chevron right.

---

### 3.3 Screen 3: Points Wallet & AI Credits (`Screen 3: Points Wallet & AI Credits`)
**Purpose:** Provide total clarity on user points balance, AI credit redemption, and transactional history.

#### Key UI Elements & Layout:
- **Header:** Back button, title `"Points & AI Credits"`, info icon `(i)`.
- **Primary Balance Display:**
  - Label: `"Accumulated points"`.
  - Dominant Metric: `"240"` (Space Grotesk / Tabular figures, ~44px).
  - Sub-badge: Compact chip `"3 AI credits available"`.
  - Clear separation between loyalty points (earned) and AI credits (utility).
- **Redeem AI Credits Options (`Redeem AI credits`):**
  - Informational note: `"Use points to redeem AI analysis credits."`.
  - **Option 1 (Available):** `"1 AI credit"` — secondary copy `"Meal photo analysis or coach breakdown"`, price `"100 points"`. Selected by default with emerald radio.
  - **Option 2 (Insufficient Points):** `"3 AI credits"`, price `"280 points"`, helper note `"40 points short to redeem this pack"`.
  - Disclaimer: `"AI credits apply to meal photo logging and in-depth Saman Coach questions. Saman+ subscribers receive unlimited AI analysis."`.
- **Recent Activity Ledger (`Recent Activity`):**
  - Row 1: `"Daily completion reward"` | `Yesterday · 20:30` | `+20 pts` (Emerald).
  - Row 2: `"Redeemed 1 AI credit"` | `Oct 22 · 09:15 · +1 AI credit` | `−100 pts`.
  - Row 3: `"Meal AI analysis (Lunch)"` | `Oct 22 · 12:45` | `−1 AI credit`.
- **Sticky CTA Action:**
  - Button: `"Redeem 1 AI credit for 100 pts"` (Solid off-white `#F9FAFB`, height 52px).

---

### 3.4 In-App Feedback Components & State Board
**Purpose:** Reusable UI feedback patterns ensuring consistent, non-intrusive responses to user actions.

#### Feedback Components:
1. **Standard Meal Saved (Snackbar):**
   - Check circle icon + `"Meal saved."` + right metric `1,850 kcal`.
2. **Meal Saved + Task Completed (Combined Snackbar):**
   - Single message: `"Meal saved."` / `"Nutrition task completed."` + Action `"View →"`.
3. **Workout Saved + Task Completed (Snackbar):**
   - Barbell icon + `"Workout saved."` / `"Workout task completed."` + Action `"View →"`.
4. **AI Meal Photo Analysis:**
   - *In-progress:* Thumbnail placeholder + animated spinner + `"Analyzing meal photo..."`.
   - *Failed:* Thumbnail preserved + `"Couldn't analyze photo. Please try again or log manually."` + Action `"Try again"`.
5. **Daily Completion Banner (Non-blocking):**
   - Badge icon + `"All set for today!"` / `"20 pts are ready to claim"` + Action button `"Claim reward"`.
6. **Missed Day Supportive Banner (Variant D):**
   - Warm sun icon + `"Let's reset and start fresh today."` / `"Consistency is built over time, not just in a single day."`.
7. **Confirmation Bottom Sheet (Modal Sheet):**
   - Title: `"Redeem 1 AI credit?"`.
   - Subtitle: `"Use 100 points to receive 1 detailed analysis credit."`.
   - Clear Balance Ledger: `"New balance: 140 pts · 4 AI credits"`.
   - Actions: Solid Emerald button `"Confirm"` + Ghost button `"Cancel"`.
8. **Transaction History Empty State:**
   - Receipt icon + `"No transactions yet"` / `"Your point rewards and redemptions will appear here."`.

---

## 4. Design System & Technical Specifications

### 4.1 Color Tokens
| Token | Hex Code | Usage |
|---|---|---|
| `canvas-base` | `#0C0D0E` | Main background, full bleed |
| `surface-card` | `#16171B` | Primary cards, rows, bottom sheets |
| `surface-hover` | `#1F2126` | Interactive hover/pressed state |
| `hairline-border` | `#26282F` | 1px dividers, card perimeters |
| `text-primary` | `#F9FAFB` | Headings, primary metrics, active text |
| `text-secondary` | `#94979E` | Subtitles, labels, timestamps |
| `accent-emerald` | `#10B981` | Completed marks, streak flames, selection rings |
| `accent-amber` | `#F59E0B` | Points indicator, warnings |
| `btn-primary-bg` | `#F9FAFB` | Primary CTA background |
| `btn-primary-text` | `#0C0D0E` | Primary CTA text |

### 4.2 Typography Hierarchy
- **Headlines:** `Space Grotesk` (Semibold, letter-spacing -0.02em)
  - Screen Titles: 24–28px
  - Card Titles: 16–18px
- **Body & Controls:** `Inter` (Regular / Medium, 14–15px)
- **Metrics & Telemetry:** `JetBrains Mono` / Tabular figures (12–32px)

### 4.3 Mobile Viewport & Accessibility
- Max content width: `420px` centered, 390px native canvas.
- Safe Area insets: `pt-safe` (top status bar ~44px) and `pb-safe` (bottom home indicator ~34px).
- Minimum touch target: 44 × 44 pt for all interactive controls.
- Contrast ratio: All primary text meets WCAG AA standard (> 4.5:1 against `#0C0D0E`).

---

## 5. Non-Functional Requirements & Engineering Guardrails

1. **Client-Side State Independence:** UI feedback and screens are decoupled from backend scheduling; visual states are driven by standard API responses (`GET /journey/active`, `POST /wallet/redeem`).
2. **Offline Resilience:** If network drops during meal or workout logging, optimistic local caching applies with `"Syncing..."` badge; never drop user input.
3. **No Duplicate Banners:** The UI container must guarantee that multiple snackbars or toasts are stacked/queued cleanly, never overlapping primary bottom CTAs.
