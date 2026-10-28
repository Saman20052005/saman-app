# Product Requirements Document (PRD) & Design Brief
**Project:** Saman — AI-Native Fitness & Nutrition Platform  
**Target Platform:** Mobile App (iOS / Android)  
**Status:** In Progress / Design Spec v1.1  
**Authors:** Product & Design Teams  

---

## 1. Executive Summary & Vision

### 1.1 Product Vision
**Saman** is an intelligent, distraction-free fitness and nutrition companion engineered for high-agency individuals and athletes. Unlike legacy calorie trackers that induce friction and anxiety, Saman unifies strength programming, macro tracking, physiological recovery, and quiet AI coaching into a single, high-contrast, premium mobile experience.

### 1.2 Core Value Proposition
- **Unified Telemetry:** Workout execution, macro budgeting, and daily recovery consolidated without switching contexts.
- **Calm AI Coaching:** Concise, high-signal insights delivered in natural language rather than intrusive gamification or pushy alerts.
- **Honest Data Visualization:** Charts and reporting that respect data integrity (clean baselines, clear target thresholds, and transparent differentiation between rest days and unlogged days).

---

## 2. Target Audience & Personas

- **Primary Persona:** Dedicated fitness enthusiasts, strength athletes, and busy professionals adhering to progressive overload training and targeted nutrition goals.
- **User Needs:**
  - Rapid, friction-free daily logging (meals, water, workout sessions).
  - Clear visual hierarchy that reveals current progress in under 5 seconds.
  - Transparent weekly trends to make actionable training and nutrition adjustments without cognitive overload.

---

## 3. Visual & Design System Principles

### 3.1 Design Ethos
- **Apple Health Clarity:** Functional readability and uncluttered chart composition.
- **Oura Metric Restraint:** Prominent, intentional metric hierarchy; zero unnecessary chrome.
- **MyFitnessPal Utility:** Straightforward caloric and macronutrient goal vs. actual comparisons.
- **Dark Elegance & Focus:** High-contrast dark surfaces designed to reduce eye strain in gym environments and morning/evening check-ins.

### 3.2 Visual Tokens
| Token | Value | Application |
| :--- | :--- | :--- |
| **Surface Base** | `#0C0D0E` | Main application background |
| **Card Surface** | `#16171A` | Primary container background |
| **Card Hover / Elevated** | `#1C1D22` / `#212329` | Modals, active states, pill containers |
| **Border Subtle** | `#26282F` | 1px clean separators and container outlines |
| **Text Primary** | `#F3F4F6` | High-emphasis headers and primary values |
| **Text Secondary / Muted** | `#94979E` / `#71717A` | Metadata, unit descriptors, inactive labels |
| **Accent Emerald** | `#10B981` | Protein intake, recovery confirmations, on-track indicators |
| **Accent Amber** | `#F59E0B` | Carbohydrate tracking, calories burned, energy metrics |
| **Accent Purple** | `#A855F7` | Fat macro tracking |
| **Tab Active Pill** | `#F9FAFB` | Inverted white surface with dark text (`#0C0D0E`) for selected tabs |
| **Border Radii** | `12px – 20px` | 12px for buttons/tags, 16–20px for cards and containers |

---

## 4. Key Features & Information Architecture

### 4.1 Global Navigation Frame (Persistent Mobile Shell)
- **Top Header Bar:** Time, connectivity, personalized greeting / screen titles, notifications indicator, profile avatar/settings.
- **Bottom Navigation (5 Primary Tabs):**
  1. **Home:** Daily command center (active workout hero, macro progress, weekly consistency preview, Saman curated picks).
  2. **Workout:** Exercise library, active workout logger, rest timers, set/rep tracker.
  3. **Saman (AI Coach):** Conversational AI interface for personalized programming questions, meal adjustments, and recovery guidance.
  4. **Nutrition:** Detailed meal logs, macronutrient breakdown, barcode scanning, micronutrient metrics.
  5. **Report:** Longitudinal analytics, weekly/monthly averages, calories in vs. out, adherence trends.

---

## 5. Detailed Screen Specifications

