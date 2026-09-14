-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/image_edit.lua
local passed = 0
local function eq(actual, expected, message)
  assert(
    vim.deep_equal(actual, expected),
    message .. '\nexpected: ' .. vim.inspect(expected) .. '\ngot: ' .. vim.inspect(actual)
  )
  passed = passed + 1
end

local mode = 'n'
vim.fn.mode = function()
  return mode
end
-- Exercise attachment events synchronously without waiting for debounce timers.
require('super-markdown.util').debounce = function(_, fn)
  return fn
end
local config = require 'super-markdown.config'
config.setup { heading = { simple = true } }
local apply = require 'super-markdown.apply'
local attach = require 'super-markdown.attach'
local protocol = require 'super-markdown.media.protocol'
local image = require 'super-markdown.media.image'
local cache = require 'super-markdown.media.cache'
local cached, started, pending = {}, {}, {}
local transmissions, killed = 0, 0
local immediate = true
protocol.supported = function()
  return true
end
protocol.size = function()
  return { cell_width = 14, cell_height = 32 }
end
protocol.png_size = function()
  return 140, 64
end
protocol.request = function(req)
  if req.a == 'T' then
    transmissions = transmissions + 1
  end
end
cache.hit = function(dest)
  return cached[dest] == true
end
image.cache_path = function(_, src)
  return '/tmp/opencode/image-edit-' .. src
end
image.prepare = function(_, src, dest, _, done)
  started[#started + 1] = src
  local function finish()
    cached[dest] = true
    done(true)
  end
  if immediate then
    finish()
  else
    pending[src] = finish
  end
  return { kill = function()
    killed = killed + 1
  end }
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'markdown'
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '', '![image](old.png)', '', '![other](other.png)', '', 'body' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
attach.attach(buf)
eq(started, { 'old.png', 'other.png' }, 'initial images are prepared')
eq(transmissions, 2, 'initial images are shown')

local function event(name)
  vim.api.nvim_exec_autocmds(name, { group = attach.group, buffer = buf })
end
local function edit(text)
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { text })
  event(mode == 'i' and 'TextChangedI' or 'TextChanged')
end
mode = 'i'
event('ModeChanged')
local cursor = vim.api.nvim_win_get_cursor(0)
edit('![image](new.png)')
eq(#started, 2, 'typing a new image path does not prepare it')
eq(transmissions, 2, 'typing does not replace the preview')
eq(vim.api.nvim_win_get_cursor(0), cursor, 'typing does not move the cursor')
edit('![image](')
eq(vim.tbl_count(apply.state(buf).media_marks), 2, 'incomplete syntax retains the old preview')
edit('![image](final.png)')
vim.api.nvim_buf_set_lines(buf, 3, 4, false, { '![other](changed.png)' })
event('TextChangedI')
eq(#started, 2, 'insert mode does not update images away from the cursor')
vim.api.nvim_win_set_cursor(0, { 6, 0 })
event('CursorMovedI')
eq(vim.tbl_contains(started, 'final.png'), true, 'changing lines in Insert mode prepares the edited image')
eq(vim.tbl_contains(started, 'changed.png'), true, 'changing lines in Insert mode prepares other changed images')
eq(vim.api.nvim_win_get_cursor(0)[1], 6, 'insert mode does not jump the cursor')
mode = 'n'
event('ModeChanged')
eq(started[3] ~= nil and started[4] ~= nil, true, 'leaving Insert mode prepares the latest paths')
eq(vim.tbl_contains(started, 'final.png'), true, 'leaving Insert mode prepares the edited image')
eq(vim.tbl_contains(started, 'changed.png'), true, 'leaving Insert mode prepares other changed images')

mode = 'i'
edit('![image](moved.png)')
eq(not vim.tbl_contains(started, 'moved.png'), true, 'insert mode does not prepare on further typing')
vim.api.nvim_win_set_cursor(0, { 3, 0 })
event('CursorMovedI')
eq(vim.tbl_contains(started, 'moved.png'), true, 'leaving the line in Insert mode prepares the latest path')

vim.api.nvim_win_set_cursor(0, { 2, 0 })
edit('plain text')
eq(vim.tbl_count(apply.state(buf).media_marks), 2, 'deleted image syntax retains its preview while editing')
mode = 'n'
event('ModeChanged')
eq(vim.tbl_count(apply.state(buf).media_marks), 1, 'leaving Insert mode removes a deleted image')
mode = 'i'
edit('![image](brand-new.png)')
eq(not vim.tbl_contains(started, 'brand-new.png'), true, 'a newly typed image is not prepared in insert')
mode = 'n'
event('ModeChanged')
eq(vim.tbl_contains(started, 'brand-new.png'), true, 'a new image renders after leaving Insert mode')

immediate = false
edit('![image](slow.png)')
eq(vim.tbl_contains(started, 'slow.png'), true, 'normal mode starts an asynchronous image job')
mode = 'i'
local before = transmissions
pending['slow.png']()
eq(transmissions, before, 'a job completing during Insert mode cannot replace the preview')
mode = 'n'
event('ModeChanged')
eq(transmissions, before + 1, 'completed image is placed after leaving Insert mode')

edit('![image](cancel.png)')
mode = 'i'
event('ModeChanged')
eq(killed, 0, 'entering Insert mode does not cancel in-flight jobs')
before = transmissions
pending['cancel.png']()
eq(transmissions, before, 'a job completing in Insert mode cannot replace the preview')
edit('![image](latest.png)')
mode = 'n'
event('ModeChanged')
eq(started[#started], 'latest.png', 'leaving Insert mode starts only the latest source')
pending['latest.png']()
eq(transmissions, before + 1, 'the latest source is displayed when ready')

edit('![image](restart.png)')
local stale = pending['restart.png']
mode = 'i'
edit('![image](newer.png)')
mode = 'n'
event('ModeChanged')
eq(started[#started], 'newer.png', 'leaving Insert mode starts the source typed while frozen')
local fresh = pending['newer.png']
before = transmissions
stale()
eq(transmissions, before, 'a job started before Insert cannot place after the source changed')
fresh()
eq(transmissions, before + 1, 'the job for the latest source places when ready')

attach.set_buf(buf, false)
eq(apply.state(buf).media_deferred_row, nil, 'buffer cleanup clears deferral')
print(passed .. ' image editing checks passed')
