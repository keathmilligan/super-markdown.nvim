---
feature: plugin
created: 2026-09-11
updated: 2026-09-11
---

# Plugin

| Created | Updated |
| --- | --- |
| 2026-09-11 | 2026-09-11 |

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

### Health

`:checkhealth super-markdown` SHALL report Neovim version, Tree-sitter
`markdown` and `markdown_inline` parsers, Kitty graphics support,
`rsvg-convert`, optional `magick`, Node, and the Mermaid and math helpers.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-11 | Initial spec from gfm-inline-render |
