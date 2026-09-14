local M = {}

M.ns = vim.api.nvim_create_namespace 'super-markdown'

---@class super_markdown.Mark
---@field key string
---@field row integer
---@field col integer
---@field opts table
---@field hide_on_cursor boolean|nil
---@field block_range? integer[]
---@field mermaid_source? boolean
---@field mermaid_anchor? boolean
---@field code_fence? boolean
---@field fence_text? string
---@field hide_in_block? boolean
---@field show_in_block? boolean
---@field image_source? boolean
---@field heading_source? boolean
---@field media_job? table

---@class super_markdown.BufState
---@field enabled boolean
---@field ids table<string, integer>
---@field by_row table<integer, super_markdown.Mark[]>
---@field plan super_markdown.Mark[]
---@field cursor_row integer
---@field orig_wo table<integer, table<string, any>>
---@field gen integer
---@field changedtick integer|nil
---@field media_tick integer|nil
---@field jobs table<string, { proc?: vim.SystemObj, dest: string }>
---@field media table[]|nil
---@field media_marks table<string, super_markdown.Mark>|nil
---@field media_deferred_row integer|nil
---@field parsed { [1]: integer, [2]: integer }|nil

---@type table<integer, super_markdown.BufState>
M.states = {}

local next_id = 1

---@type table<integer, boolean>
local cursor_busy = {}

---@param buf integer
---@return super_markdown.BufState
function M.state(buf)
  local s = M.states[buf]
  if not s then
    s = {
      enabled = true,
      ids = {},
      by_row = {},
      plan = {},
      cursor_row = -1,
      orig_wo = {},
      gen = 0,
      jobs = {},
      parsed = nil,
    }
    M.states[buf] = s
  end
  return s
end

---@param key string
---@param ids table<string, integer>
---@return integer
local function id_for(key, ids)
  local id = ids[key]
  if not id then
    next_id = next_id + 1
    id = next_id
    ids[key] = id
  end
  return id
end

---@param mark super_markdown.Mark
---@param cursor_row integer
---@return table
local function opts_for(mark, cursor_row)
  local opts = vim.tbl_extend('force', {}, mark.opts)
  opts.strict = false
  opts.invalidate = true
  opts.undo_restore = false
  local in_block = mark.block_range
    and cursor_row >= mark.block_range[1]
    and cursor_row <= mark.block_range[2]
  if mark.mermaid_source then
    opts.conceal_lines = ''
  end
  if mark.mermaid_anchor then
    if in_block then
      opts.virt_text = nil
      opts.conceal = nil
      opts.conceal_lines = nil
    else
      opts.virt_text = nil
      opts.conceal_lines = ''
    end
  end
  if mark.hide_on_cursor and mark.row == cursor_row then
    opts.virt_text = nil
    opts.virt_lines = nil
    opts.conceal = nil
    opts.conceal_lines = nil
  end
  return opts
end

---Neovim draws multiple virt_lines at one position as 1, n, n-1, ..., 2.
---A treesitter (or any other) extmark at that host makes two headings swap.
---@param mark super_markdown.Mark
---@return string|nil
local function virt_group(mark)
  local opts = mark.opts
  if not mark.media_job or not opts or not opts.virt_lines then
    return nil
  end
  return string.format('%d:%s', mark.row, opts.virt_lines_above and 'a' or 'b')
end

