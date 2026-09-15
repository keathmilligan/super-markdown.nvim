---
feature: media
created: 2026-09-11
updated: 2026-09-15
---

# Media

| Created | Updated |
| --- | --- |
| 2026-09-11 | 2026-09-15 |

## Purpose

Inline images, Mermaid diagrams, math, and heading graphics in markdown
buffers via the Kitty graphics protocol.

## Requirements

### Protocol

Images SHALL use the Kitty graphics protocol (Ghostty/Kitty) with unicode
placeholders. The protocol payload SHALL be PNG (`f=100`). SVG SHALL be
rasterized with `rsvg-convert` only. There is no Chromium or `mmdc` fallback.

Converted media SHALL be cached under `stdpath('cache')` by kind, theme,
and content identity. Images, Mermaid, and math use a content hash.
Headings use text, level, and pixel size. A cache hit SHALL NOT spawn
Node, rsvg, or magick.

### Images

Local PNG SHALL pass through. JPEG, GIF, and WebP MAY use ImageMagick
`magick` when present. Paths SHALL resolve relative to the markdown file.

A standalone image line (`![…](…)` as the whole line) SHALL hide that source
line unless the cursor is on it. The rendered image SHALL appear before the
source line. Inline images in a paragraph SHALL stay visible. When
`media.image` is false, image jobs and standalone source-line hide SHALL
NOT apply.

Standalone images SHALL NOT exceed `media.max_width` (default 75% of
window content width; values `>1` are columns) or `media.max_height`
(default the window height; values `0–1` are a window-height fraction,
`>1` are cells). Images that already fit those bounds SHALL keep their
natural size and SHALL NOT be upscaled. Aspect ratio SHALL be kept, so a
tall image MAY be narrower than `max_width` when height-capped. Inline
images SHALL fit the window width the same way (cap, no upscale). Mermaid
diagrams SHALL render at `media.max_width` and SHALL re-place on window
resize. Tables SHALL use `table.max_width`, not `media.max_width`.

`media.enabled` SHALL be a master switch: when false, images, mermaid,
math, and heading graphics SHALL NOT run.

### Mermaid

` ```mermaid ` fences SHALL render with `mermaid.render()` → SVG →
`rsvg-convert`. The diagram SHALL appear before the source. When the cursor
is outside the block, fence lines and source SHALL be hidden. When the cursor
is in the block, source SHALL be visible. When `media.mermaid` is false,
mermaid fences SHALL use code chrome only.

A parse failure SHALL show an in-buffer error. Only
parse errors SHALL be cached until that diagram’s source changes. Converter
noise and empty SVG SHALL NOT be cached as permanent failures.

### Math

`$…$` and `$$…$$` SHALL render TeX → SVG (MathJax lite adaptor) sized to
terminal cell height when the helper is installed. Inline math SHALL NOT
render when the cursor is on the same line. Math inside backticks SHALL NOT
render. Display math SHALL appear before the source, with the same
outside-block hide behavior as Mermaid.

If the helper is missing, or `media.math` is false, math SHALL remain as
source.

### Headings

Unfocused headings in full heading mode SHALL render as Kitty graphics
using the same PNG protocol and `rsvg-convert` path as other SVG media.
The graphic SHALL appear where its concealed source was, before following
content. Its virtual-line host SHALL be selected independently of cursor
position and SHALL NOT be a heading, image, or Mermaid source row. Background
SHALL be transparent so editor `Normal` shows through. Heading graphics SHALL
NOT run when heading is disabled or simple.

The graphic SHALL be sized like GitHub markdown (`h1` 2em, `h2` 1.5em, `h3`
1.25em, `h4` 1em, `h5` 0.875em, `h6` 0.85em). `1em` is the terminal cell
height. h1 and h2 SHALL include the GFM bottom border. Long
headings SHALL wrap to the window content width.

The graphic SHALL show the heading’s visible text: ATX hashes and setext
underlines stripped; inline markers stripped; link labels kept.

If Kitty graphics or `rsvg-convert` is unavailable, or media is disabled,
full-mode headings SHALL NOT emit graphics and SHALL fall back to render
chrome.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-11 | Initial spec from gfm-inline-render |
| 2026-09-12 | Unfocused headings render as cached Kitty graphics |
| 2026-09-12 | Tables share media.max_width with mermaid and standalone images |
| 2026-09-13 | media.image flag; tables use table.max_width; mermaid off is code chrome |
| 2026-09-13 | media.max_width default 75% |
| 2026-09-13 | media.max_height default window height so max_width is reachable |
| 2026-09-13 | images cap to max_width/max_height; do not upscale |
| 2026-09-15 | Heading virtual-line hosts are structural and cursor-independent |
