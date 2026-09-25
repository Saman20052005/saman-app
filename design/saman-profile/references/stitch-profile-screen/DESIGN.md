---
name: Calm Athleticism
colors:
  surface: '#121316'
  surface-dim: '#121316'
  surface-bright: '#38393c'
  surface-container-lowest: '#0d0e11'
  surface-container-low: '#1b1b1f'
  surface-container: '#1f1f23'
  surface-container-high: '#292a2d'
  surface-container-highest: '#343538'
  on-surface: '#e3e2e6'
  on-surface-variant: '#bbcabf'
  inverse-surface: '#e3e2e6'
  inverse-on-surface: '#2f3034'
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
  background: '#121316'
  on-background: '#e3e2e6'
  surface-variant: '#343538'
typography:
  headline-xl:
    fontFamily: Space Grotesk
    fontSize: 40px
    fontWeight: '600'
    lineHeight: 48px
    letterSpacing: -0.03em
  headline-xl-mobile:
    fontFamily: Space Grotesk
    fontSize: 30px
    fontWeight: '600'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 34px
    letterSpacing: -0.02em
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
    letterSpacing: 0em
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: -0.01em
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0em
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-micro-caps:
    fontFamily: JetBrains Mono
    fontSize: 10px
    fontWeight: '500'
    lineHeight: 12px
    letterSpacing: 0.12em
  label-mono:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.02em
  metric-display:
    fontFamily: JetBrains Mono
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 36px
    letterSpacing: -0.02em
  metric-display-mobile:
    fontFamily: JetBrains Mono
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1.25rem
  gutter-desktop: 1.5rem
  margin-desktop: 3rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
---

## Brand & Style

This design system embodies the philosophy of **Calm Athleticism**: an uncompromising, distraction-free environment engineered for serious athletes and dedicated strength trainees. It deliberately strips away the hyperactive visual noise typical of commercial fitness apps—such as aggressive neon gradients, flashing gamification banners, and generic high-saturation blue CTAs. Instead, it offers an austere, editorial, high-performance sanctuary reminiscent of precision horology, bespoke performance tuning, and archival journals.

The emotional signature is stoic, methodical, and confident. Visual hierarchy is established strictly through restrained contrast, deliberate micro-typography, surgical 1px hairline borders, and pure tabular data presentation. The brand mark is an austere, chiseled architectural monogram "S", functioning as a subtle stamp of precision craftsmanship.

## Colors

The palette operates under a strict monochrome dark architecture, reserving color exclusively for semantic telemetry and biological metrics.

### Canvas & Structural Neutrals
- **Canvas Base (`#0c0d0e`)**: The absolute background layer for full-bleed layouts and edge areas.
- **Canvas Elevated (`#101114`)**: Root application workspace and dashboard background.
- **Surface Card & Panels (`#16171b`)**: Foreground container panels providing high legibility against the canvas without elevation shadows.
- **Surface Hover & Active (`#1f2126`)**: Interactive state background for rows, chips, and inactive inputs.
- **Hairline Graphite Border (`#23252a` or `rgba(255, 255, 255, 0.08)`)**: Structural division line defining card perimeters, column boundaries, and separators.

### Typography Scales
- **Text Crisp Primary (`#f9fafb`)**: Headlines, critical metrics, and active states.
- **Text Slate Secondary (`#9ca3af`)**: Subtitles, body copy, and secondary metrics.
- **Text Muted Tertiary (`#6b7280`)**: Column headers, unit labels, inactive iconography, and metadata timestamps.

### Purposeful Functional Accents
Accents are used strictly for biometric telemetry, macro-nutrient distributions, and recovery data—never for decorative backgrounds or gradient fills:
- **Primary / Performance Green (`#10b981`)**: Workout completions, active streaks, optimal recovery state, and dietary protein intake.
- **Secondary / Fuel Amber (`#f59e0b`)**: Moderate exertion warnings, dietary carbohydrates, and scheduled sessions.
- **Tertiary / Metabolic Violet (`#a855f7`)**: Dietary healthy fats, sleep cycle efficiency, and strain thresholds.

## Typography

The typographic engine balances technical authority with structural precision across three distinct typefaces:

- **Headlines (`Space Grotesk`)**: Provides an understated, architectural authority. Condensed proportions and geometric tension convey deliberate intention without athletic cliché.
- **Body (`Inter`)**: Serves as the high-legibility workhorse for coaching feedback, recovery insights, and workout descriptions.
- **Telemetry & Labels (`JetBrains Mono`)**: Used for tabular weights, rep schemes, macro grams, timestamps, and uppercase micro-headers. All quantitative data must enforce `font-variant-numeric: tabular-nums` to maintain vertical decimal alignment across dynamic feeds.

