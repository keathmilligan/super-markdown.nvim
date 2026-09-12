local attach = require 'super-markdown.attach'
local config = require 'super-markdown.config'

local M = {}

local function current()
  return vim.api.nvim_get_current_buf()
end

---@param opts { args: string }
function M.run(opts)
  local arg = opts.args or ''
  if arg == '' or arg == 'toggle' then
    attach.set(not config.get().enabled)
  elseif arg == 'enable' then
    attach.set(true)
  elseif arg == 'disable' then
    attach.set(false)
  elseif arg == 'buf_toggle' then
    local buf = current()
    local s = require('super-markdown.apply').state(buf)
    attach.set_buf(buf, not s.enabled)
  elseif arg == 'buf_enable' then
    attach.set_buf(current(), true)
  elseif arg == 'buf_disable' then
    attach.set_buf(current(), false)
  else
    vim.notify('SuperMarkdown: unknown command ' .. arg, vim.log.levels.ERROR)
  end
end

function M.complete()
  return { 'enable', 'disable', 'toggle', 'buf_enable', 'buf_disable', 'buf_toggle' }
end

return M
