local apply = require 'super-markdown.apply'
local cache = require 'super-markdown.media.cache'
local config = require 'super-markdown.config'
local image = require 'super-markdown.media.image'
local log = require 'super-markdown.log'
local math_media = require 'super-markdown.media.math'
local heading = require 'super-markdown.media.heading'
local mermaid = require 'super-markdown.media.mermaid'
local protocol = require 'super-markdown.media.protocol'
local util = require 'super-markdown.util'

local M = {}

---@type table<string, { id: integer, file: string, sent: boolean }>
local images = {}

---@type table<string, integer>
local placements = {}

local function pixel_width(win, max_cols)
  local sz = protocol.size()
  return math.floor(sz.cell_width * max_cols)
end

---Host row for mermaid / display-math virt_lines. Use the line above the
---block so the image sits before the source. If the block starts on line 0,
---draw above that line instead.
---@param buf integer
---@param job table
---@return integer row
---@return boolean above
function M.block_host(buf, job)
  if job.row > 0 then
    return job.row - 1, false
  end
  return job.row, true
end

---Same as a standalone image: virt_lines on a visible neighbor line.
---Skip conceal_lines hosts (images / mermaid / display math / headings)
---so the graphic is not attached to a hidden row.
---@param buf integer
---@param job table
---@return integer row
---@return boolean above
function M.heading_host(buf, job)
  local s = apply.state(buf)
  local function hidden(row)
    if row < 0 then
      return true
    end
    for _, m in ipairs(s.plan or {}) do
      if m.row == row and (m.image_source or m.mermaid_source or m.mermaid_anchor or m.heading_source) then
        return true
      end
    end
    return false
  end
  local host = job.row - 1
  while host >= 0 and hidden(host) do
    host = host - 1
  end
  if host >= 0 and not hidden(host) then
    return host, false
  end
  -- No visible line above (first line of the buffer): draw above the next
  -- visible line so conceal_lines can hide the heading source without
  -- taking the graphic with it.
  local last = (job.end_row or (job.row + 1)) - 1
  local after = last + 1
  local line_count = vim.api.nvim_buf_line_count(buf)
  while after < line_count and hidden(after) do
    after = after + 1
  end
  if after < line_count and not hidden(after) then
    return after, true
  end
  return job.row, true
end

local function virt_line_opts(virt, above)
  local opts = {
    virt_lines = virt,
    virt_text_hide = false,
  }
  if above then
    opts.virt_lines_above = true
  end
  -- Default virt_lines wrap. A wrapped placeholder row stretches the PNG.
  if vim.fn.has 'nvim-0.11' == 1 then
    opts.virt_lines_overflow = 'trunc'
  end
  return opts
end

---@param job table
---@param buf integer
---@param win integer
---@return integer
function M.job_max_cols(job, buf, win)
  if job.max_cols then
    return job.max_cols
  end
  local win_cols = util.content_width(buf, win)
  if job.kind == 'mermaid' or job.standalone then
    local width = config.get().media.max_width
    if width == nil then
      width = 0.5
    end
    if width > 1 then
      return math.max(1, math.min(win_cols, math.floor(width)))
    end
    return math.max(1, math.floor(win_cols * width))
  end
  return win_cols
end