Micro-headers (`label-micro-caps`) are strictly uppercase with wide letter spacing (`0.12em`), creating structured anchors above numerical metric groups.

## Layout & Spacing

The layout model is anchored to an 8pt base grid with a 4pt subgrid for micro-alignments.

### Layout Philosophy
- **Mobile First & Handheld Fluidity**: Employs a single fluid column anchored by iOS-grade safe area insets (`env(safe-area-inset-bottom) + space-md`). Outer screen padding is fixed to `1.25rem` (`margin`) to maximize data density while maintaining touch isolation.
- **Desktop System**: Transitions to an asymmetric 12-column grid with a maximum content container width of `1200px`. The primary workout feed and telemetry occupy an 8-column canvas, with auxiliary macro metrics and AI coaching insights housed in a disciplined 4-column right-hand rail.
- **Structural Rhythm**: Avoid arbitrary margin values. Vertical component pacing uses `space-md` (`1rem`) between sibling metric modules, and `space-xl` (`2.5rem`) between overarching training blocks.

## Elevation & Depth

This system operates without drop shadows, diffuse glows, or blur filters. Depth is established purely via **Tonal Stratification** paired with **Hairline Graphite Outlines**.

1. **Base Surface Layer**: `#0c0d0e` forms the canvas.
2. **Container Tier**: `#16171b` defines the card boundary, framed by a continuous `1px solid rgba(255, 255, 255, 0.08)`.
3. **Elevated Elements & Modals**: `#1c1e24` with a slightly higher contrast boundary (`#2e323b`).
4. **Zero Ambient Shadowing**: No `box-shadow` styles are permitted for baseline depth. Focus, selection, and priority states are indicated exclusively by shifting the hairline border from graphite to off-white (`#f9fafb`) or the respective semantic accent token.

## Shapes

The interface embraces a structured, engineering-grade contour profile (`roundedness: 1`). Soft, rounded corners are rejected in favor of restrained, machined curvature:

- Standard controls, chips, and metric cells feature a `0.25rem` (`4px`) border radius.
- Cards, containers, and data panels use `0.5rem` (`8px`) radii (`rounded-lg`).
- Modals, action sheets, and full overlays utilize `0.75rem` (`12px`) radii (`rounded-xl`).
- The silhouette communicates precision assembly, reminiscent of aerospace and high-end gym equipment machining.

## Components

### Buttons & Trigger Actions
- **Primary CTA**: Solid crisp off-white background (`#f9fafb`) with dark obsidian text (`#0c0d0e`). High-contrast, bold, non-gradient, rectangular silhouette with `0.25rem` radius. Never use accent green or bright blue for primary system CTAs.
- **Secondary / Ghost**: Deep charcoal surface (`#16171b`), 1px hairline border (`rgba(255, 255, 255, 0.08)`), and crisp white text. Hover state triggers border transition to `#4b5563` and surface to `#1f2126`.
- **Destructive**: Hairline border tinted with `#ef4444`, dark charcoal background, muted red text.

### Chips & Filters
- Compact height (`28px`), `0.25rem` corner radius, `JetBrains Mono` 11px uppercase label.
- **Inactive**: Solid `#101114` with a 1px border of `#23252a`, text `#9ca3af`.
- **Active**: Background `#1f2126`, border `#f9fafb`, text `#f9fafb`.

### Cards & Data Panels
- Background `#16171b`, border `1px solid rgba(255, 255, 255, 0.08)`.
- Internal padding is strictly `1.25rem`.
- Header composition requires a `label-micro-caps` uppercase section title in `#6b7280` coupled with right-aligned tabular metadata or state indicators.

### Metric Cells & Macro Displays
- Designed for high-frequency athlete logging (sets, reps, RPE, barbell loads, macros).
- Numbers are rendered in `metric-display` (`JetBrains Mono`, tabular figures).
- Macro telemetry uses subtle 2px bottom borders or 6px square indicators:
  - Protein: `#10b981`
  - Carbs: `#f59e0b`
  - Fats: `#a855f7`

### Form Inputs & Text Fields
- Background `#0c0d0e`, border `1px solid #23252a`.
- Typography is `Inter` 14px for general text, or `JetBrains Mono` for numerical set inputs.
- **Focus State**: Hairline border shifts to `#f9fafb`. Zero outer glow or halo rings.
- Suffix units (`KG`, `LBS`, `KCAL`, `RPE`) sit locked in `JetBrains Mono` 10px `#6b7280`.

### Checkboxes & List Rows
- **List Rows**: Divided by a `1px solid rgba(255, 255, 255, 0.05)` baseline border.
- **Set Checkbox**: Square box (`20px x 20px`), `2px` corner radius, border `1px solid #374151`. When checked, surface fills with `#10b981` and displays an obsidian checkmark icon.