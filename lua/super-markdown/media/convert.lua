local log = require 'super-markdown.log'
local util = require 'super-markdown.util'

local M = {}

---@param cmd string
---@return boolean
function M.has(cmd)
  return vim.fn.executable(cmd) == 1
end

---@param src string
---@param dest string
---@param opts? integer|{ dpi?: integer }|fun(ok: boolean, err?: string)
---@param on_done? fun(ok: boolean, err?: string)
function M.svg_to_png(src, dest, opts, on_done)
  if type(opts) == 'function' then
    on_done = opts
    opts = {}
  elseif type(opts) == 'number' then
    opts = { width = opts }
  elseif opts == nil then
    opts = {}
  end
  on_done = on_done or function() end
  if not M.has 'rsvg-convert' then
    on_done(false, 'rsvg-convert not found')
    return
  end
  local o = opts --[[@as table]]
  local args = { 'rsvg-convert', '-f', 'png', '-o', dest }
  if o.width then
    args[#args + 1] = '-w'
    args[#args + 1] = tostring(math.max(1, o.width))
    args[#args + 1] = '-a'
  elseif o.height then
    args[#args + 1] = '-h'
    args[#args + 1] = tostring(math.max(1, o.height))
    args[#args + 1] = '-a'
  else
    args[#args + 1] = '-d'
    args[#args + 1] = tostring(o.dpi or 96)
  end
  args[#args + 1] = src
  local proc = vim.system(args, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 and util.file_exists(dest) then
        on_done(true)
      else
        on_done(false, (obj.stderr or '') ~= '' and obj.stderr or 'rsvg-convert failed')
      end
    end)
  end)
  return proc
end

---@param src string
---@param dest string
---@param on_done fun(ok: boolean, err?: string)
function M.raster_to_png(src, dest, on_done)
  if not M.has 'magick' then
    on_done(false, 'magick not found')
    return
  end
  local proc = vim.system({
    'magick',
    src .. '[0]',
    '-scale',
    '1920x1080>',
    dest,
  }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 and util.file_exists(dest) then
        on_done(true)
      else
        on_done(false, (obj.stderr or '') ~= '' and obj.stderr or 'magick failed')
      end
    end)
  end)
  return proc
end

---@param msg string
function M.fail(msg)
  log.error(msg)
end

return M
