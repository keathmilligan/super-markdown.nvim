local util = require 'super-markdown.util'

local M = {}

---@return string
function M.dir()
  local dir = vim.fn.stdpath 'cache' .. '/super-markdown'
  vim.fn.mkdir(dir, 'p')
  return dir
end

---@param kind string
---@param theme string
---@param payload string
---@return string
function M.key(kind, theme, payload)
  return vim.fn.sha256(table.concat({ kind, theme, payload }, '\0'))
end

---@param kind string
---@param theme string
---@param payload string
---@param ext? string
---@return string
function M.path(kind, theme, payload, ext)
  return M.dir() .. '/' .. M.key(kind, theme, payload) .. '.' .. (ext or 'png')
end

---@param path string
---@return string
function M.file_payload(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return path
  end
  local mtime = stat.mtime and (stat.mtime.sec or 0) or 0
  return table.concat({ path, mtime, stat.size or 0 }, ':')
end

---@param dest string
---@return boolean
function M.hit(dest)
  return util.file_exists(dest) and (vim.uv.fs_stat(dest).size or 0) > 0
end

return M
