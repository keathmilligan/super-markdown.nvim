---
id: wrap-list-items
status: accepted
features: [plugin, render]
created: 2026-09-17
updated: 2026-09-17
---

# Wrap list items

| Created | Updated |
| --- | --- |
| 2026-09-17 | 2026-09-17 |

## What

### Why

Long list items wrap at the window with Neovim `wrap`, so continuations
start at column 0. GitHub (and most rendered Markdown) uses a hanging
indent: wrapped lines line up with the item text after the marker. Short
items should stay as they are.

### Requirements

- Unordered and ordered list items SHALL wrap when the source line is
  wider than `list.max_width` (default window content width; `0–1` is a
  fraction, `>1` is columns).
- A line that already fits `list.max_width` SHALL NOT gain wrap overlay
  or virt_lines. Existing list / checkbox chrome SHALL still apply.
- Wrapped continuations SHALL indent so they align with the start of the
  item text (after leading indent, marker or checkbox, and the following
  space), matching GitHub list layout.
- Wrap SHALL be on word boundaries, same rules as table cells. Aspect of
  the marker (bullet, `N.`, checkbox glyph) SHALL stay on the first
  visual line only.
- Extra wrapped lines SHALL use `virt_lines`, or overlay Neovim wrap
  continuations when those already exist, as tables do.
- The cursor line SHALL show the source list line (no wrap overlay).
- Task-list items SHALL wrap with hanging indent under the text after
  the checkbox.
- Nested items SHALL keep their source indent and hang from that item’s
  text column.
- List items inside quotes or alerts SHALL keep the left bar on wrapped
  continuations.
- `list.enabled = false` SHALL skip list wrap.

### Scope

- In: unordered, ordered, and task list source lines; `list.max_width`;
  hanging indent; table-like virt_lines / wrap-continuation overlays;
  inline markdown rebuilt on wrapped overlays; showcase sample and tests.
- Out: changing unwrapped marker chrome; wrapping fenced code or tables
  nested in a list item; wrapping lines that host inline image or math
  media; tight/loose list spacing; `breakindent` / `showbreak`.

### Open questions

- None. Design: [wrap-list-items](../../design/wrap-list-items.md).

## How

### Approach

Per list-item source line, compare display width to `list.max_width`.
Short lines keep today’s marks. Long lines conceal the source and
rebuild overlay + hanging-indent continuations, reusing table wrap
placement and `wrap_chunks`. Details in the
[design](../../design/wrap-list-items.md).

### Impacted specifications

- `plugin` (existing) — `list.max_width`
- `render` (existing) — list wrap and hanging indent

### Plan

#### 1. Config

- [x] 1.1 Add `list.max_width` (default `1`) and a resolver like
      `table_cols`
- [x] 1.2 Document it in README next to other width keys

#### 2. Wrap placement

- [x] 2.1 Reuse `table.wrap_chunks` for list item text
- [x] 2.2 Overlay first visual line; virt_lines or wrap-continuation
      overlays for the rest; one column of slack
- [x] 2.3 Skip wrap when the line already fits or hosts media
- [x] 2.4 Hide overlay on the cursor line

#### 3. Hanging indent

- [x] 3.1 Compute hanging indent from rendered prefix (bullet /
      `N.` / checkbox)
- [x] 3.2 Keep nested source indent; wrap markdown continuation lines
      independently
- [x] 3.3 Repeat quote / alert bars on wrapped continuations

#### 4. Tests and sample

- [x] 4.1 Tests: short line unchanged; long unordered / ordered / task
      hang; nested indent; `list` off; cursor shows source
- [x] 4.2 Add a long list item to `samples/showcase.md`

## Change history

| Date | Change |
| --- | --- |
| 2026-09-17 | Initial proposal |
| 2026-09-17 | Implementation complete; ready for review |
| 2026-09-17 | Accepted; specs updated |
