local apply = require 'super-markdown.apply'
local config = require 'super-markdown.config'
local media = require 'super-markdown.media'
local parse = require 'super-markdown.parse'
local style = require 'super-markdown.style'
local ts = require 'super-markdown.ts'
local util = require 'super-markdown.util'

local M = {}

M.group = vim.api.nvim_create_augroup('SuperMarkdown', { clear = true })

---@type table<integer, boolean>
local attached = {}

---@type table<integer, fun()>
local refreshes = {}

---@param buf integer
---@param win integer
---@param rendered boolean
local function set_win_opts(buf, win, rendered)
  if win == 0 or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local s = apply.state(buf)
  s.orig_wo[win] = s.orig_wo[win] or {}
  local wo = config.get().win_options
  for name, value in pairs(wo) do
    if s.orig_wo[win][name] == nil then
      s.orig_wo[win][name] = vim.wo[win][name]
    end
    vim.wo[win][name] = rendered and value or s.orig_wo[win][name]
  end
end

---@param buf integer
local function restore_wins(buf)
  local s = apply.states[buf]
  if not s then
    return
  end
  for win, opts in pairs(s.orig_wo) do
    if vim.api.nvim_win_is_valid(win) then
      for name, value in pairs(opts) do
        pcall(function()
          vim.wo[win][name] = value
        end)
      end
    end
  end
end

---@param buf integer
---@return boolean
local function should_render(buf)
  local cfg = config.get()
  if not cfg.enabled then
    return false
  end
  local s = apply.state(buf)
  if not s.enabled then
    return false
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  if util.byte_size(buf) > cfg.max_bytes then
    return false
  end
  local win = util.buf_win(buf)
  if win == 0 then
    return false
  end
  if vim.wo[win].diff then
    return false
  end
  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  if view.leftcol and view.leftcol > 0 then
    return false
  end
  return true
end

---@param buf integer
local function render(buf)
  if not should_render(buf) then
    media.clear(buf)
    apply.clear(buf)
    local win = util.buf_win(buf)
    set_win_opts(buf, win, false)
    return
  end
  local win = util.buf_win(buf)
  set_win_opts(buf, win, true)
  local cfg = config.get()
  local plan = parse.parse(buf, win, cfg.overscan)
  if not plan then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local s = apply.state(buf)
  local marks = {}
  for _, m in ipairs(plan.marks) do
    marks[#marks + 1] = m
  end
  for _, m in ipairs(media.active_marks(plan.media, s.media_marks)) do
    marks[#marks + 1] = m
  end
  apply.apply(buf, marks, cursor[1] - 1)
  s.parsed = plan.range
  media.update(buf, win, plan.media)
end

---@param buf integer
local function make_debounced(buf)
  local cfg = config.get()
  local insert_fn = util.debounce(cfg.debounce_ms.insert, function()
    if vim.api.nvim_buf_is_valid(buf) then
      render(buf)
    end
  end)
  local normal_fn = util.debounce(cfg.debounce_ms.normal, function()
    if vim.api.nvim_buf_is_valid(buf) then
      render(buf)
    end
  end)
  return function()
    if vim.fn.mode():find 'i' then
      insert_fn()
    else
      normal_fn()
    end
  end
end

---@param buf integer
function M.attach(buf)
  if attached[buf] then
    if apply.state(buf).enabled and config.get().enabled then
      render(buf)
    end
    return
  end
  local ft = vim.bo[buf].filetype
  local ok = false
  for _, want in ipairs(config.get().filetypes) do
    if ft == want then
      ok = true
      break
    end
  end
  if not ok then
    return
  end
  attached[buf] = true
  apply.state(buf).enabled = true
  local refresh = make_debounced(buf)
  refreshes[buf] = refresh

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'WinScrolled', 'BufWinEnter' }, {
    group = M.group,
    buffer = buf,
    callback = refresh,
  })
  vim.api.nvim_create_autocmd('ModeChanged', {
    group = M.group,
    buffer = buf,
    callback = refresh,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = M.group,
    buffer = buf,
    callback = function()
      local win = util.buf_win(buf)
      if win == 0 then
        return
      end
      apply.on_cursor(buf, win)
    end,
  })
  vim.keymap.set({ 'n', 'v' }, 'k', function()
    apply.step_up(buf, vim.api.nvim_get_current_win())
  end, { buffer = buf, silent = true, desc = 'super-markdown up' })
  vim.keymap.set({ 'n', 'v' }, '<Up>', function()
    apply.step_up(buf, vim.api.nvim_get_current_win())
  end, { buffer = buf, silent = true, desc = 'super-markdown up' })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = M.group,
    buffer = buf,
    callback = function()
      attached[buf] = nil
      refreshes[buf] = nil
      restore_wins(buf)
      media.clear(buf)
      apply.drop(buf)
    end,
  })
  render(buf)
end

---@param buf integer
---@param enable boolean
function M.set_buf(buf, enable)
  apply.state(buf).enabled = enable
  if enable then
    M.attach(buf)
    render(buf)
  else
    restore_wins(buf)
    media.clear(buf)
    apply.clear(buf)
  end
end

---@param enable boolean
function M.set(enable)
  config.get().enabled = enable
  for buf in pairs(attached) do
    if vim.api.nvim_buf_is_valid(buf) then
      if enable then
        render(buf)
      else
        restore_wins(buf)
        media.clear(buf)
        apply.clear(buf)
      end
    end
  end
end

function M.setup()
  style.apply()
  ts.patch_markdown_highlights()
  vim.api.nvim_create_autocmd('FileType', {
    group = M.group,
    pattern = config.get().filetypes,
    callback = function(ev)
      M.attach(ev.buf)
    end,
  })
  local function restyle()
    style.apply()
    for buf in pairs(attached) do
      if vim.api.nvim_buf_is_valid(buf) then
        render(buf)
      end
    end
  end
  vim.api.nvim_create_autocmd('OptionSet', {
    group = M.group,
    pattern = 'background',
    callback = restyle,
  })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = M.group,
    callback = restyle,
  })
  vim.api.nvim_create_autocmd({ 'WinResized', 'VimResized' }, {
    group = M.group,
    callback = function()
      for buf, refresh in pairs(refreshes) do
        if vim.api.nvim_buf_is_valid(buf) and apply.state(buf).enabled then
          refresh()
        end
      end
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.attach(buf)
    end
  end
end

function M.refresh(buf)
  render(buf)
end

return M
