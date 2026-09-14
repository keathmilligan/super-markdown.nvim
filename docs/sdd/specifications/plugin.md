---
feature: plugin
created: 2026-09-11
updated: 2026-09-13
---

# Plugin

| Created | Updated |
| --- | --- |
| 2026-09-11 | 2026-09-13 |

## Purpose

Plugin lifecycle: attach, commands, configuration, and health for in-buffer
GFM rendering.

## Requirements

### Attach

The plugin SHALL load only for configured filetypes (default: `markdown`).
It SHALL NOT depend on snacks.nvim, nvim-web-devicons, or ImageMagick for the
default path.

#### Markdown buffer

- GIVEN a buffer whose filetype is markdown
- WHEN the buffer is opened or the plugin is enabled
- THEN rendering attaches to that buffer

#### Other filetypes

- GIVEN a buffer whose filetype is not markdown
- WHEN the plugin loads
- THEN it SHALL NOT attach or restyle that buffer

### Toggle

The plugin SHALL provide global and buffer-local enable, disable, and toggle.

#### Global toggle

- GIVEN rendering is enabled
- WHEN the user runs `:SuperMarkdown disable` or `:SuperMarkdown toggle`
- THEN attached buffers SHALL stop rendering and restore prior window options

#### Buffer-local toggle

- GIVEN a markdown buffer
- WHEN the user runs `:SuperMarkdown buf_disable`
- THEN that buffer SHALL stop rendering while others remain unchanged

### Size and window guards

Rendering SHALL skip files larger than a configurable byte cap (default 1 MiB),
windows in diff mode, and windows that are horizontally scrolled.

### Configuration

Render features SHALL be nested sections with `enabled` (default on):
heading, code, quote, alert, list, checkbox, table, hr, frontmatter, link,
codespan, strike, emphasis, emoji, and footnote. Heading SHALL also have
`simple` (default false). Table SHALL have `max_width` (default 0.75 of
window content width). Media SHALL keep `max_width` (default 0.75) as a
cap for standalone images and a render width for mermaid, `max_height`
(default 1.0 of window height) as an image cap, and SHALL include `image`,
`mermaid`, and `math` (default on).
`media.enabled` SHALL be a master switch for images, mermaid, math, and
heading graphics.

Width values `0–1` SHALL be a window-content fraction; values `>1` SHALL
be columns. Height values `0–1` SHALL be a window-height fraction; values
`>1` SHALL be cells.

Setup with options SHALL merge those options onto defaults. Setup with no
options SHALL keep the current configuration and SHALL NOT reset to
defaults.

#### Setup without options

- GIVEN the user has already set custom options
- WHEN setup is called with no options
- THEN those custom options SHALL remain

### Health

`:checkhealth super-markdown` SHALL report Neovim version, Tree-sitter
`markdown` and `markdown_inline` parsers, Kitty graphics support,
`rsvg-convert`, optional `magick`, Node, and the Mermaid and math helpers.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-11 | Initial spec from gfm-inline-render |
| 2026-09-13 | Nested feature config; table vs media width; setup() keeps user config |
| 2026-09-13 | media.max_width default 0.75 |
| 2026-09-13 | media.max_height default 1.0 of window height |
| 2026-09-13 | images cap to max size; mermaid still renders at max_width |
