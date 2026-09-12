local M = {}

---@class super_markdown.Config
local defaults = {
  enabled = true,
  filetypes = { 'markdown' },
  max_bytes = 1024 * 1024,
  debounce_ms = {
    insert = 120,
    normal = 40,
  },
  overscan = 40,
  win_options = {
    conceallevel = 2,
    concealcursor = '',
  },
  media = {
    enabled = true,
    mermaid = true,
    math = true,
    ---Max width for mermaid and standalone images. 0–1 = fraction of
    ---window content width; >1 = columns.
    max_width = 0.5,
    ---Max image height in cells.
    max_height = 40,
  },
}

---@type super_markdown.Config
M.values = vim.deepcopy(defaults)

---@param opts? super_markdown.Config
function M.setup(opts)
  M.values = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
end

function M.get()
  return M.values
end

return M
