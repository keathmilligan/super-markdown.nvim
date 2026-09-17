---
feature: render
created: 2026-09-11
updated: 2026-09-17
---

# Render

| Created | Updated |
| --- | --- |
| 2026-09-11 | 2026-09-17 |

## Purpose

In-buffer GFM chrome via Tree-sitter, conceal, and extmarks. Source on the
cursor line stays editable.

## Requirements

### Pipeline

Rendering SHALL walk Tree-sitter for the visible range plus a small overscan.
Updates SHALL be debounced (insert longer than normal). Cursor movement SHALL
NOT reparse; it SHALL only retarget cursor-line and in-block visibility.

### Feature flags

Heading, code, quote, alert, list, checkbox, table, hr, frontmatter, link,
codespan, strike, emphasis, emoji, and footnote SHALL each be independently
optional and SHALL default to on. When a feature is off, its chrome SHALL
NOT be applied.

- `code` off SHALL NOT skip mermaid diagram jobs when mermaid media is on.
- `alert` off SHALL treat GitHub alert markers as a plain quote when
  `quote` is on.
- `quote` off SHALL NOT prevent alerts when `alert` is on.
- `checkbox` off SHALL skip task glyphs; the list marker SHALL follow
  `list`.
- `list` off SHALL skip bullets and list wrap.

### Headings

ATX and setext headings SHALL both be supported. Heading render SHALL
follow `heading.enabled` and `heading.simple`. `enabled = false` SHALL win
over `simple`.

When heading is disabled, the plugin SHALL NOT apply heading marks or
heading media. Source SHALL remain as written.

When heading is enabled and `simple` is true, ATX `#` and setext underlines
SHALL be concealed. The title SHALL stay in the buffer as bold text using
the colorscheme / Tree-sitter heading color. The plugin SHALL NOT emit a
heading graphic, plugin heading highlight groups, or an h1/h2 rule.

When heading is enabled and `simple` is false (default), and Kitty graphics
and `rsvg-convert` are available and the cursor is not on the heading (any
line of a setext heading), the heading SHALL render as a graphic. Source
markers and setext underlines SHALL NOT be visible. See [media](media.md).
`simple` is not the graphics fallback: full mode SHALL still fall back to
GFM heading chrome when Kitty / `rsvg-convert` / `media.enabled` is
unavailable.

When the cursor is on an enabled or simple heading, chrome SHALL hide and
the source SHALL show as normal markdown. Plugin heading highlights SHALL
NOT apply; Tree-sitter / colorscheme heading highlights SHALL be used.

Heading graphic placement SHALL depend only on buffer structure, not cursor
position. Focusing a heading SHALL hide only that heading's graphic; moving
the cursor across neighboring headings, images, Mermaid blocks, or body lines
SHALL NOT move other heading graphics to different host rows.

Packed consecutive headings SHALL preserve source order while unfocused. In
a gapless run, focusing a later heading MAY leave a preceding graphic below
the focused source until the cursor leaves the run.

If full heading mode cannot use graphics, ATX heading markers SHALL be
concealed, the title SHALL use plugin heading highlights, and h1 and h2
SHALL show a full-width border underline.

#### Unfocused heading graphic

- GIVEN heading is enabled and not simple
- AND Kitty graphics and `rsvg-convert` are available
- AND the cursor is not on a heading
- WHEN that heading is in the viewport
- THEN it SHALL appear as a GFM-sized graphic of the visible heading text
- AND ATX `#` / setext underline SHALL NOT be visible

#### Focused heading source

- GIVEN the cursor is on an enabled or simple heading (including a setext
  underline)
- WHEN rendering updates
- THEN heading chrome and any graphic SHALL NOT appear
- AND the markdown source SHALL be visible
- AND plugin heading highlight groups SHALL NOT apply to that heading

#### Simple heading

