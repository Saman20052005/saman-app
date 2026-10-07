# Saman Fitness: Workout Complete Screen Handoff Specification (Final Production Release)

---

## 1. Screen Purpose & Placement in Flow
- **Primary Function**: The rewarding, athletic post-workout checkpoint presented to the trainee **strictly after** an active workout session has been successfully verified and committed from the "Review & Save" screen into local persistence.
- **Position in User Flow**:
  $$\text{Active Workout Logging} \xrightarrow{\text{Finish}} \text{Review \& Save} \xrightarrow{\text{Save session (success)}} \mathbf{\text{Workout Complete (Standalone Route)}} \xrightarrow{\text{View workout history / Back}} \text{Workout History / Workout Hub}$$
- **Architectural Contract**:
  - This screen represents a confirmed, committed historical event.
  - It displays strictly factual data recorded during the workout session with zero speculative vanity metrics (no calories, fake PR badges, heart rate telemetry, or false cloud-sync claims).
  - All rendered values in the accompanying `code.html` and screenshots are **visual design references for Flutter implementation**; production values must be dynamically mapped from the actual workout session state rather than hardcoded.

---

## 2. Accompanying Export Deliverables
1. `code.html` — Standalone production HTML/Tailwind implementation containing only the Workout Complete screen inside a native mobile viewport (`390 × 844 px`).
2. `screen-top.png` — Exact high-fidelity render at initial load (`scrollTop = 0`), showcasing the uncollapsed photographic hero, headline, and primary telemetry.
3. `screen-bottom.png` — Exact high-fidelity render at maximum scroll position, demonstrating full scroll clearance for the volume comparison bar, local storage notice, and pinned action dock.
4. `DESIGN.md` — This comprehensive screen-specific technical handoff document.

---

## 3. Visual Layout Hierarchy (Top to Bottom)

1. **Compact Native Top App Bar**:
   - Single clean header row (`44px` height) with native iOS status bar space (`pt-safe`).
   - Ergonomic back action: `< Workout` (`Inter`, 14px, muted slate `#9CA3AF`), returning the athlete safely to the main Workout tab.
   - Status badge: Subdued emerald chip `● SESSION COMPLETE` (`JetBrains Mono`, 10px uppercase, `#10B981` tint).
   - *Removal Note*: The redundant "SAMAN PERFORMANCE / Workout Completion..." banner and green circular profile button have been completely removed.

2. **Cinematic Photographic Hero (205px Fixed Height)**:
   - Authentic sports documentary photography featuring a male athlete performing flat dumbbell bench press in natural gym daylight with matte black dumbbells.
   - Robust container background fallback (`#16171B`) ensuring zero layout collapse or missing text if the image asset fails.
   - Directional dark obsidian gradient scrim (`#0C0D0E`) ensuring WCAG AA contrast (4.5:1+).
   - Inset context: Date/time badge (`Oct 7, 2026 · 10:36 AM`), primary headline **`Workout complete`** (`Space Grotesk`, 26px, Bold), session split `Upper Body Strength`, and calm coaching feedback: *"A solid session in the books."*

3. **Session Telemetry Summary (Editorial Hierarchy)**:
   - Prominent hero metric: **`1,078`** `kg lifted` (`Space Grotesk`, 32px, bold emerald `#10B981`).
   - Active duration companion: **`32`** `min` (`Space Grotesk`, 32px, bold off-white `#F9FAFB`).
   - Factual supporting telemetry row: `4 sets logged · 2 exercises performed` (`Inter`, 13px, `#9CA3AF`).

4. **Logged Exercises Journal**:
   - **Dumbbell Bench Press** (`448 kg total`):
     - Set 1: `24 kg × 10 reps = 240 kg`
     - Set 2: `26 kg × 8 reps = 208 kg`
   - **Lat Pulldown** (`630 kg total`):
     - Set 1: `35 kg × 10 reps = 350 kg`
     - Set 2: `35 kg × 8 reps = 280 kg`
   - Tabular figures (`JetBrains Mono`, `tabular-nums`) with non-wrapping layout guaranteeing zero digit splitting or truncation on narrow mobile devices.