### 5.1 Home Screen (Daily Command Center)
- **AI Coach Pulse Line:**
  - Single-line, high-context coaching tip (e.g., *"Saman: Leg Day ready. Aim for 40g protein before 2 PM."*).
  - Direct quick action to open chat dialog.
- **Hero Training Card (Horizontal Carousel):**
  - Displays today's recommended workout with imagery, target duration, exercise count, and planned RPE.
  - Prominent "Start Workout →" primary CTA.
  - Secondary options: Program workouts, express sessions, mobility/active recovery.
- **Daily Targets Module:**
  - Calorie progress bar (consumed vs. goal kcal).
  - 3-column macro split: Protein, Carbs, Fat with goal percentage and colored indicators.
  - Hydration bar with quick-add water button.
- **Quick Action Bar:**
  - One-tap actions: "Log meal", "Add water".
- **Weekly Consistency Preview:**
  - Completed sessions count (e.g., 3 / 4 sessions, 75% completion, 3-day streak).
  - Compact SVG sparkline tracking daily performance against target.
- **Saman Curated Content:**
  - Curated recovery articles and gear recommendations matching current training phase.

### 5.2 Report & Analytics Screen
- **Temporal Navigation:**
  - Segmented week/month picker with calendar date range and left/right navigation (e.g., `Oct 19 – 25, 2026`).
- **Segmented Sub-Views:**
  - **Overview (Default):** Unified snapshot combining energy balance, macros, and activity.
  - **Nutrition Tab:** Deep dive into caloric distribution, meal timing, and macronutrient targets.
  - **Activity Tab:** Deep dive into active energy burned, session volume, and RPE distribution.
- **Weekly Summary Tile ("Your week, at a glance"):**
  - Tracking coverage badge (e.g., `6 / 7 days recorded`).
  - Key metrics: Average Protein Intake (`152 g / day`, % of target met) and Active Days (`4 / 7 days`, average RPE).
- **Core Visual Charts:**
  1. **Calories Consumed (Bar Chart):**
     - Vertical bars for Mo–Su starting at zero baseline.
     - Dashed reference line for daily caloric ceiling/target (`2,500 kcal`).
     - Selected day highlight with active value callout badge.
     - Footer showing exact deviation (`+80 kcal over goal`).
  2. **Protein Intake (Line / Area Chart):**
     - Emerald curve with distinct data nodes and subtle area fill.
     - Horizontal target benchmark at `160g`.
     - Explicit gap handling for unlogged days (no interpolated fictional lines).
  3. **Calories Burned (Amber Bar Chart):**
     - Target line benchmark (`400 kcal`).
     - Clear legend distinguishing a recorded zero-activity rest day (`Rest: 0 kcal`) from an unlogged day (`Unlogged: —`).
- **Weekly Takeaway & Drilldown:**
  - Concise factual summary note (e.g., *"Caloric intake stayed within 4% of target while hitting protein targets across 4 heavy training sessions."*).
  - Navigation affordance: "View daily breakdown →".

---

## 6. Data Integrity & Charting Business Rules

1. **Zero Baseline Enforcement:** All bar charts must strictly anchor at zero. Truncated baselines that exaggerate small variations are prohibited.
2. **Missing vs. Zero Distinction:**
   - A day where the user logged a rest day must display as `0 kcal` / `Rest`.
   - A day where data was never submitted must show an intentional empty dash (`—`) or gap, never a calculated zero.
3. **Unit Discipline:** Never combine disparate units (e.g., kcal and grams) onto a shared dual-axis chart.
4. **Target Transparency:** Daily and weekly goals must always be rendered as distinct dashed threshold lines.
5. **No Decorative Bloat:** Avoid 3D shapes, spinning progress rings, or ambiguous "wellness scores" that cannot be traced to exact metrics.

---

## 7. Success Metrics & KPIs

- **Daily Logging Adherence:** % of active users recording ≥ 5 days of data per week.
- **Time-to-Log Friction:** Average time to log a workout set or meal (< 12 seconds).
- **Report Engagement:** % of weekly active users reviewing the Report screen at week close.
- **Goal Attainment Rate:** % of users staying within ±5% of caloric targets across a 4-week training block.
