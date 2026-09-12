if vim.g.loaded_super_markdown then
  return
end
vim.g.loaded_super_markdown = true

vim.api.nvim_create_user_command('SuperMarkdown', function(opts)
  require('super-markdown.command').run(opts)
end, {
  nargs = '?',
  complete = function()
    return require('super-markdown.command').complete()
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('SuperMarkdownPlugin', { clear = true }),
  pattern = 'markdown',
  callback = function(ev)
    require('super-markdown').attach(ev.buf)
  end,
})
