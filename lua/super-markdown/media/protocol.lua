local M = {}

-- Kitty unicode placeholder (U+10EEEE) plus combining marks for row/col.
-- See https://sw.kovidgoyal.net/kitty/graphics-protocol/#unicode-placeholders
local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)
-- stylua: ignore
local diacritics = vim.split(
  '0305,030D,030E,0310,0312,033D,033E,033F,0346,034A,034B,034C,0350,0351,0352,0357,035B,0363,0364,0365,0366,0367,0368,0369,036A,036B,036C,036D,036E,036F,0483,0484,0485,0486,0487,0592,0593,0594,0595,0597,0598,0599,059C,059D,059E,059F,05A0,05A1,05A8,05A9,05AB,05AC,05AF,05C4,0610,0611,0612,0613,0614,0615,0616,0617,0657,0658,0659,065A,065B,065D,065E,06D6,06D7,06D8,06D9,06DA,06DB,06DC,06DF,06E0,06E1,06E2,06E4,06E7,06E8,06EB,06EC,0730,0732,0733,0735,0736,073A,073D,073F,0740,0741,0743,0745,0747,0749,074A,07EB,07EC,07ED,07EE,07EF,07F0,07F1,07F3,0816,0817,0818,0819,081B,081C,081D,081E,081F,0820,0821,0822,0823,0825,0826,0827,0829,082A,082B,082C,082D,0951,0953,0954,0F82,0F83,0F86,0F87,135D,135E,135F,17DD,193A,1A17,1A75,1A76,1A77,1A78,1A79,1A7A,1A7B,1A7C,1B6B,1B6D,1B6E,1B6F,1B70,1B71,1B72,1B73,1CD0,1CD1,1CD2,1CDA,1CDB,1CE0,1DC0,1DC1,1DC3,1DC4,1DC5,1DC6,1DC7,1DC8,1DC9,1DCB,1DCC,1DD1,1DD2,1DD3,1DD4,1DD5,1DD6,1DD7,1DD8,1DD9,1DDA,1DDB,1DDC,1DDD,1DDE,1DDF,1DE0,1DE1,1DE2,1DE3,1DE4,1DE5,1DE6,1DFE,20D0,20D1,20D4,20D5,20D6,20D7,20DB,20DC,20E1,20E7,20E9,20F0,2CEF,2CF0,2CF1,2DE0,2DE1,2DE2,2DE3,2DE4,2DE5,2DE6,2DE7,2DE8,2DE9,2DEA,2DEB,2DEC,2DED,2DEE,2DEF,2DF0,2DF1,2DF2,2DF3,2DF4,2DF5,2DF6,2DF7,2DF8,2DF9,2DFA,2DFB,2DFC,2DFD,2DFE,2DFF,A66F,A67C,A67D,A6F0,A6F1,A8E0,A8E1,A8E2,A8E3,A8E4,A8E5,A8E6,A8E7,A8E8,A8E9,A8EA,A8EB,A8EC,A8ED,A8EE,A8EF,A8F0,A8F1,AAB0,AAB2,AAB3,AAB7,AAB8,AABE,AABF,AAC1,FE20,FE21,FE22,FE23,FE24,FE25,FE26,10A0F,10A38,1D185,1D186,1D187,1D188,1D189,1D1AA,1D1AB,1D1AC,1D1AD,1D242,1D243,1D244',
  ','
)

local positions = {}
setmetatable(positions, {
  __index = function(_, k)
    local n = tonumber(diacritics[k], 16)
    positions[k] = n and vim.fn.nr2char(n) or ''
    return positions[k]
  end,
})

local cell ---@type { width: number, height: number, cols: number, rows: number }|nil

---@return boolean
function M.supported()
  local program = (vim.env.TERM_PROGRAM or ''):lower()
  local term = (vim.env.TERM or ''):lower()
  if vim.env.GHOSTTY_RESOURCES_DIR or program:find('ghostty', 1, true) or term:find('ghostty', 1, true) then
    return true
  end
  if vim.env.KITTY_WINDOW_ID or program:find('kitty', 1, true) or term:find('kitty', 1, true) then
    return true
  end
  return false
end

---@return { width: number, height: number, cols: number, rows: number, cell_width: number, cell_height: number }
function M.size()
  if cell then
    return cell
  end
  local dw, dh = 9, 18
  cell = {
    width = vim.o.columns * dw,
    height = vim.o.lines * dh,
    cols = vim.o.columns,
    rows = vim.o.lines,
    cell_width = dw,
    cell_height = dh,
  }
  pcall(function()
    local ffi = require 'ffi'
    ffi.cdef [[
      typedef struct {
        unsigned short row;
        unsigned short col;
        unsigned short xpixel;
        unsigned short ypixel;
      } winsize;
      int ioctl(int, int, ...);
    ]]
    local TIOCGWINSZ = vim.fn.has 'linux' == 1 and 0x5413 or 0x40087468
    local sz = ffi.new 'winsize'
    if ffi.C.ioctl(1, TIOCGWINSZ, sz) == 0 and sz.col > 0 and sz.row > 0 and sz.xpixel > 0 then
      cell = {
        width = sz.xpixel,
        height = sz.ypixel,
        cols = sz.col,
        rows = sz.row,
        cell_width = sz.xpixel / sz.col,
        cell_height = sz.ypixel / sz.row,
      }
    end
  end)
  return cell
end

vim.api.nvim_create_autocmd('VimResized', {
  group = vim.api.nvim_create_augroup('super-markdown.term', { clear = true }),
  callback = function()
    cell = nil
  end,
})

