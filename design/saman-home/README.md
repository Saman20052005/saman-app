# Saman Home — Approved Design Handoff

## Source of truth priority

1. `home-screen.png`
   - FINAL APPROVED visual reference.
   - Use for visual hierarchy, spacing, proportions, density, card sizing, chart appearance, carousel composition, icons and bottom navigation.

2. Stitch MCP / Stitch design metadata
   - Use for structured layout information, dimensions, components, assets and design-system data.

3. `Stitch-Project-Brief.md`
   - Use for product intent and UX rationale.

4. Existing Flutter code
   - Source of truth for functionality, navigation, state, providers, models, APIs and business logic.

5. `home-screen.html`
   - Reference only.
   - Do NOT treat generated HTML as production implementation code.

## Implementation rule

Preserve existing Flutter architecture and business logic.

Before editing any Flutter file:
- inspect the approved screenshot,
- inspect Stitch MCP data,
- inspect the current Home implementation,
- map design sections to existing Flutter components,
- report missing assets/data and implementation risks.

Do not refactor unrelated code.
Do not modify backend/API behavior for visual implementation.