- GIVEN `heading.enabled` is true and `heading.simple` is true
- WHEN a heading is unfocused
- THEN ATX `#` / setext underline SHALL be concealed
- AND the title SHALL be bold colorscheme / Tree-sitter heading text
- AND no graphic, plugin heading group, or h1/h2 rule SHALL apply

#### Disabled heading

- GIVEN `heading.enabled` is false
- WHEN a heading is in the viewport
- THEN the plugin SHALL NOT apply heading marks or heading media

### Lists and tasks

Unordered list markers SHALL render as a bullet. Task-list checkboxes SHALL
replace the list marker and `[ ]` / `[x]` with unchecked / checked glyphs.
The leading `- ` before a checkbox SHALL NOT remain visible.

When a list-item source line is wider than `list.max_width` (default window
content width; values `>1` are columns), the item SHALL wrap on word
boundaries. Wrapped continuation lines SHALL indent so they align with the
start of the item text after the marker, checkbox, or existing continuation
indent (GitHub hanging indent). Nested items SHALL keep their source indent
and hang from that item’s text column. Extra wrapped lines SHALL use
`virt_lines`, or overlay the source line's wrap continuations when those
already exist. A line that already fits SHALL NOT be wrap-overlaid.

The cursor line SHALL show the source list line. Lines that host inline
image or math media SHALL NOT be wrap-overlaid. List items inside quotes
or alerts SHALL keep the left bar on wrapped continuations.

#### Short item unchanged

- GIVEN an unordered list item whose source line fits `list.max_width`
- WHEN it is rendered unfocused
- THEN it SHALL keep bullet chrome and SHALL NOT gain wrap overlay

#### Long item hanging indent

- GIVEN an unordered, ordered, or task list item wider than
  `list.max_width`
- WHEN it is rendered unfocused
- THEN wrapped lines SHALL hang under the item text after the marker or
  checkbox

### Quotes and alerts

Blockquote `>` SHALL conceal to a left bar. GitHub alert markers
(`> [!NOTE]` and the other four types) SHALL conceal to the alert title and
icon when the cursor is not on that line. Disabled alerts SHALL render as
plain quotes when quotes are on. Disabled quotes SHALL NOT prevent alerts.

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
conceal fence delimiter lines. When mermaid media is off, mermaid fences
SHALL use code chrome only.

### Tables

Pipe tables SHALL render as a reconstructed overlay even when some rows have
leading spaces before `|`. Overlay formatting SHALL start at the first `|`.
Source pipes SHALL be concealed. The cursor line SHALL show the source table
row.

When a table is wider than `table.max_width` (default 75% of window content
width; values `>1` are columns), column widths SHALL shrink so the table
fits. Cell text SHALL wrap on word boundaries inside the cell, and the row
SHALL grow downward. Shorter cells in the same row SHALL pad to that height
(HTML table layout). Extra wrapped lines SHALL use `virt_lines`, or overlay
the source line's wrap continuations when those already exist.

### Other chrome

Thematic breaks SHALL render as a full-width border rule. Links SHALL use
accent color. Strikethrough, emoji shortcodes, and footnote markers SHALL
render inline. YAML/TOML frontmatter SHALL be dimmed and SHALL remain in the
buffer.

### Cursor and navigation

Virt-text and conceal used as chrome SHALL hide on the cursor line so the
source is editable. `k` / Up SHALL NOT stick on a concealed media host line
(mermaid, display math, standalone image, heading) when the graphic extends
above the window. `k` / Up SHALL still land on a heading source, and inserting
a newline on a focused heading SHALL NOT move the cursor past a following
heading graphic.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-11 | Initial spec from gfm-inline-render |
| 2026-09-12 | Unfocused headings are graphics; focused headings show source |
| 2026-09-12 | Wide tables wrap cell text and pad sibling cells to row height |
| 2026-09-13 | Per-feature flags; heading simple/off; tables use table.max_width |
| 2026-09-15 | Stabilized heading graphic placement across cursor movement |
| 2026-09-17 | List items wrap with GitHub hanging indent |
