# Saman Chat — Approved Design Handoff

## Source of truth priority

### General Priority
1. Approved screenshots in `screens/`
   - final visual authority for structure, spacing, hierarchy, and layout composition
2. Stitch MCP / Stitch design metadata
   - structured layout, dimensions, components, assets
3. `Stitch-Project-Brief.md` / state `DESIGN.md`
   - product intent and UX rationale
4. Existing Flutter code
   - functionality, state, navigation, API and business logic
5. Stitch-generated HTML/reference files in `references/`
   - reference only, never production source

### Exception Note
State 02 (`screens/02-active-conversation.png`) and State 09 (`screens/09-long-response-table.png`) contain known stale micro-copy/styling artifacts in their packaged screenshots.
For those exact documented mismatches:
[SCREEN-STATUS.md](file:///Users/saman/Desktop/project-root/design/saman-chat/SCREEN-STATUS.md) + newest `DESIGN.md` / `code.html` override **only** the known stale screenshot text/styling (e.g. title-case `Saman` over `SAMAN` / `COACH`, no `TELEMETRY`, cleaned section headings).
Do NOT weaken screenshot authority for any other state.


## Approved states
List exactly:

1. Empty / New Conversation
   `screens/01-empty-state.png`

2. Active Conversation
   `screens/02-active-conversation.png`

3. Food Photo Result
   `screens/03-food-photo-result.png`

4. Reminder / Proactive Nudge
   `screens/04-reminder-nudge.png`

5. Typing / Generating
   `screens/05-typing-generating.png`

6. Food Photo Analysis Loading
   `screens/06-food-photo-analysis.png`

7. Recoverable Error
   `screens/07-recoverable-error.png`

8. Food Photo Failure
   `screens/08-food-photo-failure.png`

9. Long Response / Markdown / Table
   `screens/09-long-response-table.png`

10. Full-height Drawer
    `screens/10-full-height-drawer.png`

## Global approved rules
- Saman Chat must visually align with the approved Saman Home design system
- dark obsidian canvas
- charcoal surfaces
- graphite borders
- off-white primary text
- muted gray secondary text
- restrained semantic green
- no blue AI styling
- no neon
- no gradients/glassmorphism
- no generic AI/robot/sparkle visuals

- conversation-first
- fitness coach first, AI second
- contextual data appears only when relevant
- no telemetry / system / model jargon in UI

## Composer rule
Default composer:
[ + ] Ask Saman about training, meals, recovery... [ mic ] [ send ]

- default send button = neutral gray / monochrome
- green reserved for contextual actions like:
  - Log meal →
  - Plan dinner →
  - Adjust workout →
  - Retake photo →

## Branding
- Header: `Saman Coach`
- Assistant identity inside conversation: `Saman`
- use small S monogram
- do not use:
  - AI Coach
  - SAMAN AI
  - robot icon
  - sparkle/star AI icon

## Implementation rule
Before editing Flutter:
1. inspect approved screenshot
2. inspect Stitch MCP data
3. inspect current Flutter Chat implementation
4. map approved design states to existing functionality
5. identify missing assets/data
6. preserve current architecture/business logic

Do not:
- rewrite backend
- replace Riverpod/state architecture unnecessarily
- invent APIs/providers
- treat Stitch-generated HTML as production code

## Stitch Project Brief Archive
Location:
`briefs/`

- briefs are versioned Stitch exports
- they show design evolution and rationale
- screenshots remain visual authority
- `briefs/INDEX.md` explains state coverage
- do not treat version number alone as state mapping

