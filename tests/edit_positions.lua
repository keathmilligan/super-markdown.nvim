-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/edit_positions.lua
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
local refresh
require('super-markdown.util').debounce = function(_, fn)
  return function()
    refresh = fn
  end
end
local apply = require 'super-markdown.apply'
local attach = require 'super-markdown.attach'
local protocol = require 'super-markdown.media.protocol'
local image = require 'super-markdown.media.image'
local heading = require 'super-markdown.media.heading'
local cache = require 'super-markdown.media.cache'
require('super-markdown.config').setup {}
local terminal, pending = {}, {}
local cached = true
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
    terminal[req.i] = true
  elseif req.a == 'd' and req.d == 'I' then
    terminal[req.i] = nil
  end
end
cache.hit = function()
  return cached
end
image.cache_path = function(_, src)
  return '/tmp/opencode/positions-' .. src
end
image.prepare = function(_, _, _, _, done)
  done(true)
  return { kill = function() end }
end
heading.cache_path = function(text)
  return '/tmp/opencode/positions-' .. text .. '.png'
end
heading.render = function(text, _, _, _, done)
  pending[text] = done
  return { kill = function() end }
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'markdown'
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '', '![image](old.png)', '', '# Heading', '', 'body' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
attach.attach(buf)
eq(vim.tbl_count(terminal), 2, 'initial image and heading are displayed')

local function event(name)
  vim.api.nvim_exec_autocmds(name, { group = attach.group, buffer = buf })
end
local function positions()
  return vim.api.nvim_buf_get_extmarks(buf, apply.ns, 0, -1, {})
end
mode = 'i'
vim.api.nvim_buf_set_text(buf, 0, 0, 0, 0, { 'typing', '' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local moved = positions()
event('CursorMovedI')
apply.on_cursor(buf, vim.api.nvim_get_current_win())
eq(positions(), moved, 'cursor movement in insert does not reset extmarks')
eq(vim.api.nvim_win_get_cursor(0)[1], 2, 'insert mode does not jump the cursor')
event('TextChangedI')
eq(positions(), moved, 'typing does not reapply extmarks')
mode = 'n'
event('ModeChanged')
refresh()
eq(#apply.state(buf).media, 2, 'inserting above an image does not retain a duplicate at its old row')
eq(vim.tbl_count(terminal), 2, 'only one terminal placement per source remains after inserting a line')
for _, job in ipairs(apply.state(buf).media) do
  eq(job.row, job.kind == 'image' and 2 or 4, 'media jobs follow their source lines')
end

-- A completed render must not reapply the old heading plan while a text
-- change is waiting for its debounce timer.
mode = 'n'
cached = false
vim.api.nvim_buf_set_lines(buf, 4, 5, false, { '# Pending' })
event('TextChanged')
refresh()
eq(pending.Pending ~= nil, true, 'heading render is in flight')
eq(apply.state(buf).media_marks['heading:4'], nil, 'a reused heading key does not retain the old content')
mode = 'i'
vim.api.nvim_buf_set_text(buf, 1, 0, 1, 0, { 'more', '' })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
moved = positions()
local count = vim.tbl_count(terminal)
pending.Pending(true)
eq(positions(), moved, 'an asynchronous completion cannot restore a stale plan')
eq(vim.tbl_count(terminal), count, 'a stale completion does not transmit a misplaced heading')
cached = true
mode = 'n'
event('ModeChanged')
refresh()
eq(vim.tbl_count(terminal), 2, 'refresh displays only the current image and heading')
local mark = apply.state(buf).media_marks['heading:5']
eq(mark.row, 4, 'heading preview is anchored above its updated source row')
eq(mark.block_range, { 5, 5 }, 'heading cursor visibility uses the updated source range')

-- Splitting the start of an image line moves both its source and its frozen
-- preview, without creating another occurrence while the cursor stays on it.
vim.api.nvim_win_set_cursor(0, { 4, 0 })
mode = 'i'
event('ModeChanged')
vim.api.nvim_buf_set_text(buf, 3, 0, 3, 0, { '', '' })
vim.api.nvim_win_set_cursor(0, { 5, 0 })
event('TextChangedI')
mode = 'n'
event('ModeChanged')
refresh()
eq(#apply.state(buf).media, 2, 'splitting before an edited image keeps a single occurrence')
eq(vim.tbl_count(terminal), 2, 'moving a deferred source does not duplicate its placement')
for _, job in ipairs(apply.state(buf).media) do
  if job.kind == 'image' then
    eq(job.row, 4, 'the deferred image follows the split source line')
    eq(apply.state(buf).media_marks[job.key].row, 3, 'the frozen preview follows its source')
  end
end
-- Enter at the end leaves the source behind and releases deferral.
local text = vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1]
mode = 'i'
vim.api.nvim_buf_set_text(buf, 4, #text, 4, #text, { '', '' })
vim.api.nvim_win_set_cursor(0, { 6, 0 })
event('TextChangedI')
mode = 'n'
event('ModeChanged')
refresh()
eq(apply.state(buf).media_deferred_row, nil, 'Enter after an image releases its source line')
eq(vim.tbl_count(terminal), 2, 'Enter after an image leaves one preview per source')

mode = 'i'
vim.api.nvim_buf_set_lines(buf, 1, 3, false, {})
vim.api.nvim_win_set_cursor(0, { 2, 0 })
moved = positions()
event('CursorMovedI')
eq(positions(), moved, 'deleting preceding lines does not restore old graphics coordinates')
event('TextChangedI')
mode = 'n'
event('ModeChanged')
refresh()
eq(vim.tbl_count(terminal), 2, 'deleting preceding lines leaves one preview per source')
eq(apply.state(buf).media_marks['heading:5'].row, 4, 'heading moves up after preceding lines are deleted')

attach.set_buf(buf, false)
mode = 'n'
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '', '![inline](old.png) trailing text', '', '# After', '', 'body' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
attach.set_buf(buf, true)
mode = 'i'
vim.api.nvim_buf_set_text(buf, 1, 22, 1, 22, { '', '' })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
event('TextChangedI')
mode = 'n'
event('ModeChanged')
refresh()
eq(#apply.state(buf).media, 2, 'splitting text after an inline image does not duplicate the image')
for _, job in ipairs(apply.state(buf).media) do
  if job.kind == 'image' then
    eq(job.row, 1, 'an inline image stays with its source when trailing text moves down')
  end
end
attach.set_buf(buf, false)
print(passed .. ' editing position checks passed')
