---
feature: style
created: 2026-09-11
updated: 2026-09-12
---

# Style

| Created | Updated |
| --- | --- |
| 2026-09-11 | 2026-09-12 |

## Purpose

Document chrome colors and highlight groups. Editor `Normal` stays on the
active colorscheme.

## Requirements

### Tokens

Markdown **elements** SHALL use GitHub light/dark tokens. The plugin
SHALL NOT restyle `Normal`.

| Token | Light | Dark |
| --- | --- | --- |
| foreground | `#1f2328` | `#c9d1d9` |
| muted | `#59636e` | `#9198a1` |
| border | `#d1d9e0` | `#3d444d` |
| accent | `#0969da` | `#4493f8` |

Alert colors (light / dark): NOTE `#0969da` / `#4493f8`, TIP `#1a7f37` /
`#3fb950`, IMPORTANT `#8250df` / `#ab7df8`, WARNING `#9a6700` / `#d29922`,
CAUTION `#cf222e` / `#f85149`.

Palette SHALL follow `vim.o.background`. Highlights SHALL reload on
`ColorScheme` and background change.

### Headings

Unfocused heading graphics SHALL use GFM heading tokens: document
foreground (not the colorscheme); h6 muted. h1 and h2 SHALL include the
GFM bottom border.

Focused headings SHALL use Tree-sitter / colorscheme markdown heading
highlights, not plugin heading groups.

When graphics are unavailable, heading chrome SHALL use document
foreground, bold; h6 muted; h1 and h2 MAY show a border-colored underline.

### Code frames

Fenced code background SHALL be derived from the editor `Normal` background:
slightly lighter on dark themes, slightly darker on light themes. The shade
SHALL extend to the end of the window on every code-block line, including
both fence lines.

Language labels on an unfocused opening fence SHALL use muted italic text on
that code background. Syntax inside the fence SHALL keep the editor
Tree-sitter highlighter.

### Alerts

GitHub alerts SHALL use the alert token for bar, body, and title. Titles
SHALL be Note, Tip, Important, Warning, and Caution.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-11 | Initial spec from gfm-inline-render |
| 2026-09-12 | Unfocused heading tokens vs focused colorscheme highlights |
