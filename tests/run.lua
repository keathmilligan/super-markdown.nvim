local failed = 0
local passed = 0

local function ok(cond, msg)
  if cond then
    passed = passed + 1
    print('ok  ' .. msg)
  else
    failed = failed + 1
    print('FAIL  ' .. msg)
  end
end

local function eq(a, b, msg)
  if vim.deep_equal(a, b) then
    ok(true, msg)
  else
    failed = failed + 1
    print('FAIL  ' .. msg)
    print('  expected ' .. vim.inspect(b))
    print('  got      ' .. vim.inspect(a))
  end
end

-- style
local style = require 'super-markdown.style'
vim.o.background = 'dark'
eq(style.palette().accent, '#4493f8', 'dark accent token')
eq(style.palette().alert.NOTE, '#4493f8', 'dark note alert')
vim.o.background = 'light'
eq(style.palette().accent, '#0969da', 'light accent token')
eq(style.palette().alert.CAUTION, '#cf222e', 'light caution alert')
style.apply()
ok(vim.fn.hlexists 'SuperMarkdownH1' == 1, 'H1 highlight defined')
ok(vim.fn.hlexists 'SuperMarkdownHeadingSimple' == 1, 'simple heading highlight defined')
ok(vim.fn.hlexists 'SuperMarkdownAlertNoteTitle' == 1, 'alert title highlight')
local simple_hl = vim.api.nvim_get_hl(0, { name = 'SuperMarkdownHeadingSimple', link = false })
ok(simple_hl.bold == true, 'simple heading is bold')
ok(simple_hl.fg == nil, 'simple heading does not set fg')

vim.o.background = 'dark'
vim.api.nvim_set_hl(0, 'Normal', { fg = '#c9d1d9', bg = '#0d1117' })
style.apply()
local dark_code = vim.api.nvim_get_hl(0, { name = 'SuperMarkdownCodeBlock', link = false })
ok(dark_code.bg ~= nil and dark_code.bg > 0x0d1117, 'dark code block bg is lighter than editor bg')
vim.o.background = 'light'
vim.api.nvim_set_hl(0, 'Normal', { fg = '#1f2328', bg = '#ffffff' })
style.apply()
local light_code = vim.api.nvim_get_hl(0, { name = 'SuperMarkdownCodeBlock', link = false })
ok(light_code.bg ~= nil and light_code.bg < 0xffffff, 'light code block bg is darker than editor bg')

