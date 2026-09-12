local emoji = require 'super-markdown.emoji'
local heading_media = require 'super-markdown.media.heading'
local util = require 'super-markdown.util'

local M = {}

local ALERTS = {
  NOTE = { title = 'Note', icon = vim.fn.nr2char(0xF02FC) }, -- 󰋼 md-information
  TIP = { title = 'Tip', icon = vim.fn.nr2char(0xF0335) }, -- 󰌵 md-lightbulb
  IMPORTANT = { title = 'Important', icon = vim.fn.nr2char(0xF002A) }, -- 󰀪 md-alert
  WARNING = { title = 'Warning', icon = vim.fn.nr2char(0xF0026) }, -- 󰀦 md-alert-octagon
  CAUTION = { title = 'Caution', icon = vim.fn.nr2char(0xF0159) }, -- 󰅙 md-close-circle
}

local md_query ---@type vim.treesitter.Query
local inline_query ---@type vim.treesitter.Query

local function queries()
  if not md_query then
    md_query = vim.treesitter.query.parse(
      'markdown',
      [[
        (atx_heading) @heading
        (setext_heading) @heading
        (fenced_code_block) @code
        (pipe_table) @table
        (block_quote) @quote
        (list_item) @list
        (thematic_break) @hr
        (minus_metadata) @frontmatter
        (plus_metadata) @frontmatter
        (task_list_marker_checked) @task_checked
        (task_list_marker_unchecked) @task_unchecked
      ]]
    )
  end
  if not inline_query then
    inline_query = vim.treesitter.query.parse(
      'markdown_inline',
      [[
        (inline_link) @link
        (full_reference_link) @link
        (collapsed_reference_link) @link
        (image) @image
        (code_span) @codespan
        (strikethrough) @strike
        (emphasis) @emphasis
        (strong_emphasis) @strong
        (shortcut_link) @shortcut
        (uri_autolink) @autolink
        (email_autolink) @autolink
      ]]
    )
  end
end

---@param buf integer
---@param row integer
---@return string
local function line(buf, row)
  return util.line(buf, row)
end

