---
id: improved-configuration
created: 2026-09-12
updated: 2026-09-12
---

# Design: Improved configuration

| Created | Updated |
| --- | --- |
| 2026-09-12 | 2026-09-12 |

## Approach

Give each render feature its own config section with `enabled` (default
on). Split table width from media width. Headings grow a third mode,
`simple`, beside full render and off.

## Analysis

Today `media.max_width` (default `0.5`) caps mermaid, standalone images,
**and** tables. Tables read denser than diagrams; 75% of the window is a
better default while diagrams stay at 50%. `config.max_cols` must take an
explicit width so table and media do not share one value.

Render features are always on. Users who want source-faithful markdown, or
who dislike heading graphics, have no per-feature switch. A nested
`{ enabled = true }` section per feature matches how this plugin already
groups `media`, stays merge-friendly with `vim.tbl_deep_extend`, and leaves
room for later keys (icons, borders) without a second config pass.

Heading is the only extra mode. Other features are a single `enabled`
boolean. Headings keep `enabled` as a boolean and add `simple` (default
false). `enabled = false` turns heading render off even if `simple` is
true.

### Heading modes

| Config | Unfocused | Focused (cursor on heading) |
| --- | --- | --- |
| `enabled = true` (default) | Kitty graphic when available; else conceal markers, GFM heading tokens, h1/h2 rule | Source + colorscheme heading highlights (unchanged) |
| `simple = true` | Conceal ATX `#` / setext underline. Title stays in the buffer as bold text using the colorscheme / Tree-sitter heading color. No graphic, no `SuperMarkdownH*`, no h1/h2 rule | Source, same as other chrome |
| `enabled = false` | No plugin marks or media jobs | Source |

`simple` is not the graphics fallback. Full mode still falls back to GFM
heading chrome when Kitty/`rsvg-convert`/`media.enabled` is unavailable.

### Feature map

Parse captures and media jobs gate on config:

| Section | Off means |
| --- | --- |
| `heading` | Skip heading marks and heading media |
| `code` | Skip fence chrome (language label, shade, backtick conceal). Mermaid still runs if `media.mermaid` is on |
| `quote` | Skip quote bar/body. Alerts still render if `alert` is on |
| `alert` | Treat `> [!NOTE]` as a plain quote when `quote` is on |
| `list` | Skip bullet replacement |
| `checkbox` | Skip task glyphs; list marker follows `list` |
| `table` | Skip overlay / wrap |
| `hr` | Skip thematic-break rule |
| `frontmatter` | Skip dimming |
| `link` | Skip accent + destination conceal |
| `codespan` | Skip inline code conceal/chrome |
| `strike` | Skip strikethrough conceal |
| `emphasis` | Skip `*` / `**` conceal |
| `emoji` | Skip shortcode replacement |
| `footnote` | Skip `[^x]` chrome |
| `media.image` | Skip image jobs and standalone conceal_lines |
| `media.mermaid` | Mermaid fences use code chrome only |
| `media.math` | Skip math jobs |
| `media.enabled` | Master switch: no images, mermaid, math, or heading graphics |

### Width helper

```lua
config.resolve_cols(win_cols, width)  -- 0–1 fraction or >1 columns
config.max_cols(win_cols)             -- media.max_width (0.5)
config.table_cols(win_cols)           -- table.max_width (0.75)
```

`media.job_max_cols` stays on `max_cols`. Tables call `table_cols`.

## Decisions

- Nested sections with `enabled`, not a flat boolean bag and not a separate
  `render = { ... }` table. Heading, table, and media already need extra keys.
- `heading.enabled` boolean plus `heading.simple` boolean. `enabled` is
  the master switch; `simple` only applies when enabled.
- `table` as the config key (Lua allows it). `max_width` lives there, not
  under media.
- `simple` headings combine colorscheme color with plugin bold; they do not
  restyle `Normal` or apply GFM heading tokens.

## Risks

- Tests that assert tables share `media.max_width` must switch to
  `table.max_width`.
- `code.enabled = false` with `media.mermaid = true` still needs the fence
  range for mermaid hide/show.
- A previous implementation also edited attach, init, util `buf_win`, and
  media mark lifetime. Those changes broke image and heading placement.
  The redo MUST stay in config + parse + table.lua + tests/README.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-12 | Initial design |
| 2026-09-12 | Heading `simple` is its own boolean |
| 2026-09-12 | Reverted implementation; stay parse-only |
