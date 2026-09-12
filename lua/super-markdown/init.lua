local attach = require 'super-markdown.attach'
local config = require 'super-markdown.config'
local style = require 'super-markdown.style'

local M = {}

M._setup = false

---@param opts? super_markdown.Config
function M.setup(opts)
  config.setup(opts)
  style.apply()
  if not M._setup then
    attach.setup()
    M._setup = true
  end
end

function M.enable()
  attach.set(true)
end

function M.disable()
  attach.set(false)
end

function M.toggle()
  attach.set(not config.get().enabled)
end

---@param buf? integer
function M.buf_enable(buf)
  attach.set_buf(buf or vim.api.nvim_get_current_buf(), true)
end

---@param buf? integer
function M.buf_disable(buf)
  attach.set_buf(buf or vim.api.nvim_get_current_buf(), false)
end

---@param buf? integer
function M.buf_toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local s = require('super-markdown.apply').state(buf)
  attach.set_buf(buf, not s.enabled)
end

---@param buf integer
function M.attach(buf)
  M.setup()
  attach.attach(buf)
end

return M