-- cache keys
local cache = require 'super-markdown.media.cache'
local k1 = cache.key('mermaid', 'dark', 'flowchart LR\nA-->B')
local k2 = cache.key('mermaid', 'dark', 'flowchart LR\nA-->B')
local k3 = cache.key('mermaid', 'default', 'flowchart LR\nA-->B')
eq(k1, k2, 'cache key stable')
ok(k1 ~= k3, 'cache key changes with theme')
ok(#k1 == 64, 'sha256 hex length')

local mermaid = require 'super-markdown.media.mermaid'
eq(mermaid.cached_error 'flowchart LR\nA-->flowchart[X]', nil, 'no mermaid error before failure')
eq(
  mermaid.format_error 'super-markdown mermaid.render() failed: Parse error on line 3:\ngot GRAPH',
  'Parse error on line 3:\ngot GRAPH',
  'strips mermaid helper prefix'
)
eq(
  mermaid.format_error(
    'MERMAID_ERROR {"message":"Parse error on line 3:\\ngot GRAPH","text":"flowchart","token":"GRAPH","line":3,"column":10}'
  ),
  'line 3, column 10\nunexpected "flowchart" (GRAPH)\nParse error on line 3:\ngot GRAPH',
  'formats mermaid JSON parse error'
)
mermaid.remember_error('flowchart LR\nA-->flowchart[X]', 'Parse error on line 3:\ngot GRAPH')
eq(mermaid.cached_error 'flowchart LR\nA-->flowchart[X]', 'Parse error on line 3:\ngot GRAPH', 'caches mermaid failure by source')
eq(mermaid.cached_error 'flowchart LR\nA-->B', nil, 'mermaid failure cache is per diagram source')
mermaid.remember_error('bad svg', 'Error reading SVG: Input file is too short')
eq(mermaid.cached_error 'bad svg', nil, 'does not cache converter noise')
mermaid.remember_error('empty svg', 'mermaid.render() produced no SVG')
eq(mermaid.cached_error 'empty svg', nil, 'does not cache empty SVG as a permanent failure')

-- path resolve
local path = require 'super-markdown.media.path'
eq(path.resolve('/tmp/doc/a.md', 'img/x.png'), '/tmp/doc/img/x.png', 'relative image path')
eq(path.resolve('/tmp/doc/a.md', '/abs/x.png'), '/abs/x.png', 'absolute image path')
eq(path.resolve('/tmp/doc/a.md', 'https://example.com/a.png'), 'https://example.com/a.png', 'url passthrough')

-- plan diff
local apply = require 'super-markdown.apply'
local added, removed = apply.diff_keys({ 'a', 'b' }, { 'b', 'c' })
eq(added, { 'c' }, 'diff added')
eq(removed, { 'a' }, 'diff removed')

local media = require 'super-markdown.media'
local active_media = media.active_marks({ { key = 'heading:2' } }, {
  ['heading:1'] = { key = 'media:heading:1' },
  ['heading:2'] = { key = 'media:heading:2' },
})
eq(#active_media, 1, 'stale media marks are filtered after edits move headings')
eq(active_media[1].key, 'media:heading:2', 'shifted heading keeps only its current media mark')

-- emoji
local emoji = require 'super-markdown.emoji'
eq(emoji.get 'rocket', '🚀', 'emoji rocket')
eq(emoji.get 'file_folder', '📁', 'emoji folder')
eq(emoji.get 'not_a_real_emoji', nil, 'unknown shortcode')

local tmod = require 'super-markdown.table'
eq(
  tmod.wrap_chunks({ { 'one two three', 'Normal' } }, 5),
  { { { 'one', 'Normal' } }, { { 'two', 'Normal' } }, { { 'three', 'Normal' } } },
  'wrap chunks at word boundaries'
)
eq(tmod.col_widths({ 3, 20 }, 10), { 3, 7 }, 'short column keeps natural width')
eq(tmod.col_widths({ 4, 4 }, 20), { 4, 4 }, 'fitting table keeps natural widths')
eq(tmod.alignment ':---:', 'center', 'center alignment')
eq(tmod.alignment '---:', 'right', 'right alignment')
eq(tmod.alignment '---', 'left', 'left alignment')
eq(tmod.byte_at_display('abcdefghij', 5), 5, 'byte at display column')
eq(tmod.byte_at_display('', 5), 0, 'byte at display of empty string')
eq(tmod.pad_chunks({ { 'ab', 'Normal' } }, 5, 'left', 'Normal'), { { 'ab', 'Normal' }, { '   ', 'Normal' } }, 'left pad cell')
eq(tmod.pad_chunks({ { 'ab', 'Normal' } }, 5, 'right', 'Normal'), { { '   ', 'Normal' }, { 'ab', 'Normal' } }, 'right pad cell')
local wrapped_hl = tmod.wrap_chunks({ { 'hello ', 'Normal' }, { 'world', 'SuperMarkdownStrong' } }, 5)
eq(wrapped_hl[1], { { 'hello', 'Normal' } }, 'wrap keeps first-line highlight')
eq(wrapped_hl[2], { { 'world', 'SuperMarkdownStrong' } }, 'wrap keeps second-line highlight')

local cfg = require 'super-markdown.config'
eq(cfg.max_cols(80), 40, 'media.max_width 0.5 of 80 cols')
eq(cfg.table_cols(80), 60, 'table.max_width 0.75 of 80 cols')
eq(cfg.max_cols(1), 1, 'max_cols at least 1')
eq(cfg.get().media.max_width, 0.5, 'default media max_width')
eq(cfg.get().table.max_width, 0.75, 'default table max_width')
eq(cfg.get().media.image, true, 'default media.image')
eq(cfg.get().heading.enabled, true, 'default heading enabled')
eq(cfg.get().heading.simple, false, 'default heading simple off')
eq(cfg.feature 'list', true, 'features default on')
eq(cfg.heading_mode(), 'full', 'default heading mode is full')
eq(cfg.resolve_cols(80, 0.5), 40, 'resolve_cols fraction')
eq(cfg.resolve_cols(80, 20), 20, 'resolve_cols absolute columns')
do
  local prev = cfg.get().media.max_width
  cfg.get().media.max_width = 20
  local abs = cfg.max_cols(80)
  cfg.get().media.max_width = 100
  local capped = cfg.max_cols(80)
  cfg.get().media.max_width = prev
  eq(abs, 20, 'absolute max_width is columns')
  eq(capped, 80, 'absolute max_width capped to window')
end
do
  local prev = cfg.get().table.max_width
  cfg.get().table.max_width = 20
  local abs = cfg.table_cols(80)
  cfg.get().table.max_width = prev
  eq(abs, 20, 'absolute table.max_width is columns')
end
do
  local orig = vim.deepcopy(cfg.get())
  cfg.get().heading.enabled = false
  eq(cfg.heading_mode(), 'off', 'heading.enabled false is off')
  cfg.get().heading.enabled = true
  cfg.get().heading.simple = true
  eq(cfg.heading_mode(), 'simple', 'heading.simple is simple mode')
  cfg.get().heading.enabled = false
  eq(cfg.heading_mode(), 'off', 'enabled false wins over simple')
  cfg.get().list.enabled = false
  eq(cfg.feature 'list', false, 'feature off')
  cfg.values = orig
end
do
  local orig = vim.deepcopy(cfg.get())
  cfg.setup { media = { max_width = 0.3 }, heading = { simple = true } }
  eq(cfg.get().media.max_width, 0.3, 'setup merges opts')
  eq(cfg.get().media.mermaid, true, 'setup keeps default mermaid')
  eq(cfg.get().heading.simple, true, 'setup merges heading.simple')
  eq(cfg.get().heading.enabled, true, 'setup keeps default heading.enabled')
  cfg.setup()
  eq(cfg.get().media.max_width, 0.3, 'setup() without opts keeps user config')
  eq(cfg.get().heading.simple, true, 'setup() without opts keeps heading.simple')
  cfg.values = orig
end

local heading_media = require 'super-markdown.media.heading'
eq(heading_media.em(1), 2, 'h1 is 2em')
eq(heading_media.em(2), 1.5, 'h2 is 1.5em')
eq(heading_media.em(6), 0.85, 'h6 is 0.85em')
eq(heading_media.visible_text '**Bold** and [lab](url)', 'Bold and lab', 'heading visible text strips inline markup')
eq(heading_media.wrap('one two three', 5), { 'one', 'two', 'three' }, 'heading wrap at column budget')
local svg = heading_media.svg('Hello', 1, { max_cols = 40, cell_width = 9, cell_height = 18, fg = '#c9d1d9', border = '#3d444d' })
ok(svg:find('font-size="36', 1, true) ~= nil, 'h1 svg font-size is 2em of cell height')
ok(svg:find('font-weight="600"', 1, true) ~= nil, 'heading svg is weight 600')
ok(svg:find('<text x="0"', 1, true) ~= nil, 'heading text is flush with the left edge')
ok(svg:find('<line', 1, true) ~= nil, 'h1 svg includes a bottom rule')
ok(
  heading_media.svg('Hi', 3, { max_cols = 40, cell_width = 9, cell_height = 18 }):find('<line', 1, true) == nil,
  'h3 svg has no bottom rule'
)
local w1 = tonumber(svg:match('width="(%d+)"')) or 0
local ht = tonumber(svg:match('height="(%d+)"')) or 0
eq(w1, 39 * 9, 'heading svg is a full-width cell rectangle')
eq(ht, 3 * 18, 'h1 svg is three cells tall')
eq(heading_media.rows(1), 2, 'h1 type occupies two cells')
eq(heading_media.rows(2), 2, 'h2 occupies two cells')
eq(heading_media.rows(3), 2, 'h3 occupies two cells')
eq(heading_media.rows(4), 1, 'h4 occupies one cell')
eq(heading_media.rows(6), 1, 'h6 occupies one cell')
local text_y = tonumber(svg:match('y="(%d+)"')) or 0
local line_y = tonumber(svg:match('y1="(%d+)"')) or 0
ok(line_y - text_y >= 12, 'h1 underline sits below the em-box')
ok(ht - line_y <= 1, 'h1 underline sits at the bottom of the graphic')
local svg2 = heading_media.svg('Hi', 2, { max_cols = 40, cell_width = 9, cell_height = 18, fg = '#c9d1d9', border = '#3d444d' })
local t2 = tonumber(svg2:match('y="(%d+)"')) or 0
local l2 = tonumber(svg2:match('y1="(%d+)"')) or 0
local h2h = tonumber(svg2:match('height="(%d+)"')) or 0
ok(l2 - t2 >= 12, 'h2 underline sits below the em-box')
ok(h2h - l2 <= 1, 'h2 underline sits at the bottom of the graphic')
local h4 = heading_media.svg('Hi', 4, { max_cols = 40, cell_width = 9, cell_height = 18 })
eq(tonumber(h4:match('height="(%d+)"')), 18, 'h4 svg is one cell tall')

-- buffer GFM constructs
local has_parser = #vim.api.nvim_get_runtime_file('parser/markdown.so', false) > 0
if not has_parser then
  print 'skip buffer tests (no markdown parser)'
else
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = 'markdown'
  local fixture = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/fixtures/gfm.md'
  local lines = vim.fn.readfile(fixture)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd 'file tests/fixtures/gfm.md'
  pcall(vim.treesitter.start, buf, 'markdown')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  local parse = require 'super-markdown.parse'
  local plan = parse.parse(buf, win, 200)
  ok(plan ~= nil, 'parse gfm fixture')
  if plan then
    local kinds = {}
    for _, m in ipairs(plan.marks) do
      local kind = m.key:match('^(%a+)')
      kinds[kind] = (kinds[kind] or 0) + 1
    end
    ok((kinds.h or 0) > 0 or (kinds.hsrc or 0) > 0, 'parsed headings')
    ok((kinds.li or 0) > 0 or (kinds.task or 0) > 0, 'parsed lists or tasks')
    local task_hides_dash = false
    for _, m in ipairs(plan.marks) do
      if m.key:match '^task:' and m.opts.conceal and m.col < m.opts.end_col - 3 then
        task_hides_dash = true
        break
      end
    end
    ok(task_hides_dash, 'task checkbox conceals leading list marker')
    ok((kinds.tov or 0) > 0, 'parsed table overlay')
    ok((kinds.hr or 0) > 0, 'parsed thematic break')
    ok((kinds.emo or 0) > 0, 'parsed emoji shortcodes')
  end

  local alerts = vim.fn.fnamemodify(fixture, ':h') .. '/alerts.md'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(alerts))
  plan = parse.parse(buf, win, 200)
  if plan then
    local n = 0
    for _, m in ipairs(plan.marks) do
      if m.key:match '^alert:' then
        n = n + 1
      end
    end
    eq(n, 5, 'five github alerts')
  else
    ok(false, 'parse alerts fixture')
  end

  local codef = vim.fn.fnamemodify(fixture, ':h') .. '/code.md'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(codef))
  plan = parse.parse(buf, win, 200)
  if plan then
    local n = 0
    for _, m in ipairs(plan.marks) do
      if m.key:match '^cfence:' then
        n = n + 1
      end
    end
    ok(n >= 4, 'fenced code blocks')
  end

  local tsmod = require 'super-markdown.ts'
  tsmod.patch_markdown_highlights()
  local hlq = vim.treesitter.query.get('markdown', 'highlights')
  ok(hlq and not hlq.has_conceal_line, 'markdown highlights do not conceal fence lines')

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'intro',
    '```lua',
    'print(1)',
    'print(2)',
    '```',
    'outro',
  })
  pcall(vim.treesitter.start, buf, 'markdown')
  plan = parse.parse(buf, win, 50)
  local apply = require 'super-markdown.apply'
  local open_row, close_row, block
  if plan then
    for _, m in ipairs(plan.marks) do
      if m.key:match '^cfence:' then
        open_row = m.row
        block = m.block_range
      elseif m.key:match '^cfence_end:' then
        close_row = m.row
      end
    end
  end
  ok(open_row == 1 and close_row == 4, 'lua fence rows')
  ok(block and block[1] == 1 and block[2] == 4, 'fence block_range covers open through close')

  local function row_hidden(row)
    local marks = vim.api.nvim_buf_get_extmarks(buf, apply.ns, { row, 0 }, { row, -1 }, { details = true })
    for _, em in ipairs(marks) do
      if em[4].conceal_lines ~= nil then
        return true
      end
    end
    return false
  end

  local function row_hl_eol(row)
    local marks = vim.api.nvim_buf_get_extmarks(buf, apply.ns, { row, 0 }, { row, -1 }, { details = true })
    for _, em in ipairs(marks) do
      if em[4].line_hl_group == 'SuperMarkdownCodeBlock'
        or (em[4].hl_eol and em[4].hl_group == 'SuperMarkdownCodeBlock')
      then
        return true
      end
    end
    return false
  end

  local function tick_concealed(row)
    local marks = vim.api.nvim_buf_get_extmarks(buf, apply.ns, { row, 0 }, { row, -1 }, { details = true })
    for _, em in ipairs(marks) do
      if em[4].conceal ~= nil then
        return true
      end
    end
    return false
  end

  local function lang_muted(row)
    local marks = vim.api.nvim_buf_get_extmarks(buf, apply.ns, { row, 0 }, { row, -1 }, { details = true })
    for _, em in ipairs(marks) do
      if em[4].hl_group == 'SuperMarkdownCodeLabel' then
        return true
      end
    end
    return false
  end

  if plan then
    apply.apply(buf, plan.marks, 0)
    ok(not row_hidden(open_row) and not row_hidden(close_row), 'code fence lines stay visible when cursor is outside')
    ok(tick_concealed(open_row) and tick_concealed(close_row), 'code fence backticks hidden when cursor is outside')
    ok(lang_muted(open_row), 'code fence language muted when cursor is outside')
    ok(row_hl_eol(open_row) and row_hl_eol(open_row + 1) and row_hl_eol(close_row), 'code block shade extends to end of window')
    apply.apply(buf, plan.marks, 2)
    ok(row_hl_eol(open_row) and row_hl_eol(open_row + 1) and row_hl_eol(close_row), 'code block shade stays when cursor is in the block')
    ok(not tick_concealed(open_row) and not tick_concealed(close_row), 'code fence backticks visible with cursor on body')
    ok(not lang_muted(open_row), 'code fence language uses syntax highlight in the block')
    apply.apply(buf, plan.marks, 1)
    ok(not tick_concealed(open_row) and not tick_concealed(close_row), 'code fence backticks visible with cursor on open fence')
    apply.apply(buf, plan.marks, 4)
    ok(not tick_concealed(open_row) and not tick_concealed(close_row), 'code fence backticks visible with cursor on close fence')
    apply.apply(buf, plan.marks, 5)
    ok(tick_concealed(open_row) and tick_concealed(close_row), 'code fence backticks hidden again after leaving the block')
  else
    ok(false, 'parse lua fence block')
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'before',
    '```mermaid',
    'flowchart LR',
    '  A-->B',
    '```',
    'after',
  })
  pcall(vim.treesitter.start, buf, 'markdown')
  plan = parse.parse(buf, win, 50)
  local mmd_open, mmd_close
  if plan then
    for _, m in ipairs(plan.marks) do
      if m.key:match '^mmd_open:' then
        mmd_open = m.row
      elseif m.key:match '^mmd_close:' then
        mmd_close = m.row
      end
    end
  end
  ok(mmd_open == 1 and mmd_close == 4, 'mermaid fence rows')
  if plan and mmd_open then
    apply.apply(buf, plan.marks, 0)
    ok(row_hidden(mmd_open), 'mermaid open fence hidden when cursor is outside')
    ok(row_hidden(mmd_close), 'mermaid close fence hidden when cursor is outside')
    ok(row_hidden(mmd_open + 1), 'mermaid source hidden when cursor is outside')
    apply.apply(buf, plan.marks, mmd_open)
    ok(not row_hidden(mmd_open) and not row_hidden(mmd_close), 'mermaid fences visible with cursor on open fence')
    local media = require 'super-markdown.media'
    local host, above = media.block_host(buf, { row = mmd_open, end_row = mmd_close + 1 })
    eq({ host, above }, { 0, false }, 'mermaid diagram hosts on the line before the block')
    local hosted = vim.list_extend(vim.deepcopy(plan.marks), {
      {
        key = 'media:mermaid:1',
        row = host,
        col = 0,
        opts = { virt_lines = { { { 'diagram', 'Normal' } } } },
      },
    })
    vim.wo[win].conceallevel = 2
    apply.apply(buf, hosted, mmd_open)
    vim.api.nvim_win_set_cursor(win, { mmd_open + 1, 0 })
    apply.step_up(buf, win)
    eq(vim.api.nvim_win_get_cursor(win)[1], mmd_open, 'k from mermaid open fence moves to the line above')
  else
    ok(false, 'parse mermaid fence block')
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '| Command                | Purpose                                                             |',
    '| ---------------------- | ------------------------------------------------------------------- |',
    '| `npm run dev`          | Run the Vite client and assistant gateway together.                 |',
    '| `npm run dev:client`   | Run only the browser application on port 5173.                      |',
    '| `npm run dev:server`   | Run only the assistant gateway on port 8787.                        |',
  })
  plan = parse.parse(buf, win, 50)
  if plan then
    local overlays = 0
    for _, m in ipairs(plan.marks) do
      if m.key:match '^tov:' then
        overlays = overlays + 1
      end
    end
    ok(overlays >= 5, 'formatted table overlay rows')
  else
    ok(false, 'parse formatted table')
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '| Drawer       | Kinds                                    |',
    '  | ------------ | ---------------------------------------- |',
    '  | Flowchart    | `terminator`, `step`, `decision`, `data` |',
    '  | Workflow     | `event`, `timer`                         |',
  })
  plan = parse.parse(buf, win, 50)
  if plan then
    local concealed, indented = 0, 0
    for _, m in ipairs(plan.marks) do
      if m.key:match '^tov:' then
        if m.opts.conceal == '' then
          concealed = concealed + 1
        end
        if m.col > 0 then
          indented = indented + 1
        end
      end
    end
    ok(concealed >= 4, 'indented table conceals source pipes')
    ok(indented >= 3, 'indented table overlay starts at first pipe')
  else
    ok(false, 'parse indented table')
  end

  local function chunks_text(chunks)
    local s = ''
    for _, c in ipairs(chunks or {}) do
      s = s .. c[1]
    end
    return s
  end

  local old_cols = vim.o.columns
  vim.o.columns = 48
  pcall(vim.api.nvim_win_set_width, win, 48)
  local long = ('alpha beta gamma delta epsilon zeta '):rep(4)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '| Keep | Wrap this cell |',
    '| --- | --- |',
    '| x | ' .. vim.trim(long) .. ' |',
  })
  plan = parse.parse(buf, win, 50)
  vim.o.columns = old_cols
  if plan then
    local data, extra_chunks
    for _, m in ipairs(plan.marks) do
      if m.key:match '^tov:' and m.row == 2 then
        if m.key:match '^tov:%d+:%d+$' then
          data = m
        elseif not extra_chunks then
          extra_chunks = m.opts.virt_text
        end
      end
    end
    ok(data ~= nil, 'wrapped table data overlay')
    if data then
      local first = chunks_text(data.opts.virt_text)
      ok(first:find('│', 1, true) ~= nil and first:find('x', 1, true) ~= nil, 'first table line keeps short cell')
      ok(not first:find(vim.trim(long), 1, true), 'long cell wraps off the first overlay line')
      extra_chunks = extra_chunks or (data.opts.virt_lines and data.opts.virt_lines[1])
      ok(extra_chunks ~= nil, 'wrapped cell grows downward')
      if extra_chunks then
        local extra = chunks_text(extra_chunks)
        ok(extra:find('│', 1, true) ~= nil, 'wrapped continuation has borders')
        ok(extra:match '│%s+│' ~= nil, 'short cell padded on wrapped continuation')
      end
    end
  else
    ok(false, 'parse wrapping table')
  end

  -- Source shorter than the window but longer than table.max_width must
  -- grow with virt_lines. Overlaying at table_cols stacked on one visual
  -- line, so only the last wrapped cell line was visible.
  local old_wrap = vim.wo[win].wrap
  vim.wo[win].wrap = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.o.columns = 120
  pcall(vim.api.nvim_win_set_width, win, 120)
  local prose =
    'Long prose wraps inside this cell and the short cell grows with it so both rows stay a rectangle.'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '| Keep | Wrap this cell |',
    '| --- | --- |',
    '| short | ' .. prose .. ' |',
  })
  plan = parse.parse(buf, win, 50)
  vim.wo[win].wrap = old_wrap
  vim.o.columns = old_cols
  if plan then
    local data, cont
    for _, m in ipairs(plan.marks) do
      if m.key:match '^tov:' and m.row == 2 then
        if m.key:match '^tov:%d+:%d+$' then
          data = m
        elseif m.key:match '^tov:%d+:%d+:%d+$' then
          cont = true
        end
      end
    end
    ok(data ~= nil, 'fits-window wrapped table overlay')
    if data then
      local first = chunks_text(data.opts.virt_text)
      ok(first:find('short', 1, true) ~= nil, 'fits-window first line keeps short cell')
      ok(not first:find(prose, 1, true), 'fits-window prose wraps off the first overlay line')
      ok(
        data.opts.virt_lines ~= nil and #data.opts.virt_lines > 0,
        'source that fits the window grows with virt_lines'
      )
      ok(not cont, 'source that fits the window has no wrap-continuation overlays')
    end
  else
    ok(false, 'parse fits-window wrapping table')
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '| A | B |',
    '| --- | --- |',
    '| 1 | 2 |',
  })
  plan = parse.parse(buf, win, 50)
  if plan then
    local grew = false
    for _, m in ipairs(plan.marks) do
      if m.key:match '^tov:' and (m.opts.virt_lines or m.key:match '^tov:%d+:%d+:%d+$') then
        grew = true
      end
    end
    ok(not grew, 'narrow table does not wrap')
  else
    ok(false, 'parse narrow table')
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '| Keep | Wrap this cell |',
    '| --- | --- |',
    '| x | ' .. ('word '):rep(30) .. '|',
  })
  plan = parse.parse(buf, win, 50)
  if plan then
    local cap = require('super-markdown.config').table_cols(require('super-markdown.util').content_width(buf, win))
    local head
    for _, m in ipairs(plan.marks) do
      if m.key:match '^tov:' and m.row == 0 then
        head = m
        break
      end
    end
    ok(head ~= nil, 'table overlay for max_width')
    if head then
      ok(tmod.display_width(head.opts.virt_text) <= cap, 'table overlay respects table.max_width')
    end
  else
    ok(false, 'parse table max_width')
  end

  local mer = vim.fn.fnamemodify(fixture, ':h') .. '/mermaid.md'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(mer))
  plan = parse.parse(buf, win, 400)
  if plan then
    local n = 0
    for _, job in ipairs(plan.media) do
      if job.kind == 'mermaid' then
        n = n + 1
      end
    end
    ok(n >= 5, 'mermaid media jobs')
  end

  local mathf = vim.fn.fnamemodify(fixture, ':h') .. '/math.md'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(mathf))
  plan = parse.parse(buf, win, 200)
  if plan then
    local n = 0
    for _, job in ipairs(plan.media) do
      if job.kind == 'math' then
        n = n + 1
      end
    end
    ok(n >= 3, 'math media jobs')
    local coded = 0
    for _, job in ipairs(plan.media) do
      if job.kind == 'math' and job.content:find('E = mc', 1, true) then
        coded = coded + 1
      end
    end
    eq(coded, 1, 'math inside backticks is not rendered')
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'Keep `$E = mc^2$` as code, render $a^2$ though.',
  })
  plan = parse.parse(buf, win, 20)
  if plan then
    local contents = {}
    for _, job in ipairs(plan.media) do
      if job.kind == 'math' then
        contents[#contents + 1] = job.content
      end
    end
    eq(contents, { 'a^2' }, 'only math outside backticks is rendered')
  else
    ok(false, 'parse math in backticks')
  end

  local media = require 'super-markdown.media'
  local util = require 'super-markdown.util'
  local win_cols = util.content_width(buf, win)
  eq(require('super-markdown.config').get().media.max_width, 0.5, 'default max width fraction')
  eq(
    media.job_max_cols({ kind = 'mermaid' }, buf, win),
    math.max(1, math.floor(win_cols * 0.5)),
    'mermaid uses 50% of window width'
  )
  eq(
    media.job_max_cols({ kind = 'image', standalone = true }, buf, win),
    math.max(1, math.floor(win_cols * 0.5)),
    'standalone images use max width'
  )
  ok(
    media.job_max_cols({ kind = 'image' }, buf, win) == win_cols,
    'inline images use full window cap'
  )
  local protocol = require 'super-markdown.media.protocol'
  local mcols, mrows = protocol.fit_to_width(100, 50, 40, 100)
  eq(mcols, 40, 'mermaid fit_to_width uses target columns')
  ok(mrows >= 1, 'mermaid fit_to_width keeps aspect ratio')
  local c2, r2 = protocol.fit_to_width(100, 50, 40, 1)
  eq(r2, 1, 'mermaid fit_to_width respects max rows')
  ok(c2 <= 40, 'mermaid fit_to_width shrinks cols when height capped')

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'PNG passthrough:',
    '',
    '![Blue gradient](images/gradient.png)',
    '',
    'See ![inline](x.png) here',
  })
  plan = parse.parse(buf, win, 50)
  if plan then
    local src_marks, standalone, inline_img = 0, 0, 0
    for _, m in ipairs(plan.marks) do
      if m.key:match '^img_src:' then
        src_marks = src_marks + 1
        eq(m.row, 2, 'standalone image source mark row')
        ok(m.image_source and m.opts.conceal_lines == '', 'standalone image uses conceal_lines')
      end
    end
    for _, job in ipairs(plan.media) do
      if job.kind == 'image' then
        if job.standalone then
          standalone = standalone + 1
        else
          inline_img = inline_img + 1
        end
      end
    end
    eq(src_marks, 1, 'one standalone image source line')
    eq(standalone, 1, 'one standalone image job')
    eq(inline_img, 1, 'inline image is not standalone')
    apply.apply(buf, plan.marks, 0)
    local function img_hidden()
      local marks = vim.api.nvim_buf_get_extmarks(buf, apply.ns, { 2, 0 }, { 2, -1 }, { details = true })
      for _, em in ipairs(marks) do
        if em[4].conceal_lines ~= nil then
          return true
        end
      end
      return false
    end
    ok(img_hidden(), 'image markdown line hidden when cursor is elsewhere')
    apply.apply(buf, plan.marks, 2)
    ok(not img_hidden(), 'image markdown line visible on cursor line')
    ok(apply.is_media_open(plan.marks, 2), 'standalone image line is a media open row')
    local hosted = vim.list_extend(vim.deepcopy(plan.marks), {
      {
        key = 'media:img:2',
        row = 1,
        col = 0,
        opts = { virt_lines = { { { 'img', 'Normal' } }, { { 'img', 'Normal' } } } },
      },
    })
    apply.apply(buf, hosted, 2)
    vim.api.nvim_win_set_cursor(win, { 3, 0 })
    apply.step_up(buf, win)
    eq(vim.api.nvim_win_get_cursor(win)[1], 2, 'k from standalone image moves to the line above')
  else
    ok(false, 'parse standalone image line')
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Inline $E = mc^2$ here' })
  apply.apply(buf, {
    {
      key = 'media:mathi:0:8',
      row = 0,
      col = 8,
      hide_on_cursor = true,
      opts = {
        end_col = 17,
        conceal = '',
        virt_text = { { 'X', 'Normal' } },
        virt_text_pos = 'inline',
      },
    },
  }, 1)
  local function math_opts(row)
    local marks = vim.api.nvim_buf_get_extmarks(buf, apply.ns, { row, 0 }, { row, -1 }, { details = true })
    return marks[1] and marks[1][4] or {}
  end
  local shown = math_opts(0)
  ok(shown.virt_text ~= nil and shown.conceal == '', 'inline math rendered off cursor line')
  apply.cursor(buf, 0)
  local hidden = math_opts(0)
  ok(hidden.virt_text == nil and hidden.conceal == nil, 'inline math hidden on cursor line')

  local orig_avail = heading_media.available
  heading_media.available = function()
    return true
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '# Title One',
    '',
    'Setext',
    '======',
    'body',
  })
  pcall(vim.treesitter.start, buf, 'markdown')
  plan = parse.parse(buf, win, 50)
  if plan then
    local atx, setext_title, setext_rule, jobs = nil, nil, nil, 0
    local h_hl = 0
    for _, m in ipairs(plan.marks) do
      if m.key == 'hsrc:0' then
        atx = m
      elseif m.key == 'hsrc:2' then
        setext_title = m
      elseif m.key == 'hsrc:3' then
        setext_rule = m
      elseif m.key:match '^h:' then
        h_hl = h_hl + 1
      end
    end
    for _, job in ipairs(plan.media) do
      if job.kind == 'heading' then
        jobs = jobs + 1
      end
    end
    ok(jobs >= 2, 'unfocused heading plan includes a media job')
    ok(atx and atx.heading_source and atx.opts.conceal_lines == '', 'ATX heading source uses conceal_lines')
    ok(atx and atx.opts.conceal == nil, 'ATX heading does not leave a concealed blank line')
    ok(atx and atx.block_range and atx.block_range[1] == 0 and atx.block_range[2] == 0, 'ATX heading is one line')
    ok(
      setext_title
        and setext_rule
        and setext_title.block_range[1] == 2
        and setext_title.block_range[2] == 3
        and setext_rule.block_range[1] == 2
        and setext_rule.block_range[2] == 3,
      'setext span covers title and underline'
    )
    eq(h_hl, 0, 'graphics path does not apply SuperMarkdownH*')
    local function row_concealed(row)
      local marks = vim.api.nvim_buf_get_extmarks(buf, apply.ns, { row, 0 }, { row, -1 }, { details = true })
      for _, em in ipairs(marks) do
        if em[4].conceal ~= nil or em[4].conceal_lines ~= nil then
          return true
        end
      end
      return false
    end
    apply.apply(buf, plan.marks, 4)
    ok(row_concealed(0) and row_concealed(2) and row_concealed(3), 'heading source hidden when cursor is outside')
    apply.apply(buf, plan.marks, 0)
    ok(not row_concealed(0), 'ATX heading source visible when focused')
    local focused_hl = false
    for _, em in ipairs(vim.api.nvim_buf_get_extmarks(buf, apply.ns, { 0, 0 }, { 0, -1 }, { details = true })) do
      if em[4].hl_group and tostring(em[4].hl_group):match '^SuperMarkdownH' then
        focused_hl = true
      end
    end
    ok(not focused_hl, 'focused heading has no SuperMarkdownH* highlight')
    local media = require 'super-markdown.media'
    local host, above = media.heading_host(buf, { row = 2, end_row = 4 })
    eq({ host, above }, { 1, false }, 'heading graphic hosts on the previous line like an image')

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '# Editing',
      '# Below',
      'body',
    })
    plan = parse.parse(buf, win, 50)
    if plan then
      apply.apply(buf, plan.marks, 0)
      host, above = media.heading_host(buf, { row = 1, end_row = 2 })
      eq(
        { host, above },
        { 0, false },
        'following heading graphic stays below the heading being edited'
      )
    else
      ok(false, 'parse consecutive headings')
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '# Title One',
      '',
      'Setext',
      '======',
      'body',
    })
    plan = parse.parse(buf, win, 50)
    local hosted = vim.list_extend(vim.deepcopy(plan.marks), {
      {
        key = 'media:heading:0',
        row = 0,
        col = 0,
        hide_in_block = true,
        block_range = { 0, 0 },
        opts = { virt_lines = { { { 'H', 'Normal' } } }, virt_lines_above = true },
      },
    })
    local function has_heading_vl()
      local marks = vim.api.nvim_buf_get_extmarks(buf, apply.ns, 0, -1, { details = true })
      for _, em in ipairs(marks) do
        if em[4].virt_lines then
          return true
        end
      end
      return false
    end
    apply.apply(buf, hosted, 0)
    ok(not has_heading_vl(), 'heading graphic hidden when focused')
    apply.apply(buf, hosted, 4)
    ok(has_heading_vl(), 'heading graphic shown when unfocused')
    ok(not apply.is_media_open(plan.marks, 0), 'heading source is not skipped as a media open row')
    apply.apply(buf, plan.marks, 4)
    vim.api.nvim_win_set_cursor(win, { 5, 0 })
    apply.step_up(buf, win)
    eq(vim.api.nvim_win_get_cursor(win)[1], 4, 'k from below a heading lands on the heading')
    apply.apply(buf, plan.marks, 4)
    vim.api.nvim_win_set_cursor(win, { 5, 0 })
    apply.cursor(buf, 4)
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    apply.on_cursor(buf, win)
    eq(vim.api.nvim_win_get_cursor(win)[1], 1, 'jump to start is not intercepted as a skipped heading')
  else
    ok(false, 'parse heading graphics')
  end
  heading_media.available = orig_avail

  local function with_cfg(patch, fn)
    local orig = vim.deepcopy(cfg.get())
    cfg.values = vim.tbl_deep_extend('force', vim.deepcopy(orig), patch)
    local ran, err = pcall(fn)
    cfg.values = orig
    if not ran then
      error(err)
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '# Title One',
    '',
    'Setext',
    '======',
    '- item',
    '- [ ] task',
    '> quote',
    '',
    '> [!NOTE]',
    '> note body',
    '',
    '```lua',
    'print(1)',
    '```',
    '',
    '```mermaid',
    'flowchart LR',
    '  A-->B',
    '```',
  })
  pcall(vim.treesitter.start, buf, 'markdown')

  with_cfg({ heading = { enabled = false } }, function()
    heading_media.available = function()
      return true
    end
    plan = parse.parse(buf, win, 50)
    heading_media.available = orig_avail
    if plan then
      local hmarks, hjobs = 0, 0
      for _, m in ipairs(plan.marks) do
        if m.key:match '^h' then
          hmarks = hmarks + 1
        end
      end
      for _, job in ipairs(plan.media) do
        if job.kind == 'heading' then
          hjobs = hjobs + 1
        end
      end
      eq(hmarks, 0, 'heading disabled emits no heading marks')
      eq(hjobs, 0, 'heading disabled emits no heading jobs')
    else
      ok(false, 'parse heading disabled')
    end
  end)

  with_cfg({ heading = { enabled = true, simple = true } }, function()
    heading_media.available = function()
      return true
    end
    plan = parse.parse(buf, win, 50)
    heading_media.available = orig_avail
    if plan then
      local simple, hstar, rule, jobs, setext = 0, 0, 0, 0, 0
      local hmark
      for _, m in ipairs(plan.marks) do
        if m.key:match '^hsimple:' then
          simple = simple + 1
          ok(m.opts.hl_group == 'SuperMarkdownHeadingSimple', 'simple heading uses bold-only group')
          ok(m.hide_in_block == true, 'simple heading chrome hides when focused')
        elseif m.key:match '^h:' then
          hstar = hstar + 1
        elseif m.key:match '^hmark:' then
          hmark = m
        elseif m.key:match '^hsetext:' then
          setext = setext + 1
        end
        if m.opts.virt_lines then
          rule = rule + 1
        end
      end
      for _, job in ipairs(plan.media) do
        if job.kind == 'heading' then
          jobs = jobs + 1
        end
      end
      ok(simple >= 2, 'simple mode marks ATX and setext titles')
      ok(hmark and hmark.opts.conceal == '', 'simple mode conceals ATX hashes')
      ok(setext >= 1, 'simple mode conceals setext underline')
      eq(hstar, 0, 'simple mode does not use SuperMarkdownH*')
      eq(jobs, 0, 'simple mode does not emit heading graphics')
      eq(rule, 0, 'simple mode has no h1/h2 rule')
    else
      ok(false, 'parse heading simple')
    end
  end)

  with_cfg({ list = { enabled = false } }, function()
    plan = parse.parse(buf, win, 50)
    if plan then
      local n = 0
      for _, m in ipairs(plan.marks) do
        if m.key:match '^li:' then
          n = n + 1
        end
      end
      eq(n, 0, 'list disabled emits no bullet marks')
    else
      ok(false, 'parse list disabled')
    end
  end)

  with_cfg({ alert = { enabled = false } }, function()
    plan = parse.parse(buf, win, 50)
    if plan then
      local alerts, quotes = 0, 0
      for _, m in ipairs(plan.marks) do
        if m.key:match '^alert:' then
          alerts = alerts + 1
        elseif m.key:match '^q:' then
          quotes = quotes + 1
        end
      end
      eq(alerts, 0, 'alert disabled emits no alert titles')
      ok(quotes > 0, 'alert disabled falls back to quote chrome')
    else
      ok(false, 'parse alert disabled')
    end
  end)

  with_cfg({ quote = { enabled = false } }, function()
    plan = parse.parse(buf, win, 50)
    if plan then
      local alerts, plain = 0, 0
      for _, m in ipairs(plan.marks) do
        if m.key:match '^alert:' then
          alerts = alerts + 1
        elseif m.key:match '^q:' and m.row == 6 then
          plain = plain + 1
        end
      end
      ok(alerts > 0, 'quote disabled still renders alerts')
      eq(plain, 0, 'quote disabled skips plain quotes')
    else
      ok(false, 'parse quote disabled')
    end
  end)

  with_cfg({ media = { mermaid = false } }, function()
    plan = parse.parse(buf, win, 50)
    if plan then
      local mmd, cfence = 0, 0
      for _, job in ipairs(plan.media) do
        if job.kind == 'mermaid' then
          mmd = mmd + 1
        end
      end
      for _, m in ipairs(plan.marks) do
        if m.key:match '^cfence:' and m.row == 15 then
          cfence = cfence + 1
        end
      end
      eq(mmd, 0, 'mermaid off emits no mermaid jobs')
      ok(cfence > 0, 'mermaid off uses code chrome')
    else
      ok(false, 'parse mermaid off')
    end
  end)

  with_cfg({ code = { enabled = false } }, function()
    plan = parse.parse(buf, win, 50)
    if plan then
      local mmd, cfence = 0, 0
      for _, job in ipairs(plan.media) do
        if job.kind == 'mermaid' then
          mmd = mmd + 1
        end
      end
      for _, m in ipairs(plan.marks) do
        if m.key:match '^cfence:' then
          cfence = cfence + 1
        end
      end
      ok(mmd > 0, 'code off still emits mermaid jobs')
      eq(cfence, 0, 'code off emits no fence chrome')
    else
      ok(false, 'parse code off mermaid on')
    end
  end)
