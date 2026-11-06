---
name: Obsidian Kinetic
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
  secondary: '#c5c6cf'
  on-secondary: '#2e3037'
  secondary-container: '#45464e'
  on-secondary-container: '#b4b4bd'
  tertiary: '#ffb3af'
  on-tertiary: '#650911'
  tertiary-container: '#fc7c78'
  on-tertiary-container: '#711419'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#6ffbbe'
  primary-fixed-dim: '#4edea3'
  on-primary-fixed: '#002113'
  on-primary-fixed-variant: '#005236'
  secondary-fixed: '#e1e2eb'
  secondary-fixed-dim: '#c5c6cf'
  on-secondary-fixed: '#191b22'
  on-secondary-fixed-variant: '#45464e'
  tertiary-fixed: '#ffdad7'
  tertiary-fixed-dim: '#ffb3af'
  on-tertiary-fixed: '#410005'
  on-tertiary-fixed-variant: '#842225'
  background: '#121314'
  on-background: '#e3e2e3'
  surface-variant: '#343536'
typography:
  display-hero:
    fontFamily: Be Vietnam Pro
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
  headline-lg:
    fontFamily: Be Vietnam Pro
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 34px
  headline-md:
    fontFamily: Be Vietnam Pro
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
  headline-sm:
    fontFamily: Be Vietnam Pro
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Be Vietnam Pro
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Be Vietnam Pro
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Be Vietnam Pro
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  label-md:
    fontFamily: Be Vietnam Pro
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
  label-sm:
    fontFamily: Be Vietnam Pro
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
  numeric-stat:
    fontFamily: Be Vietnam Pro
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 36px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style
The design system establishes a high-performance, focused environment tailored for health, kinetic discipline, and nutrition tracking. Built for an edge-to-edge mobile experience, the visual language avoids frivolous ornament, developer tags, synthetic skeuomorphism, and aggressive drop shadows.

### Core Philosophy
- **Aesthetic Direction:** Elevated Dark Minimal with modern iOS structural discipline. Surfaces remain deep, near-black obsidian, allowing nutritional metrics, performance markers, and progress vectors to emerge with quiet authority.
- **Audience & Context:** Athletes, health-conscious operators, and individuals demanding clarity in low-light gym conditions or fast, glanceable daily tracking.
- **Emotional Intent:** Discipline, clinical precision, calm confidence, and effortless motion. Zero cognitive clutter; interactions are immediate, deliberate, and visually silent until activated.

## Colors
The palette leverages deep, neutral dark steps accented by an electric emerald signal hue (`#10b981`). Background hierarchy is structured to preserve organic contrast without relying on visual weight from dropshadows.

### Structural Palettes
- **Canvas (`#0c0d0e`):** The primary view background. Renders true pitch-black ambiance for edge-to-edge layouts while easing OLED panel clipping.
- **Surface Level 1 (`#16171b`):** The structural container for cards, sheet presentations, navigation modules, and list clusters.
- **Surface Level 2 (`#1e2025`):** Segmented controls, input fields, interactive touch targets, and inset metric pills.
- **Subtle Borders (`#23252a` to `#272930`):** 1px structural framing used sparingly to delineate nested panels against baseline darks.

### Content Hierarchy
- **Text Primary (`#ffffff` / `#f3f4f6`):** Reserved for primary numerical readings, headline values, and primary labels.
- **Text Secondary (`#9ca3af`):** Body context, metadata tags, metric denominations (e.g., `kcal`, `reps`), and inactive states.
- **Text Muted (`#4b5563`):** Dividers, disabled actions, and de-emphasized grid rules.
- **Accent Emerald (`#10b981`):** Applied exclusively to positive deltas, macro adherence completion, primary call-to-actions, and active tab indicators. Never applied across expansive surface fills.

## Typography
Typographic rhythm relies uniformly on **Be Vietnam Pro** across displays, interface copies, and numeric charts. Its deliberate geometry ensures absolute legibility for full Vietnamese tone mark accents, complex workout terminology, and numeric data matrices.

- **Weight Disciplines:** Use `700` and `600` strictly for hero stats, screen titles, and interactive confirmations. Body prose is restricted to `400` weight to minimize visual noise on dark surfaces.
- **Numbers & Metrics:** Tabular figures must be enabled (`font-variant-numeric: tabular-nums`) across rep counters, macro targets, and timer screens to prevent layout shifts during live tracking.
- **Letter Spacing:** Maintain a subtle negative tracking (`-0.02em`) on headline entries above 24px for a compact, engineered feel; maintain zero tracking on body and micro metadata.