---@param buf integer
---@param win integer
---@param job table
local function place_png(buf, win, job, file)
  if not protocol.supported() then
    log.debug 'kitty graphics protocol not detected; skip image placement'
    return
  end
  local cfg = config.get()
  local max_cols = M.job_max_cols(job, buf, win)
  local max_rows = job.max_rows or cfg.media.max_height or 40
  file = vim.fn.fnamemodify(file, ':p')
  local pw, ph = protocol.png_size(file)
  if not pw then
    log.error('not a PNG or unreadable: ' .. file)
    return
  end
  local cols, rows
  if job.kind == 'mermaid' or job.standalone then
    cols, rows = protocol.fit_to_width(pw, ph, max_cols, max_rows)
  elseif job.kind == 'heading' then
    -- Bitmap is already an integer number of cells. Do not fit_cells: that
    -- changes r/c and is what stretched/clipped thin heading strips.
    local sz = protocol.size()
    local cap = math.max(1, max_cols - 1)
    cols = math.max(1, math.min(cap, math.floor(pw / sz.cell_width + 0.5)))
    rows = math.max(1, math.floor(ph / sz.cell_height + 0.5))
    if rows > max_rows then
      rows = max_rows
    end
  else
    cols, rows = protocol.fit_cells(pw, ph, max_cols, max_rows)
  end
  local img = images[file]
  if not img then
    img = { id = protocol.next_image_id(), file = file }
    images[file] = img
  end
  local pid = placements[job.key]
  if not pid then
    pid = protocol.next_placement_id()
    placements[job.key] = pid
  end
  protocol.show(img.id, pid, file, cols, rows)
  local grid, hl = protocol.grid(img.id, pid, rows, cols)
  local s = apply.state(buf)
  local prefix = 'media:' .. job.key
  s.media_marks = s.media_marks or {}

  local function add_mark(mark)
    s.media_marks[job.key] = mark
  end

  if job.kind == 'math' and not job.display then
    add_mark {
      key = prefix,
      row = job.row,
      col = job.col,
      opts = {
        end_col = job.end_col or job.col,
        conceal = '',
        virt_text = { { grid[1], hl } },
        virt_text_pos = 'inline',
        virt_text_hide = false,
      },
      hide_on_cursor = true,
    }
  elseif job.kind == 'heading' then
    local last = (job.end_row or (job.row + 1)) - 1
    local virt = {}
    for _, g in ipairs(grid) do
      virt[#virt + 1] = { { g, hl } }
    end
    if #virt > 0 then
      local host, above = M.heading_host(buf, job)
      add_mark {
        key = prefix,
        row = host,
        col = 0,
        opts = virt_line_opts(virt, above),
        block_range = { job.row, last },
        hide_in_block = true,
      }
    end
  elseif job.kind == 'mermaid' or job.display then
    local all = {}
    for i = 1, #grid do
      all[#all + 1] = { { grid[i], hl } }
    end
    local host, above = M.block_host(buf, job)
    add_mark {
      key = prefix,
      row = host,
      col = 0,
      opts = virt_line_opts(all, above),
    }
  elseif job.standalone then
    local virt = {}
    for _, g in ipairs(grid) do
      virt[#virt + 1] = { { g, hl } }
    end
    local anchor = job.row > 0 and (job.row - 1) or job.row
    add_mark {
      key = prefix,
      row = anchor,
      col = 0,
      opts = virt_line_opts(virt, false),
    }
  else
    local virt = {}
    for _, g in ipairs(grid) do
      virt[#virt + 1] = { { g, hl } }
    end
    add_mark {
      key = prefix,
      row = job.row,
      col = job.col,
      opts = {
        end_col = job.end_col or job.col,
        conceal = '',
        virt_lines = virt,
        virt_text_hide = false,
      },
    }
  end
  s.media_shown = s.media_shown or {}
  s.media_shown[job.key] = nil
  local existing = {}
  for _, m in ipairs(s.plan) do
    if not m.key:match '^media:' then
      existing[#existing + 1] = m
    end
  end
  for _, m in pairs(s.media_marks) do
    existing[#existing + 1] = m
  end
  apply.apply(buf, existing, s.cursor_row)
end

---@param handle { proc?: vim.SystemObj, dest?: string }|vim.SystemObj|nil
local function kill_job(handle)
  if not handle then
    return
  end
  local proc = handle.proc or handle
  pcall(function()
    proc:kill 'sigterm'
  end)
end

---@param buf integer
---@param job table
---@param err? string
local function place_mermaid_error(buf, job, err)
  local s = apply.state(buf)
  if not s.enabled or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  err = mermaid.format_error(err or 'mermaid.render() failed')
  local title = 'Syntax error in text'
  if not (err:find('[Pp]arse') or err:find('[Ss]yntax') or err:find('unexpected') or err:find('line ')) then
    title = 'Mermaid render failed'
  end
  local width = 72
  local win = util.buf_win(buf)
  if win ~= 0 then
    width = math.max(40, util.content_width(buf, win) - 2)
  end
  local virt = { { { ' ' .. title, 'SuperMarkdownMermaidErrorTitle' } } }
  for _, raw in ipairs(vim.split(err, '\n', { plain = true })) do
    local line = raw
    while vim.fn.strchars(line) > width do
      virt[#virt + 1] = { { ' ' .. vim.fn.strcharpart(line, 0, width), 'SuperMarkdownMermaidError' } }
      line = vim.fn.strcharpart(line, width)
    end
    if line ~= '' then
      virt[#virt + 1] = { { ' ' .. line, 'SuperMarkdownMermaidError' } }
    end
  end
  local prefix = 'media:' .. job.key
  local sig = job.row .. '\0' .. err
  if s.media_shown and s.media_shown[job.key] == sig then
    return
  end
  s.media_shown = s.media_shown or {}
  s.media_shown[job.key] = sig
  local host, above = M.block_host(buf, job)
  s.media_marks = s.media_marks or {}
  s.media_marks[job.key] = {
    key = prefix,
    row = host,
    col = 0,
    opts = virt_line_opts(virt, above),
  }
  local existing = {}
  for _, m in ipairs(s.plan) do
    if not m.key:match '^media:' then
      existing[#existing + 1] = m
    end
  end
  for _, m in pairs(s.media_marks) do
    existing[#existing + 1] = m
  end
  apply.apply(buf, existing, s.cursor_row)
end

---@param buf integer
---@param job table
---@param file string
local function place_if_wanted(buf, job, file)
  local s = apply.state(buf)
  if not s.enabled or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local current
  for _, j in ipairs(s.media or {}) do
    if j.key == job.key then
      current = j
      break
    end
  end
  if not current then
    return
  end
  local win = util.buf_win(buf)
  if win == 0 then
    return
  end
  place_png(buf, win, current, file)
end

---@param buf integer
---@param job table
---@param dest string
---@param start fun(done: fun(ok: boolean, err?: string, file?: string)): vim.SystemObj|nil
local function ensure_job(buf, job, dest, start)
  local s = apply.state(buf)
  local inflight = s.jobs[job.key]
  if inflight and inflight.dest == dest then
    return
  end
  if inflight then
    kill_job(inflight)
    s.jobs[job.key] = nil
  end
  if cache.hit(dest) then
    place_if_wanted(buf, job, dest)
    return
  end
  s.jobs[job.key] = { dest = dest }
  local proc = start(function(ok, err, file)
    local cur = s.jobs[job.key]
    local wanted = cur and cur.dest == dest
    if wanted then
      s.jobs[job.key] = nil
    end
    if not wanted then
      return
    end
    if not ok then
      if job.kind == 'mermaid' then
        mermaid.remember_error(job.content, err or 'mermaid.render() failed')
        place_mermaid_error(buf, job, err)
        return
      end
      if err then
        log.error(err)
      end
      return
    end
    place_if_wanted(buf, job, file or dest)
  end)
  if s.jobs[job.key] and s.jobs[job.key].dest == dest then
    s.jobs[job.key].proc = proc
  end
end

---@param buf integer
---@param win integer
---@param jobs table[]
function M.update(buf, win, jobs)
  local cfg = config.get()
  if not cfg.media.enabled then
    return
  end
  local s = apply.state(buf)
  s.media = jobs
  local parts = { tostring(util.content_width(buf, win)) }
  for _, job in ipairs(jobs) do
    parts[#parts + 1] = table.concat({
      job.key,
      job.kind,
      job.content or job.src or '',
      tostring(job.row),
    }, '\0')
  end
  local sig = table.concat(parts, '\n')
  if s.media_sig == sig then
    return
  end
  s.media_sig = sig
  local markdown_file = vim.api.nvim_buf_get_name(buf)
  local live = {} ---@type table<string, boolean>

  local function bucket_px(n)
    return math.max(32, math.floor(n / 32 + 0.5) * 32)
  end

  for _, job in ipairs(jobs) do
    live[job.key] = true
    if job.kind == 'image' then
      local img_px = bucket_px(pixel_width(win, M.job_max_cols(job, buf, win)))
      local dest = image.cache_path(markdown_file, job.src, img_px)
      ensure_job(buf, job, dest, function(done)
        return image.prepare(markdown_file, job.src, dest, img_px, done)
      end)
    elseif job.kind == 'mermaid' and cfg.media.mermaid then
      local cached_err = mermaid.cached_error(job.content)
      if cached_err then
        place_mermaid_error(buf, job, cached_err)
      else
        local mermaid_px = bucket_px(pixel_width(win, M.job_max_cols(job, buf, win)))
        local dest = mermaid.cache_path(job.content, mermaid_px)
        ensure_job(buf, job, dest, function(done)
          return mermaid.render(job.content, dest, mermaid_px, done)
        end)
      end
    elseif job.kind == 'math' and cfg.media.math then
      local cell_h = protocol.size().cell_height
      local height = job.display and math.max(72, math.floor(cell_h * 4)) or math.max(cell_h, math.floor(cell_h * 1.05))
      local dest = math_media.cache_path(job.content, job.display, height)
      ensure_job(buf, job, dest, function(done)
        return math_media.render(job.content, job.display, dest, height, done)
      end)
    elseif job.kind == 'heading' then
      local cell = protocol.size()
      local cols = M.job_max_cols(job, buf, win)
      local dest = heading.cache_path(job.content, job.level, cols, cell)
      ensure_job(buf, job, dest, function(done)
        return heading.render(job.content, job.level, dest, {
          max_cols = cols,
          cell_width = cell.cell_width,
          cell_height = cell.cell_height,
        }, done)
      end)
    end
  end

  for key, handle in pairs(s.jobs) do
    if not live[key] then
      kill_job(handle)
      s.jobs[key] = nil
    end
  end
  if s.media_marks then
    for key in pairs(s.media_marks) do
      if not live[key] then
        s.media_marks[key] = nil
      end
    end
  end
end

return M
