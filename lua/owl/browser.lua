-- Cross-platform URL opener.
-- Detects the right command per OS and honours user overrides.

local os_util = require('owl.util.os')
local config  = require('owl.config')
local log     = require('owl.util.log')

local M = {}

local function pick_cmd()
  local opts = config.get().browser
  if opts.cmd and opts.cmd ~= 'auto' then return opts.cmd end
  if os_util.is_windows() then return 'start' end
  if os_util.is_mac()     then return 'open' end
  if os_util.is_wsl()     then
    if os_util.executable('wslview') then return 'wslview' end
    return 'wsl-powershell-start'
  end
  return 'xdg-open'
end

function M.open(url)
  local cmd = pick_cmd()
  local br  = config.get().browser
  log.debug('opening', url, 'via', cmd, 'override=', br.override)

  if cmd == 'start' then
    -- Windows: `start` is a cmd.exe built-in.
    local args = { 'cmd', '/c', 'start', '' }
    if br.override then args = { 'cmd', '/c', 'start', '', br.override } end
    args[#args + 1] = url
    vim.fn.jobstart(args, { detach = true })
  elseif cmd == 'wsl-powershell-start' then
    vim.fn.jobstart({ 'powershell.exe', '-NoProfile', '-Command', 'Start-Process', '"' .. url .. '"' },
      { detach = true })
  elseif cmd == 'wslview' then
    vim.fn.jobstart({ 'wslview', url }, { detach = true })
  elseif cmd == 'open' then
    local args = { 'open' }
    if br.override then table.insert(args, '-a'); table.insert(args, br.override) end
    if br.new_window then table.insert(args, '--new') end
    table.insert(args, url)
    vim.fn.jobstart(args, { detach = true })
  elseif cmd == 'xdg-open' then
    if br.override and os_util.executable(br.override) then
      vim.fn.jobstart({ br.override, url }, { detach = true })
    else
      vim.fn.jobstart({ 'xdg-open', url }, { detach = true })
    end
  else
    vim.fn.jobstart({ cmd, url }, { detach = true })
  end
end

return M
