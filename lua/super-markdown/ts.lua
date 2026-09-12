local M = {}

local patched = false

--- nvim-treesitter (and Neovim's bundled markdown highlights) set
--- `conceal_lines` on fenced_code_block delimiters. That hides the whole
--- fence except the cursor line, so this plugin cannot show both fences
--- when the cursor is inside the block. We own fence chrome; strip those.
function M.patch_markdown_highlights()
  if patched then
    return
  end
  patched = true
  local ok_files, files = pcall(vim.treesitter.query.get_files, 'markdown', 'highlights')
  if not ok_files or not files or #files == 0 then
    return
  end
  local parts = {}
  for _, path in ipairs(files) do
    if type(path) == 'string' then
      local ok_read, text = pcall(function()
        return table.concat(vim.fn.readfile(path), '\n')
      end)
      if ok_read and text then
        parts[#parts + 1] = text
      end
    end
  end
  if #parts == 0 then
    return
  end
  local src = table.concat(parts, '\n\n')
  src = src:gsub('%(%s*#set!%s+conceal_lines%s+""%s*%)', '')
  src = src:gsub('%(%s*#set!%s+conceal%s+""%s*%)', '')
  if not pcall(vim.treesitter.query.set, 'markdown', 'highlights', src) then
    return
  end
  local active = vim.treesitter.highlighter.active
  if not active then
    return
  end
  for buf in pairs(active) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'markdown' then
      pcall(vim.treesitter.stop, buf)
      pcall(vim.treesitter.start, buf, 'markdown')
    end
  end
end

return M
