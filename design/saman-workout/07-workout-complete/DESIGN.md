---
name: Calm Athleticism
colors:
  surface: '#121314'
  surface-dim: '#121314'
  surface-bright: '#39393a'
  surface-container-lowest: '#0d0e0f'
  surface-container-low: '#1b1c1d'
  surface-container: '#1f2021'
  surface-container-high: '#292a2b'
  surface-container-highest: '#343536'
  on-surface: '#e3e2e3'
  on-surface-variant: '#bbcabf'
  inverse-surface: '#e3e2e3'
  inverse-on-surface: '#303031'
  outline: '#86948a'
  outline-variant: '#3c4a42'
  surface-tint: '#4edea3'
  primary: '#4edea3'
  on-primary: '#003824'
  primary-container: '#10b981'
  on-primary-container: '#00422b'
  inverse-primary: '#006c49'
  secondary: '#ffb95f'
  on-secondary: '#472a00'
  secondary-container: '#ee9800'
  on-secondary-container: '#5b3800'
  tertiary: '#ddb7ff'
  on-tertiary: '#490080'
  tertiary-container: '#c487ff'
  on-tertiary-container: '#550093'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#6ffbbe'
  primary-fixed-dim: '#4edea3'
  on-primary-fixed: '#002113'
  on-primary-fixed-variant: '#005236'
  secondary-fixed: '#ffddb8'
  secondary-fixed-dim: '#ffb95f'
  on-secondary-fixed: '#2a1700'
  on-secondary-fixed-variant: '#653e00'
  tertiary-fixed: '#f0dbff'
  tertiary-fixed-dim: '#ddb7ff'
  on-tertiary-fixed: '#2c0051'
  on-tertiary-fixed-variant: '#6900b3'
  background: '#121314'
  on-background: '#e3e2e3'
  surface-variant: '#343536'
typography:
  display:
    fontFamily: Space Grotesk
    fontSize: 48px
    fontWeight: '600'
    lineHeight: 52px
    letterSpacing: -0.03em
  display-mobile:
    fontFamily: Space Grotesk
    fontSize: 36px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 38px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Space Grotesk
    fontSize: 26px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.015em
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 22px
    fontWeight: '500'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Space Grotesk
    fontSize: 18px
    fontWeight: '500'
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  metric-xl:
    fontFamily: JetBrains Mono
    fontSize: 36px
    fontWeight: '500'
    lineHeight: 40px
    letterSpacing: -0.04em
  metric-md:
    fontFamily: JetBrains Mono
    fontSize: 20px
    fontWeight: '500'
    lineHeight: 24px
    letterSpacing: -0.02em
  data-mono:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  label-caps:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.08em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-tablet: 1.5rem
  margin-desktop: 2.5rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
---

## Brand & Style

This design system embodies "Calm Athleticism"—a stark departure from the aggressive, hyper-saturated, gamified aesthetics typical of modern fitness applications. Instead of high-dopamine neon flashes and chaotic dashboards, it frames human performance through an architectural, editorial lens characterized by quiet confidence, precision, and focus.

The experience appeals to dedicated athletes, lifters, and wellness practitioners who demand clarity over noise. The emotional resonance is focused, grounded, and authoritative. Visuals lean on an obsidian palette accented by purposeful, bio-functional spectral colors (emerald, amber, violet). Surfaces feel milled and chiseled rather than floating or skeuomorphic, structured cleanly with razor-thin hairline borders, disciplined typographic cadence, and uncompromised negative space.

## Colors

The color system functions strictly on semantic, physiological roles rather than purely decorative accents:

- **Base Canvas (`#0C0D0E`)**: A deep, true obsidian ground providing immense contrast and eliminating OLED battery drain during long training sessions.
- **Card & Surface (`#16171B`)**: An ultra-subtle elevated charcoal tone that separates interactive components from the canvas without introducing visual glare.
- **Structural Border (`#26282F`)**: A muted 1px hairline border used to chisel surfaces, split metric columns, and frame data zones.
- **Performance Emerald (`#10B981`)**: Dedicated strictly to movement completion, active training status, recovery readiness, and affirmative physiological metrics.
- **Fuel Amber (`#F59E0B`)**: Represents caloric intake, macronutrients, intensity spikes, and load management warnings.
- **Metabolic Violet (`#A855F7`)**: Designates cardiovascular expenditure, heart rate variability (HRV), sleep architecture, and nervous system balance.
- **Typography Tones**: Primary headers and critical data anchor on crisp off-white (`#F9FAFB`), while contextual labels, units, and structural metadata resolve into neutral muted slate (`#94979E`).

## Typography

Typography establishes an analytical hierarchy between narrative framing, coaching guidance, and biometric feedback:

- **Space Grotesk (Headings & Section Dividers)**: Expresses an athletic, geometric posture without feeling aggressive. Its technical character brings structural authority to training block titles and modal overlays.
- **Inter (Body & Coaching Notes)**: Renders workout instructions, form guidance, and recovery insights with absolute legibility at high density.
- **JetBrains Mono (Metrics, Nutrition, Chrono & Sets)**: Exclusively employed for tabular alignment, split times, macronutrient tallies (g/kcal), rep-schemes, and percentage load outputs. Prevents jitter during live timers and maintains strict vertical axis alignment across tabular grids.
- **Stylistic Rule**: Use `label-caps` in uppercase styling with the specified tracking (`letterSpacing: 0.08em`) when introducing data categories (e.g., `TOTAL VOLUME`, `RPE TARGET`, `HR ZONE 4`).

## Layout & Spacing

The structural layout utilizes a fluid grid with a strict 4px/8px incremental cadence, ensuring disciplined content distribution across mobile handsets, tablets, and desktop telemetry dashboards:

- **Mobile (< 768px)**: 4-column layout with 16px (`1rem`) outer margins and 16px gutters. Maximizes functional touch real estate for quick interaction during active workout logs.
- **Tablet (768px - 1024px)**: 8-column layout with 24px (`1.5rem`) outer margins and 16px gutters. Accommodates split views (e.g., exercise list on the left, telemetry and active set counter on the right).
- **Desktop (> 1024px)**: 12-column layout with 40px (`2.5rem`) margins and 24px (`1.5rem`) gutters, maxing out at a 1280px centralized content container.
- **Rhythm**: Component interiors standardize on `space-md` for standard card padding and `space-sm` for metric-label gap coupling. Outer section breaks utilize `space-xl` to enforce an open, contemplative rhythm.

## Elevation & Depth

This design system avoids blurry drop shadows, heavy colored glows, and artificial lighting skeuomorphism. Depth is achieved via architectural surface layering and low-contrast perimeter framing:

1. **Ground Zero (`#0C0D0E`)**: Base view canvas.
2. **Layer 1 Surface (`#16171B`)**: Card modules, bottom sheets, and metric blocks framed by a crisp, continuous 1px outline of Border (`#26282F`).
3. **Layer 2 Raised (`#1D1F25`)**: Dropdowns, active modal trays, and floating sticky control bars, maintaining the 1px hairline border with an optional subtle ambient shadow: `0 8px 24px rgba(0, 0, 0, 0.6)`.
4. **Focused State**: Rather than adding elevation blur, focused or active elements brighten their border from `#26282F` to the contextual functional accent (e.g., Emerald `#10B981` or off-white `#F9FAFB`) with zero shift in surface geometry.

## Shapes

The shape profile is chiseled and architectural. With a base soft corner radius of `0.25rem` (4px), containers and input elements remain grounded and precision-machined rather than bulbous or playful:

- **Standard Elements (4px / `roundedness: 1`)**: Standard buttons, metric cards, text fields, and set-entry rows.
- **Grouping Modules (8px / `rounded-lg`)**: Master exercise cards, weekly volume diagrams, and modal containers.
- **Data Chips & Progress Indicators (12px / `rounded-xl`)**: Compact status pills and telemetry filters.
- **Full Circles**: Dedicated solely to micro user avatars and timer completion rings.

## Components

### Buttons
- **Primary**: Background `#10B981`, foreground `#0C0D0E` (Space Grotesk Medium), 0.25rem radius, no border. Subtle dark feedback state on press (opacity 0.9).
- **Secondary / Subdued**: Background `#16171B`, border 1px `#26282F`, text `#F9FAFB`. On hover/focus, border shifts to `#94979E`.
- **Ghost Action**: Transparent background, text `#94979E`, hovering turns text to `#F9FAFB`.

### Metric & Telemetry Cards
- Surface `#16171B` with 1px border `#26282F`.
- Card header consists of `label-caps` in `#94979E`, coupled with an optional mono dot in the assigned domain accent (Emerald for recovery, Amber for nutrition, Violet for cardio load).
- Quantitative readout displays in JetBrains Mono (`metric-xl` or `metric-md`), with unit tags rendered in `#94979E` (`data-mono`) aligned along the metric baseline.

### Chips & Badges
- Compact padding (`0.25rem 0.5rem`).
- Surface `#16171B` bounded by 1px `#26282F`.
- Typography is strictly `label-caps` in `#F9FAFB` or tinted dynamically with functional colors at low-alpha backgrounds (e.g., `#10B981` at 12% opacity with solid `#10B981` text).

### Lists & Set Logs
- Rows divided by 1px border lines `#26282F` without margin separators.
- Numerical set indices, target weights, and actual reps render in JetBrains Mono (`data-mono`) for column integrity.
- Completed sets trigger a stroke change on the checkbox and set indicator from `#26282F` to `#10B981`.

### Form Fields & Inputs
- Background `#16171B`, height 44px, border 1px `#26282F`, corner radius 4px (`0.25rem`).
- Placeholder text in `#94979E`. Active text in `#F9FAFB`.
- Focus state: Border transitions to `#10B981` with zero outer glow.
- Numeric log inputs leverage tabular figures through JetBrains Mono.

### Checkboxes & Toggle Elements
- Custom 18x18px squared shape with 2px radius and 1px `#26282F` border.
- Active/Checked: Fill turns solid `#10B981`, border matches, containing a crisp obsidian (`#0C0D0E`) check icon.