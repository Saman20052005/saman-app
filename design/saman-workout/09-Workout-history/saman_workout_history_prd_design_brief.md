# Product Requirements Document (PRD) & Design Specification

**Feature / Domain:** Workout History & Training Journal Redesign  
**Product:** Saman Mobile Fitness App  
**Status:** Approved & Shipped (v2.6)  
**Target Viewport:** Mobile iOS / Android (~390px responsive width)  
**Design Direction:** Calm Athleticism (Dark obsidian surface `#0C0D0E`, graphite hairline borders `#26282F`, emerald accent `#10B981`)

---

## 1. Executive Summary & Objective

### 1.1 Context
Saman is an elite, minimalist digital training companion tailored for dedicated lifters and athletes. While the core **Workout Home** tab established a high benchmark for documentary-style photography, typographic clarity, and restrained visual hierarchy, the legacy **Workout History** interface remained a functional, low-contrast prototype.

### 1.2 Core Objective
Transform the legacy functional screen into a **photo-led, narrative training journal** that functions as a natural, seamless extension of Workout Home. Athletes should feel a sense of tangible progress and ownership over their logged sessions without being subjected to gamified clutter, aggressive neon palettes, or unsolicited AI scoreboards.

---

## 2. Product Principles & Design Language ("Calm Athleticism")

| Design Token | Specification / Value | Usage & Intent |
| :--- | :--- | :--- |
| **Canvas Background** | `#0C0D0E` | Deep obsidian backdrop; eliminates harsh contrast while preserving true dark-mode depth. |
| **Primary Surface** | `#16171B` | Card backgrounds, elevated components, and grouped lists. |
| **Secondary Surface** | `#212328` | Search bars, thumbnail backgrounds, subtle pill containers. |
| **Hairline Borders** | `1px solid #26282F` | Subtle architectural boundary definition across all containers. |
| **Primary Text** | `#F9FAFB` | Headings, essential metric numbers, key titles. |
| **Secondary / Muted** | `#94979E` / `#CBD5E1` | Subtitles, labels, date stamps, unit suffixes (`kg`, `min`). |
| **Accent Hue** | `#10B981` (Emerald) | Restrained indicators: completion badges, active filter dot markers. |
| **Primary CTA** | Solid `#F9FAFB` on `#0C0D0E` | High tactile salience without relying on loud neon colors. |
| **Typography** | `Space Grotesk` (Headings) / `Inter` (Body) / `JetBrains Mono` (Metrics & Timestamps) | Rigorous typographic rhythm balancing athletic poise with data precision. |

---

## 3. Information Architecture & Navigation

```
[Workout Home] (Main 5-Tab Bar Hub)
       │
       └──> Tapping "View history >" / "Last Workout"
                 │
                 ├──> [Workout History - Default Populated State]
                 │         │
                 │         ├── [Calendar Dropdown Tap] ──> [Expanded Calendar Filter State]
                 │         ├── [Active Search Query]   ──> [Search Filtered State / No Matches]
                 │         │
                 │         └── [Session Card Tap] ──────> [Workout Session Detail Screen]
                 │                                              │
                 │                                              └── [Exercise Card Expand]
                 │                                                    └── Set-by-Set Data Table
                 │
                 └──> [Zero State (New Account)] ────────> [Fresh Journal Empty State]
```

### 3.1 Hierarchy Rules
- **Secondary Stack Architecture:** Workout History and Session Detail are sub-screens. They use a standard top app bar with a back navigation arrow and **do not render the global 5-tab bar**, keeping focus entirely on data review.
- **Top Bar Contract:** Back button (`arrow_back`), title (`Workout History` / `Session Summary`), supporting subtitle (`Your training, recorded.`), and an overflow/share action where appropriate.

---

## 4. Key Functional Requirements & Screen Specs

### 4.1 Screen 1: Workout History (Default Populated)
* **Search & Filter Row:**
  - Full-width search bar (`Search workouts`) with leading search icon and dynamic trailing clear (`close`) icon.
  - Compact date period bar (`October 2026 · All 31 days · Calendar & overview`) with expandable chevron.
* **Period Summary Strip:**
  - 3-column metric card summarizing the selected temporal window:
    - **Sessions:** e.g., `14` (+3 vs Sep).
    - **Total Time:** e.g., `11h 42m`.
    - **Total Volume:** e.g., `34,180 kg`.
  - Non-intrusive strip that anchors context without displacing the workout feed.
