---
id: gfm-inline-render
status: accepted
features: [plugin, render, media, style]
created: 2026-09-09
updated: 2026-09-11
---

# GFM inline markdown rendering

| Created | Updated |
| --- | --- |
| 2026-09-09 | 2026-09-11 |

## What

### Why

Markdown buffers in Neovim are currently dressed by two plugins that overlap
and fight the editor:

- [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
  walks Tree-sitter, then paints headings, tables, callouts, and the rest with
  extmarks. It depends on `nvim-treesitter` and `nvim-web-devicons`, rebuilds
  marks on a wide event set (including `CursorMoved`), and styles headings as
  colorful blocks rather than GitHub-flavored Markdown.
- [snacks.nvim](https://github.com/folke/snacks.nvim) is a kitchen-sink plugin
  loaded at startup (`lazy = false`) solely for inline images and Mermaid.
  Images go through ImageMagick. Mermaid goes through `mmdc` plus a full
  Chromium via Puppeteer (`mermaid-puppeteer.json`). Math is already disabled
  because the LaTeX path is too heavy.

The two plugins each walk Tree-sitter and manage their own marks, so a
markdown buffer pays twice. Neither looks like
[gfm-hotview](https://github.com/keathmilligan/gfm-hotview), which is the
visual reference for GFM in this workspace.

`super-markdown.nvim` should be a single, markdown-only plugin that renders
GFM inline, shows images and diagrams in-buffer, and stays cheap enough that
opening a note is not a hitch.

### Requirements

- Render GitHub-Flavored Markdown **inline in the markdown buffer** (conceal +
  extmarks), not in a browser or a second preview window. `gfm-hotview`
  remains the pixel-accurate preview.
- Appearance SHALL follow gfm-hotview document chrome: GitHub light/dark
  tokens, h1/h2 underlines, GitHub alerts, tables, task lists, blockquotes,
  fenced code frames, horizontal rules, links, strikethrough, footnotes, and
  emoji shortcodes. See the [design](../design/gfm-inline-render.md).
- Inline media SHALL cover local images (PNG, JPEG, GIF, WebP, SVG) and
  ` ```mermaid ` fences, using the Kitty graphics protocol (Ghostty).
- Math (`$…$`, `$$…$$`) SHALL render to SVG when the helper is installed,
  not with LaTeX/tectonic. KaTeX cannot emit SVG without a browser; the
  helper uses MathJax’s lite adaptor (same TeX input, SVG output).
- Rendering SHALL be viewport-scoped, incrementally updated, and debounced.
  A buffer change SHALL not rebuild every extmark or respawn Chromium.
- Converted media SHALL be cached by content hash and theme across sessions.
- Mermaid SHALL be rendered with `mermaid.render()` to SVG. On failure the
  plugin SHALL log an error and leave the fence as source. There is no
  Chromium / `mmdc` fallback.
- Markdown buffers SHALL keep the editor `Normal` highlight. GFM tokens apply
  to document elements only.
- The plugin SHALL load only for markdown buffers. It SHALL NOT depend on
  snacks.nvim, nvim-web-devicons, or ImageMagick for the default path.
- Source on the cursor line SHALL remain editable (anti-conceal) without a
  full redraw on every `CursorMoved`.
- Toggle, buffer-local disable, and `:checkhealth` SHALL exist.

### Scope

- In: markdown filetype only; GFM document chrome; inline images; Mermaid;
  optional TeX math; gfm-hotview color tokens; health checks; tests against
  gfm-hotview sample constructs.
- Out: browser/webview preview; image-file buffers as a full image viewer;
  PDF/video; HTML/TSX/Vue image scanning; Obsidian wiki links and extra
  callouts; org-indent; completions LSP; injected markdown in other
  filetypes; rainbow heading palettes; replacing `gfm-hotview`.

### Open questions

- None

## How

### Approach

Stay in the source buffer. One Tree-sitter walk of the visible range produces
a render plan: extmark operations for chrome, and media jobs for images,
Mermaid, and math. Extmarks are diffed and reused. Media is converted only on
cache miss, through `rsvg-convert` for SVG and a small Node helper for
Mermaid (and MathJax SVG for math) — not ImageMagick and not a Chromium
process per diagram.

Style comes from gfm-hotview CSS tokens (`--gv-*` and GitHub alert colors),
mapped to highlight groups. Syntax highlighting inside fenced code stays with
the editor’s Tree-sitter highlighter.

Details, trade-offs, and pipelines are in
[design/gfm-inline-render.md](../design/gfm-inline-render.md).

### Impacted specifications

- `plugin` (new)
- `render` (new)
- `media` (new)
- `style` (new)

### Plan

#### 1. Plugin skeleton

- [x] 1.1 Create the Neovim plugin layout (`lua/super-markdown/`,
      `plugin/super-markdown.lua`) with `setup`, defaults, and filetype attach
- [x] 1.2 Add commands: enable / disable / toggle / buffer-local toggle
- [x] 1.3 Add `:checkhealth` for Tree-sitter markdown parsers, Ghostty/Kitty
      graphics, `rsvg-convert`, Node + mermaid, and optional math helper
- [x] 1.4 Add a README describing install, requirements, and the gfm-hotview
      visual contract

#### 2. Style

- [x] 2.1 Encode gfm-hotview light/dark tokens as Lua palettes keyed off
      `vim.o.background`
- [x] 2.2 Define highlight groups for headings, links, quotes, alerts, code
      frames, tables, rules, checkboxes, and footnotes
- [x] 2.3 Reload highlights on `ColorScheme` and background change

#### 3. Render scheduler

- [x] 3.1 Attach on markdown `FileType`; debounce `TextChanged` /
      `TextChangedI`, `WinScrolled`, `WinResized`, and `ModeChanged`
- [x] 3.2 Parse only the visible range plus a small overscan via Tree-sitter
- [x] 3.3 Diff the render plan and reuse extmark ids; do not clear the
      namespace on every update
- [x] 3.4 Anti-conceal: prefer conceal for syntax; index remaining virt-text
      marks by line and toggle only the old/new cursor line
- [x] 3.5 Skip rendering when the window is horizontally scrolled or in diff
      mode; skip files over a configurable size

#### 4. GFM elements

- [x] 4.1 Headings: conceal markers, bold title, h1/h2 underline
- [x] 4.2 Lists, task-list checkboxes, and blockquotes
- [x] 4.3 GitHub alerts (`> [!NOTE]` and the other four types) with gfm-hotview
      colors and titles
- [x] 4.4 Fenced and inline code frames (language label; editor syntax colors)
- [x] 4.5 Pipe tables, horizontal rules, links, strikethrough
- [x] 4.6 Emoji shortcodes and footnote markers
- [x] 4.7 Dim YAML/TOML frontmatter; do not strip it from the buffer

#### 5. Media

- [x] 5.1 Kitty graphics protocol placement with Ghostty unicode placeholders
- [x] 5.2 Content-hash + theme cache under `stdpath('cache')`
- [x] 5.3 PNG passthrough; JPEG/GIF/WebP via a lightweight decode or one-shot
      `magick` only when needed; SVG via `rsvg-convert`
- [x] 5.4 Resolve image paths relative to the markdown file
- [x] 5.5 Convert and place only media whose source range intersects the
      viewport; cancel jobs that scroll out of view
- [x] 5.6 Node helper: Mermaid → SVG with gfm-hotview themes (`default` /
      `dark`), then `rsvg-convert`; log an error and keep the fence as source
      if `mermaid.render()` fails
- [x] 5.7 Optional math helper for `$…$` / `$$…$$` → SVG → `rsvg-convert`
      (MathJax lite adaptor; KaTeX has no SVG backend without a browser)

#### 6. Tests and fixtures

- [x] 6.1 Unit tests for palette, plan diff, path resolve, and cache keys
- [x] 6.2 Buffer tests for each GFM construct using fixtures drawn from
      gfm-hotview `samples/`
- [x] 6.3 Health-gated tests for image placement and Mermaid conversion

## Change history

| Date | Change |
| --- | --- |
| 2026-09-09 | Initial proposal |
| 2026-09-09 | Resolved open questions: no Normal restyle; no mmdc/Chromium fallback |
| 2026-09-09 | Approved; implementation started |
| 2026-09-09 | Implementation complete; math helper uses MathJax SVG |
| 2026-09-11 | Accepted; living specs written under specifications/ |
