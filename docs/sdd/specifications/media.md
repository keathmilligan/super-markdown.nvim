---
feature: media
created: 2026-09-11
updated: 2026-09-12
---

# Media

| Created | Updated |
| --- | --- |
| 2026-09-11 | 2026-09-12 |

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
source line. Inline images in a paragraph SHALL stay visible.

Mermaid diagrams, standalone images, and tables SHALL fit `media.max_width`
(default 50% of window content width; values `>1` are columns). Inline
images SHALL fit the window width. Mermaid SHALL re-place on window resize.

### Mermaid

` ```mermaid ` fences SHALL render with `mermaid.render()` → SVG →
`rsvg-convert`. The diagram SHALL appear before the source. When the cursor
is outside the block, fence lines and source SHALL be hidden. When the cursor
is in the block, source SHALL be visible.

A parse failure SHALL show an in-buffer error. Only
parse errors SHALL be cached until that diagram’s source changes. Converter
noise and empty SVG SHALL NOT be cached as permanent failures.

### Math

`$…$` and `$$…$$` SHALL render TeX → SVG (MathJax lite adaptor) sized to
terminal cell height when the helper is installed. Inline math SHALL NOT
render when the cursor is on the same line. Math inside backticks SHALL NOT
render. Display math SHALL appear before the source, with the same
outside-block hide behavior as Mermaid.

If the helper is missing, math SHALL remain as source.

### Headings

Unfocused headings SHALL render as Kitty graphics using the same PNG
protocol and `rsvg-convert` path as other SVG media. The graphic SHALL
appear before the source. Background SHALL be transparent so editor
`Normal` shows through.

The graphic SHALL be sized like GitHub markdown (`h1` 2em, `h2` 1.5em, `h3`
1.25em, `h4` 1em, `h5` 0.875em, `h6` 0.85em). `1em` is the terminal cell
height. h1 and h2 SHALL include the GFM bottom border. Long
headings SHALL wrap to the window content width.

The graphic SHALL show the heading’s visible text: ATX hashes and setext
underlines stripped; inline markers stripped; link labels kept.

If Kitty graphics or `rsvg-convert` is unavailable, or media is disabled,
headings SHALL NOT emit graphics and SHALL fall back to render chrome.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-11 | Initial spec from gfm-inline-render |
| 2026-09-12 | Unfocused headings render as cached Kitty graphics |
| 2026-09-12 | Tables share media.max_width with mermaid and standalone images |