---@param marks super_markdown.Mark[]
---@param mark super_markdown.Mark
local function add(marks, mark)
  marks[#marks + 1] = mark
end

---Set for the duration of a parse. Used so inline conceals can pad table cells.
---@class super_markdown.ParseCtx
---@field buf integer
---@field marks super_markdown.Mark[]
---@field cells { row: integer, col: integer, end_col: integer }[]
---@field pads table<string, { row: integer, col: integer, n: integer }>
---@field tables table[]
local ctx ---@type super_markdown.ParseCtx|nil

---@param key string
---@param row integer
---@param col integer
---@param end_col integer
---@param ch? string
---@param hl? string
---@param hide_on_cursor? boolean
local function add_conceal(key, row, col, end_col, ch, hl, hide_on_cursor)
  if not ctx or end_col <= col then
    return
  end
  add(ctx.marks, {
    key = key,
    row = row,
    col = col,
    opts = { end_col = end_col, conceal = ch or '', hl_group = hl },
    hide_on_cursor = hide_on_cursor,
  })
end

local function flush_pads()
  if not ctx then
    return
  end
  for id, pad in pairs(ctx.pads) do
    if pad.n > 0 then
      add(ctx.marks, {
        key = 'tpad:' .. id,
        row = pad.row,
        col = pad.col,
        opts = {
          virt_text = { { string.rep(' ', pad.n), 'SuperMarkdownTableBorder' } },
          virt_text_pos = 'inline',
        },
      })
    end
  end
end

---@param name string
---@return string
local function alert_hl(name, suffix)
  local key = name:sub(1, 1) .. name:sub(2):lower()
  return 'SuperMarkdownAlert' .. key .. (suffix or '')
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
---@param media table[]
---@param width integer
local function heading(buf, node, marks, media, width)
  local srow, _, erow = node:range()
  local last = math.max(srow, erow - 1)
  local ln = line(buf, srow)
  local hashes, rest = ln:match('^(#+)%s*(.*)$')
  local level = 1
  local text = ''
  if hashes then
    level = math.min(6, math.max(1, #hashes))
    rest = (rest or ''):gsub('%s+#*%s*$', '')
    text = heading_media.visible_text(rest)
  else
    local setext = line(buf, last)
    if setext:match('^=+') then
      level = 1
    else
      level = 2
    end
    text = heading_media.visible_text(ln)
  end
  if heading_media.available() then
    media[#media + 1] = {
      key = string.format('heading:%d', srow),
      kind = 'heading',
      row = srow,
      col = 0,
      end_row = last + 1,
      end_col = #ln,
      content = text,
      level = level,
      max_rows = 8,
    }
    for r = srow, last do
      local rl = line(buf, r)
      add(marks, {
        key = string.format('hsrc:%d', r),
        row = r,
        col = 0,
        opts = { end_col = math.max(#rl, 1), conceal_lines = '' },
        block_range = { srow, last },
        hide_in_block = true,
        heading_source = true,
      })
    end
    return
  end
  if hashes then
    local end_col = #hashes
    if ln:sub(end_col + 1, end_col + 1) == ' ' then
      end_col = end_col + 1
    end
    add(marks, {
      key = string.format('hmark:%d', srow),
      row = srow,
      col = 0,
      opts = { end_col = end_col, conceal = '' },
    })
  end
  add(marks, {
    key = string.format('h:%d', srow),
    row = srow,
    col = 0,
    opts = {
      end_col = #ln,
      hl_group = 'SuperMarkdownH' .. level,
      virt_lines = level <= 2 and { { { string.rep('─', width), 'SuperMarkdownBorder' } } } or nil,
    },
  })
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
---@param media table[]
---@param width integer
local function code_block(buf, node, marks, media, width)
  local srow, _, erow = node:range()
  local lang = ''
  local content_s, content_e = srow + 1, erow - 1
  for child in node:iter_children() do
    local t = child:type()
    if t == 'info_string' or t == 'language' then
      lang = vim.trim(util.node_text(buf, child)):match('^%S+') or ''
    elseif t == 'code_fence_content' then
      content_s, _, content_e = child:range()
    end
  end
  local open = line(buf, srow)
  if lang == 'mermaid' then
    local src = table.concat(vim.api.nvim_buf_get_lines(buf, content_s, content_e, false), '\n')
    local last = math.max(srow, erow - 1)
    media[#media + 1] = {
      key = string.format('mermaid:%d', srow),
      kind = 'mermaid',
      row = srow,
      col = 0,
      end_row = last + 1,
      end_col = #open,
      content = src,
    }
    add(marks, {
      key = string.format('mmd_open:%d', srow),
      row = srow,
      col = 0,
      opts = { end_col = #open },
      block_range = { srow, last },
      mermaid_anchor = true,
      fence_text = open,
    })
    if last > srow then
      local close = line(buf, last)
      add(marks, {
        key = string.format('mmd_close:%d', last),
        row = last,
        col = 0,
        opts = { end_col = #close },
        block_range = { srow, last },
        mermaid_anchor = true,
        fence_text = close,
      })
    end
    for r = srow + 1, last - 1 do
      local ln = line(buf, r)
      add(marks, {
        key = string.format('mmd_src:%d', r),
        row = r,
        col = 0,
        opts = { end_col = math.max(#ln, 1), conceal_lines = '' },
        block_range = { srow, last },
        mermaid_source = true,
      })
    end
    return
  end
  local last = math.max(srow, erow - 1)
  local indent, ticks, rest = open:match('^(%s*)([`~]+)(.*)$')
  add(marks, {
    key = string.format('cfence:%d', srow),
    row = srow,
    col = 0,
    opts = {
      end_col = math.max(#open, 1),
      hl_group = 'SuperMarkdownCodeBlock',
      line_hl_group = 'SuperMarkdownCodeBlock',
      hl_eol = true,
    },
    block_range = { srow, last },
    fence_text = open,
  })
  if ticks then
    local tick_col = #indent
    add(marks, {
      key = string.format('cfence_ticks:%d', srow),
      row = srow,
      col = tick_col,
      opts = { end_col = tick_col + #ticks, conceal = '' },
      block_range = { srow, last },
      hide_in_block = true,
    })
    if lang ~= '' then
      local pad = (rest or ''):match('^(%s*)') or ''
      local lang_col = tick_col + #ticks + #pad
      add(marks, {
        key = string.format('cfence_lang:%d', srow),
        row = srow,
        col = lang_col,
        opts = { end_col = lang_col + #lang, hl_group = 'SuperMarkdownCodeLabel' },
        block_range = { srow, last },
        hide_in_block = true,
      })
    end
  end
  if erow > srow then
    local close = line(buf, last)
    local cindent, cticks = close:match('^(%s*)([`~]+)')
    if cticks then
      add(marks, {
        key = string.format('cfence_end:%d', last),
        row = last,
        col = 0,
        opts = {
          end_col = math.max(#close, 1),
          hl_group = 'SuperMarkdownCodeBlock',
          line_hl_group = 'SuperMarkdownCodeBlock',
          hl_eol = true,
        },
        block_range = { srow, last },
        fence_text = close,
      })
      add(marks, {
        key = string.format('cfence_end_ticks:%d', last),
        row = last,
        col = #cindent,
        opts = { end_col = #cindent + #cticks, conceal = '' },
        block_range = { srow, last },
        hide_in_block = true,
      })
    end
  end
  for r = srow + 1, last - 1 do
    add(marks, {
      key = string.format('cbg:%d', r),
      row = r,
      col = 0,
      opts = {
        hl_group = 'SuperMarkdownCodeBlock',
        line_hl_group = 'SuperMarkdownCodeBlock',
        hl_eol = true,
      },
    })
  end
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
local function quote_or_alert(buf, node, marks)
  local srow, _, erow = node:range()
  local first = line(buf, srow)
  local raw = first:match('%[!([%a]+)%]')
  local atype = raw and ALERTS[raw:upper()]
  local aname = raw and raw:upper() or nil
  for r = srow, erow - 1 do
    local ln = line(buf, r)
    local bar_hl = atype and alert_hl(aname, 'Bar') or 'SuperMarkdownQuoteBar'
    local gt = ln:find('>')
    if gt then
      add(marks, {
        key = string.format('qmark:%d', r),
        row = r,
        col = gt - 1,
        opts = { end_col = gt, conceal = '▎', hl_group = bar_hl },
      })
    end
    add(marks, {
      key = string.format('q:%d', r),
      row = r,
      col = 0,
      opts = {
        end_col = #ln,
        hl_group = atype and alert_hl(aname) or 'SuperMarkdownQuote',
      },
    })
  end
  if atype then
    local ln = first
    local a, b = ln:find('%[![%a]+%]')
    if a then
      add(marks, {
        key = string.format('alert:%d', srow),
        row = srow,
        col = a - 1,
        opts = {
          end_col = b,
          conceal = '',
          virt_text = { { atype.icon .. ' ' .. atype.title, alert_hl(aname, 'Title') } },
          virt_text_pos = 'inline',
        },
        hide_on_cursor = true,
      })
    end
  end
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
local function list_item(buf, node, marks)
  local row = node:range()
  local ln = line(buf, row)
  if ln:match('%[[ xX]%]') then
    return
  end
  local col = ln:find('[-*+]') or ln:find('%d+%.')
  if not col then
    return
  end
  local bullet = ln:match('^%s*([-*+])')
  if bullet then
    add(marks, {
      key = string.format('li:%d', row),
      row = row,
      col = col - 1,
      opts = { end_col = col, conceal = '•', hl_group = 'SuperMarkdownListIcon' },
    })
  end
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
---@param checked boolean
local function task(buf, node, marks, checked)
  local row, col = node:range()
  local ln = line(buf, row)
  local prefix = ln:sub(1, col)
  local marker = prefix:find('[-*+]%s*$') or prefix:find('%d+%.%s*$')
  local from = marker and (marker - 1) or col
  add(marks, {
    key = string.format('task:%d:%d', row, col),
    row = row,
    col = from,
    opts = {
      end_col = col + 3,
      conceal = checked and '󰱒' or '󰄱',
      hl_group = checked and 'SuperMarkdownCheckboxChecked' or 'SuperMarkdownCheckbox',
    },
  })
end

---@param raw string
---@param base_hl string
---@return { [1]: string, [2]: string }[]
---@return integer
local function cell_chunks(raw, base_hl)
  local s = vim.trim(raw)
  local chunks = {}
  local i = 1
  local function push(text, hl)
    if text ~= '' then
      chunks[#chunks + 1] = { text, hl }
    end
  end
  while i <= #s do
    local rest = s:sub(i)
    local a, b, cap = rest:find '^`([^`]+)`'
    if a == 1 then
      push(cap, 'SuperMarkdownCode')
      i = i + b
    else
      a, b, cap = rest:find '^%*%*([^*]+)%*%*'
      if a == 1 then
        push(cap, 'SuperMarkdownStrong')
        i = i + b
      else
        a, b, cap = rest:find '^~~([^~]+)~~'
        if a == 1 then
          push(cap, 'SuperMarkdownStrike')
          i = i + b
        else
          a, b, cap = rest:find '^%*([^*]+)%*'
          if a == 1 then
            push(cap, 'SuperMarkdownEm')
            i = i + b
          else
            a, b, cap = rest:find '^%[([^%]]+)%]%([^)]+%)'
            if a == 1 then
              push(cap, 'SuperMarkdownLink')
              i = i + b
            else
              a, b, cap = rest:find '^:([%w_+-]+):'
              if a == 1 then
                push(emoji.get(cap) or rest:sub(a, b), base_hl)
                i = i + b
              else
                local nxt = rest:find '[`%*~%[:]'
                if nxt and nxt > 1 then
                  push(rest:sub(1, nxt - 1), base_hl)
                  i = i + nxt - 1
                elseif nxt == 1 then
                  push(rest:sub(1, 1), base_hl)
                  i = i + 1
                else
                  push(rest, base_hl)
                  break
                end
              end
            end
          end
        end
      end
    end
  end
  local width = 0
  for _, ch in ipairs(chunks) do
    width = width + vim.fn.strdisplaywidth(ch[1])
  end
  return chunks, width
end

local function table_block(buf, node, marks)
  if not ctx then
    return
  end
  local tbl = { rows = {} }
  local data_i = 0
  for row_node in node:iter_children() do
    local rtype = row_node:type()
    local r = row_node:range()
    local ln = line(buf, r)
    local kind = rtype == 'pipe_table_delimiter_row' and 'delim'
      or (rtype == 'pipe_table_header' and 'head' or 'data')
    local cells = {}
    for part in row_node:iter_children() do
      local pt = part:type()
      if pt == 'pipe_table_cell' or pt == 'pipe_table_delimiter_cell' then
        cells[#cells + 1] = util.node_text(buf, part)
        local pr, pc, _, pec = part:range()
        ctx.cells[#ctx.cells + 1] = { row = pr, col = pc, end_col = pec }
      end
    end
    if kind == 'data' then
      data_i = data_i + 1
    end
    local pipe = ln:find('|', 1, true)
    tbl.rows[#tbl.rows + 1] = {
      row = r,
      kind = kind,
      cells = cells,
      stripe = kind == 'data' and data_i % 2 == 1,
      line_len = #ln,
      indent = pipe and (pipe - 1) or 0,
    }
  end
  ctx.tables[#ctx.tables + 1] = tbl
end

local function flush_tables()
  if not ctx then
    return
  end
  for t, tbl in ipairs(ctx.tables) do
    local widths = {}
    for _, row in ipairs(tbl.rows) do
      if row.kind ~= 'delim' then
        local hl = row.kind == 'head' and 'SuperMarkdownTableHead' or 'Normal'
        for i, raw in ipairs(row.cells) do
          local _, w = cell_chunks(raw, hl)
          widths[i] = math.max(widths[i] or 0, w)
        end
      end
    end
    for _, row in ipairs(tbl.rows) do
      local chunks = { { '│', 'SuperMarkdownTableBorder' } }
      if row.kind == 'delim' then
        for i = 1, #widths do
          chunks[#chunks + 1] = { string.rep('─', widths[i] + 2), 'SuperMarkdownTableBorder' }
          chunks[#chunks + 1] = { '│', 'SuperMarkdownTableBorder' }
        end
      else
        local hl = row.kind == 'head' and 'SuperMarkdownTableHead'
          or (row.stripe and 'SuperMarkdownTableRowAlt' or 'Normal')
        for i, raw in ipairs(row.cells) do
          local inner, w = cell_chunks(raw, hl)
          local pad = math.max(0, (widths[i] or 0) - w)
          chunks[#chunks + 1] = { ' ', hl }
          for _, ch in ipairs(inner) do
            chunks[#chunks + 1] = ch
          end
          chunks[#chunks + 1] = { string.rep(' ', pad) .. ' ', hl }
          chunks[#chunks + 1] = { '│', 'SuperMarkdownTableBorder' }
        end
      end
      add(ctx.marks, {
        key = string.format('tov:%d:%d', t, row.row),
        row = row.row,
        col = row.indent or 0,
        opts = {
          end_col = row.line_len,
          conceal = '',
          virt_text = chunks,
          virt_text_pos = 'overlay',
          virt_text_hide = true,
        },
        hide_on_cursor = true,
      })
    end
  end
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
---@param width integer
local function hr(buf, node, marks, width)
  local row = node:range()
  local ln = line(buf, row)
  add(marks, {
    key = string.format('hr:%d', row),
    row = row,
    col = 0,
    opts = {
      end_col = #ln,
      conceal = '',
      virt_text = { { string.rep('─', width), 'SuperMarkdownHr' } },
      virt_text_pos = 'overlay',
    },
    hide_on_cursor = true,
  })
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
local function frontmatter(buf, node, marks)
  local srow, _, erow = node:range()
  add(marks, {
    key = string.format('fm:%d', srow),
    row = srow,
    col = 0,
    opts = { end_row = erow, end_col = 0, hl_group = 'SuperMarkdownFrontmatter' },
  })
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
local function codespan(buf, node, marks)
  local row, col, _, ecol = node:range()
  add(marks, {
    key = string.format('cs:%d:%d', row, col),
    row = row,
    col = col,
    opts = { end_col = ecol, hl_group = 'SuperMarkdownCode' },
  })
  local text = util.node_text(buf, node)
  local ticks = text:match('^(`+)')
  if ticks then
    local n = #ticks
    add_conceal(string.format('csL:%d:%d', row, col), row, col, col + n)
    add_conceal(string.format('csR:%d:%d', row, ecol), row, ecol - n, ecol)
  end
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
local function strike(buf, node, marks)
  local row, col, _, ecol = node:range()
  local ln = line(buf, row)
  if ln:sub(col + 1, col + 2) == '~~' then
    add_conceal(string.format('stL:%d:%d', row, col), row, col, col + 2)
  end
  if ln:sub(ecol - 1, ecol) == '~~' then
    add_conceal(string.format('stR:%d:%d', row, ecol), row, ecol - 2, ecol)
  end
  add(marks, {
    key = string.format('st:%d:%d', row, col),
    row = row,
    col = col,
    opts = { end_col = ecol, hl_group = 'SuperMarkdownStrike' },
  })
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
---@param hl string
local function emphasis(buf, node, marks, hl)
  local row, col, _, ecol = node:range()
  local text = util.node_text(buf, node)
  local open = text:match('^([*_]+)')
  if open then
    local n = #open
    add_conceal(string.format('emL:%d:%d', row, col), row, col, col + n)
    if text:sub(-n) == open then
      add_conceal(string.format('emR:%d:%d', row, ecol), row, ecol - n, ecol)
    end
  end
  add(marks, {
    key = string.format('em:%d:%d', row, col),
    row = row,
    col = col,
    opts = { end_col = ecol, hl_group = hl },
  })
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
local function link(buf, node, marks)
  local row, col, _, ecol = node:range()
  add(marks, {
    key = string.format('ln:%d:%d', row, col),
    row = row,
    col = col,
    opts = { end_col = ecol, hl_group = 'SuperMarkdownLink' },
  })
  local ln = line(buf, row)
  local dest = ln:sub(col + 1, ecol):match('%((.-)%)$')
  if dest then
    local dest_start = ecol - #dest - 2
    if dest_start >= col then
      add_conceal(string.format('lnd:%d:%d', row, col), row, dest_start, ecol, '', nil, true)
    end
  end
end

---@param buf integer
---@param node TSNode
---@param marks super_markdown.Mark[]
local function shortcut(buf, node, marks)
  local row, col, _, ecol = node:range()
  local text = util.node_text(buf, node)
  if text:match('^%[%^') then
    add_conceal(string.format('fn:%d:%d', row, col), row, col, ecol, '', 'SuperMarkdownFootnote', true)
    add(marks, {
      key = string.format('fnv:%d:%d', row, col),
      row = row,
      col = col,
      opts = {
        virt_text = { { text:gsub('[%[%]%^]', ''), 'SuperMarkdownFootnote' } },
        virt_text_pos = 'inline',
      },
      hide_on_cursor = true,
    })
  end
end

---@param buf integer
---@param node TSNode
---@param media table[]
local function image(buf, node, marks, media)
  local row, col, erow, ecol = node:range()
  local src
  for child in node:iter_children() do
    if child:type() == 'link_destination' then
      src = util.node_text(buf, child)
      break
    end
  end
  if not src then
    local text = util.node_text(buf, node)
    src = text:match('%((.-)%)') or text:match('%b[]')
  end
  if not src or src == '' then
    return
  end
  src = src:gsub('^<', ''):gsub('>$', '')
  src = src:match('^(%S+)') or src
  local ln = line(buf, row)
  local standalone = vim.trim(ln) == vim.trim(util.node_text(buf, node))
  media[#media + 1] = {
    key = string.format('img:%d:%d:%s', row, col, src),
    kind = 'image',
    row = row,
    col = col,
    end_row = erow,
    end_col = ecol,
    src = src,
    standalone = standalone,
  }
  if standalone then
    add(marks, {
      key = string.format('img_src:%d', row),
      row = row,
      col = 0,
      opts = { end_col = math.max(#ln, 1), conceal_lines = '' },
      image_source = true,
    })
  end
end

---@param buf integer
---@param srow integer
---@param erow integer
---@param marks super_markdown.Mark[]
local function emojis(buf, srow, erow, marks)
  local lines = vim.api.nvim_buf_get_lines(buf, srow, erow, false)
  for i, ln in ipairs(lines) do
    local row = srow + i - 1
    local col = 1
    while true do
      local a, b, name = ln:find(':([%w_+-]+):', col)
      if not a then
        break
      end
      local glyph = emoji.get(name)
      if glyph then
        add_conceal(string.format('emo:%d:%d', row, a), row, a - 1, b, glyph)
      end
      col = b + 1
    end
  end
end

---@param ln string
---@return { [1]: integer, [2]: integer }[]
local function backtick_spans(ln)
  local spans = {}
  local i = 1
  while i <= #ln do
    local a, b, ticks = ln:find('(`+)', i)
    if not a then
      break
    end
    local close = ln:find(ticks, b + 1, true)
    if not close then
      break
    end
    local cend = close + #ticks - 1
    spans[#spans + 1] = { a, cend }
    i = cend + 1
  end
  return spans
end

---@param spans { [1]: integer, [2]: integer }[]
---@param a integer
---@param b integer
---@return boolean
local function in_backticks(spans, a, b)
  for _, s in ipairs(spans) do
    if a >= s[1] and b <= s[2] then
      return true
    end
  end
  return false
end

---@param buf integer
---@param srow integer
---@param erow integer
---@param code_ranges { [1]: integer, [2]: integer }[]
---@param media table[]
local function math_blocks(buf, srow, erow, code_ranges, media)
  local function in_code(row)
    for _, r in ipairs(code_ranges) do
      if row >= r[1] and row < r[2] then
        return true
      end
    end
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(buf, srow, erow, false)
  local i = 1
  while i <= #lines do
    local row = srow + i - 1
    if not in_code(row) then
      local ln = lines[i]
      local spans = backtick_spans(ln)
      local ds, de = ln:find('%$%$')
      if ln:match('^%s*%$%$') and not (ds and in_backticks(spans, ds, de)) then
        local chunk = { ln }
        local j = i
        if not ln:match('%$%$%s*$') or ln:match('^%s*%$%$%s*$') then
          j = i + 1
          while j <= #lines do
            chunk[#chunk + 1] = lines[j]
            if lines[j]:match('%$%$') then
              break
            end
            j = j + 1
          end
        end
        local src = table.concat(chunk, '\n'):gsub('^%s*%$%$', ''):gsub('%$%$%s*$', '')
        local last = srow + j - 1
        media[#media + 1] = {
          key = string.format('math:%d', row),
          kind = 'math',
          row = row,
          col = 0,
          end_row = last + 1,
          end_col = #ln,
          content = vim.trim(src),
          display = true,
          max_rows = 8,
        }
        add(ctx.marks, {
          key = string.format('math_open:%d', row),
          row = row,
          col = 0,
          opts = { end_col = #ln },
          block_range = { row, last },
          mermaid_anchor = true,
          fence_text = ln,
        })
        if last > row then
          local close = line(buf, last)
          add(ctx.marks, {
            key = string.format('math_close:%d', last),
            row = last,
            col = 0,
            opts = { end_col = #close },
            block_range = { row, last },
            mermaid_anchor = true,
            fence_text = close,
          })
        end
        for r = row + 1, last - 1 do
          local rl = line(buf, r)
          add(ctx.marks, {
            key = string.format('math_src:%d', r),
            row = r,
            col = 0,
            opts = { end_col = math.max(#rl, 1), conceal_lines = '' },
            block_range = { row, last },
            mermaid_source = true,
          })
        end
        i = j
      else
        local col = 1
        while true do
          local a, b = ln:find('%$[^$]+%$', col)
          if not a then
            break
          end
          if not ln:match('^%s*%$%$') and not in_backticks(spans, a, b) then
            local src = ln:sub(a + 1, b - 1)
            media[#media + 1] = {
              key = string.format('mathi:%d:%d', row, a),
              kind = 'math',
              row = row,
              col = a - 1,
              end_row = row,
              end_col = b,
              content = src,
              display = false,
              max_rows = 1,
            }
          end
          col = b + 1
        end
      end
    end
    i = i + 1
  end
end

---@class super_markdown.Plan
---@field marks super_markdown.Mark[]
---@field media table[]
---@field range { [1]: integer, [2]: integer }

---@param buf integer
---@param win integer
---@param overscan integer
---@return super_markdown.Plan|nil
function M.parse(buf, win, overscan)
  queries()
  local srow, erow = util.view_range(win, overscan)
  local width = util.content_width(buf, win)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok or not parser then
    return nil
  end
  local range = { srow, 0, erow, 0 }
  parser:parse(range)
  local marks = {} ---@type super_markdown.Mark[]
  local media = {}
  local code_ranges = {}
  ctx = { buf = buf, marks = marks, cells = {}, pads = {}, tables = {} }

  local function walk(langtree)
    local trees = langtree:trees()
    if not trees or #trees == 0 then
      trees = langtree:parse(range)
    end
    local lang = langtree:lang()
    for _, tree in ipairs(trees or {}) do
      local root = tree:root()
      if lang == 'markdown' then
        for id, node in md_query:iter_captures(root, buf, srow, erow) do
          local cap = md_query.captures[id]
          if cap == 'heading' then
            heading(buf, node, marks, media, width)
          elseif cap == 'code' then
            local a, _, b = node:range()
            code_ranges[#code_ranges + 1] = { a, b }
            code_block(buf, node, marks, media, width)
          elseif cap == 'quote' then
            quote_or_alert(buf, node, marks)
          elseif cap == 'list' then
            list_item(buf, node, marks)
          elseif cap == 'task_checked' then
            task(buf, node, marks, true)
          elseif cap == 'task_unchecked' then
            task(buf, node, marks, false)
          elseif cap == 'table' then
            table_block(buf, node, marks)
          elseif cap == 'hr' then
            hr(buf, node, marks, width)
          elseif cap == 'frontmatter' then
            frontmatter(buf, node, marks)
          end
        end
      elseif lang == 'markdown_inline' then
        for id, node in inline_query:iter_captures(root, buf, srow, erow) do
          local cap = inline_query.captures[id]
          if cap == 'link' or cap == 'autolink' then
            link(buf, node, marks)
          elseif cap == 'image' then
            image(buf, node, marks, media)
          elseif cap == 'codespan' then
            codespan(buf, node, marks)
          elseif cap == 'strike' then
            strike(buf, node, marks)
          elseif cap == 'emphasis' then
            emphasis(buf, node, marks, 'SuperMarkdownEm')
          elseif cap == 'strong' then
            emphasis(buf, node, marks, 'SuperMarkdownStrong')
          elseif cap == 'shortcut' then
            shortcut(buf, node, marks)
          end
        end
      end
    end
    for _, child in pairs(langtree:children()) do
      walk(child)
    end
  end
  walk(parser)

  emojis(buf, srow, erow, marks)
  math_blocks(buf, srow, erow, code_ranges, media)
  flush_pads()
  flush_tables()
  ctx = nil
  return { marks = marks, media = media, range = { srow, erow } }
end

return M
