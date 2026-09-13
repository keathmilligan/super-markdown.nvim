local config = require 'super-markdown.config'
local emoji = require 'super-markdown.emoji'

local M = {}

---@param chunks { [1]: string, [2]: string }[]
---@return integer
function M.display_width(chunks)
  local width = 0
  for _, ch in ipairs(chunks) do
    width = width + vim.fn.strdisplaywidth(ch[1])
  end
  return width
end

---@param raw string
---@param base_hl string
---@return { [1]: string, [2]: string }[]
---@return integer
function M.cell_chunks(raw, base_hl)
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
  return chunks, M.display_width(chunks)
end

---@param text string
---@param hl string
---@param width integer
---@param add fun(text: string, hl: string)
---@param flush fun()
local function add_long(text, hl, width, add, flush)
  local buf = ''
  local n = vim.fn.strchars(text)
  for i = 0, n - 1 do
    local ch = vim.fn.strcharpart(text, i, 1)
    if buf ~= '' and vim.fn.strdisplaywidth(buf .. ch) > width then
      add(buf, hl)
      flush()
      buf = ch
    else
      buf = buf .. ch
    end
  end
  if buf ~= '' then
    add(buf, hl)
  end
end

---Word-wrap highlighted chunks to `width` display columns.
---@param chunks { [1]: string, [2]: string }[]
---@param width integer
---@return { [1]: string, [2]: string }[][]
function M.wrap_chunks(chunks, width)
  width = math.max(1, math.floor(width))
  if M.display_width(chunks) <= width then
    return { chunks }
  end
  local lines = {}
  local cur = {}
  local cur_w = 0
  local function flush()
    while #cur > 0 and cur[#cur][1]:match '^%s+$' do
      cur_w = cur_w - vim.fn.strdisplaywidth(cur[#cur][1])
      cur[#cur] = nil
    end
    lines[#lines + 1] = cur
    cur = {}
    cur_w = 0
  end
  local function add(text, hl)
    if text == '' then
      return
    end
    cur[#cur + 1] = { text, hl }
    cur_w = cur_w + vim.fn.strdisplaywidth(text)
  end
  local function add_word(text, hl)
    local tw = vim.fn.strdisplaywidth(text)
    if tw > width then
      if cur_w > 0 then
        flush()
      end
      add_long(text, hl, width, add, flush)
      return
    end
    if cur_w > 0 and cur_w + tw > width then
      flush()
    end
    add(text, hl)
  end
  for _, ch in ipairs(chunks) do
    local text, hl = ch[1], ch[2]
    local i = 1
    while i <= #text do
      local a, b = text:find('%s+', i)
      if a == i then
        local sp = text:sub(a, b)
        local sw = vim.fn.strdisplaywidth(sp)
        if cur_w > 0 and cur_w + sw <= width then
          add(sp, hl)
        elseif cur_w > 0 then
          flush()
        end
        i = b + 1
      elseif a then
        add_word(text:sub(i, a - 1), hl)
        i = a
      else
        add_word(text:sub(i), hl)
        break
      end
    end
  end
  if cur_w > 0 or #lines == 0 then
    flush()
  end
  return lines
end

---@param chunks { [1]: string, [2]: string }[]
---@param width integer
---@param align 'left'|'right'|'center'
---@param hl string
---@return { [1]: string, [2]: string }[]
function M.pad_chunks(chunks, width, align, hl)
  local w = M.display_width(chunks)
  local pad = math.max(0, width - w)
  if pad == 0 then
    return chunks
  end
  local left, right = 0, pad
  if align == 'right' then
    left, right = pad, 0
  elseif align == 'center' then
    left = math.floor(pad / 2)
    right = pad - left
  end
  local out = {}
  if left > 0 then
    out[#out + 1] = { string.rep(' ', left), hl }
  end
  for _, ch in ipairs(chunks) do
    out[#out + 1] = ch
  end
  if right > 0 then
    out[#out + 1] = { string.rep(' ', right), hl }
  end
  return out
end

---Lock short columns at their natural width; split leftover budget among the rest.
---@param naturals integer[]
---@param budget integer
---@return integer[]
function M.col_widths(naturals, budget)
  local n = #naturals
  if n == 0 then
    return {}
  end
  budget = math.max(n, math.floor(budget))
  local sum = 0
  for _, w in ipairs(naturals) do
    sum = sum + w
  end
  if sum <= budget then
    local out = {}
    for i, w in ipairs(naturals) do
      out[i] = math.max(1, w)
    end
    return out
  end
  local locked = {}
  local locked_total = 0
  local locked_count = 0
  local share = math.floor(budget / n)
  local changed = true
  while changed do
    changed = false
    for i = 1, n do
      if not locked[i] and naturals[i] <= share then
        locked[i] = true
        locked_total = locked_total + math.max(1, naturals[i])
        locked_count = locked_count + 1
        changed = true
      end
    end
    if changed then
      local free = n - locked_count
      if free > 0 then
        share = math.floor((budget - locked_total) / free)
      end
    end
  end
  local out = {}
  for i = 1, n do
    out[i] = locked[i] and math.max(1, naturals[i]) or math.max(1, share)
  end
  return out
end

---@param raw string
---@return 'left'|'right'|'center'
function M.alignment(raw)
  local s = vim.trim(raw)
  local left = s:sub(1, 1) == ':'
  local right = s:sub(-1) == ':'
  if left and right then
    return 'center'
  elseif right then
    return 'right'
  end
  return 'left'
end

---@param s string
---@param target integer
---@return integer
function M.byte_at_display(s, target)
  if target <= 0 or s == '' then
    return 0
  end
  local display, byte = 0, 0
  local n = vim.fn.strchars(s)
  for ci = 0, n - 1 do
    local ch = vim.fn.strcharpart(s, ci, 1)
    local w = vim.fn.strdisplaywidth(ch)
    if display + w > target then
      return byte
    end
    display = display + w
    byte = byte + #ch
  end
  return #s
end

local BORDER = 'SuperMarkdownTableBorder'

---@param widths integer[]
---@return { [1]: string, [2]: string }[]
local function delim_line(widths)
  local chunks = { { '│', BORDER } }
  for i = 1, #widths do
    chunks[#chunks + 1] = { string.rep('─', widths[i] + 2), BORDER }
    chunks[#chunks + 1] = { '│', BORDER }
  end
  return chunks
end

---@param wrapped { [1]: string, [2]: string }[][][]
---@param vis integer
---@param widths integer[]
---@param aligns string[]
---@param hl string
---@return { [1]: string, [2]: string }[]
local function data_line(wrapped, vis, widths, aligns, hl)
  local chunks = { { '│', BORDER } }
  for i, w in ipairs(widths) do
    local inner = (wrapped[i] and wrapped[i][vis]) or {}
    inner = M.pad_chunks(inner, w, aligns[i] or 'left', hl)
    chunks[#chunks + 1] = { ' ', hl }
    for _, ch in ipairs(inner) do
      chunks[#chunks + 1] = ch
    end
    chunks[#chunks + 1] = { ' ', hl }
    chunks[#chunks + 1] = { '│', BORDER }
  end
  return chunks
end

---@param chunks { [1]: string, [2]: string }[]
---@param indent integer
---@return { [1]: string, [2]: string }[]
local function with_indent(chunks, indent)
  if indent <= 0 then
    return chunks
  end
  local out = { { string.rep(' ', indent), 'Normal' } }
  for _, ch in ipairs(chunks) do
    out[#out + 1] = ch
  end
  return out
end

---@param ctx super_markdown.ParseCtx
---@param t integer
---@param tbl table
---@param table_width integer
---@param content_width integer
local function flush_one(ctx, t, tbl, table_width, content_width)
  local ncols = 0
  local indent = 0
  local aligns = {}
  for _, row in ipairs(tbl.rows) do
    ncols = math.max(ncols, #row.cells)
    indent = math.max(indent, row.indent or 0)
    if row.kind == 'delim' then
      for i, raw in ipairs(row.cells) do
        aligns[i] = M.alignment(raw)
      end
    end
  end
  if ncols == 0 then
    return
  end
  local naturals = {}
  for i = 1, ncols do
    naturals[i] = 1
  end
  for _, row in ipairs(tbl.rows) do
    if row.kind ~= 'delim' then
      local hl = row.kind == 'head' and 'SuperMarkdownTableHead' or 'Normal'
      for i, raw in ipairs(row.cells) do
        local _, w = M.cell_chunks(raw, hl)
        naturals[i] = math.max(naturals[i] or 1, w)
      end
    end
  end
  -- 1 col slack so overlay / virt_lines do not wrap at the window edge.
  -- overhead: left border + per cell (pad + pad + right border).
  local budget = math.max(ncols, table_width - indent - 1 - (1 + 3 * ncols))
  local widths = M.col_widths(naturals, budget)
  -- Source wrap continuations follow the window, not table.max_width.
  -- Using the table cap here stacked overlays on one visual line so only
  -- the last wrapped cell line was visible.
  local wrap_w = math.max(1, content_width)
  for _, row in ipairs(tbl.rows) do
    local hl = row.kind == 'head' and 'SuperMarkdownTableHead'
      or (row.stripe and 'SuperMarkdownTableRowAlt' or 'Normal')
    local wrapped = {}
    local height = 1
    if row.kind ~= 'delim' then
      for i = 1, ncols do
        local inner = M.cell_chunks(row.cells[i] or '', hl)
        wrapped[i] = M.wrap_chunks(inner, widths[i])
        height = math.max(height, #wrapped[i])
      end
    end
    local line = row.line or ''
    local src_wraps = 1
    if ctx.wrap ~= false then
      src_wraps = math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / wrap_w))
    end
    height = math.max(height, src_wraps)
    local function visual(vis)
      if row.kind == 'delim' then
        return delim_line(widths)
      end
      return data_line(wrapped, vis, widths, aligns, hl)
    end
    local function seg_end(vis)
      if vis >= src_wraps then
        return row.line_len
      end
      return M.byte_at_display(line, vis * wrap_w)
    end
    local first = visual(1)
    local virt = {}
    for vis = 2, height do
      if vis > src_wraps then
        virt[#virt + 1] = with_indent(visual(vis), row.indent or 0)
      end
    end
    local opts = {
      end_col = seg_end(1),
      conceal = '',
      virt_text = first,
      virt_text_pos = 'overlay',
      virt_text_hide = true,
    }
    if #virt > 0 then
      opts.virt_lines = virt
      if vim.fn.has 'nvim-0.11' == 1 then
        opts.virt_lines_overflow = 'trunc'
      end
    end
    ctx.marks[#ctx.marks + 1] = {
      key = string.format('tov:%d:%d', t, row.row),
      row = row.row,
      col = row.indent or 0,
      opts = opts,
      hide_on_cursor = true,
    }
    for vis = 2, math.min(height, src_wraps) do
      ctx.marks[#ctx.marks + 1] = {
        key = string.format('tov:%d:%d:%d', t, row.row, vis),
        row = row.row,
        col = M.byte_at_display(line, (vis - 1) * wrap_w),
        opts = {
          end_col = seg_end(vis),
          conceal = '',
          virt_text = with_indent(visual(vis), row.indent or 0),
          virt_text_pos = 'overlay',
          virt_text_hide = true,
        },
        hide_on_cursor = true,
      }
    end
  end
end

---@param ctx super_markdown.ParseCtx
function M.flush(ctx)
  local content_width = math.max(1, ctx.width or vim.o.columns)
  local table_width = config.table_cols(content_width)
  for t, tbl in ipairs(ctx.tables) do
    flush_one(ctx, t, tbl, table_width, content_width)
  end
end

return M
