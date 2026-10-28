# Product Requirements Document (PRD)

## Project: Saman — Fitness Companion Mobile App
**Document Version:** 1.0.0  
**Target Platform:** Mobile (iOS / Android / Flutter)  
**Status:** In Progress / Design Specification  

---

## 1. Executive Summary & Vision
**Saman** is a refined, minimalist mobile fitness companion designed to help users track workout progress, manage personal health goals (e.g., hypertrophy, strength), and customize their fitness experience without visual clutter. 

### Core Value Proposition
- **Clutter-Free Minimalism:** Calm, dark-mode-first aesthetic with clear typography and soft surface contrasts.
- **Goal-Oriented Dashboard & Tracking:** Straightforward tracking for body metrics, workout goals, and nutrition.
- **Global & Localized Readiness:** Bilingual support (English & Vietnamese / Tiếng Việt) with dual measurement systems (Metric & Imperial).

---

## 2. Target Audience & Personas
- **Primary Persona:** Dedicated fitness enthusiasts and gym-goers who want efficient session tracking, clear baseline metrics (height, weight, activity tier), and no intrusive ads or high-friction interfaces.
- **Secondary Persona:** Users transitioning from casual exercise to structured hypertrophy or strength training requiring simple goal reminders and metric logging.

---

## 3. Brand Identity & Design System Standards

### 3.1 Visual Language
- **Theme:** Pure Dark Mode (`#0D0D11` to `#121216` background).
- **Surface Elevation:** Charcoal containers (`#1A1A22` / `#22222C`) with subtle 1px border outlines (`#2C2C38`).
- **Typography:** Modern clean sans-serif (Inter / SF Pro / Roboto), high-contrast white headers (`#FFFFFF`), muted gray secondary copy (`#8E8E9F`).
- **Iconography:** Consistent 1.5px–2px outline icons (Lucide / Feather / SF Symbols style), no bulky or filled neon icons.
- **Corner Radius:** 16px–20px for grouped cards; 10px–12px for interactive chips and buttons.
- **Touch Ergonomics:** Minimum 48px tappable row height across all settings and action items.

---

## 4. Information Architecture & Navigation Structure

```
Saman App
├── 1. Home (Dashboard, daily streak, workout snapshot)
├── 2. Workout (Routines, exercise library, active session logging)
├── 3. Saman AI / Companion (Quick actions, coaching feedback)
├── 4. Nutrition (Caloric targets, macro split, meal tracking)
└── 5. Profile (User account, stats, tier, navigation to settings)
    └── App Settings (Secondary drill-down)
        ├── Language Selection Sheet
        ├── Units Selection Sheet
        ├── Legal & Support Links
        └── App Version & Build
```

---

## 5. Functional Feature Requirements

### 5.1 Profile Module (Existing Reference)
- **User Identity:** Profile avatar (monogram/photo), display name ("Saman"), subtitle.
- **Your Goal Card:** Primary fitness objective (e.g., "Build muscle - Focus on building muscle") with contextual thematic backdrop.
- **Physical Metrics Overview:**
  - Age (e.g., 21)
  - Gender (e.g., Male)
  - Height (e.g., 171 cm / 5'7")
  - Weight (e.g., 68 kg / 150 lbs)
- **Activity Level:** Indicator with descriptive tier (e.g., "Very active — Frequent exercise and plenty of daily movement").
- **Membership Status:** Membership badge and tier status (Free / Plus / Pro / Ultra).
- **Profile Actions:** "Edit profile" CTA button, "Manage membership", and "Log out".

### 5.2 App Settings Module (Secondary Screen)
- **Preferences:**
  - **Language / Ngôn ngữ:** Current selection display (`English`). On tap: modal bottom sheet with options:
    - *Use device language*
    - *Tiếng Việt*
    - *English*
  - **Units:** Current selection display (`Metric`, secondary caption `kg, cm`). On tap: modal bottom sheet with options:
    - *Metric — kg, cm*
    - *Imperial — lb, ft/in*
- **About Saman:**
  - *Privacy Policy* (webview / modal)
  - *Terms of Service* (webview / modal)
  - *Help & Support* (in-app ticketing / FAQ)
- **App Information:**
  - Version number indicator (e.g., `1.0.0` design placeholder).
- **Footer:** Brand tagline `"Saman · Your fitness companion"`.

---

## 6. Technical Stack & Implementation Notes
- **Frontend Framework:** Flutter (Dart) with Cupertino / Material Design 3 base styled to custom theme tokens.
- **State Management:** Riverpod / Bloc for user preferences, localization switching, and offline metric sync.
- **Internationalization (i18n):** `flutter_localizations` with ARB / JSON bundles supporting English (`en`) and Vietnamese (`vi`).
- **Data Persistence:** Local secure storage (Hive / SharedPreferences) for user units and language cache.

---

## 7. Roadmap & Next Phases
- **Phase 1 (Complete):** Core Profile UI & App Settings UI specifications.
- **Phase 2 (Next):** Interactive bottom sheet components for Language and Units switching; Edit Profile modal.
- **Phase 3:** Workout logging screen and Home dashboard feed.
- **Phase 4:** Membership paywall screen (Plus, Pro & Ultra tier comparison).
