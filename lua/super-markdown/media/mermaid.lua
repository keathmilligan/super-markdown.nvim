local cache = require 'super-markdown.media.cache'
local convert = require 'super-markdown.media.convert'
local util = require 'super-markdown.util'

local M = {}

---@type table<string, string>
local errors = {}

---@param source string
---@return string
local function error_key(source)
  local theme = vim.o.background == 'light' and 'default' or 'dark'
  return cache.key('mermaid-fail', theme, source)
end

---@param err string
---@return string
function M.format_error(err)
  err = err or 'mermaid.render() failed'
  local json = err:match('MERMAID_ERROR%s+(%{.*%})')
  if json then
    local ok, payload = pcall(vim.json.decode, json)
    if ok and type(payload) == 'table' then
      local lines = {}
      if payload.line then
        lines[#lines + 1] = string.format(
          'line %s, column %s',
          tostring(payload.line),
          tostring(payload.column or '?')
        )
      end
      if payload.text and payload.text ~= '' then
        local extra = payload.token and string.format(' (%s)', payload.token) or ''
        lines[#lines + 1] = string.format('unexpected %q%s', payload.text, extra)
      end
      if payload.message and payload.message ~= '' then
        lines[#lines + 1] = payload.message
      end
      if #lines > 0 then
        return table.concat(lines, '\n')
      end
    end
  end
  err = err:gsub('^super%-markdown mermaid%.render%(%) failed:%s*', '')
  err = err:gsub('^super%-markdown mermaid:%s*', '')
  return vim.trim(err)
end

---@param err string
---@return boolean
function M.is_parse_error(err)
  err = err or ''
  return err:find('[Pp]arse') ~= nil
    or err:find('[Ss]yntax') ~= nil
    or err:find('unexpected') ~= nil
    or err:find("got 'GRAPH'") ~= nil
end

---@param source string
---@param err string
function M.remember_error(source, err)
  local formatted = M.format_error(err)
  if not M.is_parse_error(formatted) then
    return
  end
  errors[error_key(source)] = formatted
end

---@param source string
---@return string|nil
function M.cached_error(source)
  return errors[error_key(source)]
end

---@return string
local function script()
  return util.plugin_root() .. '/scripts/mermaid-render.mjs'
end

---@return string
local function scripts_dir()
  return util.plugin_root() .. '/scripts'
end

---@return boolean
function M.available()
  return vim.fn.executable 'node' == 1 and util.file_exists(script())
end

---@param source string
---@param dest_png string
---@param pixel_width integer
---@param on_done fun(ok: boolean, err?: string)
---@return vim.SystemObj|nil
function M.render(source, dest_png, pixel_width, on_done)
  if not M.available() then
    on_done(false, 'node mermaid helper missing')
    return
  end
  local theme = vim.o.background == 'light' and 'default' or 'dark'
  local svg_path = dest_png:gsub('%.png$', '.svg')
  local proc = vim.system({ 'node', script(), theme }, {
    cwd = scripts_dir(),
    stdin = source,
    text = true,
  }, function(obj)
    vim.schedule(function()
      local stderr = vim.trim(obj.stderr or '')
      local svg = obj.stdout or ''
      if obj.code ~= 0 then
        on_done(false, stderr ~= '' and stderr or 'mermaid.render() failed')
        return
      end
      if not svg:find('<svg') or #svg < 64 then
        on_done(false, stderr ~= '' and stderr or 'mermaid.render() produced no SVG')
        return
      end
      util.write_file(svg_path, svg)
      convert.svg_to_png(svg_path, dest_png, pixel_width, function(ok, err)
        if ok then
          on_done(true)
          return
        end
        on_done(false, stderr ~= '' and stderr or err or 'rsvg-convert failed')
      end)
    end)
  end)
  return proc
end

---@param source string
---@param pixel_width? integer
---@return string dest
function M.cache_path(source, pixel_width)
  local theme = vim.o.background == 'light' and 'default' or 'dark'
  local w = math.max(0, math.floor(tonumber(pixel_width) or 0))
  return cache.path('mermaid-w' .. tostring(w), theme, source)
end

return M
