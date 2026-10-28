# Saman Fitness App — Workout & Custom Plans
## Product Requirements Document (PRD) & Design Specification

---

### 1. Executive Summary & Product Overview
**Saman** is a premium, minimalist personal fitness companion designed to bridge the gap between structured strength programming and daily workout logging. 

This PRD formalizes the requirements, UX architecture, and design specifications for the **Workout Experience** and the **Custom Routine Management** feature set (comprising *My Plans* and *Create Plan* sub-flows).

The module allows athletes and fitness enthusiasts to:
1. View and initiate daily scheduled workouts directly from their primary Workout dashboard.
2. Manage a personal routine collection through the dedicated **My Plans** view.
3. Rapidly assemble and save tailored training routines through a focused modal flow (**Create Plan**).

---

### 2. Objectives & Success Metrics
- **Seamless Navigation**: Provide a natural progression from the main Workout tab into routine customization without disorienting the user.
- **Cognitive Clarity**: Keep empty states actionable and inspiring rather than sterile or confusing.
- **Design System Fidelity**: Maintain 100% aesthetic parity with the approved Saman dark-mode design language (monochromatic foundation with intentional emerald accents).
- **Time-to-Routine**: Enable users to name and configure a routine in under 60 seconds.

---

### 3. Target User & Persona
- **Primary Persona**: Dedicated gym-goer / strength training enthusiast who tracks progressive overload and prefers executing personalized split routines over generic algorithmically generated workouts.
- **Key Pain Point**: Complex gym apps clutter the screen with overwhelming analytics, social feeds, and intrusive paywalls while working out.
- **User Expectation**: High contrast, quick legibility under gym lighting, large touch targets for sweaty hands, and fast interactions without lag.

---

### 4. Information Architecture & User Flow

```
[Workout Tab (Primary Hub)]
       │
       ├──► Start Scheduled Workout (One-tap execution)
       ├──► Quick Start (Ad-hoc logging)
       ├──► Browse Library (Exercise database)
       └──► [Top Header: "My Plans" Button]
                   │
                   ▼
       [Screen 1: My Plans]
       ├── Empty State: Atmospheric Gym Hero + "Build your first plan" CTA
       └── Populated State: Saved Plan Cards (Name, Exercises, Duration)
                   │
                   ▼ (Tap "+ Create" or "Create plan")
       [Screen 2: Create Plan (Modal Sheet)]
       ├── Header: Close icon, Title "Create plan", Demo tag
       ├── Panoramic Gym Intro banner
       ├── Form: "Plan Name" text field
       ├── Exercises List:
       │     ├── Empty: Dumbbell icon + "Add your first exercise" + "Browse library"
       │     └── Populated: Draggable exercise list rows + remove actions
       └── Sticky Footer: "Save plan" action (Enabled only when valid)
```

---

### 5. Detailed Screen Specifications

#### 5.1 Workout Tab (`Workout`) — Reference Hub
- **Purpose**: Primary anchor for scheduled sessions, muscle focus navigation, and quick logging.
- **Key Components**:
  - Pinned Status Bar (9:41, battery, Wi-Fi indicators).
  - Header with discreet "My Plans" bookmark button.
  - Featured session card with atmospheric training photography, session tags (`Upper Body Protocol`), exercise count, and primary off-white CTA (`Start workout`).
  - Focus grid (Upper Body, Lower Body).
  - Upcoming schedule and history preview.
  - Persistent bottom tab bar (Home, Workout [Active], S Monogram, Nutrition, Profile).

#### 5.2 My Plans (`My Plans — Empty & Populated`)
- **Navigation Type**: Stack Push (Top back button, NO bottom tab bar).
- **Header**:
  - Back arrow with minimum 44×44px touch target.
  - Title: `My Plans`.
  - Subtitle: `Your routines, ready when you are.`
  - System status pill: `DEMO MODE`.
- **Empty State Requirements**:
  - Full-width hero photography card featuring atmospheric gym lighting.
  - Dark gradient overlay for WCAG AA text contrast.
  - Category pill: `CUSTOM TRAINING`.
  - Headline: `Build your first plan`.
  - Body: `Create a routine that fits your goals.`
  - Primary CTA: Borderless off-white button (`#F9FAFB`) labeled `Create plan`.
  - *Negative Constraint*: No floating action buttons or duplicate creation triggers.

#### 5.3 Create Plan (`Create Plan — Empty`)
- **Navigation Type**: Modal / Sheet Presentation (Top close `×` button).
- **Header & Visual Intro**:
  - Close button leading back to previous context without unsaved changes warning (if empty).
  - Title: `Create plan`.
  - Compact panoramic gym photography banner (commercial/standard gym equipment).
- **Form Controls**:
  - **Plan Name Field**: Labeled `PLAN NAME` in JetBrains Mono (`text-[10px]`, tracking-wider).
  - Input field background `#16171B`, 1px border `#26282F`, placeholder: `e.g. Upper Body Strength`.
  - **Exercises Section**: Section header `Exercises` with badge counter `0` and secondary action `+ Add`.
  - **Empty Exercise Card**:
    - Dumbbell symbol container (`#212328`, 48×48px, rounded-2xl).
    - Heading: `Add your first exercise`.
    - Body: `Choose exercises from your library.`
    - Action: Filled `#212328` secondary button `Browse library`.
- **Sticky Footer Action**:
  - Full-width `Save plan` button docked to bottom respecting safe area.
  - Disabled state: `#1F2126` surface, `#94979E` text, inactive cursor.
  - Active state: `#F9FAFB` surface, `#0C0D0E` text.

---

### 6. Design System Tokens & Style Guide

| Category | Token / Value | Application |
|---|---|---|
| **Base Background** | `#0C0D0E` | Main canvas, global container |
| **Card / Input Surface** | `#16171B` | Plan cards, input fields, empty containers |
| **Hover / Accent Surface** | `#1F2126` | Interactive hover states, disabled button bg |
| **Icon Container Surface**| `#212328` | Icon boxes, badge backgrounds |
| **Divider & Border** | `#26282F` | 1px subtle card outlines and section dividers |
| **Primary Text** | `#F3F4F6` | Headlines, active values, button labels |
| **Secondary / Muted** | `#94979E` | Subtitles, labels, inactive hints |
| **Brand Accent** | `#10B981` (Emerald) | Status pills, active indicators, category chips |
| **Primary CTA Surface** | `#F9FAFB` | "Start workout", "Create plan", "Save plan" |
| **Primary CTA Text** | `#0C0D0E` | High-contrast label on primary CTA |
| **Headline Typography** | `Space Grotesk` | H1, H2, routine titles, modal headers |
| **Body Typography** | `Inter` | Descriptions, supporting body copy, helper text |
| **Metadata Typography** | `JetBrains Mono` | Timers, timestamps, badges, field captions |
| **Border Radii** | `16px` to `20px` | Cards, hero containers, inputs, buttons |

---

### 7. Non-Functional & Technical Constraints
1. **Device Target**: Responsive mobile portrait (Baseline iPhone / 390 × 844 px).
2. **Keyboard Handling**: Form inputs and exercise lists must reside within a scroll container so that virtual keyboards do not obscure the input or the sticky bottom CTA.
3. **Data Persistence**: In demo mode, sessions remain in-memory; UI avoids misleading technical labels like "Not synced" in favor of discreet "Demo mode" tags.
4. **Photography Standards**: High-fidelity, real gym environment photography (warm/dark ambient gym studio or bright modern commercial gym), strictly avoiding illustrations or generic vector clip art.
