-- Window tiling coordinator.
-- Windows/WSL: delegates to scripts/tile-window.ps1 (one-shot).
-- Elsewhere: falls back to plain browser launch via owl.browser.

local os_util = require('owl.util.os')
local config  = require('owl.config')
local log     = require('owl.util.log')

local M = {}

-- Track browser processes by nvim-buf so we can kill them cleanly later.
-- Keyed by preview id (the same one used by server registration).
local tracked = {}   -- id -> { pid = <windows pid>, data_dir = <path> }

-- ---------------------------------------------------------------------------
-- Path helper: locate the tiling script (relative to the plugin root)
-- ---------------------------------------------------------------------------
local function tile_script_path()
  local server = require('owl.server')
  return server.plugin_root() .. '/scripts/tile-window.ps1'
end

-- ---------------------------------------------------------------------------
-- Convert a WSL Linux path to a Windows path (only used from WSL)
-- ---------------------------------------------------------------------------
local function wslpath_w(p)
  local out = vim.fn.system({ 'wslpath', '-w', p })
  return (out or ''):gsub('[\r\n]+$', '')
end

-- ---------------------------------------------------------------------------
-- Tile a preview URL. Returns true if the tiled mode was attempted.
-- ---------------------------------------------------------------------------
function M.tile(id, url)
  local opts = config.get().window
  if opts.mode ~= 'tiled' then return false end
  if not (os_util.is_windows() or os_util.is_wsl()) then
    log.debug('tile: OS not Windows/WSL, deferring to browser fallback')
    return false
  end

  local ps_script = tile_script_path()
  if vim.fn.filereadable(ps_script) == 0 then
    log.warn('tile: script not found at', ps_script)
    return false
  end

  -- The PS script argument list
  local ps_args = {
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', ps_script,
    '-Url', url,
    '-NvimPid', tostring(vim.fn.getpid()),
    '-BrowserSide',    opts.side or 'right',
    '-BrowserPercent', tostring(opts.width_percent or 50),
  }

  -- In WSL, ps_script is a Linux path and powershell.exe cannot read it
  -- directly. Convert to a Windows-visible path.
  if os_util.is_wsl() then
    ps_args[6] = wslpath_w(ps_script)   -- index 6 is the -File argument
  end

  -- Collect the OWL_BROWSER_PID / OWL_DATA_DIR markers from stdout
  local seen = { pid = nil, data_dir = nil }
  local cmd = { 'powershell.exe' }
  for _, a in ipairs(ps_args) do table.insert(cmd, a) end

  vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        if line then
          local pid = line:match('^OWL_BROWSER_PID=(%d+)')
          if pid then seen.pid = tonumber(pid) end
          local dd = line:match('^OWL_DATA_DIR=(.+)$')
          if dd then seen.data_dir = dd:gsub('[\r\n]+$', '') end
        end
      end
      if seen.pid or seen.data_dir then
        tracked[id] = seen
        log.debug('tile: tracked', id, seen)
      end
    end,
    on_stderr = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        if line and line ~= '' then log.debug('tile ps stderr:', line) end
      end
    end,
    on_exit = function(_, code)
      log.debug('tile: powershell exited', code)
    end,
  })

  return true
end

-- ---------------------------------------------------------------------------
-- Close a previously launched preview (kills the browser process).
-- ---------------------------------------------------------------------------
function M.close(id)
  local t = tracked[id]
  if not t then return end
  tracked[id] = nil

  local kill_cmd
  if t.pid and (os_util.is_windows() or os_util.is_wsl()) then
    kill_cmd = { 'powershell.exe', '-NoProfile', '-Command',
      string.format("Stop-Process -Id %d -Force -ErrorAction SilentlyContinue", t.pid) }
  elseif t.data_dir and (os_util.is_windows() or os_util.is_wsl()) then
    -- Fallback: kill anything using our data-dir marker
    kill_cmd = { 'powershell.exe', '-NoProfile', '-Command', string.format(
      "Get-CimInstance Win32_Process | Where-Object {$_.CommandLine -match [regex]::Escape('%s')} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }",
      t.data_dir:gsub("'", "''")
    )}
  end

  if kill_cmd then
    vim.fn.jobstart(kill_cmd, { detach = true })
    log.debug('tile: closed', id)
  end
end

function M.close_all()
  for id in pairs(tracked) do M.close(id) end
end

return M
