local M = {}

---@return string
function M.plugin_root()
  local src = debug.getinfo(1, 'S').source:sub(2)
  local root = src:match('(.+)/lua/super%-markdown/')
  return vim.fs.normalize(root or '.')
end

---@param buf integer
---@return integer
function M.buf_win(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
  return 0
end

---@param buf integer
---@return integer[]
function M.buf_wins(buf)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      wins[#wins + 1] = win
    end
  end
  return wins
end

---@param buf integer
---@return integer
function M.byte_size(buf)
  local lines = vim.api.nvim_buf_line_count(buf)
  if lines == 0 then
    return 0
  end
  local last = vim.api.nvim_buf_get_lines(buf, lines - 1, lines, false)[1] or ''
  local ok, pos = pcall(vim.api.nvim_buf_get_offset, buf, lines)
  if ok then
    return pos + #last
  end
  return lines * 80
end

---@param buf integer
---@param row integer
---@return string
function M.line(buf, row)
  return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
end

---@param buf integer
---@param node TSNode
---@return string
function M.node_text(buf, node)
  return vim.treesitter.get_node_text(node, buf)
end

---0-based exclusive end row of the last visible line plus overscan.
---@param win integer
---@param overscan integer
---@return integer start_row
---@return integer end_row
function M.view_range(win, overscan)
  local ok, info = pcall(vim.fn.getwininfo, win)
  if not ok or not info or not info[1] then
    return 0, 0
  end
  local top = math.max(0, info[1].topline - 1 - overscan)
  local bot = info[1].botline + overscan
  return top, bot
end

---@param buf integer
---@param win integer
---@return integer
function M.content_width(buf, win)
  if win == 0 or not vim.api.nvim_win_is_valid(win) then
    return vim.o.columns
  end
  local width = vim.api.nvim_win_get_width(win)
  local textoff = 0
  local info = vim.fn.getwininfo(win)[1]
  if info then
    textoff = info.textoff or 0
  end
  return math.max(1, width - textoff)
end

---@generic T
---@param ms integer
---@param fn fun()
---@return fun()
function M.debounce(ms, fn)
  local timer ---@type uv.uv_timer_t|nil
  return function()
    if timer then
      timer:stop()
      timer:close()
    end
    timer = vim.uv.new_timer()
    timer:start(ms, 0, function()
      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end
      vim.schedule(fn)
    end)
  end
end

---@param path string
---@return string
function M.read_file(path)
  local fd = assert(io.open(path, 'rb'), 'cannot open ' .. path)
  local data = fd:read('*a') or ''
  fd:close()
  return data
end

---@param path string
---@param data string
function M.write_file(path, data)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  local fd = assert(io.open(path, 'wb'), 'cannot write ' .. path)
  fd:write(data)
  fd:close()
end

---@param path string
---@return boolean
function M.file_exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == 'file'
end

return M