---@param opts table
function M.request(opts)
  local parts = {}
  for k, v in pairs(opts) do
    if k ~= 'data' then
      parts[#parts + 1] = string.format('%s=%s', k, v)
    end
  end
  local msg = '\27_G' .. table.concat(parts, ',')
  if opts.data then
    msg = msg .. ';' .. opts.data
  end
  msg = msg .. '\27\\'
  if vim.api.nvim_ui_send then
    vim.api.nvim_ui_send(msg)
  else
    io.stdout:write(msg)
    io.stdout:flush()
  end
end

---@param path string
---@return string
local function b64_file(path)
  path = vim.fn.fnamemodify(path, ':p')
  if vim.base64 and vim.base64.encode then
    return vim.base64.encode(path)
  end
  return vim.trim(vim.fn.system({ 'base64', '-w0' }, path))
end

local next_img = 100
local next_place = 1

---@return integer
function M.next_image_id()
  next_img = next_img + 1
  return next_img
end

---@return integer
function M.next_placement_id()
  next_place = next_place + 1
  return next_place
end

---@param image_id integer
---@param path string
function M.transmit(image_id, path)
  M.request {
    a = 't',
    t = 'f',
    i = image_id,
    f = 100,
    q = 2,
    data = b64_file(path),
  }
end

---@param image_id integer
---@param placement_id integer
---@param cols integer
---@param rows integer
local placed = {} ---@type table<integer, { i: integer, c: integer, r: integer }>

function M.place(image_id, placement_id, cols, rows)
  M.request {
    a = 'p',
    U = 1,
    i = image_id,
    p = placement_id,
    C = 1,
    q = 2,
    c = cols,
    r = rows,
  }
  placed[placement_id] = { i = image_id, c = cols, r = rows }
end

---Transmit a PNG and place it in one graphics command so the terminal
---cannot observe a place before the image exists.
---@param image_id integer
---@param placement_id integer
---@param path string
---@param cols integer
---@param rows integer
function M.show(image_id, placement_id, path, cols, rows)
  M.request {
    a = 'T',
    t = 'f',
    U = 1,
    C = 1,
    i = image_id,
    p = placement_id,
    f = 100,
    q = 2,
    c = cols,
    r = rows,
    data = b64_file(path),
  }
  placed[placement_id] = { i = image_id, c = cols, r = rows }
end

---@param image_id integer
---@param placement_id? integer
function M.delete(image_id, placement_id)
  if placement_id then
    M.request { a = 'd', d = 'i', i = image_id, p = placement_id, q = 2 }
  else
    M.request { a = 'd', d = 'i', i = image_id, q = 2 }
  end
end

---@param image_id integer
---@param placement_id integer
---@param rows integer
---@param cols integer
---@return string[]
---@return string hl
function M.grid(image_id, placement_id, rows, cols)
  -- Unicode placeholders encode image id in fg and placement id in underline (sp).
  local hl = string.format('SuperMarkdownImg%d_%d', image_id, placement_id)
  vim.api.nvim_set_hl(0, hl, { fg = image_id, sp = placement_id, nocombine = true })
  rows = math.min(rows, #diacritics)
  cols = math.min(cols, #diacritics)
  local lines = {}
  for r = 1, rows do
    local cells = {}
    for c = 1, cols do
      cells[#cells + 1] = PLACEHOLDER .. positions[r] .. positions[c]
    end
    lines[#lines + 1] = table.concat(cells)
  end
  return lines, hl
end

---@param path string
---@return integer|nil w
---@return integer|nil h
function M.png_size(path)
  local fd = io.open(path, 'rb')
  if not fd then
    return
  end
  local header = fd:read(24)
  fd:close()
  if not header or #header < 24 or header:sub(1, 8) ~= '\137PNG\r\n\26\n' then
    return
  end
  local w = header:byte(17) * 16777216 + header:byte(18) * 65536 + header:byte(19) * 256 + header:byte(20)
  local h = header:byte(21) * 16777216 + header:byte(22) * 65536 + header:byte(23) * 256 + header:byte(24)
  return w, h
end

---@param px_w integer
---@param px_h integer
---@param max_cols integer
---@param max_rows integer
---@return integer cols
---@return integer rows
function M.fit_cells(px_w, px_h, max_cols, max_rows)
  local sz = M.size()
  local cols = math.max(1, math.ceil(px_w / sz.cell_width))
  local rows = math.max(1, math.ceil(px_h / sz.cell_height))
  if cols <= max_cols and rows <= max_rows then
    return cols, rows
  end
  local scale = math.min(max_cols / cols, max_rows / rows)
  return math.max(1, math.floor(cols * scale + 0.5)), math.max(1, math.floor(rows * scale + 0.5))
end

---Scale an image to an exact column width, keeping aspect ratio.
---@param px_w integer
---@param px_h integer
---@param target_cols integer
---@param max_rows integer
---@return integer cols
---@return integer rows
function M.fit_to_width(px_w, px_h, target_cols, max_rows)
  local sz = M.size()
  local cols = math.max(1, target_cols)
  if px_w < 1 or px_h < 1 then
    return cols, 1
  end
  local rows = math.max(1, math.floor(px_h / px_w * cols * sz.cell_width / sz.cell_height + 0.5))
  if rows > max_rows then
    cols = math.max(1, math.floor(cols * max_rows / rows + 0.5))
    rows = max_rows
  end
  return cols, rows
end

return M