end

-- images
local img_md = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h') .. '/samples/showcase.md'
local png = vim.fn.fnamemodify(img_md, ':h') .. '/images/gradient.png'
local protocol = require 'super-markdown.media.protocol'
local pw, ph = protocol.png_size(png)
ok(pw ~= nil and pw > 0 and ph > 0, 'png_size reads sample PNG')
eq(path.resolve(img_md, 'images/gradient.png'), vim.fn.fnamemodify(png, ':p'), 'resolve showcase image')

if has_parser then
  local parse = require 'super-markdown.parse'
  local ibuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(ibuf)
  vim.bo[ibuf].filetype = 'markdown'
  vim.api.nvim_buf_set_name(ibuf, img_md)
  vim.api.nvim_buf_set_lines(ibuf, 0, -1, false, vim.fn.readfile(img_md))
  pcall(vim.treesitter.start, ibuf, 'markdown')
  local iwin = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(iwin, ibuf)
  local iplan = parse.parse(ibuf, iwin, 400)
  if iplan then
    local images, mermaids, maths = 0, 0, 0
    for _, job in ipairs(iplan.media) do
      if job.kind == 'image' then
        images = images + 1
      elseif job.kind == 'mermaid' then
        mermaids = mermaids + 1
      elseif job.kind == 'math' then
        maths = maths + 1
      end
    end
    ok(images >= 3, 'showcase image jobs')
    ok(mermaids >= 2, 'showcase mermaid jobs')
    ok(maths >= 2, 'showcase math jobs')
  else
    ok(false, 'parse showcase')
  end
