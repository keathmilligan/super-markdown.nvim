local cache = require 'super-markdown.media.cache'
local convert = require 'super-markdown.media.convert'
local log = require 'super-markdown.log'
local pathmod = require 'super-markdown.media.path'
local util = require 'super-markdown.util'

local M = {}

local RASTER = { jpg = true, jpeg = true, gif = true, webp = true, bmp = true, tiff = true }

---@param src string
---@return string
function M.ext(src)
  return (src:match('%.([%w]+)$') or ''):lower()
end

---@param markdown_file string
---@param src string
---@param dest_png string
---@param pixel_width integer
---@param on_done fun(ok: boolean, err?: string, file?: string)
---@return vim.SystemObj|nil
function M.prepare(markdown_file, src, dest_png, pixel_width, on_done)
  if src:match('^https?://') then
    on_done(false, 'remote images are not fetched')
    return
  end
  local abs = pathmod.resolve(markdown_file, src)
  if not util.file_exists(abs) then
    log.error('image not found: ' .. abs)
    on_done(false, 'image not found: ' .. abs)
    return
  end
  local ext = M.ext(abs)
  if ext == 'png' then
    on_done(true, nil, abs)
    return
  end
  if ext == 'svg' then
    return convert.svg_to_png(abs, dest_png, pixel_width, function(ok, err)
      on_done(ok, err, dest_png)
    end)
  end
  if RASTER[ext] then
    return convert.raster_to_png(abs, dest_png, function(ok, err)
      on_done(ok, err, dest_png)
    end)
  end
  log.error('unsupported image type: ' .. ext)
  on_done(false, 'unsupported image type: ' .. ext)
end

---@param markdown_file string
---@param src string
---@param pixel_width? integer
---@return string
function M.cache_path(markdown_file, src, pixel_width)
  local abs = pathmod.resolve(markdown_file, src)
  local theme = vim.o.background == 'light' and 'light' or 'dark'
  local w = math.max(0, math.floor(tonumber(pixel_width) or 0))
  local prefix = w > 0 and ('image-w' .. tostring(w)) or 'image-dpi96'
  return cache.path(prefix, theme, cache.file_payload(abs))
end

return M