5. **Volume by Exercise Comparison Bar**:
   - Replaced previous violet tones with a **muted performance teal** (`#14B8A6` / `#2DD4BF`) that harmonizes seamlessly with Saman's emerald palette (`#10B981`).
   - Multi-modal clarity: Segments are clearly distinguished by color dots, exercise names, absolute weights, and calculated percentages:
     - **Dumbbell Bench Press**: Emerald `#10B981` — `448 kg (41.6%)`
     - **Lat Pulldown**: Muted Teal `#14B8A6` — `630 kg (58.4%)`

6. **Local-Demo Storage Notice**:
   - Honest, plain-language text in lower container: *"Saved on this device for this demo. It clears when the app restarts."*

7. **Persistent Safe-Area Action Dock**:
   - Primary CTA: **`View workout history`** (`48px` tactile height, rounded-xl, `#F9FAFB` fill, `#0C0D0E` text, subtle history icon).
   - Secondary action: **`Back to Workout`** (accessible text trigger with ample spacing).
   - Anchored above iOS safe area (`pb-safe`) with `pb-32` scroll clearance, guaranteeing that all exercise rows, chart segments, and demo notices scroll completely above the dock.

---

## 4. Design Tokens & Styling Specifications

| Token | Hex / CSS Value | Applied Component |
| :--- | :--- | :--- |
| **Canvas Base** | `#0C0D0E` | Root mobile viewport background (`390 × 844 px`) |
| **Surface Card** | `#16171B` | Hero card ground, summary card, exercise blocks, demo notice |
| **Row Divider / Hairline** | `#26282F` / `rgba(255,255,255,0.06)` | 1px clean container borders and row separations |
| **Set Detail Inset** | `#212328` | Individual set row highlight background |
| **Text Primary** | `#F9FAFB` | Primary headline, weight numbers, exercise titles |
| **Text Secondary / Muted** | `#CBD5E1` / `#9CA3AF` / `#6B7280` | Subtitles, units, timestamps, secondary link |
| **Emerald Accent** | `#10B981` | Volume primary figure, verified badge, Bench Press segment |
| **Muted Teal Accent** | `#14B8A6` | Lat Pulldown comparison segment and legend indicator |
| **Primary CTA Fill** | `#F9FAFB` fill, `#0C0D0E` text | 48px tactile rounded-xl "View workout history" button |

---

## 5. Data Grounding & Factual Arithmetic

$$\begin{aligned}
\text{Dumbbell Bench Press Set 1:} \quad & 24\text{ kg} \times 10\text{ reps} = 240\text{ kg} \\
\text{Dumbbell Bench Press Set 2:} \quad & 26\text{ kg} \times 8\text{ reps} = 208\text{ kg} \\
\mathbf{\text{DB Bench Press Total:}} \quad & \mathbf{448\text{ kg total}} \quad \left(\frac{448}{1078} = 41.56\% \approx 41.6\%\right) \\[6pt]
\text{Lat Pulldown Set 1:} \quad & 35\text{ kg} \times 10\text{ reps} = 350\text{ kg} \\
\text{Lat Pulldown Set 2:} \quad & 35\text{ kg} \times 8\text{ reps} = 280\text{ kg} \\
\mathbf{\text{Lat Pulldown Total:}} \quad & \mathbf{630\text{ kg total}} \quad \left(\frac{630}{1078} = 58.44\% \approx 58.4\%\right) \\[6pt]
\mathbf{\text{Net Accumulated Volume:}} \quad & \mathbf{1,078\text{ kg}} \quad (240 + 208 + 350 + 280)
\end{aligned}$$

- **Active Duration**: `32 min`
- **Logged Sets**: `4 sets logged`
- **Exercises Performed**: `2 exercises`

---

## 6. Edge Cases & Component Behavior Rules

1. **Missing Session Duration**:
   - If the workout chronometer was interrupted or unavailable, the duration readout displays a neutral dash (`—`) rather than misleading text such as "0m".
2. **Single Logged Exercise**:
   - If an athlete logged sets for only 1 exercise, the "Volume by exercise" bar renders as a solid 100% emerald bar with zero layout shift, displaying the single exercise name and total kg.
3. **Local-Demo Storage Limitation**:
   - In accordance with the local storage demo architecture, sets are held in device local memory and clear upon app restart.
4. **Button Destinations**:
   - **`View workout history`**: Pushes to the chronological workout log (`Workout History`).
   - **`Back to Workout`** & **Header Chevron**: Pops navigation back to the primary Workout tab with today's scheduled split updated to finished status.
