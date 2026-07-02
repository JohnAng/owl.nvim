-- Preview launcher.
-- Prefers `owl.window.tile` when config.window.mode == 'tiled' and the OS
-- supports it (Windows or WSL). Falls back to plain OS-specific browser open.

local os_util = require('owl.util.os')
local config  = require('owl.config')
local log     = require('owl.util.log')
local window  = require('owl.window')

local M = {}

-- ---------------------------------------------------------------------------
-- Plain-open fallback (opens the user's default handler)
-- ---------------------------------------------------------------------------
local function pick_cmd()
  local br = config.get().browser
  if br.cmd and br.cmd ~= 'auto' then return br.cmd end
  if os_util.is_windows() then return 'start' end
  if os_util.is_mac()     then return 'open' end
  if os_util.is_wsl()     then
    if os_util.executable('wslview') then return 'wslview' end
    return 'wsl-powershell-start'
  end
  return 'xdg-open'
end

local function open_default(url)
  local cmd = pick_cmd()
  local br  = config.get().browser
  log.debug('opening (default handler)', url, 'via', cmd)

  if cmd == 'start' then
    vim.fn.jobstart({ 'cmd', '/c', 'start', '', url }, { detach = true })
  elseif cmd == 'wsl-powershell-start' then
    vim.fn.jobstart({ 'powershell.exe', '-NoProfile', '-Command', 'Start-Process', '"' .. url .. '"' },
      { detach = true })
  elseif cmd == 'wslview' then
    vim.fn.jobstart({ 'wslview', url }, { detach = true })
  elseif cmd == 'open' then
    local args = { 'open' }
    if br.override then table.insert(args, '-a'); table.insert(args, br.override) end
    table.insert(args, url)
    vim.fn.jobstart(args, { detach = true })
  elseif cmd == 'xdg-open' then
    vim.fn.jobstart({ 'xdg-open', url }, { detach = true })
  else
    vim.fn.jobstart({ cmd, url }, { detach = true })
  end
end

-- ---------------------------------------------------------------------------
-- Public: open a preview URL, tiled if possible, otherwise plain.
-- `id` is the preview id (matches server registration).
-- ---------------------------------------------------------------------------
function M.open(id, url)
  local mode = config.get().window.mode
  if mode == 'off' then
    log.info('window.mode=off — printing url instead: ' .. url)
    return
  end

  if mode == 'tiled' then
    if window.tile(id, url) then return end
    log.debug('tile mode unavailable, falling back to default open')
  end

  open_default(url)
end

function M.close(id)
  window.close(id)
end

function M.close_all()
  window.close_all()
end

return M
