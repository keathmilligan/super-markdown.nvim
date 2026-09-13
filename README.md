# super-markdown.nvim

Inline GitHub-Flavored Markdown rendering for Neovim. Document chrome follows
GitHub light/dark tokens; images and Mermaid use the Kitty graphics protocol
(Ghostty/Kitty).

This plugin is meant to replace `render-markdown.nvim` plus snacks’ image
module.

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

Markdown **elements** use GitHub light/dark tokens (headings, alerts,
quotes, tables, code frames, links). `Normal` stays on your colorscheme. Fenced
code **syntax** stays with Tree-sitter / the editor highlighter.

GitHub alerts (`> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`)
use GitHub’s titles and colors.

Mermaid is `mermaid.render()` → SVG → `rsvg-convert`. On failure the plugin
logs an error and leaves the fence as source. There is no Chromium fallback.

Math (`$…$`, `$$…$$`) is TeX → SVG (MathJax lite adaptor; KaTeX has no SVG
backend without a browser). Skip if the helper is not installed.

## Configuration

Each render feature is a nested section with `enabled` (default on). Width
values `0–1` are a window fraction; `>1` are columns.

```lua
require('super-markdown').setup {
  debounce_ms = { insert = 120, normal = 40 },
  max_bytes = 1024 * 1024,
  heading = {
    enabled = true,
    -- Conceal `#` / setext underline; bold colorscheme title; no graphic.
    simple = false,
  },
  code = { enabled = true },
  quote = { enabled = true },
  alert = { enabled = true },
  list = { enabled = true },
  checkbox = { enabled = true },
  table = {
    enabled = true,
    max_width = 0.75,
  },
  hr = { enabled = true },
  frontmatter = { enabled = true },
  link = { enabled = true },
  codespan = { enabled = true },
  strike = { enabled = true },
  emphasis = { enabled = true },
  emoji = { enabled = true },
  footnote = { enabled = true },
  media = {
    enabled = true,
    image = true,
    mermaid = true,
    math = true,
    -- Mermaid and standalone images.
    max_width = 0.5,
  },
}
```

`heading.enabled = false` skips heading chrome and heading graphics.
`heading.simple = true` (with `enabled = true`) keeps the title as bold
text in the colorscheme / Tree-sitter heading color. `media.enabled` is
the master switch for images, mermaid, math, and heading graphics.