* **Photo-Led Workout Cards (Feed Core):**
  - **Date Section Dividers:** Grouped chronologically (e.g., `Wednesday, Oct 28, 2026 · 1 session`).
  - **Aspect & Cover Image:** Moderately sized 16:9 documentary athletic photograph representing the primary movement.
  - **Overlays:** Dark gradient bottom scrim ensuring legible `#F9FAFB` headlines, a timestamp pill (`Oct 28, 2026 · 13:14`), and an emerald `Completed` status badge.
  - **Essential Metric Row:** Exercises count, duration, and volume (strictly preserving exact athlete logs, including `<1 min` edge cases).
  - **Exercise Previews:** Horizontal sequence of thumbnail chips with movement names (e.g., `Incline DB Press · 2 sets · 208 kg`) + `+N more` overflow badge.
  - **Action Affordance:** Entire card is tappable with an explicit `View session ->` micro-link.

---

### 4.2 Screen 2: Workout History (Expanded Calendar Filter State)
* **Purpose:** Allows athletes to visually audit workout distribution, frequency, and rest days across a given month.
* **Monthly Grid View:**
  - Compact header with Month Switcher (`< Oct 2026 >`) and active sessions count badge (`14 Active Days`).
  - 7-column day-of-week grid (`Mo, Tu, We, Th, Fr, Sa, Su`).
  - Days with completed sessions feature an emerald activity dot indicator under the date.
  - Selected day (`Oct 28`) is encased in a high-contrast pill ring.
* **Period Quick-Filter Chips:**
  - `This Week`, `October (Active)`, `Last 30 Days`, `Year 2026`.
* **Dynamic Feed Scoping:**
  - Context indicator banner: `Showing 1 session on Oct 28, 2026` with a `Show All in Oct` reset trigger.

---

### 4.3 Screen 3: Workout Session Detail Screen
* **Purpose:** Full forensic audit of a completed training session.
* **Header & Media:**
  - Hero header card echoing the session photograph, timestamp, and volume metrics.
* **Summary Metrics Grid:**
  - `Exercises (1 total)`, `Duration (<1 min)`, `Total Volume (208 kg)`.
* **Exercise Log Breakdown:**
  - Chronological list of movements in their saved order.
  - Collapsible exercise cards with primary/secondary movement tags (e.g., `CHEST · PRIMARY COMPOUND`).
  - Expanded set table with discrete, readable data rows:
    - `Set 1` | `26.0 kg (ea)` | `4 Reps` | `104 kg` | Completed Checkmark
    - `Set 2` | `26.0 kg (ea)` | `4 Reps` | `104 kg` | Completed Checkmark
  - **Athlete Notes Callout:** High-contrast recessed card for user-entered form observations or notes.
* **Footer Actions:**
  - Secondary button: `Edit Logged Values` + Delete session icon.

---

### 4.4 Screen 4: States, Fallbacks & Edge Cases
1. **Search Empty State:**
   - Displayed when search yields no matches in the active period.
   - Micro-icon with slash, headline `No workouts found`, contextual quote of the search term, and an explicit `Clear search filter` button.
2. **Fresh Journal State (First-Time User):**
   - Clean, encouraging empty state: `No saved workouts yet`.
   - Explanatory copy: *"Completed training sessions, weights, and set logs will be automatically archived here."*
   - Primary solid CTA: `Start a workout`.
3. **Missing Exercise Imagery Fallback:**
   - Dark geometric dumbbell icon tile (`#212328`) preserving card alignment when library assets or custom movements have no photograph.

---

## 5. Non-Functional Requirements & Constraints

1. **Strict Data Veracity:** Durations, volumes, and set counts must never be rounded or estimated (e.g., `<1 min` must not round up to `1 min`).
2. **Exclusion of Extraneous Features:** Explicitly excluded: social feeds, community leaderboards, calorie burn estimations, AI strain scores, and subscription upsells.
3. **Ergonomics & Accessibility:**
   - Minimum 44×44pt touch targets across all interactive affordances.
   - Text contrast ratios exceed WCAG AA standards against dark surfaces.
   - Support for dynamic type and graceful truncation of long custom exercise titles.
