local M = {}

---@param file string markdown file path
---@param src string
---@return string
function M.resolve(file, src)
  if src:match('^https?://') or src:match('^data:') then
    return src
  end
  src = src:gsub('^file://', '')
  if src:sub(1, 1) == '/' then
    return vim.fn.fnamemodify(src, ':p')
  end
  local dir = vim.fn.fnamemodify(file, ':p:h')
  return vim.fn.fnamemodify(dir .. '/' .. src, ':p')
end

return M
