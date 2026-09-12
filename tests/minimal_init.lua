local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(vim.fn.expand '~/.local/share/nvim/lazy/nvim-treesitter')
vim.cmd 'runtime plugin/super-markdown.lua'
