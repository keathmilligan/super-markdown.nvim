local M = {}

---@class super_markdown.Feature
---@field enabled boolean

---@class super_markdown.HeadingConfig
---@field enabled boolean
---@field simple boolean

---@class super_markdown.TableConfig
---@field enabled boolean
---@field max_width number

---@class super_markdown.MediaConfig
---@field enabled boolean
---@field image boolean
---@field mermaid boolean
---@field math boolean
---@field max_width number
---@field max_height integer

---@class super_markdown.Config
---@field enabled boolean
---@field filetypes string[]
---@field max_bytes integer
---@field debounce_ms { insert: integer, normal: integer }
---@field overscan integer
---@field win_options table
---@field heading super_markdown.HeadingConfig
---@field code super_markdown.Feature
---@field quote super_markdown.Feature
---@field alert super_markdown.Feature
---@field list super_markdown.Feature
---@field checkbox super_markdown.Feature
---@field table super_markdown.TableConfig
---@field hr super_markdown.Feature
---@field frontmatter super_markdown.Feature
---@field link super_markdown.Feature
---@field codespan super_markdown.Feature
---@field strike super_markdown.Feature
---@field emphasis super_markdown.Feature
---@field emoji super_markdown.Feature
---@field footnote super_markdown.Feature
---@field media super_markdown.MediaConfig
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
  heading = {
    enabled = true,
    simple = false,
  },
  code = { enabled = true },
  quote = { enabled = true },
  alert = { enabled = true },
  list = { enabled = true },
  checkbox = { enabled = true },
  table = {
    enabled = true,
    ---Max width for tables. 0–1 = fraction of window content width;
    --->1 = columns.
    max_width = 0.75,
  },
  hr = { enabled = true },
  frontmatter = { enabled = true },
  link = { enabled = true },
  codespan = { enabled = true },
  strike = { enabled = true },
  emphasis = { enabled = true },
  emoji = { enabled = true },
  footnote = { enabled = true },
  media = {
    enabled = true,
    image = true,
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
  if not opts then
    return
  end
  M.values = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts)
end

function M.get()
  return M.values
end

---Whether a nested render feature is on (missing section defaults on).
---@param name string
---@return boolean
function M.feature(name)
  local sec = M.get()[name]
  if type(sec) ~= 'table' then
    return true
  end
  return sec.enabled ~= false
end

---Heading render mode. `enabled = false` wins over `simple`.
---@return 'full'|'simple'|'off'
function M.heading_mode()
  local h = M.get().heading
  if type(h) == 'table' then
    if h.enabled == false then
      return 'off'
    end
    if h.simple then
      return 'simple'
    end
  end
  return 'full'
end

---Whether parse should emit jobs for a media kind.
---@param kind 'image'|'mermaid'|'math'
---@return boolean
function M.media_kind(kind)
  local m = M.get().media
  if type(m) ~= 'table' or m.enabled == false then
    return false
  end
  return m[kind] ~= false
end

---Resolve a width against a window content width.
---0–1 is a fraction; >1 is columns.
---@param win_cols integer
---@param width? number
---@return integer
function M.resolve_cols(win_cols, width)
  if width == nil then
    width = 0.5
  end
  win_cols = math.max(1, win_cols)
  if width > 1 then
    return math.max(1, math.min(win_cols, math.floor(width)))
  end
  return math.max(1, math.floor(win_cols * width))
end

---Resolve `media.max_width` against a window content width.
---@param win_cols integer
---@return integer
function M.max_cols(win_cols)
  local media = M.get().media
  local width = media and media.max_width
  return M.resolve_cols(win_cols, width)
end

---Resolve `table.max_width` against a window content width.
---@param win_cols integer
---@return integer
function M.table_cols(win_cols)
  local tbl = M.get().table
  local width = tbl and tbl.max_width
  if width == nil then
    width = 0.75
  end
  return M.resolve_cols(win_cols, width)
end

return M
