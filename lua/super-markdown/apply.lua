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

---@class super_markdown.BufState
---@field enabled boolean
---@field ids table<string, integer>
---@field by_row table<integer, super_markdown.Mark[]>
---@field plan super_markdown.Mark[]
---@field cursor_row integer
---@field orig_wo table<integer, table<string, any>>
---@field gen integer
---@field jobs table<string, { proc?: vim.SystemObj, dest: string }>
---@field media table[]|nil
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

---@param buf integer
---@param plan super_markdown.Mark[]
---@param cursor_row integer
function M.apply(buf, plan, cursor_row)
  local s = M.state(buf)
  s.plan = plan
  s.cursor_row = cursor_row
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  s.ids = {}
  local by_row = {} ---@type table<integer, super_markdown.Mark[]>
  for _, mark in ipairs(plan) do
    local in_block = mark.block_range
      and cursor_row >= mark.block_range[1]
      and cursor_row <= mark.block_range[2]
    if mark.mermaid_source and in_block then
      goto continue
    end
    if mark.hide_in_block and in_block then
      goto continue
    end
    if mark.show_in_block and not in_block then
      goto continue
    end
    if mark.image_source and cursor_row == mark.row then
      goto continue
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
end

---@param buf integer
---@param row integer
function M.reapply_row(buf, row)
  local s = M.states[buf]
  if not s then
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

---@param buf integer
---@param new_row integer
function M.cursor(buf, new_row)
  local s = M.states[buf]
  if not s or s.cursor_row == new_row then
    return
  end
  M.apply(buf, s.plan, new_row)
end

---Keep `k` from sticking on a mermaid/math opening fence that sits
---just below virt_lines (Neovim conceal_lines + virt_lines bug).
---@param buf integer
---@param win integer
function M.on_cursor(buf, win)
  if cursor_busy[buf] then
    return
  end
  if win == 0 or not vim.api.nvim_win_is_valid(win) then
    return
  end
  cursor_busy[buf] = true
  local cur = vim.api.nvim_win_get_cursor(win)
  local row, col = cur[1] - 1, cur[2]
  local s = M.state(buf)
  local prev = s.cursor_row
  if M.is_media_open(s.plan, row) and prev > row and row > 0 then
    row = row - 1
    pcall(vim.api.nvim_win_set_cursor, win, { row + 1, col })
  end
  M.cursor(buf, row)
  local function pin()
    if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
      return
    end
    local now = vim.api.nvim_win_get_cursor(win)[1] - 1
    if now ~= row and M.is_media_open(M.state(buf).plan, now) then
      pcall(vim.api.nvim_win_set_cursor, win, { row + 1, col })
    end
  end
  pin()
  vim.schedule(function()
    pin()
    cursor_busy[buf] = nil
  end)
end

---@param buf integer
---@param win integer
function M.step_up(buf, win)
  local before = vim.api.nvim_win_get_cursor(win)
  local count = vim.v.count1
  vim.cmd('normal! ' .. count .. 'k')
  local after = vim.api.nvim_win_get_cursor(win)
  -- virt_lines (images / mermaid) can swallow `k` when the host line is
  -- off-screen. If the cursor did not move, step to the previous buffer line.
  if after[1] == before[1] and before[1] > 1 then
    pcall(vim.api.nvim_win_set_cursor, win, { before[1] - 1, before[2] })
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
    s.media_shown = nil
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
