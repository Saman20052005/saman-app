# Saman Chat — Screen & Reference Status

This document tracks the approval, visual artifact fidelity, and reference status for all 10 approved Saman Chat design states.

---

## Source of Truth & Exception Rules

> [!IMPORTANT]
> **General Priority:**
> 1. Approved screenshots in `screens/` (final visual authority for structure, spacing, hierarchy, layout composition)
> 2. Structured Stitch metadata (`code.html` and `DESIGN.md` in `references/`)
> 3. Documented UX rationale and briefs
> 4. Existing Flutter functionality and architecture
>
> **Documented Exception for State 02 and State 09:**
> The packaged `screen.png` files for State 02 and State 09 represent **VISUAL SNAPSHOTS WITH KNOWN STALE MICRO-STYLING**.
> For these two states only, the latest `code.html`, `DESIGN.md`, and the documented final micro-rules in this file **strictly override** the stale text and micro-styling artifacts visible in the screenshot.

---

## State Status Inventory

### State 01 — Empty / New Conversation
- **Canonical Screenshot:** `screens/01-empty-state.png`
- **Canonical Reference:** `references/01-empty-state/` (`code.html`, `DESIGN.md`)
- **Screenshot Status:** FINAL APPROVED VISUAL REFERENCE
- **Reference Status:** COMPLETE
- **Approval Status:** FULLY APPROVED
- **Known Exceptions:** None. Clean dark obsidian canvas, centered S monogram, neutral monochrome composer.

---

### State 02 — Active Conversation
- **Canonical Screenshot:** `screens/02-active-conversation.png`
- **Canonical Reference:** `references/02-active-conversation/` (`code.html`, `DESIGN.md`)
- **Screenshot Status:** VISUAL SNAPSHOT — OUTDATED MICRO-STYLING
- **Reference Status:** COMPLETE (latest clean export)
- **Approval Status:** APPROVED WITH DOCUMENTED MICRO-EXCEPTION
- **Visual Composition Authority:** Approved for conversational layout, speech bubble geometry, inline training/nutrition cards, quick suggestion chips, and composer docking.
- **Known Screenshot Exception:**
  - Assistant message header in `screen.png` visually renders uppercase **`SAMAN`** (due to Tailwind `uppercase` class applied to label micro-caps).
- **Final Approved Implementation Rule:**
  - Assistant identity must be implemented as title-case **`Saman`** alongside the 20x20px charcoal `S` monogram badge.
  - Never render `SAMAN`, `Saman COACH`, or `SAMAN AI`.

---

### State 03 — Food Photo Result
- **Canonical Screenshot:** `screens/03-food-photo-result.png`
- **Canonical Reference:** `references/03-food-photo-result/` (`code.html`, `DESIGN.md`)
- **Screenshot Status:** FINAL APPROVED VISUAL REFERENCE
- **Reference Status:** COMPLETE
- **Approval Status:** FULLY APPROVED
- **Known Exceptions:** None. Structured meal estimate card, macro chips, and semantic green `Log meal →` primary CTA.

---

### State 04 — Reminder / Proactive Nudge
- **Canonical Screenshot:** `screens/04-reminder-nudge.png`
- **Canonical Reference:** `references/04-reminder-nudge/` (`code.html`, `DESIGN.md`)
- **Screenshot Status:** FINAL APPROVED VISUAL REFERENCE
- **Reference Status:** COMPLETE
- **Approval Status:** FULLY APPROVED
- **Known Exceptions:** None. Proactive check-in card, notification bell dot, follow-up suggestion bubble.

---

### State 05 — Typing / Generating
- **Canonical Screenshot:** `screens/05-typing-generating.png`
- **Canonical Reference:** `references/05-typing-generating/` (`code.html`, `DESIGN.md`)
- **Screenshot Status:** FINAL APPROVED VISUAL REFERENCE
- **Reference Status:** COMPLETE
- **Approval Status:** FULLY APPROVED
- **Known Exceptions:** None. Subtle three-dot animation bubble, natural loading text, neutral monochrome stop button.

---

### State 06 — Food Photo Analysis Loading
- **Canonical Screenshot:** `screens/06-food-photo-analysis.png`
- **Canonical Reference:** `references/06-food-photo-analysis/` (`code.html`, `DESIGN.md`)
- **Screenshot Status:** FINAL APPROVED VISUAL REFERENCE
- **Reference Status:** COMPLETE
- **Approval Status:** FULLY APPROVED
- **Known Exceptions:** None. Food image thumbnail preview, scanning progress text, no premature macro estimation.

---

### State 07 — Recoverable Error
- **Canonical Screenshot:** `screens/07-recoverable-error.png`
- **Canonical Reference:** `references/07-recoverable-error/` (`code.html`, `DESIGN.md`)
- **Screenshot Status:** FINAL APPROVED VISUAL REFERENCE
- **Reference Status:** COMPLETE
- **Approval Status:** FULLY APPROVED
- **Known Exceptions:** None. Calm conversational recovery message, green `Retry →` CTA, gray `Edit question` button. No red error banner.

---

### State 08 — Food Photo Failure
- **Canonical Screenshot:** `screens/08-food-photo-failure.png`
- **Canonical Reference:** `references/08-food-photo-failure/` (`code.html`, `DESIGN.md`)
- **Screenshot Status:** FINAL APPROVED VISUAL REFERENCE
- **Reference Status:** COMPLETE
- **Approval Status:** FULLY APPROVED
- **Known Exceptions:** None. Friendly photographic advice bullet list, `Retake photo →` and `Enter meal manually →` CTAs.

---

### State 09 — Long Response / Markdown / Table
- **Canonical Screenshot:** `screens/09-long-response-table.png`
- **Canonical Reference:** `references/09-long-response-table/` (`code.html`, `DESIGN.md`)
- **Screenshot Status:** VISUAL SNAPSHOT — OUTDATED MICRO-STYLING
- **Reference Status:** COMPLETE (latest clean export)
- **Approval Status:** APPROVED WITH DOCUMENTED MICRO-EXCEPTIONS
- **Visual Composition Authority:** Approved for multi-section periodization response layout, numbered recommendation items, compact mobile metric table, and dual CTA buttons (`Adjust tomorrow's workout →` and `Plan breakfast →`).
- **Known Screenshot Exceptions:**
  - Screenshot still shows badge **`Saman COACH`** with green pill.
  - Screenshot still shows **`TELEMETRY SYNCED`** in small monospace font next to the feedback action row.
  - Screenshot still displays older uppercase section headings (`TRAINING FOCUS`, `NUTRITION DELTA`, `TOMORROW STRATEGY`).
- **Final Approved Implementation Rules:**
  - Assistant identity must be **`Saman`** (title case, without `COACH` badge).
  - No `TELEMETRY` or system telemetry status text anywhere on canvas.
  - Conversational Markdown headings must be title-case: **`Training`**, **`Nutrition`**, **`Tomorrow`** (matching the updated `code.html`).
  - Metric comparison table headers must be: **`Metric`**, **`Today`**, **`Target`**.

---

### State 10 — Full-Height Drawer
- **Canonical Screenshot:** `screens/10-full-height-drawer.png`
- **Canonical Reference:** `references/10-full-height-drawer/` (`code.html`, `DESIGN.md`)
- **Screenshot Status:** FINAL APPROVED VISUAL REFERENCE
- **Reference Status:** COMPLETE
- **Approval Status:** FULLY APPROVED
- **Known Exceptions:** None. ~80% width modal overlay, translucent dark scrim (`bg-black/60`), `+ New conversation`, Recent conversations list, Coach tools, active Reminders indicator, and Saman preferences.
