local convert = require 'super-markdown.media.convert'
local mermaid = require 'super-markdown.media.mermaid'
local math_media = require 'super-markdown.media.math'
local protocol = require 'super-markdown.media.protocol'
local util = require 'super-markdown.util'

local M = {}

function M.check()
  vim.health.start 'super-markdown'

  if vim.fn.has 'nvim-0.11' == 1 then
    vim.health.ok('Neovim ' .. vim.version().major .. '.' .. vim.version().minor)
  else
    vim.health.error 'Neovim >= 0.11 required'
  end

  local function parser(name)
    local files = vim.api.nvim_get_runtime_file('parser/' .. name .. '.so', false)
    if #files > 0 then
      vim.health.ok('Tree-sitter parser: ' .. name)
    else
      vim.health.error('Tree-sitter parser missing: ' .. name)
    end
  end
  parser 'markdown'
  parser 'markdown_inline'

  local graphics = protocol.supported()
  local outer = protocol.outer_terminal()
  if graphics then
    if protocol.in_tmux() then
      vim.health.ok('Kitty graphics protocol (' .. outer .. ' via tmux)')
    else
      vim.health.ok 'Kitty graphics protocol (Ghostty/Kitty)'
    end
  else
    vim.health.warn 'Kitty graphics protocol not detected; images and diagrams will not display'
  end

  if protocol.in_tmux() then
    local ver = protocol.tmux { 'tmux', '-V' }
    if ver then
      vim.health.ok(ver)
    else
      vim.health.warn 'tmux detected but `tmux -V` failed'
    end
    if graphics then
      vim.health.ok 'tmux allow-passthrough all'
    elseif outer then
      vim.health.warn 'tmux passthrough unavailable (need tmux 3.3+; plugin sets allow-passthrough all on the pane)'
    else
      vim.health.warn 'tmux outer terminal is not Kitty or Ghostty'
    end
  end

  if convert.has 'rsvg-convert' then
    vim.health.ok 'rsvg-convert'
  else
    vim.health.error 'rsvg-convert missing (needed for SVG, Mermaid, math)'
  end

  if convert.has 'magick' then
    vim.health.ok 'magick (optional JPEG/WebP/GIF)'
  else
    vim.health.warn 'magick missing; JPEG/WebP/GIF conversion unavailable'
  end

  if vim.fn.executable 'node' == 1 then
    vim.health.ok('node ' .. vim.trim(vim.fn.system { 'node', '-v' }))
  else
    vim.health.error 'node missing (needed for Mermaid and math)'
  end

  local scripts = util.plugin_root() .. '/scripts'
  if util.file_exists(scripts .. '/node_modules/mermaid/package.json') then
    vim.health.ok 'scripts/node_modules/mermaid'
  else
    vim.health.error 'run `npm install` in scripts/ for Mermaid'
  end
  if mermaid.available() then
    vim.health.ok 'mermaid helper'
  else
    vim.health.error 'mermaid helper not available'
  end

  if util.file_exists(scripts .. '/node_modules/mathjax-full/js/mathjax.js') then
    vim.health.ok 'scripts/node_modules/mathjax-full'
  else
    vim.health.warn 'mathjax-full not installed; math will stay as source'
  end
  if math_media.available() then
    vim.health.ok 'math helper'
  else
    vim.health.warn 'math helper not available'
  end
end

return M