---@param marks super_markdown.Mark[]
---@return super_markdown.Mark
local function pack_virt(marks)
  if #marks == 1 then
    return marks[1]
  end
  local virt = {}
  for _, m in ipairs(marks) do
    for _, line in ipairs(m.opts.virt_lines) do
      virt[#virt + 1] = line
    end
  end
  local first = marks[1]
  local opts = vim.tbl_extend('force', {}, first.opts)
  opts.virt_lines = virt
  return {
    key = first.key,
    row = first.row,
    col = first.col,
    opts = opts,
  }
end

---Place heading graphics on a visible neighbor, skipping concealed sources.
---This is cursor-dependent: revealing a heading changes its neighbors' hosts.
---@param buf integer
---@param job table
---@return integer row
---@return boolean above
function M.heading_host(buf, job)
  local s = M.state(buf)
  local function hidden(row)
    if row < 0 then
      return true
    end
    for _, m in ipairs(s.plan or {}) do
      if m.row == row then
        local in_block = m.block_range and s.cursor_row >= m.block_range[1] and s.cursor_row <= m.block_range[2]
        if m.image_source and s.cursor_row ~= row then
          return true
        end
        if (m.mermaid_source or m.mermaid_anchor or m.heading_source) and not in_block then
          return true
        end
      end
    end
    return false
  end
  local host = job.row - 1
  while host >= 0 and hidden(host) do
    host = host - 1
  end
  -- virt_lines below the cursor line make <CR> jump past the graphic.
  if host >= 0 and host ~= s.cursor_row then
    return host, false
  end
  local after = job.end_row or (job.row + 1)
  local line_count = vim.api.nvim_buf_line_count(buf)
  while after < line_count and hidden(after) do
    after = after + 1
  end
  -- A following heading must stay below the source being edited.
  if job.row > s.cursor_row then
    while after < line_count and after == s.cursor_row do
      after = after + 1
      while after < line_count and hidden(after) do
        after = after + 1
      end
    end
  end
  if after < line_count then
    return after, true
  end
  return job.row, true
end

---@param buf integer
---@param plan super_markdown.Mark[]
---@param cursor_row integer
function M.apply(buf, plan, cursor_row)
  local s = M.state(buf)
  s.plan = plan
  s.changedtick = vim.api.nvim_buf_get_changedtick(buf)
  s.cursor_row = cursor_row
  local saved = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      saved[win] = vim.api.nvim_win_get_cursor(win)
    end
  end
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  s.ids = {}
  local visible = {} ---@type super_markdown.Mark[]
  for _, mark in ipairs(plan) do
    if mark.media_job and mark.media_job.kind == 'heading' then
      local row, above = M.heading_host(buf, mark.media_job)
      mark.row = row
      mark.opts.virt_lines_above = above or nil
    end
    local in_block = mark.block_range
      and cursor_row >= mark.block_range[1]
      and cursor_row <= mark.block_range[2]
    if mark.mermaid_source and in_block then
      goto skip
    end
    if mark.hide_in_block and in_block then
      goto skip
    end
    if mark.show_in_block and not in_block then
      goto skip
    end
    if mark.image_source and cursor_row == mark.row then
      goto skip
    end
    if mark.heading_source and in_block then
      goto skip
    end
    visible[#visible + 1] = mark
    ::skip::
  end
  local grouped = {} ---@type table<string, super_markdown.Mark[]>
  for _, mark in ipairs(visible) do
    local gk = virt_group(mark)
    if gk then
      grouped[gk] = grouped[gk] or {}
      grouped[gk][#grouped[gk] + 1] = mark
    end
  end
  local by_row = {} ---@type table<integer, super_markdown.Mark[]>
  local emitted = {} ---@type table<string, boolean>
  for _, mark in ipairs(visible) do
    local gk = virt_group(mark)
    if gk then
      if emitted[gk] then
        goto continue
      end
      emitted[gk] = true
      mark = pack_virt(grouped[gk])
    end
    local row = mark.row
    by_row[row] = by_row[row] or {}
    by_row[row][#by_row[row] + 1] = mark
    local opts = opts_for(mark, cursor_row)
    local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, mark.row, mark.col, opts)
    if ok then
      s.ids[mark.key] = id
    end
    ::continue::
  end
  s.by_row = by_row
  -- conceal_lines can snap the cursor to a later visible line (e.g. a table).
  for win, cur in pairs(saved) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      local now = vim.api.nvim_win_get_cursor(win)
      if now[1] ~= cur[1] then
        pcall(vim.api.nvim_win_set_cursor, win, cur)
      end
    end
  end
end

---Extmarks follow edits automatically; the Lua plan keeps its old coordinates
---until parsing finishes. Never reset those extmarks from a stale plan.
---@param buf integer
---@return boolean
function M.is_current(buf)
  local s = M.states[buf]
  return s ~= nil and (s.changedtick == nil or s.changedtick == vim.api.nvim_buf_get_changedtick(buf))
end

---@param buf integer
---@param row integer
function M.reapply_row(buf, row)
  local s = M.states[buf]
  if not s or not M.is_current(buf) then
    return
  end
  local marks = s.by_row[row]
  if not marks then
    return
  end
  for _, mark in ipairs(marks) do
    local id = s.ids[mark.key]
    if id then
      local opts = opts_for(mark, s.cursor_row)
      opts.id = id
      pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, mark.row, mark.col, opts)
    end
  end
end

---@param plan super_markdown.Mark[]|nil
---@param row integer
---@return boolean
function M.is_media_open(plan, row)
  if not plan then
    return false
  end
  for _, m in ipairs(plan) do
    if m.row == row and (m.key:match '^mmd_open:' or m.key:match '^math_open:' or m.image_source) then
      return true
    end
  end
  return false
end

---Rows hidden with conceal_lines while the cursor is outside the block.
---@param plan super_markdown.Mark[]|nil
---@param row integer
---@return boolean
local function is_concealed_media_row(plan, row)
  if not plan then
    return false
  end
  for _, m in ipairs(plan) do
    if m.row == row and (m.mermaid_source or m.mermaid_anchor or m.image_source or m.heading_source) then
      return true
    end
  end
  return false
end

---Closest heading source row strictly between `after` and `before` when moving up.
---@param plan super_markdown.Mark[]|nil
---@param before_row integer
---@param after_row integer
---@return integer|nil
local function skipped_heading(plan, before_row, after_row)
  if not plan or before_row <= after_row + 1 then
    return nil
  end
  local best
  for _, m in ipairs(plan) do
    if m.heading_source and m.row < before_row and m.row > after_row then
      if not best or m.row > best then
        best = m.row
      end
    end
  end
  return best
end

---@param buf integer
---@param new_row integer
function M.cursor(buf, new_row)
  local s = M.states[buf]
  if not s or s.cursor_row == new_row or not M.is_current(buf) then
    return
  end
  M.apply(buf, s.plan, new_row)
end

---Keep `k` from sticking on a mermaid/math opening fence that sits
---just below virt_lines (Neovim conceal_lines + virt_lines bug).
---@param buf integer
---@param win integer
function M.on_cursor(buf, win)
  if vim.api.nvim_get_current_buf() == buf and vim.fn.mode():sub(1, 1) == 'i' then
    return
  end
  if cursor_busy[buf] or not M.is_current(buf) then
    return
  end
  if win == 0 or not vim.api.nvim_win_is_valid(win) then
    return
  end
  cursor_busy[buf] = true
  local cur = vim.api.nvim_win_get_cursor(win)
  local row, col = cur[1] - 1, cur[2]
  local s = M.state(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local prev = s.cursor_row
  -- Only unstick mermaid/image traps. Do not intercept long jumps (gg / Ctrl-Home).
  if M.is_media_open(s.plan, row) and prev == row + 1 and row > 0 then
    row = row - 1
    pcall(vim.api.nvim_win_set_cursor, win, { row + 1, col })
  end
  M.cursor(buf, row)
  local function pin()
    if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
      return
    end
    if vim.api.nvim_buf_get_changedtick(buf) ~= tick or M.state(buf).cursor_row ~= row then
      return
    end
    local now = vim.api.nvim_win_get_cursor(win)[1] - 1
    if now == row then
      return
    end
    if M.is_media_open(M.state(buf).plan, now) then
      pcall(vim.api.nvim_win_set_cursor, win, { row + 1, col })
    elseif prev > row and now > row then
      -- conceal_lines snapped the cursor back down (e.g. to EOF).
      pcall(vim.api.nvim_win_set_cursor, win, { row + 1, col })
    end
  end
  pin()
  vim.schedule(function()
    pin()
    cursor_busy[buf] = nil
  end)
end

---@param win integer
---@param lnum integer
---@param col integer
local function set_line_cursor(win, lnum, col)
  local buf = vim.api.nvim_win_get_buf(win)
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
  if col > #line then
    col = #line
  end
  pcall(vim.api.nvim_win_set_cursor, win, { lnum, col })
end

---Move one buffer line. Reveal the destination first so conceal_lines
---cannot snap the cursor (and so a long column still lands on a short line).
---@param buf integer
---@param win integer
---@param dir integer
function M.step_visible(buf, win, dir)
  if win == 0 then
    win = vim.api.nvim_get_current_win()
  end
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(win)
  local last = vim.api.nvim_buf_line_count(buf)
  local target = cur[1] + dir
  if target < 1 or target > last then
    return
  end
  if M.is_current(buf) then
    M.cursor(buf, target - 1)
  end
  set_line_cursor(win, target, cur[2])
end

---@param buf integer
---@param win integer
function M.step_up(buf, win)
  local before = vim.api.nvim_win_get_cursor(win)
  local count = vim.v.count1
  vim.cmd('normal! ' .. count .. 'k')
  local function lnum()
    return vim.api.nvim_win_get_cursor(win)[1]
  end
  -- conceal_lines (mermaid / images) can snap the cursor back, so `k` from
  -- the last visible line looks stuck. Walk up until the line actually changes.
  if lnum() >= before[1] and before[1] > 1 then
    local plan = M.state(buf).plan
    local target = before[1] - 1
    local guard = 0
    while target >= 1 and guard < 400 do
      if is_concealed_media_row(plan, target - 1) then
        target = target - 1
      else
        pcall(vim.api.nvim_win_set_cursor, win, { target, before[2] })
        if lnum() < before[1] then
          break
        end
        target = target - 1
      end
      guard = guard + 1
    end
  end
  local after = vim.api.nvim_win_get_cursor(win)
  -- Only land on a heading that `k` just skipped (adjacent), never a long jump.
  local heading = skipped_heading(M.state(buf).plan, before[1] - 1, after[1] - 1)
  if heading and (before[1] - 1) - heading <= 2 then
    pcall(vim.api.nvim_win_set_cursor, win, { heading + 1, before[2] })
  end
  M.on_cursor(buf, win)
end

---@param buf integer
function M.clear(buf)
  local s = M.states[buf]
  if s then
    for _, job in pairs(s.jobs) do
      pcall(function()
        local proc = job.proc or job
        proc:kill 'sigterm'
      end)
    end
    s.jobs = {}
    s.media = nil
    s.media_sig = nil
    s.media_tick = nil
    s.media_deferred_row = nil
    s.media_shown = nil
    s.media_marks = nil
    s.ids = {}
    s.by_row = {}
    s.plan = {}
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  end
end

---@param buf integer
function M.drop(buf)
  M.clear(buf)
  cursor_busy[buf] = nil
  M.states[buf] = nil
end

---Diff two mark plans by key. Pure; used by tests.
---@param old_keys string[]
---@param new_keys string[]
---@return string[] added
---@return string[] removed
function M.diff_keys(old_keys, new_keys)
  local newset = {}
  for _, k in ipairs(new_keys) do
    newset[k] = true
  end
  local oldset = {}
  for _, k in ipairs(old_keys) do
    oldset[k] = true
  end
  local added, removed = {}, {}
  for _, k in ipairs(new_keys) do
    if not oldset[k] then
      added[#added + 1] = k
    end
  end
  for _, k in ipairs(old_keys) do
    if not newset[k] then
      removed[#removed + 1] = k
    end
  end
  table.sort(added)
  table.sort(removed)
  return added, removed
end

return M
