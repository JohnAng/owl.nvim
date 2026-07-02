-- User-facing commands. Loaded once on plugin startup.
if vim.g.loaded_owl then return end
vim.g.loaded_owl = true

local function owl() return require('owl') end

vim.api.nvim_create_user_command('OwlPreview',       function() owl().preview() end, { desc = 'Start live preview for current buffer' })
vim.api.nvim_create_user_command('OwlStop',          function() owl().stop()    end, { desc = 'Stop preview for current buffer' })
vim.api.nvim_create_user_command('OwlToggle',        function() owl().toggle()  end, { desc = 'Toggle preview for current buffer' })
vim.api.nvim_create_user_command('OwlStopAll',       function() owl().stop_all() end, { desc = 'Stop all previews and shut server down' })
vim.api.nvim_create_user_command('OwlSyncTexHere',   function() require('owl.latex').synctex_here() end, { desc = 'Forward SyncTeX to current cursor position' })

vim.api.nvim_create_user_command('OwlServerUrl', function()
  local server = require('owl.server')
  local url = server.url('/')
  if url then vim.notify('owl server: ' .. url) else vim.notify('owl server not running') end
end, {})