## Layout & Spacing
Designed explicitly around the standard 390px mobile viewport width. The layout adopts edge-to-edge fluid grouping bounded by strict dynamic padding and horizontal constraints.

### Screen Geometry
- **Outer Canvas Margins:** 16px (`1rem`) on horizontal bounds, stretching cards edge-to-edge while respecting the iOS status bar and dynamic home indicator safe areas.
- **Grid Architecture:** 4-column dynamic fluid layout for nested metrics (e.g., Protein, Carbs, Fats, Calories), separated by 12px to 16px gutters.
- **Vertical Rythm:** Stacks of cards operate on `space-md` (16px) separation. Internal grouping within a card uses `space-xs` (4px) to `space-sm` (8px) for tightly coupled label-value pairs.

## Elevation & Depth
Elevation is achieved exclusively via tonal layer distinction and hairline edge borders. Cast shadows, diffuse drop glows, and skeuomorphic gradients are strictly excluded.

### Layer Mechanics
1. **Canvas (`#0c0d0e`):** Infinite ground plane.
2. **Sheet / Card (`#16171b`):** 1px border stroke (`#23252a` or `#272930`). This baseline provides total structural separation against adjacent dark space without blur or diffuse spread.
3. **Elevated Controls & Floating Action Bars:** Solid `#1e2025` with hairline stroke `#272930`. If placed over scrollable lists, use an iOS-style native backdrop blur (`backdrop-filter: blur(20px)`) coupled with `#0c0d0ecc` alpha containment.
4. **Active Selection:** A crisp 1px stroke of `#10b981` replaces `#272930` to reflect touch focus or selected state without shifting element footprint.

## Shapes
Geometry uses clean, continuous rounding consistent with modern iOS human interface standards:

- **Cards & Primary Modules:** `16px` (`rounded-lg`) border-radius provides a tactile, smooth container without drifting into exaggerated bubble aesthetics.
- **Input Fields & Segmented Tiles:** `12px` border-radius.
- **Action Buttons & Modals:** `12px` to `16px` corner curvature. Pill silhouettes are banned for buttons, status tags, or filters; interactive chips must present structural rectangles with uniform `8px` to `10px` radius.

## Components

### Buttons
- **Primary Action:** Solid emerald background (`#10b981`), full width or responsive block, 52px height, 14px border radius. Typography: `#0c0d0e` bold text (providing maximum contrast on touch target). Zero shadows.
- **Secondary Action:** Surface fill (`#16171b`), 1px border (`#272930`), 52px height. Typography: `#f3f4f6` medium text.
- **Ghost/Tertiary:** No background, no border. Typography: `#9ca3af` hover/press to `#f3f4f6`.

### Cards & Metric Modules
- Base styling uses `#16171b` with a 1px border (`#23252a`).
- Internal padding: `16px` (`space-md`).
- Metric cards (e.g., Macro distribution) embed horizontal linear progress tracks: track base `#1e2025`, track fill `#10b981`, height 4px, border radius 2px.

### Inputs & Search
- Container height 48px, background `#16171b`, border 1px `#23252a`.
- Typography: `#ffffff`, placeholder text `#4b5563`.
- Active focus state: border transitions directly to `#10b981` with zero focus rings or outer glow rings.

### Lists & Workout Rows
- Flush edge rows separated by a 1px border line (`#1e2025`), no full-length horizontal divider bleed.
- Left-aligned icon or index counter in `#9ca3af`. Primary label in `#f3f4f6`. Numeric targets (e.g., `80 kg × 8`) right-aligned in tabular font styling.

### Filter & Selection Chips
- Rectangular with 8px radius; no pill shapes.
- Inactive: `#16171b` background, `#23252a` border, `#9ca3af` text.
- Active: `#1e2025` background, `#10b981` border stroke, `#10b981` text.

### Segmented Bar / Switcher
- Used for Daily / Weekly / Monthly toggles or Workout / Nutrition modes.
- Outer container: `#16171b`, 1px border `#23252a`, 40px height, 10px radius.
- Active segment: `#272930` background, `#ffffff` text, 6px internal radius, smooth lateral translate transitions.