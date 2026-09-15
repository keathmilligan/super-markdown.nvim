---
id: stable-heading-hosts
status: accepted
features: [render, media]
created: 2026-09-14
updated: 2026-09-15
---

# Stable heading virt_line hosts

| Created | Updated |
| --- | --- |
| 2026-09-14 | 2026-09-15 |

## What

### Why

Unfocused heading graphics are Kitty placeholder grids on `virt_lines`.
`heading_host` picks those host rows from the cursor, so `j`/`k` onto a
heading (or onto the paragraph used as a host) **moves** neighbor
placeholders to another buffer row. Neovim then rewrites the `U+10EEEE`
grid; multiplexers that recover virtual placements by scanning cells
(Herdr, Zellij-class) treat that as a new layout and re-place every
image.

Native Ghostty absorbs the same Lua. The host movement is still wasted
work, and it is the plugin-side half of the Herdr jank in
`~/ws/notes/analysis-neovim-super-markdown-performance.md` (mitigation:
stable virt_line hosts).

Hiding the focused heading’s own graphic is required. Re-hosting
**other** headings is not, except to keep a consecutive stack split
around the line being edited. This change drops that split so hosts
depend only on buffer structure.

### Requirements

- `heading_host` SHALL NOT use the cursor. Suitable vs unsuitable host
  rows SHALL be the same whether a heading, image, or mermaid block is
  focused.
- Unsuitable hosts SHALL be rows marked `heading_source`,
  `image_source`, `mermaid_source`, or `mermaid_anchor`. Concealed
  media must not carry another heading’s `virt_lines` (those lines do
  not paint).
- Prefer the first suitable row **after** the heading, with
  `virt_lines_above`. If none, the last suitable row **before** it,
  with `virt_lines` below. If none, the heading’s own source row with
  `virt_lines_above`.
- When the cursor is outside a heading run, each heading graphic SHALL
  still appear where its concealed source was (before following
  content). Packed consecutive headings SHALL keep source order on
  their shared host.
- Focusing a heading SHALL hide only that heading’s graphic
  (`hide_in_block`). Neighbor host rows SHALL NOT change.
- In a gapless consecutive run, that stable host MAY leave preceding
  graphics below the focused source until the cursor leaves the run.
- A following heading SHALL NOT host on the line being edited
  (heading sources are never hosts).
- `k` / Up SHALL still land on heading source. Inserting a newline on
  a focused heading SHALL NOT jump the cursor past a following
  heading graphic.
- Image, mermaid, and math hosting SHALL NOT change.

### Scope

- In: `heading_host` / apply assignment of heading media rows; tests
  that encode cursor-dependent hosts; render/media wording for
  placement vs cursor.
- Out: incremental extmarks / `clear_namespace` on cursor (separate
  mitigation); Herdr or protocol changes; heading SVG; simple/off
  heading modes; remapping `<CR>`.

### Open questions

- None. Approval accepts that, for gapless consecutive headings, a
  predecessor’s graphic stays below a focused later heading. Unfocused
  order is unchanged.

## How

### Approach

Replace the cursor predicates in `heading_host` with a structural walk.
Details: [design](../design/stable-heading-hosts.md).

`apply()` still assigns `mark.row` every paint so edits that add or
remove suitable lines still retarget. The assignment becomes a pure
function of the plan and buffer, not `cursor_row`.

### Impacted specifications

- `render` (existing) — heading graphic host vs cursor
- `media` (existing) — “graphic before source” vs extmark row

### Plan

#### 1. Host selection

- [x] 1.1 Rewrite `apply.heading_host`: unsuitable rows ignore cursor;
      prefer after/`virt_lines_above`, then before/below, then own row
- [x] 1.2 Remove the `<CR>` dodge (`host ~= cursor_row`) and the
      “following heading skips the cursor row” loop; both become
      redundant if heading sources are never hosts and after is
      preferred

#### 2. Tests

- [x] 2.1 `heading_host` on a setext after an empty line uses the
      first suitable **after** row (`virt_lines_above`), not the
      previous line
- [x] 2.2 Consecutive headings: following graphic still not hosted on
      the edited heading; host for the unfocused heading is unchanged
      when the cursor enters the other heading or the previous
      paragraph
- [x] 2.3 `tests/heading_order.lua`: keep unfocused source order,
      “next preview below while editing the earlier heading,” not
      hosted on the edited line, newline does not skip the next
      graphic; drop or invert “preceding preview stays above” for
      gapless consecutive headings
- [x] 2.4 `k` from below a heading still lands on it

### Verification

- `tests/heading_order.lua`: 90 passed
- `tests/edit_positions.lua`: 26 passed
- `tests/image_edit.lua`: 30 passed
- `tests/graphics.lua`: 42 passed
- `tests/run.lua`: 219 passed; two unrelated assertions remain red
  (`source that fits the window has no wrap-continuation overlays` and
  `showcase image jobs`; the showcase contains two images while the
  assertion expects at least three)
- All three Mermaid design blocks render; `git diff --check` passes

## Change history

| Date | Change |
| --- | --- |
| 2026-09-14 | Initial proposal |
| 2026-09-14 | Approved; implementation started; spec updates deferred to acceptance |
| 2026-09-14 | Implementation complete; moved to review |
| 2026-09-14 | Clarified the accepted gapless-focus exception |
| 2026-09-15 | Review approved; specs updated and change accepted |
