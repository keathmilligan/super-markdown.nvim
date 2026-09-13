-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/graphics.lua
local passed = 0
local function eq(actual, expected, message)
  assert(
    vim.deep_equal(actual, expected),
    message .. '\nexpected: ' .. vim.inspect(expected) .. '\ngot: ' .. vim.inspect(actual)
  )
  passed = passed + 1
end

local ffi = require 'ffi'
-- Another graphics plugin may already have declared this public name.
ffi.cdef [[typedef struct {
  unsigned short row, col, xpixel, ypixel;
} winsize;]]
local available = false
local pixels = { row = 84, col = 214, xpixel = 2996, ypixel = 2710 }
local fs_open = vim.uv.fs_open
vim.uv.fs_open = function()
  return nil
end
package.loaded.ffi = setmetatable({
  C = {
    ioctl = function(_, _, sz)
      if not available then
        return -1
      end
      for k, v in pairs(pixels) do
        sz[k] = v
      end
      return 0
    end,
  },
}, { __index = ffi })

local protocol = require 'super-markdown.media.protocol'
eq(protocol.size().cell_height, 18, 'unavailable terminal uses a temporary fallback')
available = true
eq(protocol.size().cell_height, 32, 'failed query is retried; partial terminal row is excluded')
eq(protocol.size().cell_width, 14, 'existing winsize typedef does not block measurement')
for i = 1, 3 do
  pixels.xpixel = 214 * (14 + i) + 7
  pixels.ypixel = 84 * (32 + i) + 22
  vim.api.nvim_exec_autocmds('VimResized', { group = 'super-markdown.term' })
  local size = protocol.size()
  eq(
    { size.cell_width, size.cell_height },
    { 14 + i, 32 + i },
    'resize remeasures without an FFI redeclaration failure'
  )
end
package.loaded.ffi = ffi
vim.uv.fs_open = fs_open

local heading = require 'super-markdown.media.heading'
local cell = { cell_width = 14, cell_height = 32 }
protocol.size = function()
  return cell
end
for level = 1, 6 do
  local svg = heading.svg('Heading', level, { max_cols = 214, cell_width = 14, cell_height = 32 })
  local w, h = tonumber(svg:match 'width="(%d+)"'), tonumber(svg:match 'height="(%d+)"')
  eq(w, 213 * 14, 'heading canvas covers exactly the placement columns')
  eq(h % 32, 0, 'heading canvas covers whole pixel rows without horizontal letterboxing')
end

local media = require 'super-markdown.media'
local apply = require 'super-markdown.apply'
local cache = require 'super-markdown.media.cache'
local requests, terminal = {}, {}
protocol.request = function(req)
  requests[#requests + 1] = vim.deepcopy(req)
  if req.a == 'T' then
    -- Kitty retransmission replaces all placements of the image.
    terminal[req.i] = { cols = req.c, rows = req.r }
  elseif req.a == 'd' and req.d == 'I' then
    terminal[req.i] = nil
  end
end
protocol.supported = function()
  return true
end
cache.hit = function()
  return true
end
local paths = {}
heading.cache_path = function(text, level, cols, size)
  local path = '/heading-' .. text .. '-' .. level .. '-' .. cols .. '-' .. size.cell_height .. '.png'
  paths[path] = { (cols - 1) * size.cell_width, level * size.cell_height }
  return path
end
protocol.png_size = function(path)
  return unpack(paths[path])
end

local function buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '', '# Same', '', '# Same', '', 'body' })
  apply.state(buf).enabled = true
  apply.state(buf).cursor_row = 5
  vim.api.nvim_set_current_buf(buf)
  return buf
end
local function job(row)
  return {
    key = 'heading:' .. row,
    kind = 'heading',
    row = row,
    end_row = row + 1,
    content = 'Same',
    level = 2,
    max_cols = 40,
  }
end
local win = vim.api.nvim_get_current_win()
local a = buffer()
local jobs = { job(1), job(3) }
media.update(a, win, jobs)
eq(#requests, 2, 'identical headings each get a terminal image')
local first, second = requests[1].i, requests[2].i
eq(first ~= second, true, 'identical files do not share ambiguous virtual placements')
eq(first > 0 and first <= 0xFFFFFF, true, 'image IDs fit the placeholder foreground color')
media.update(a, win, jobs)
eq(#requests, 2, 'unchanged rendering does not retransmit images')

local b = buffer()
media.update(b, win, { job(1) })
local other = requests[#requests].i
eq(other ~= first and other ~= second, true, 'same job key in another buffer owns a distinct image')
vim.api.nvim_set_current_buf(a)
jobs[1].max_cols = 30
media.update(a, win, jobs)
eq(terminal[first], nil, 'resizing releases the previous virtual placement and image data')
eq(terminal[second] ~= nil and terminal[other] ~= nil, true, 'resizing one heading preserves other occurrences')
eq(#requests, 5, 'resizing only replaces the changed occurrence')
local resized = requests[#requests].i
eq(terminal[resized].cols, 29, 'replacement uses the new column budget')

jobs[1].level = 3
media.update(a, win, jobs)
eq(terminal[resized], nil, 'changing only the heading level invalidates the media signature')
eq(requests[#requests].r, 3, 'heading level change updates image geometry')
local before = #requests
cell = { cell_width = 14, cell_height = 34 }
media.update(a, win, jobs)
eq(#requests, before + 4, 'cell pixel changes rerender headings even with unchanged window columns')
media.update(a, win, {})
eq(vim.tbl_count(terminal), 1, 'removing headings releases their terminal images')
media.clear(b)
apply.clear(b)
eq(vim.tbl_count(terminal), 0, 'clearing a buffer releases its images')

media.update(a, win, { job(1) })
vim.api.nvim_exec_autocmds('VimLeavePre', { group = 'super-markdown.graphics' })
eq(vim.tbl_count(terminal), 0, 'Neovim exit frees all images owned by the plugin')
eq(requests[#requests].d, 'I', 'cleanup deletes virtual placements and frees pixel data')
print(passed .. ' graphics checks passed')
