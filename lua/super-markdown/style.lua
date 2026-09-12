local M = {}

---gfm-hotview tokens from web/assets/app.css and markdown.css.
M.light = {
  bg = '#ffffff',
  fg = '#1f2328',
  muted = '#59636e',
  border = '#d1d9e0',
  pre_bg = '#f6f8fa',
  accent = '#0969da',
  stripe = '#f8fafc',
  alert = {
    NOTE = '#0969da',
    TIP = '#1a7f37',
    IMPORTANT = '#8250df',
    WARNING = '#9a6700',
    CAUTION = '#cf222e',
  },
}

M.dark = {
  bg = '#0d1117',
  fg = '#c9d1d9',
  muted = '#9198a1',
  border = '#3d444d',
  pre_bg = '#151b22',
  accent = '#4493f8',
  stripe = '#21262d',
  alert = {
    NOTE = '#4493f8',
    TIP = '#3fb950',
    IMPORTANT = '#ab7df8',
    WARNING = '#d29922',
    CAUTION = '#f85149',
  },
}

---@return table
function M.palette()
  return vim.o.background == 'light' and M.light or M.dark
end

---@param color integer
---@param toward integer
---@param t number
---@return string
local function mix(color, toward, t)
  local function ch(n, shift)
    return math.floor(n / shift) % 256
  end
  local r = ch(color, 65536)
  local g = ch(color, 256)
  local b = color % 256
  local tr = ch(toward, 65536)
  local tg = ch(toward, 256)
  local tb = toward % 256
  local nr = math.max(0, math.min(255, math.floor(r + (tr - r) * t + 0.5)))
  local ng = math.max(0, math.min(255, math.floor(g + (tg - g) * t + 0.5)))
  local nb = math.max(0, math.min(255, math.floor(b + (tb - b) * t + 0.5)))
  return string.format('#%02x%02x%02x', nr, ng, nb)
end

---Code-block background relative to the editor `Normal` bg: slightly
---lighter on dark themes, slightly darker on light themes.
---@return string
function M.code_bg()
  local hl = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local bg = hl.bg
  if not bg then
    bg = tonumber(M.palette().bg:gsub('#', ''), 16)
  end
  if vim.o.background == 'light' then
    return mix(bg, 0x000000, 0.06)
  end
  return mix(bg, 0xffffff, 0.08)
end

function M.apply()
  local p = M.palette()
  local function hl(name, spec)
    spec.default = true
    vim.api.nvim_set_hl(0, name, spec)
  end
  local cbg = M.code_bg()

  hl('SuperMarkdownH1', { fg = p.fg, bold = true })
  hl('SuperMarkdownH2', { fg = p.fg, bold = true })
  hl('SuperMarkdownH3', { fg = p.fg, bold = true })
  hl('SuperMarkdownH4', { fg = p.fg, bold = true })
  hl('SuperMarkdownH5', { fg = p.fg, bold = true })
  hl('SuperMarkdownH6', { fg = p.muted, bold = true })
  hl('SuperMarkdownBorder', { fg = p.border })
  hl('SuperMarkdownLink', { fg = p.accent, underline = false })
  hl('SuperMarkdownQuote', { fg = p.muted })
  hl('SuperMarkdownQuoteBar', { fg = p.border })
  vim.api.nvim_set_hl(0, 'SuperMarkdownCode', { fg = p.fg, bg = cbg })
  vim.api.nvim_set_hl(0, 'SuperMarkdownCodeBlock', { bg = cbg })
  vim.api.nvim_set_hl(0, 'SuperMarkdownCodeLabel', { fg = p.muted, bg = cbg, italic = true })
  hl('SuperMarkdownTableBorder', { fg = p.border })
  hl('SuperMarkdownTableHead', { fg = p.fg, bold = true })
  hl('SuperMarkdownTableRowAlt', { bg = p.stripe })
  hl('SuperMarkdownHr', { fg = p.border })
  hl('SuperMarkdownListIcon', { fg = p.fg })
  hl('SuperMarkdownCheckbox', { fg = p.muted })
  hl('SuperMarkdownCheckboxChecked', { fg = p.alert.TIP })
  hl('SuperMarkdownFootnote', { fg = p.accent })
  hl('SuperMarkdownFrontmatter', { fg = p.muted })
  hl('SuperMarkdownStrike', { fg = p.muted, strikethrough = true })
  hl('SuperMarkdownStrong', { fg = p.fg, bold = true })
  hl('SuperMarkdownEm', { fg = p.fg, italic = true })
  hl('SuperMarkdownMuted', { fg = p.muted })
  hl('SuperMarkdownMermaidError', { fg = p.alert.CAUTION })
  hl('SuperMarkdownMermaidErrorTitle', { fg = p.alert.CAUTION, bold = true })

  for name, color in pairs(p.alert) do
    local key = name:sub(1, 1) .. name:sub(2):lower()
    hl('SuperMarkdownAlert' .. key, { fg = color })
    hl('SuperMarkdownAlert' .. key .. 'Title', { fg = color, bold = true })
    hl('SuperMarkdownAlert' .. key .. 'Bar', { fg = color })
  end
end

return M
