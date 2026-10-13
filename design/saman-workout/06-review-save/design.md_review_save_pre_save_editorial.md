# Saman Fitness: Review & Save Screen Handoff Specification (Pre-Save Editorial)

---

## 1. Screen Purpose & UX Flow
- **Primary Function**: The pre-save verification checkpoint presented immediately when an athlete taps "Finish" during an active workout session, **before** the session is committed or written to local storage.
- **Pre-Save Contract**:
  - Sets have been recorded during the workout but have **not yet been committed** to history.
  - The status is strictly **Pre-Save / Unsaved**; this screen never displays labels such as *"Completed"*, *"Session saved"*, *"Saved on this device"*, or *"100% verified"*.
- **Placement in Flow**:
  $$\text{Active Workout Execution} \xrightarrow{\text{Finish}} \mathbf{\text{Review \& Save (Standalone Pre-Save Screen)}} \xrightarrow{\text{Save session (success)}} \text{Workout Complete}$$
- **Non-Destructive Exits**: Both the header back chevron (`< Review session`) and the secondary action (`Keep training`) dismiss the review and safely return the athlete to the active workout session with all logged sets intact.

---

## 2. Visual Architecture & Design Tokens

| Token | Value | Applied Element |
| :--- | :--- | :--- |
| **Canvas Base** | `#0C0D0E` | Root mobile viewport background (`390 × 844 px`) |
| **Journal Container** | `#16171B` | Editorial summary card, exercise blocks, demo notice |
| **Dividers & Hairlines** | `#26282F` / `rgba(255,255,255,0.06)` | 1px clean boundaries and row separations |
| **Text Primary** | `#F9FAFB` | Workout headline, primary values, exercise titles |
| **Text Slate / Muted** | `#CBD5E1` / `#9CA3AF` / `#6B7280` | Context timestamps, units, metadata descriptors |
| **Completion Accent** | `#10B981` | Restrained emerald accent for verified dot and primary volume figure |
| **Primary CTA** | `#F9FAFB` fill, `#0C0D0E` text | 48px tactile, rounded-xl "Save session" button |

### Typography Scale
- **Headline**: `Space Grotesk` (26px, SemiBold) — *"Upper Body Strength"*.
- **Hero Numeral**: `Space Grotesk` / tabular numerals (36px, Bold) — `1,078` with subordinate `kg` and `32 min` active duration.
- **Supporting Telemetry**: `Inter` (13–14px, Regular/Medium) — natural labels (*"4 sets logged · 2 movements"*).
- **Secondary Figures**: `JetBrains Mono` tabular figures for weights and reps (`24 kg × 10 reps = 240 kg`).

---

## 3. Data Grounding & Arithmetic Precision

All displayed metrics strictly reflect actual logged sets with zero speculative vanity metrics (no calories, PR badges, or artificial score projections):

$$\begin{aligned}
\text{Dumbbell Bench Press Set 1:} \quad & 24\text{ kg} \times 10\text{ reps} = 240\text{ kg} \\
\text{Dumbbell Bench Press Set 2:} \quad & 26\text{ kg} \times 8\text{ reps} = 208\text{ kg} \\
\mathbf{\text{DB Bench Press Total:}} \quad & \mathbf{448\text{ kg}} \\[6pt]
\text{Lat Pulldown Set 1:} \quad & 35\text{ kg} \times 10\text{ reps} = 350\text{ kg} \\
\text{Lat Pulldown Set 2:} \quad & 35\text{ kg} \times 8\text{ reps} = 280\text{ kg} \\
\mathbf{\text{Lat Pulldown Total:}} \quad & \mathbf{630\text{ kg}} \\[6pt]
\mathbf{\text{Net Accumulated Volume:}} \quad & \mathbf{1,078\text{ kg}} \quad (240 + 208 + 350 + 280)
\end{aligned}$$

- **Active Duration**: `32 min`
- **Logged Sets**: `4 sets logged`
- **Movements Performed**: `2 movements`

---

## 4. Component Behavior & Pre-Save States

1. **Active Pre-Save Default State**:
   - Status badge: `● STAGE · PENDING CONFIRMATION`.
   - Primary action active: **`Save session →`**.
   - Secondary action clear and accessible: **`Keep training`**.
2. **Zero Logged Sets (Save Disabled)**:
   - If an athlete taps "Finish" with 0 completed sets, the Save button is rendered disabled (`opacity-40 cursor-not-allowed`) with supporting guidance *"At least 1 completed set required to save"*.
3. **Saving In-Progress**:
   - Tapping "Save session" engages an in-progress spinner and button label changes to *"Saving session..."*. The UI remains locked to prevent double-commits.
4. **Save Interrupted / Failure (Retry State)**:
   - If local storage persistence encounters an issue, the review screen remains open with an alert: *"Local save write interrupted"* and a prominent **`Retry`** affordance.
5. **Route Navigation on Success**:
   - Only when the local save write successfully commits does the application navigate forward to the standalone **Workout Complete** screen.
6. **Pre-Save Local Storage Notice**:
   - Plain-language notice in the lower container: *"This demo saves your workout on this device until the app restarts."*