end

-- mermaid helper (health-gated)
if mermaid.available() and vim.fn.executable 'rsvg-convert' == 1 then
  local dest = vim.fn.tempname() .. '.png'
  local done = false
  local ok_render = false
  mermaid.render('flowchart LR\n  A-->B\n', dest, 400, function(success)
    ok_render = success
    done = true
  end)
  vim.wait(15000, function()
    return done
  end, 50)
  ok(ok_render and vim.uv.fs_stat(dest) ~= nil, 'mermaid.render to png')

  local seq_dest = vim.fn.tempname() .. '.png'
  local seq_done, seq_ok, seq_err = false, false, nil
  mermaid.render(
    table.concat({
      'sequenceDiagram',
      '  participant Nvim',
      '  participant Helper as mermaid.render',
      '  Nvim->>Helper: diagram source',
      '  Helper-->>Nvim: SVG',
    }, '\n'),
    seq_dest,
    400,
    function(success, err)
      seq_ok, seq_err, seq_done = success, err, true
    end
  )
  vim.wait(20000, function()
    return seq_done
  end, 50)
  ok(seq_ok and vim.uv.fs_stat(seq_dest) ~= nil, 'sequence diagram renders to png')
  if not seq_ok then
    print('  sequence err: ' .. tostring(seq_err))
  end
else
  print 'skip mermaid conversion (helper or rsvg-convert missing)'
end

print(string.format('\n%d passed, %d failed', passed, failed))
if failed > 0 then
  vim.cmd 'cquit 1'
else
  vim.cmd 'qa!'
end
