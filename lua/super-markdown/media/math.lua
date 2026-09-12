local cache = require 'super-markdown.media.cache'
local convert = require 'super-markdown.media.convert'
local log = require 'super-markdown.log'
local style = require 'super-markdown.style'
local util = require 'super-markdown.util'

local M = {}

---@return string
local function script()
  return util.plugin_root() .. '/scripts/math-render.mjs'
end

---@return string
local function scripts_dir()
  return util.plugin_root() .. '/scripts'
end

---@return boolean
function M.available()
  return vim.fn.executable 'node' == 1 and util.file_exists(script())
end

---@param tex string
---@param display boolean
---@param dest_png string
---@param height integer
---@param on_done fun(ok: boolean, err?: string)
---@return vim.SystemObj|nil
function M.render(tex, display, dest_png, height, on_done)
  if not M.available() then
    on_done(false, 'math helper missing')
    return
  end
  local mode = display and 'display' or 'inline'
  local color = style.palette().fg
  local svg_path = dest_png:gsub('%.png$', '.svg')
  local proc = vim.system({ 'node', script(), mode, color }, {
    cwd = scripts_dir(),
    stdin = tex,
    text = true,
  }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        local err = vim.trim(obj.stderr or obj.stdout or 'math render failed')
        log.error(err)
        on_done(false, err)
        return
      end
      util.write_file(svg_path, obj.stdout or '')
      convert.svg_to_png(svg_path, dest_png, { height = height }, on_done)
    end)
  end)
  return proc
end

---@param tex string
---@param display boolean
---@param height integer
---@return string
function M.cache_path(tex, display, height)
  local theme = vim.o.background == 'light' and 'light' or 'dark'
  return cache.path('math-h' .. tostring(height), theme, (display and 'd:' or 'i:') .. tex)
end

return M
