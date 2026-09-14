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

-- Each buffer occurrence owns one image and one virtual placement. Neovim
-- does not send underline colors for non-underlined placeholders, so terminals
-- may choose any placement for an image; sharing one across sizes is ambiguous.
---@type table<integer, table<string, { id: integer, pid: integer, file: string, cols: integer, rows: integer }>>
local placements = {}
local source_ns = vim.api.nvim_create_namespace 'super-markdown.media.sources'
local sources = {} ---@type table<integer, table<string, integer>>

---@param buf integer
function M.clear(buf)
  for _, img in pairs(placements[buf] or {}) do
    protocol.delete(img.id)
  end
  placements[buf] = nil
  sources[buf] = nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, source_ns, 0, -1)
  end
end

local function matches(job, mark)
  -- Row-based keys can be reused by different content after an edit.
  return job and (not mark.media_job or vim.deep_equal(job, mark.media_job))
end

---@param jobs table[]
---@param marks table<string, super_markdown.Mark>|nil
---@return super_markdown.Mark[]
function M.active_marks(jobs, marks)
  local live = {}
  for _, job in ipairs(jobs) do
    live[job.key] = job
  end
  local active = {}
  for key, mark in pairs(marks or {}) do
    if matches(live[key], mark) then
      active[#active + 1] = mark
    end
  end
  -- Several graphics can share one visible host when consecutive source
  -- lines are concealed. apply() merges those virt_lines; sort so the
  -- combined stack follows source order.
  table.sort(active, function(a, b)
    local aj, bj = a.media_job or a, b.media_job or b
    if aj.row ~= bj.row then
      return aj.row < bj.row
    end
    if (aj.col or 0) ~= (bj.col or 0) then
      return (aj.col or 0) < (bj.col or 0)
    end
    return a.key < b.key
  end)
  return active
end

local function in_insert(buf)
  return vim.api.nvim_get_current_buf() == buf and vim.fn.mode():sub(1, 1) == 'i'
end

local function insert_row(buf)
  if in_insert(buf) then
    return vim.api.nvim_win_get_cursor(0)[1] - 1
  end
end

---Keep the previous image jobs while their source line is being edited,
---including when incomplete Markdown temporarily removes them from the parse.
---@param buf integer
---@param jobs table[]
---@return table[]
function M.defer_images(buf, jobs)
  local s = apply.state(buf)
  local row = insert_row(buf)
  local deferred = row ~= nil and s.media_deferred_row == row
  local ready = {}
  for _, job in ipairs(jobs) do
    if job.kind == 'image' and job.row == row then
      deferred = true
    else
      ready[#ready + 1] = job
    end
  end
  for _, job in ipairs(s.media or {}) do
    local source = sources[buf] and sources[buf][job.key]
    local pos = source and vim.api.nvim_buf_get_extmark_by_id(buf, source_ns, source, {}) or {}
    if row ~= nil and job.kind == 'image' and pos[1] == row then
      deferred = true
      local delta = row - job.row
      if delta ~= 0 then
        job = vim.deepcopy(job)
        job.row = row
        job.end_row = job.end_row and (job.end_row + delta)
        local mark = s.media_marks and s.media_marks[job.key]
        if mark then
          mark.row = job.standalone and math.max(0, row - 1) or row
          mark.media_job = vim.deepcopy(job)
        end
      end
      ready[#ready + 1] = job
    end
  end
  s.media_deferred_row = deferred and row or nil
  return ready
end

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

M.heading_host = apply.heading_host

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
    return config.max_cols(win_cols)
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
  local max_cols = M.job_max_cols(job, buf, win)
  local max_rows = job.max_rows
  if not max_rows then
    local win_rows = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_height(win) or 40
    max_rows = config.max_rows(win_rows)
  end
  file = vim.fn.fnamemodify(file, ':p')
  local pw, ph = protocol.png_size(file)
  if not pw then
    log.error('not a PNG or unreadable: ' .. file)
    return
  end
  local cols, rows
  if job.kind == 'mermaid' then
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
    -- Images and math: natural size, scaled down only to fit the cap.
    cols, rows = protocol.fit_cells(pw, ph, max_cols, max_rows)
  end
  placements[buf] = placements[buf] or {}
  local img = placements[buf][job.key]
  if img and (img.file ~= file or img.cols ~= cols or img.rows ~= rows) then
    protocol.delete(img.id)
    img = nil
  end
  if not img then
    img = {
      id = protocol.next_image_id(),
      pid = protocol.next_placement_id(),
      file = file,
      cols = cols,
      rows = rows,
    }
    placements[buf][job.key] = img
    protocol.show(img.id, img.pid, file, cols, rows)
  end
  local grid, hl = protocol.grid(img.id, img.pid, rows, cols)
  local s = apply.state(buf)
  local prefix = 'media:' .. job.key
  s.media_marks = s.media_marks or {}

  local function add_mark(mark)
    mark.media_job = vim.deepcopy(job)
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
  for _, m in ipairs(M.active_marks(s.media or {}, s.media_marks)) do
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
  if not (err:find '[Pp]arse' or err:find '[Ss]yntax' or err:find 'unexpected' or err:find 'line ') then
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
    media_job = vim.deepcopy(job),
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
  for _, m in ipairs(M.active_marks(s.media or {}, s.media_marks)) do
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
  if s.media_tick ~= vim.api.nvim_buf_get_changedtick(buf) then
    s.media_sig = nil
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
  if current.kind == 'image' and current.row == insert_row(buf) then
    s.media_deferred_row = current.row
    s.media_sig = nil
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
    s.jobs[job.key] = nil
    kill_job(inflight)
  end
  if cache.hit(dest) then
    place_if_wanted(buf, job, dest)
    return
  end
  local handle = { dest = dest }
  s.jobs[job.key] = handle
  local proc = start(function(ok, err, file)
    local cur = s.jobs[job.key]
    local wanted = cur == handle
    if wanted then
      s.jobs[job.key] = nil
    end
    if not wanted then
      return
    end
    if not vim.api.nvim_buf_is_valid(buf) or s.media_tick ~= vim.api.nvim_buf_get_changedtick(buf) then
      s.media_sig = nil
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
  if s.jobs[job.key] == handle then
    handle.proc = proc
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
  s.media_tick = vim.api.nvim_buf_get_changedtick(buf)
  -- Track the end of each image's source separately from its preview's
  -- host line. Left gravity keeps typing Enter at the end on the old source;
  -- inserting lines before the image moves the anchor with the image.
  vim.api.nvim_buf_clear_namespace(buf, source_ns, 0, -1)
  sources[buf] = {}
  local live = {} ---@type table<string, table>
  local deferred = {} ---@type table<string, boolean>
  for _, job in ipairs(jobs) do
    live[job.key] = job
    deferred[job.key] = job.kind == 'image' and job.row == s.media_deferred_row
    if job.kind == 'image' then
      local line = vim.api.nvim_buf_get_lines(buf, job.row, job.row + 1, false)[1] or ''
      local col = job.end_row == job.row and job.end_col or #line
      sources[buf][job.key] = vim.api.nvim_buf_set_extmark(buf, source_ns, job.row, math.min(col, #line), {
        right_gravity = false,
        strict = false,
      })
    end
  end
  for key, img in pairs(placements[buf] or {}) do
    if not live[key] then
      protocol.delete(img.id)
      placements[buf][key] = nil
    end
  end
  for key, handle in pairs(s.jobs) do
    if not live[key] or deferred[key] then
      s.jobs[key] = nil
      kill_job(handle)
    end
  end
  if s.media_marks then
    for key, mark in pairs(s.media_marks) do
      if not matches(live[key], mark) then
        s.media_marks[key] = nil
        if s.media_shown then
          s.media_shown[key] = nil
        end
      end
    end
  end
  local cell = protocol.size()
  local parts = {
    tostring(util.content_width(buf, win)),
    tostring(vim.api.nvim_win_get_height(win)),
    tostring(cell.cell_width),
    tostring(cell.cell_height),
    tostring(cfg.media.max_width),
    tostring(cfg.media.max_height),
    vim.o.background,
    tostring(s.media_deferred_row),
  }
  for _, job in ipairs(jobs) do
    parts[#parts + 1] = table.concat({
      job.key,
      job.kind,
      job.content or job.src or '',
      tostring(job.row),
      tostring(job.col),
      tostring(job.end_row),
      tostring(job.end_col),
      tostring(job.standalone),
      tostring(job.display),
      tostring(job.level),
      tostring(job.max_cols),
      tostring(job.max_rows),
    }, '\0')
  end
  local sig = table.concat(parts, '\n')
  if s.media_sig == sig then
    return
  end
  s.media_sig = sig
  local markdown_file = vim.api.nvim_buf_get_name(buf)

  local function bucket_px(n)
    return math.max(32, math.floor(n / 32 + 0.5) * 32)
  end

  for _, job in ipairs(jobs) do
    if job.kind == 'image' then
      if job.row ~= s.media_deferred_row then
        -- Rasterize at intrinsic size (PNG passthrough / SVG at 96dpi).
        -- Placement caps to max_width × max_height without upscaling.
        local dest = image.cache_path(markdown_file, job.src)
        ensure_job(buf, job, dest, function(done)
          return image.prepare(markdown_file, job.src, dest, nil, done)
        end)
      end
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
      -- Even one extra pixel rounds up to two rows in fit_cells, halving
      -- the width when inline math is constrained back to a single row.
      local height = job.display and math.max(72, math.floor(cell_h * 4)) or cell_h
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
end

return M
