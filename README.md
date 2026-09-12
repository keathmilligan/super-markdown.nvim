# super-markdown.nvim

Inline GitHub-Flavored Markdown rendering for Neovim. Document chrome follows
[gfm-hotview](https://github.com/keathmilligan/gfm-hotview) tokens; images and
Mermaid use the Kitty graphics protocol (Ghostty/Kitty).

This plugin is meant to replace `render-markdown.nvim` plus snacks’ image
module. `gfm-hotview` remains the browser-accurate preview.

## Requirements

- Neovim `>= 0.11` (developed on 0.12)
- Tree-sitter parsers `markdown` and `markdown_inline`
- Ghostty or Kitty for inline images
- [`rsvg-convert`](https://gitlab.gnome.org/GNOME/librsvg) for SVG / Mermaid / math
- Node.js, then `npm install` in `scripts/` for Mermaid (and math)
- ImageMagick `magick` only for JPEG/GIF/WebP

## Install

lazy.nvim:

```lua
{
  'keathmilligan/super-markdown.nvim',
  ft = 'markdown',
  opts = {},
  build = 'npm install --prefix scripts',
}
```

After clone, install helpers:

```sh
npm install --prefix scripts
```

## Commands

| Command | Action |
| --- | --- |
| `:SuperMarkdown` / `:SuperMarkdown toggle` | Toggle globally |
| `:SuperMarkdown enable` / `disable` | Global on/off |
| `:SuperMarkdown buf_toggle` | Toggle current buffer |
| `:SuperMarkdown buf_enable` / `buf_disable` | Buffer-local |

`:checkhealth super-markdown` reports parsers, terminal graphics, `rsvg-convert`, Node, and helpers.

Open [`samples/showcase.md`](samples/showcase.md) to exercise headings, alerts,
tables, images, Mermaid, and math in one buffer.

## Appearance

Markdown **elements** use gfm-hotview light/dark tokens (headings, alerts,
quotes, tables, code frames, links). `Normal` stays on your colorscheme. Fenced
code **syntax** stays with Tree-sitter / the editor highlighter.

GitHub alerts (`> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`)
use the same titles and colors as gfm-hotview.

Mermaid is `mermaid.render()` → SVG → `rsvg-convert`. On failure the plugin
logs an error and leaves the fence as source. There is no Chromium fallback.

Math (`$…$`, `$$…$$`) is TeX → SVG (MathJax lite adaptor; KaTeX has no SVG
backend without a browser). Skip if the helper is not installed.

## Configuration

```lua
require('super-markdown').setup {
  debounce_ms = { insert = 120, normal = 40 },
  max_bytes = 1024 * 1024,
  media = {
    enabled = true,
    mermaid = true,
    math = true,
    -- Mermaid, standalone images, and tables. 0–1 = window fraction; >1 = columns.
    max_width = 0.5,
  },
}
```
