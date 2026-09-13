---
id: improved-configuration
status: accepted
features: [plugin, render, media, style]
created: 2026-09-12
updated: 2026-09-13
---

# Improved configuration

| Created | Updated |
| --- | --- |
| 2026-09-12 | 2026-09-13 |

## What

### Why

One `media.max_width` forces tables to the same 50% cap as diagrams.
Render features cannot be turned off, and headings have no middle ground
between full GFM graphics and raw source.

### Requirements

- Each render feature SHALL be optional and SHALL default to on.
- Tables SHALL default to 75% of window content width. Mermaid and
  standalone images SHALL remain 50%. Values `0–1` are a window fraction;
  values `>1` are columns. Inline images SHALL still fit the window.
- Headings SHALL support three modes via two booleans (`enabled`, `simple`):
  - **enabled** (default: `enabled = true`, `simple = false`): current full
    render (graphics when available, else GFM heading chrome)
  - **disabled** (`enabled = false`): no heading marks or heading media
  - **simple** (`enabled = true`, `simple = true`): conceal ATX `#` and
    setext underlines; show the title as bold text in the colorscheme /
    Tree-sitter heading color; no graphic, no `SuperMarkdownH*`, no h1/h2
    rule. `enabled = false` wins over `simple`. In this mode, the heading
    is *not* rendered graphically - it is just normal text.
- Cursor-line source editing SHALL still apply to enabled and simple
  headings (chrome hides, markdown source is visible).
- `media.enabled` SHALL remain a master switch for images, mermaid, math,
  and heading graphics.
- README SHALL document the new sections and defaults.
- Existing image, mermaid, math, and heading-graphic placement SHALL NOT
  change except to honor the new flags.

### Scope

- In: config schema, per-feature gates in parse, table vs media width,
  heading simple/disabled, tests, README
- Out: attach/init/setup lifecycle changes; `buf_win` / window-picking
  changes; media placement, Kitty protocol, or heading SVG changes;
  per-buffer feature overrides; changing global/buffer enable commands

### Open questions

- None. Implement as one change (user request).

## How

### Approach

Parse-only. Nested `{ enabled = true }` sections; `heading.simple` is a
boolean. Table width uses `table.max_width`; media keeps `media.max_width`.
Gating is `if not config.feature(...) then return end` in parse — no
changes to attach, init, util, or media placement. Details:
[design](../design/improved-configuration.md).

### Impacted specifications

- `plugin` (existing) — configuration surface
- `render` (existing) — feature flags, heading modes, table width
- `media` (existing) — image flag, tables no longer share `media.max_width`
- `style` (existing) — simple heading bold without GFM tokens

### Plan

#### 1. Config only

- [x] 1.1 Add feature sections with `enabled = true`; `heading.simple`
      boolean (default false)
- [x] 1.2 `table.max_width = 0.75`; keep `media.max_width = 0.5`; add
      `media.image = true`
- [x] 1.3 `resolve_cols` / `table_cols`; `max_cols` stays on media width
- [x] 1.4 Helpers: heading mode and whether a feature is on
- [x] 1.5 `setup(opts)` still merges opts; `setup()` with no args MUST keep
      current values (do not reset to defaults)

#### 2. Parse gates (no media/attach edits)

- [x] 2.1 Skip parse marks when the matching feature is off
- [x] 2.2 Quote vs alert: disabled alert falls back to quote chrome;
      disabled quote still allows alerts
- [x] 2.3 Skip mermaid/math/image *jobs in parse* when those flags are off;
      mermaid off leaves fences to code chrome. Do not edit
      `media/init.lua`.

#### 3. Headings (parse only)

- [x] 3.1 `disabled`: no heading marks or media jobs
- [x] 3.2 `simple`: conceal markers; bold colorscheme heading text; no
      graphic / plugin heading groups / h1-h2 rule
- [x] 3.3 `enabled`: unchanged full path, including graphics fallback

#### 4. Table width

- [x] 4.1 Size tables with `table.max_width` in `table.lua` only

#### 5. Docs and tests

- [x] 5.1 Update README configuration sample
- [x] 5.2 Tests: defaults, table 75% vs media 50%, heading modes, a feature
      off emits no marks, setup() without opts keeps user config

## Change history

| Date | Change |
| --- | --- |
| 2026-09-12 | Initial proposal |
| 2026-09-12 | Implemented; ready for review |
| 2026-09-12 | Heading `simple` is its own boolean; `enabled` stays boolean |
| 2026-09-12 | setup() without opts no longer wipes user config on attach |
| 2026-09-12 | Reverted implementation (image/heading regressions); proposal reset |
| 2026-09-13 | Implementing as one change |
| 2026-09-13 | Implemented parse-only; simple heading bold group in style.lua |
| 2026-09-13 | Accepted; specs updated |
