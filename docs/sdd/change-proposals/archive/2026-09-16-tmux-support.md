---
id: tmux-support
status: accepted
features: [media, plugin]
created: 2026-09-16
updated: 2026-09-16
---

# Add tmux support

| Created | Updated |
| --- | --- |
| 2026-09-16 | 2026-09-16 |

## What

### Why

Kitty graphics APC is swallowed inside tmux unless it is wrapped in tmux's
DCS passthrough. Detection can already succeed (inherited
`KITTY_WINDOW_ID` / `GHOSTTY_RESOURCES_DIR`) while images, mermaid, math,
and heading graphics silently fail. The original design left this out of
scope; it is needed now.

### Requirements

- Graphics SHALL work in tmux 3.3+ when the outer terminal is Kitty or
  Ghostty, using the same unicode-placeholder protocol as today.
- APC payloads SHALL be wrapped in tmux DCS passthrough
  (`\ePtmux;…\e\\`, with `\e` doubled in the payload).
- The plugin SHALL enable pane-local `allow-passthrough all` so users do
  not need a tmux.conf change. tmux 3.3+ is required.
- `protocol.supported()` SHALL still require Kitty or Ghostty as the
  outer terminal. Inside tmux it SHALL also consult
  `#{client_termname}` when env vars are not enough, and SHALL be false
  when passthrough cannot be enabled.
- Cell metrics inside tmux SHALL use ioctl when pixel sizes are present,
  else `#{client_cell_width}` / `#{client_cell_height}`. The existing
  9×18 fallback remains if both fail.
- `:checkhealth super-markdown` SHALL report tmux version, passthrough,
  and the outer terminal when `TMUX` is set.
- README SHALL document tmux 3.3+ in Kitty/Ghostty. Zellij, GNU screen,
  nested tmux, and WezTerm remain unsupported.

### Scope

- In: wrap APC in `protocol.request`, tmux detection, pane-local
  passthrough, cell-size fallback, health, tests, README
- Out: Zellij, GNU screen, nested tmux, WezTerm, SSH/`t=f` remote
  files, XTVERSION probes, changing placement/placeholders, mux-specific
  config keys

### Open questions

- None

## How

### Approach

Keep placeholders and PNG transmit as they are. When `TMUX` is set, wrap
every graphics APC and enable pane-local passthrough — the same sequence
snacks.image and image.nvim use, which tmux documents. Details:
[design](../design/tmux-support.md).

### Impacted specifications

- `media` (existing) — protocol works through tmux passthrough
- `plugin` (existing) — health reports tmux / passthrough / outer terminal

### Plan

#### 1. Protocol wrap and detection

- [x] 1.1 Wrap APC in DCS passthrough inside `protocol.request` when
      `TMUX` is set; leave payloads unchanged otherwise
- [x] 1.2 Detect Kitty/Ghostty from existing env vars and, in tmux, from
      `#{client_termname}`
- [x] 1.3 Enable pane-local `allow-passthrough all` and treat graphics as
      unsupported if that fails or tmux is older than 3.3

#### 2. Cell size

- [x] 2.1 If ioctl pixel sizes are missing inside tmux, use
      `#{client_cell_width}` / `#{client_cell_height}`
- [x] 2.2 Keep the temporary 9×18 fallback when both queries fail

#### 3. Health, README, tests

- [x] 3.1 Report tmux, version, passthrough, and outer terminal in
      `:checkhealth super-markdown`
- [x] 3.2 Replace the multiplexer README note with tmux 3.3+ /
      Kitty / Ghostty instructions
- [x] 3.3 Unit-test wrap, `supported()` env/`client_termname` cases, and
      tmux cell-size fallback without a live tmux session

## Change history

| Date | Change |
| --- | --- |
| 2026-09-16 | Initial proposal |
| 2026-09-16 | Implementation complete; awaiting review |
| 2026-09-16 | Accepted; specs updated |
