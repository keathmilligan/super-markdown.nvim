---
feature: render
created: 2026-09-11
updated: 2026-09-12
---

# Render

| Created | Updated |
| --- | --- |
| 2026-09-11 | 2026-09-12 |

## Purpose

In-buffer GFM chrome via Tree-sitter, conceal, and extmarks. Source on the
cursor line stays editable.

## Requirements

### Pipeline

Rendering SHALL walk Tree-sitter for the visible range plus a small overscan.
Updates SHALL be debounced (insert longer than normal). Cursor movement SHALL
NOT reparse; it SHALL only retarget cursor-line and in-block visibility.

### Headings

ATX and setext headings SHALL both be supported.

When Kitty graphics and `rsvg-convert` are available and the cursor is not
on the heading (any line of a setext heading), the heading SHALL render as
a graphic. Source markers and setext underlines SHALL NOT be visible. See
[media](media.md).

When the cursor is on the heading, the graphic SHALL hide and the source
SHALL show as normal markdown. Plugin heading highlights SHALL NOT apply;
Tree-sitter / colorscheme heading highlights SHALL be used.

If Kitty graphics or `rsvg-convert` is unavailable, ATX heading markers
SHALL be concealed, the title SHALL use plugin heading highlights, and h1
and h2 SHALL show a full-width border underline.

#### Unfocused heading graphic

- GIVEN Kitty graphics and `rsvg-convert` are available
- AND the cursor is not on a heading
- WHEN that heading is in the viewport
- THEN it SHALL appear as a GFM-sized graphic of the visible heading text
- AND ATX `#` / setext underline SHALL NOT be visible

#### Focused heading source

- GIVEN the cursor is on a heading (including a setext underline)
- WHEN rendering updates
- THEN the graphic SHALL NOT appear
- AND the markdown source SHALL be visible
- AND plugin heading highlight groups SHALL NOT apply to that heading

### Lists and tasks

Unordered list markers SHALL render as a bullet. Task-list checkboxes SHALL
replace the list marker and `[ ]` / `[x]` with unchecked / checked glyphs.
The leading `- ` before a checkbox SHALL NOT remain visible.

### Quotes and alerts

Blockquote `>` SHALL conceal to a left bar. GitHub alert markers
(`> [!NOTE]` and the other four types) SHALL conceal to the alert title and
icon when the cursor is not on that line.

### Code fences

When the cursor is outside a fenced code block:

- Both fence lines SHALL remain visible
- Fence backticks SHALL be concealed
- The opening fence language name SHALL be muted
- Every line of the block, including both fences, SHALL use the code-block
  shade to the end of the window

When the cursor is anywhere in the block (opening fence through closing fence):

- Fence backticks SHALL be visible
- The language name SHALL use the editor syntax highlight
- The code-block shade SHALL remain

The plugin SHALL own fence chrome. Tree-sitter markdown highlights SHALL NOT
conceal fence delimiter lines.

### Tables

Pipe tables SHALL render as a reconstructed overlay even when some rows have
leading spaces before `|`. Overlay formatting SHALL start at the first `|`.
Source pipes SHALL be concealed. The cursor line SHALL show the source table
row.

When a table is wider than `media.max_width` (same cap as mermaid and
standalone images), column widths SHALL shrink so the table fits. Cell text
SHALL wrap on word boundaries inside the cell, and the row SHALL grow
downward. Shorter cells in the same row SHALL pad to that height (HTML table
layout). Extra wrapped lines SHALL use `virt_lines`, or overlay the source
line's wrap continuations when those already exist.

### Other chrome

Thematic breaks SHALL render as a full-width border rule. Links SHALL use
accent color. Strikethrough, emoji shortcodes, and footnote markers SHALL
render inline. YAML/TOML frontmatter SHALL be dimmed and SHALL remain in the
buffer.

### Cursor and navigation

Virt-text and conceal used as chrome SHALL hide on the cursor line so the
source is editable. `k` / Up SHALL NOT stick on a concealed media host line
(mermaid, display math, standalone image, heading) when the graphic extends
above the window.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-11 | Initial spec from gfm-inline-render |
| 2026-09-12 | Unfocused headings are graphics; focused headings show source |
| 2026-09-12 | Wide tables wrap cell text and pad sibling cells to row height |
