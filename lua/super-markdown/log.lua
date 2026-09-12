local M = {}

---@param msg string
function M.error(msg)
  vim.notify('super-markdown: ' .. msg, vim.log.levels.ERROR)
end

---@param msg string
function M.warn(msg)
  vim.notify('super-markdown: ' .. msg, vim.log.levels.WARN)
end

---@param msg string
function M.info(msg)
  vim.notify('super-markdown: ' .. msg, vim.log.levels.INFO)
end

---@param msg string
function M.debug(msg)
  if vim.g.super_markdown_debug then
    vim.notify('super-markdown: ' .. msg, vim.log.levels.DEBUG)
  end
end

return M
