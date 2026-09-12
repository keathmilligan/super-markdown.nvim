local cache = require 'super-markdown.media.cache'
local convert = require 'super-markdown.media.convert'
local style = require 'super-markdown.style'
local util = require 'super-markdown.util'

local M = {}

---gfm-hotview markdown.css font-size. 1em = terminal cell height.
M.EM = { 2, 1.5, 1.25, 1, 0.875, 0.85 }

---@param level integer
---@return number
function M.em(level)
  return M.EM[level] or 1
end

---Integer terminal rows for a heading graphic.
---Type size in em, rounded up to whole cells. The h1/h2 hairline shares
---the last cell instead of adding another row of margin.
---@param level integer
---@return integer
function M.rows(level)
  return math.max(1, math.ceil(M.em(level)))
end

---@return boolean
function M.available()
  local cfg = require('super-markdown.config').get()
  if not cfg.media.enabled then
    return false
  end
  local protocol = require 'super-markdown.media.protocol'
  return protocol.supported() and convert.has 'rsvg-convert'
end

---@param s string
---@return string
function M.visible_text(s)
  s = s or ''
  s = s:gsub('%[([^%]]-)%]%([^)]-%)', '%1')
  s = s:gsub('%[([^%]]-)%]%[[^%]]-%]', '%1')
  s = s:gsub('`([^`]+)`', '%1')
  s = s:gsub('~~([^~]+)~~', '%1')
  s = s:gsub('%*%*([^*]+)%*%*', '%1')
  s = s:gsub('__([^_]+)__', '%1')
  s = s:gsub('%*([^*]+)%*', '%1')
  s = s:gsub('_([^_]+)_', '%1')
  s = s:gsub(':([%w_+-]+):', function(name)
    return require('super-markdown.emoji').get(name) or (':' .. name .. ':')
  end)
  return vim.trim(s)
end

---@param s string
---@return string
local function xml_escape(s)
  return (s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'))
end

---@param word string
---@param max_cols integer
---@param out string[]
---@return string leftover
local function split_long(word, max_cols, out)
  local buf = ''
  local n = vim.fn.strchars(word)
  for i = 0, n - 1 do
    local ch = vim.fn.strcharpart(word, i, 1)
    if buf ~= '' and vim.fn.strdisplaywidth(buf .. ch) > max_cols then
      out[#out + 1] = buf
      buf = ch
    else
      buf = buf .. ch
    end
  end
  return buf
end

---@param text string
---@param max_cols integer
---@return string[]
function M.wrap(text, max_cols)
  max_cols = math.max(1, math.floor(max_cols))
  local lines = {}
  if text == '' then
    return { '' }
  end
  for para in vim.gsplit(text, '\n', { plain = true }) do
    if para == '' then
      lines[#lines + 1] = ''
    else
      local cur = ''
      for word in para:gmatch('%S+') do
        if vim.fn.strdisplaywidth(word) > max_cols then
          if cur ~= '' then
            lines[#lines + 1] = cur
            cur = ''
          end
          cur = split_long(word, max_cols, lines)
        elseif cur == '' then
          cur = word
        elseif vim.fn.strdisplaywidth(cur .. ' ' .. word) <= max_cols then
          cur = cur .. ' ' .. word
        else
          lines[#lines + 1] = cur
          cur = word
        end
      end
      if cur ~= '' then
        lines[#lines + 1] = cur
      end
    end
  end
  if #lines == 0 then
    return { '' }
  end
  return lines
end

---@class super_markdown.HeadingSvgOpts
---@field max_cols integer
---@field cell_width number
---@field cell_height number
---@field fg? string
---@field border? string

---Pixel size of the heading bitmap: exact integer cells so Kitty does not scale.
---@param cols integer
---@param rows integer
---@param cell_w number
---@param cell_h number
---@return integer
---@return integer
function M.canvas_px(cols, rows, cell_w, cell_h)
  local w = math.max(1, math.floor(cols * cell_w + 0.5))
  local h = math.max(1, math.floor(rows * cell_h + 0.5))
  return w, h
end

---@param text string
---@param level integer
---@param opts super_markdown.HeadingSvgOpts
---@return string
function M.svg(text, level, opts)
  level = math.min(6, math.max(1, level))
  local cell_w = math.max(1, opts.cell_width or 9)
  local cell_h = math.max(1, opts.cell_height or 18)
  local max_cols = math.max(2, opts.max_cols)
  -- One column of slack so virt_lines cannot wrap (wrap stretches Kitty images).
  local cols = math.max(1, max_cols - 1)
  local fs = M.em(level) * cell_h
  local lines = M.wrap(text, math.max(1, cols - 1))
  -- Hairline sits below the em-box, not the alphabetic baseline (which
  -- still runs through descenders and the bottom of most glyphs).
  local rule_pad = level <= 2 and 8 or 0
  local content_bottom = math.floor(#lines * fs + rule_pad)
  local rows = math.max(M.rows(level), math.max(1, math.ceil(content_bottom / cell_h)))
  local w, h = M.canvas_px(cols, rows, cell_w, cell_h)
  local p = style.palette()
  local fg = opts.fg or (level >= 6 and p.muted or p.fg)
  local parts = {
    string.format(
      '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">',
      w,
      h,
      w,
      h
    ),
  }
  -- Leftover cell pixels go above the glyphs, not under the rule/text.
  local shift = math.max(0, h - content_bottom)
  for i, ln in ipairs(lines) do
    local y = math.floor((i - 1) * fs + fs * 0.8) + shift
    parts[#parts + 1] = string.format(
      '<text x="2" y="%d" font-family="Liberation Sans, Noto Sans, DejaVu Sans, sans-serif" font-size="%.2f" font-weight="600" fill="%s">%s</text>',
      y,
      fs,
      fg,
      xml_escape(ln)
    )
  end
  if level <= 2 then
    local y = math.min(h - 1, content_bottom - 1 + shift)
    parts[#parts + 1] = string.format(
      '<line x1="0" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>',
      y,
      w,
      y,
      opts.border or p.border
    )
  end
  parts[#parts + 1] = '</svg>'
  return table.concat(parts, '')
end

---@param text string
---@param level integer
---@param max_cols integer
---@param cell { cell_width: number, cell_height: number }
---@return string
function M.cache_path(text, level, max_cols, cell)
  local theme = vim.o.background == 'light' and 'light' or 'dark'
  local payload = table.concat({
    'v11-rule',
    tostring(level),
    tostring(max_cols),
    tostring(math.floor((cell.cell_width or 0) * 100)),
    tostring(math.floor((cell.cell_height or 0) * 100)),
    text,
  }, '\0')
  return cache.path('heading', theme, payload)
end

---@param text string
---@param level integer
---@param dest_png string
---@param opts super_markdown.HeadingSvgOpts
---@param on_done fun(ok: boolean, err?: string, file?: string)
---@return vim.SystemObj|nil
function M.render(text, level, dest_png, opts, on_done)
  if not convert.has 'rsvg-convert' then
    on_done(false, 'rsvg-convert not found')
    return
  end
  local svg = M.svg(text, level, opts)
  local svg_path = dest_png:gsub('%.png$', '.svg')
  util.write_file(svg_path, svg)
  local w = tonumber(svg:match('width="(%d+)"'))
  local h = tonumber(svg:match('height="(%d+)"'))
  return convert.svg_to_png(svg_path, dest_png, { width = w, height = h }, function(ok, err)
    on_done(ok, err, dest_png)
  end)
end

return M
