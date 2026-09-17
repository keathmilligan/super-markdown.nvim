local config = require 'super-markdown.config'
local mdtable = require 'super-markdown.table'

local M = {}

local BULLET = '•'
local CHECKED = '󰱒'
local UNCHECKED = '󰄱'

---@param ctx super_markdown.ParseCtx
---@param item { row: integer, kind: 'ul'|'ol'|'task'|'cont', checked?: boolean }
function M.collect(ctx, item)
  if not ctx then
    return
  end
  ctx.lists = ctx.lists or {}
  for _, it in ipairs(ctx.lists) do
    if it.row == item.row then
      if item.kind == 'task' then
        it.kind = 'task'
        it.checked = item.checked
      end
      return
    end
  end
  ctx.lists[#ctx.lists + 1] = item
end

---@param ctx super_markdown.ParseCtx
---@param buf integer
---@param node TSNode
---@param srow integer
function M.collect_continuations(ctx, buf, node, srow)
  if not ctx then
    return
  end
  for child in node:iter_children() do
    if child:type() == 'paragraph' then
      local ps, _, pe = child:range()
      for r = ps, pe - 1 do
        if r ~= srow then
          M.collect(ctx, { row = r, kind = 'cont' })
        end
      end
    end
  end
end

---@param s string
---@return integer|nil used
local function quote_marker_len(s)
  local n = 0
  while n < 3 and s:sub(n + 1, n + 1):match '[ \t]' do
    n = n + 1
  end
  if s:sub(n + 1, n + 1) ~= '>' then
    return nil
  end
  local used = n + 1
  if s:sub(used + 1, used + 1) == ' ' then
    used = used + 1
  end
  return used
end

---@param ln string
---@param bar_hl? string
---@return { [1]: string, [2]: string }[] chunks
---@return string rest
local function split_quote(ln, bar_hl)
  if not bar_hl then
    return {}, ln
  end
  local chunks = {}
  local i = 1
  while i <= #ln do
    local used = quote_marker_len(ln:sub(i))
    if not used then
      break
    end
    local piece = ln:sub(i, i + used - 1)
    for ci = 1, #piece do
      local ch = piece:sub(ci, ci)
      if ch == '>' then
        chunks[#chunks + 1] = { '▎', bar_hl }
      elseif ch == ' ' or ch == '\t' then
        local w = vim.fn.strdisplaywidth(ch)
        if w > 0 then
          chunks[#chunks + 1] = { string.rep(' ', w), 'Normal' }
        end
      end
    end
    i = i + used
  end
  return chunks, ln:sub(i)
end

---@param n integer
---@return { [1]: string, [2]: string }[]
local function spaces(n)
  if n <= 0 then
    return {}
  end
  return { { string.rep(' ', n), 'Normal' } }
end

---@param chunks { [1]: string, [2]: string }[]
---@param extra { [1]: string, [2]: string }[]
---@return { [1]: string, [2]: string }[]
local function concat_chunks(chunks, extra)
  local out = {}
  for _, ch in ipairs(chunks) do
    out[#out + 1] = ch
  end
  for _, ch in ipairs(extra) do
    out[#out + 1] = ch
  end
  return out
end

---@param content string
---@param kind 'ul'|'ol'|'task'|'cont'
---@param checked? boolean
---@return { prefix: { [1]: string, [2]: string }[], hanging: integer, text: string }|nil
local function parse_content(content, kind, checked)
  local indent = content:match '^%s*' or ''
  local rest = content:sub(#indent + 1)
  local indent_w = vim.fn.strdisplaywidth(indent)
  if kind == 'cont' then
    return {
      prefix = spaces(indent_w),
      hanging = indent_w,
      text = rest,
    }
  end
  if kind == 'task' then
    local marker = rest:match '^[-*+]%s+%[[ xX]%]' or rest:match '^%d+[.)]%s+%[[ xX]%]'
    if not marker then
      return nil
    end
    local after = rest:sub(#marker + 1)
    local sp = after:match '^%s*' or ''
    local text = after:sub(#sp + 1)
    local glyph = checked and CHECKED or UNCHECKED
    local hl = checked and 'SuperMarkdownCheckboxChecked' or 'SuperMarkdownCheckbox'
    local prefix = concat_chunks(spaces(indent_w), { { glyph, hl } })
    local sp_w = vim.fn.strdisplaywidth(sp)
    if sp_w > 0 then
      prefix = concat_chunks(prefix, spaces(sp_w))
    end
    return {
      prefix = prefix,
      hanging = indent_w + vim.fn.strdisplaywidth(glyph) + sp_w,
      text = text,
    }
  end
  if kind == 'ul' then
    local bullet = rest:match '^[-*+]'
    if not bullet then
      return nil
    end
    local after = rest:sub(2)
    local sp = after:match '^%s*' or ''
    local text = after:sub(#sp + 1)
    local prefix = concat_chunks(spaces(indent_w), { { BULLET, 'SuperMarkdownListIcon' } })
    local sp_w = vim.fn.strdisplaywidth(sp)
    if sp_w > 0 then
      prefix = concat_chunks(prefix, spaces(sp_w))
    end
    return {
      prefix = prefix,
      hanging = indent_w + vim.fn.strdisplaywidth(BULLET) + sp_w,
      text = text,
    }
  end
  local num = rest:match '^%d+[.)]'
  if not num then
    return nil
  end
  local after = rest:sub(#num + 1)
  local sp = after:match '^%s*' or ''
  local text = after:sub(#sp + 1)
  local prefix = concat_chunks(spaces(indent_w), { { num, 'Normal' } })
  local sp_w = vim.fn.strdisplaywidth(sp)
  if sp_w > 0 then
    prefix = concat_chunks(prefix, spaces(sp_w))
  end
  return {
    prefix = prefix,
    hanging = indent_w + vim.fn.strdisplaywidth(num) + sp_w,
    text = text,
  }
end

---@param media table[]
---@return table<integer, boolean>
local function media_rows(media)
  local rows = {}
  for _, job in ipairs(media or {}) do
    local a = job.row or 0
    local b = job.end_row or (a + 1)
    if b <= a then
      b = a + 1
    end
    for r = a, b - 1 do
      rows[r] = true
    end
  end
  return rows
end

---@param ctx super_markdown.ParseCtx
---@param row integer
---@param line string
---@param visuals { [1]: string, [2]: string }[][]
local function emit(ctx, row, line, visuals)
  local wrap_w = math.max(1, ctx.width or vim.o.columns)
  local src_wraps = 1
  if ctx.wrap ~= false then
    src_wraps = math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / wrap_w))
  end
  local height = math.max(#visuals, src_wraps)
  local function visual(vis)
    return visuals[vis] or { { '', 'Normal' } }
  end
  local function seg_end(vis)
    if vis >= src_wraps then
      return #line
    end
    return mdtable.byte_at_display(line, vis * wrap_w)
  end
  local virt = {}
  for vis = 2, height do
    if vis > src_wraps then
      virt[#virt + 1] = visual(vis)
    end
  end
  local opts = {
    end_col = math.max(seg_end(1), 1),
    conceal = '',
    virt_text = visual(1),
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
    key = string.format('lov:%d', row),
    row = row,
    col = 0,
    opts = opts,
    hide_on_cursor = true,
  }
  for vis = 2, math.min(height, src_wraps) do
    ctx.marks[#ctx.marks + 1] = {
      key = string.format('lov:%d:%d', row, vis),
      row = row,
      col = mdtable.byte_at_display(line, (vis - 1) * wrap_w),
      opts = {
        end_col = seg_end(vis),
        conceal = '',
        virt_text = visual(vis),
        virt_text_pos = 'overlay',
        virt_text_hide = true,
      },
      hide_on_cursor = true,
    }
  end
end

---@param ctx super_markdown.ParseCtx
---@param media table[]
function M.flush(ctx, media)
  if not ctx or not ctx.lists or not config.feature 'list' then
    return
  end
  local buf = ctx.buf
  local max_cols = config.list_cols(math.max(1, ctx.width or vim.o.columns))
  local budget = math.max(1, max_cols - 1)
  local skip = media_rows(media)
  local quote_hl = ctx.quote_hl or {}
  for _, item in ipairs(ctx.lists) do
    if not skip[item.row] then
      local ln = vim.api.nvim_buf_get_lines(buf, item.row, item.row + 1, false)[1] or ''
      if ln ~= '' and vim.fn.strdisplaywidth(ln) > max_cols then
        local qhl = quote_hl[item.row]
        local qchunks, content = split_quote(ln, qhl and qhl.bar)
        local parsed = parse_content(content, item.kind, item.checked)
        if parsed then
          local q_w = mdtable.display_width(qchunks)
          local hanging = q_w + parsed.hanging
          local text_w = math.max(1, budget - hanging)
          local inner = mdtable.cell_chunks(parsed.text, 'Normal')
          local wrapped = mdtable.wrap_chunks(inner, text_w)
          local hang_prefix = concat_chunks(qchunks, spaces(parsed.hanging))
          local first_prefix = concat_chunks(qchunks, parsed.prefix)
          local visuals = {}
          for i, part in ipairs(wrapped) do
            local prefix = i == 1 and first_prefix or hang_prefix
            visuals[i] = concat_chunks(prefix, part)
          end
          emit(ctx, item.row, ln, visuals)
        end
      end
    end
  end
end

return M
