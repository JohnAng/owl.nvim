-- owl.nvim — universal Markdown & LaTeX live preview
-- Public API + setup.

local config   = require('owl.config')
local server   = require('owl.server')
local log      = require('owl.util.log')
local markdown = require('owl.markdown')
local latex    = require('owl.latex')

local M = {}

M.config   = config
M.server   = server
M.markdown = markdown
M.latex    = latex

local function dispatch_for(ft)
  if ft == 'markdown' or ft == 'md' or ft == 'quarto' or ft == 'rmarkdown' then return markdown end
  if ft == 'tex' or ft == 'latex' or ft == 'plaintex' then return latex end
  return nil
end

function M.preview(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  local mod = dispatch_for(ft)
  if not mod then log.warn('unsupported filetype:', ft); return end
  mod.start(bufnr)
end

function M.stop(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  markdown.stop(bufnr)
  latex.stop(bufnr)
end

function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if markdown.is_active(bufnr) or latex.is_active(bufnr) then
    M.stop(bufnr)
  else
    M.preview(bufnr)
  end
end

function M.stop_all()
  markdown.stop_all()
  latex.stop_all()
  require('owl.browser').close_all()
  server.stop()
end

function M.setup(user)
  config.setup(user)
  log.set_level(config.get().log_level or 'info')

  if config.get().auto_shutdown then
    vim.api.nvim_create_autocmd('VimLeavePre', {
      group = vim.api.nvim_create_augroup('owl_shutdown', { clear = true }),
      callback = function() M.stop_all() end,
    })
  end
end

return M
