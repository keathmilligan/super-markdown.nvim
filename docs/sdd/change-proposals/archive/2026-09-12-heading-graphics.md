---
id: heading-graphics
status: accepted
features: [render, media, style]
created: 2026-09-11
updated: 2026-09-12
---

# Heading graphics

| Created | Updated |
| --- | --- |
| 2026-09-11 | 2026-09-12 |

## What

### Why

Neovim cannot grow heading font size. The current chrome conceals `#` and
paints bold gfm-hotview colors, so every heading is still one terminal row.
gfm-hotview sizes h1 at `2em` down to h6 at `0.85em`. Kitty graphics already
render math and images at real pixel sizes; headings should use the same
path so an unfocused heading reads at GFM scale.

When the cursor is on a heading the user is editing it, so the source and
the colorscheme’s markdown heading highlights must come back.

### Requirements

- When the cursor is **not** on a heading, that heading SHALL render as a
  Kitty graphic sized like gfm-hotview (`h1` 2em, `h2` 1.5em, `h3` 1.25em,
  `h4` 1em, `h5` 0.875em, `h6` 0.85em muted). `1em` is the terminal cell
  height. h1 and h2 SHALL include the bottom border from gfm-hotview.
- The graphic SHALL show the heading’s visible text (no ATX `#` / setext
  underline). Background SHALL be transparent so editor `Normal` shows
  through. Color SHALL follow gfm-hotview heading tokens (foreground; h6
  muted), not the colorscheme.
- When the cursor is **on** the heading (any line of a setext heading), the
  graphic SHALL hide and the source SHALL show as normal markdown. Plugin
  heading highlights (`SuperMarkdownH*`) SHALL NOT apply on the focused
  heading; Tree-sitter / colorscheme heading highlights SHALL be used.
- ATX and setext headings SHALL both be supported.
- Long headings SHALL wrap to the window content width.
- Graphics SHALL cache by text, level, theme, and pixel size. Rasterize SVG
  with `rsvg-convert` only.
- `k` / Up SHALL NOT stick on a concealed heading host line.
- If Kitty graphics or `rsvg-convert` is unavailable, keep today’s conceal +
  highlight + h1/h2 underline chrome.

### Scope

- In: ATX and setext headings in markdown buffers; unfocused graphic at GFM
  sizes; focused source with colorscheme highlights; h1/h2 rule in the
  graphic; wrap to window width; cache; fallback without graphics.
- Out: heading permalink anchors; changing non-heading chrome; rasterizing
  the whole buffer; custom per-level colorschemes while unfocused.

### Open questions

- None. Inline markdown inside a heading is stripped to visible text in the
  graphic (link labels, no `**` / `` ` ``). Full inline styling in the SVG
  can come later.

## How

### Approach

Treat an unfocused heading like a standalone image: conceal the source
line(s), draw a PNG above them. Build a small SVG (Pango text via librsvg)
at the GFM em size, convert with `rsvg-convert`, place with the existing
Kitty protocol. On the cursor line, skip the graphic and the plugin heading
highlights so the highlighter shows through.

Details are in [design/heading-graphics.md](../design/heading-graphics.md).

### Impacted specifications

- `render` (existing)
- `media` (existing)
- `style` (existing)

### Plan

#### 1. Parse and cursor

- [x] 1.1 Emit a heading media job (level, text, row span) instead of only
      conceal + `SuperMarkdownH*` + virt-line underline
- [x] 1.2 Conceal heading source lines when the cursor is outside the span;
      show source and drop plugin heading highlights when the cursor is inside
- [x] 1.3 Treat heading source rows as media-open so `k` / Up can leave them

#### 2. Graphic

- [x] 2.1 Generate SVG text at gfm-hotview sizes, weight 600, theme colors,
      h1/h2 bottom border; wrap to window pixel width
- [x] 2.2 Rasterize with `rsvg-convert`; cache by text, level, theme, width
- [x] 2.3 Place the PNG before the source; hide it on the focused heading
- [x] 2.4 Fall back to current heading chrome when graphics or rsvg is missing

#### 3. Tests

- [x] 3.1 Unfocused heading plan includes a media job and concealed source
- [x] 3.2 Focused heading shows source and no heading graphic / SuperMarkdownH*
- [x] 3.3 Setext span covers title and underline; ATX is one line

## Change history

| Date | Change |
| --- | --- |
| 2026-09-11 | Initial proposal |
| 2026-09-11 | Approved; implementation complete |
| 2026-09-12 | Accepted; specs updated |
