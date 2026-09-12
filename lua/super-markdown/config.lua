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
    ---Max width for mermaid, standalone images, and tables. 0–1 =
    ---fraction of window content width; >1 = columns.
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

---Resolve `media.max_width` against a window content width.
---@param win_cols integer
---@return integer
function M.max_cols(win_cols)
  local width = M.get().media.max_width
  if width == nil then
    width = 0.5
  end
  win_cols = math.max(1, win_cols)
  if width > 1 then
    return math.max(1, math.min(win_cols, math.floor(width)))
  end
  return math.max(1, math.floor(win_cols * width))
end

return M
