-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/heading_order.lua
local passed = 0
local function eq(actual, expected, message)
  assert(
    vim.deep_equal(actual, expected),
    message .. '\nexpected: ' .. vim.inspect(expected) .. '\ngot: ' .. vim.inspect(actual)
  )
  passed = passed + 1
end

local apply = require 'super-markdown.apply'
local attach = require 'super-markdown.attach'
local heading = require 'super-markdown.media.heading'
local protocol = require 'super-markdown.media.protocol'
local cache = require 'super-markdown.media.cache'
require('super-markdown.config').setup {}
local cached, pending, labels = false, {}, {}
local transmissions = 0
cache.hit = function()
  return cached
end
heading.available = function()
  return true
end
heading.cache_path = function(text)
  return '/tmp/opencode/order-' .. text .. '.png'
end
heading.render = function(text, _, _, _, done)
  pending[text] = done
  return { kill = function() end }
end
protocol.supported = function()
  return true
end
protocol.size = function()
  return { cell_width = 14, cell_height = 32 }
end
protocol.png_size = function()
  return 280, 32
end
protocol.show = function(id, _, path)
  transmissions = transmissions + 1
  labels[id] = 'PREVIEW ' .. path:match('order%-(.-)%.png$')
end
protocol.delete = function() end
-- Use readable placeholders so assertions exercise Neovim's actual screen
-- stacking, rather than inferring visual order from extmark coordinates.
protocol.grid = function(id)
  return { labels[id] }, 'Normal'
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'markdown'
-- Treesitter (and any other plugin) puts extmarks on the host line.
-- Neovim then draws two virt_lines as n, 1 instead of 1, 2.
local deco = vim.api.nvim_create_namespace 'super-markdown.heading-order-deco'
local function decorate()
  vim.api.nvim_buf_clear_namespace(buf, deco, 0, -1)
  for row = 0, vim.api.nvim_buf_line_count(buf) - 1 do
    vim.api.nvim_buf_set_extmark(buf, deco, row, 0, {
      hl_group = 'Comment',
      end_col = 1,
      strict = false,
    })
  end
end
local function screen()
  vim.cmd 'redraw!'
  local rows = {}
  for row = 1, vim.o.lines - 2 do
    local text = {}
    for col = 1, vim.o.columns do
      text[#text + 1] = vim.fn.screenstring(row, col)
    end
    rows[#rows + 1] = table.concat(text)
  end
  return table.concat(rows, '\n')
end
local function ordered(first, second, message)
  local text = screen()
  local a, b = text:find(first, 1, true), text:find(second, 1, true)
  assert(a and b and a < b, message .. '\n' .. text)
  passed = passed + 1
end
local function cursor(row)
  vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
  apply.cursor(buf, row)
end
local function scenario(lines, math_row, install_row, completion)
  attach.set_buf(buf, false)
  cached = false
  pending = {}
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  decorate()
  vim.api.nvim_win_set_cursor(0, { #lines, 0 })
  attach.set_buf(buf, true)
  for _, title in ipairs(completion) do
    pending[title](true)
  end
  local before = transmissions
  ordered('PREVIEW Math', 'PREVIEW Install', 'headings follow source order regardless of completion order')
  cursor(math_row)
  ordered('### Math', 'PREVIEW Install', 'the next preview stays below the heading being edited')
  local install_mark = apply.state(buf).media_marks['heading:' .. install_row]
  eq(install_mark ~= nil and install_mark.row ~= math_row, true, 'next heading graphic is not hosted on the edited line')
  cursor(install_row)
  ordered('PREVIEW Math', '## Install', 'the preceding preview stays above the heading being edited')
  cursor(#lines - 1)
  ordered('PREVIEW Math', 'PREVIEW Install', 'leaving a heading restores source order')
  cached = true
  attach.refresh(buf)
  ordered('PREVIEW Math', 'PREVIEW Install', 'a cached refresh preserves heading order')
  eq(transmissions, before, 'cursor-dependent layout does not retransmit heading images')
end

for _, completion in ipairs { { 'Math', 'Install' }, { 'Install', 'Math' } } do
  scenario({ '', '### Math', '## Install', '', 'body' }, 1, 2, completion)
  scenario({ '### Math', '## Install', '', 'body' }, 0, 1, completion)
  scenario({ '', '### Math', '', '## Install', '', 'body' }, 1, 3, completion)
  -- Match the reported line numbers, including keys spanning two digits.
  local lines = {}
  for _ = 1, 48 do
    lines[#lines + 1] = ''
  end
  vim.list_extend(lines, { '### Math', '## Install', '', 'lazy.nvim:', '' })
  scenario(lines, 48, 49, completion)
end
attach.set_buf(buf, false)
cached = false
pending = {}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '', '### Math', '## Install', '', 'body' })
decorate()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
attach.set_buf(buf, true)
pending.Math(true)
pending.Install(true)
cursor(1)
local math_line = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
vim.api.nvim_win_set_cursor(0, { 2, #math_line })
vim.api.nvim_buf_set_text(buf, 1, #math_line, 1, #math_line, { '', '' })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.cmd 'redraw!'
eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[4], '## Install', 'a newline after Math keeps Install on the next source line')
eq(vim.api.nvim_win_get_cursor(0)[1], 3, 'cursor stays on the new line instead of jumping past Install')
attach.set_buf(buf, false)
print(passed .. ' heading screen-order checks passed')
