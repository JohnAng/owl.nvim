-- Node preview server lifecycle.
-- The server is bundled under <plugin-root>/server.
-- A single process is shared across all buffers in a Neovim session.

local uv     = vim.loop
local log    = require('owl.util.log')
local config = require('owl.config')

local M = {}

local state = {
  job_id  = nil,
  pid     = nil,
  host    = nil,
  port    = nil,
  ready   = false,
  waiters = {},   -- functions called when the server becomes ready
  ws      = nil,  -- reserved for future in-process WS (we use jobstart shell now)
}

-- Locate this plugin's root (walk up from lua/owl/server.lua)
-- File path is: <root>/lua/owl/server.lua
-- :p:h -> lua/owl,  :h -> lua,  :h -> <root>
local function plugin_root()
  local this = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(this, ':p:h:h:h')
end

function M.plugin_root() return plugin_root() end

function M.server_dir() return plugin_root() .. '/server' end

function M.is_ready() return state.ready end

function M.address()
  if not state.ready then return nil end
  return { host = state.host, port = state.port }
end

function M.url(path)
  if not state.ready then return nil end
  return string.format('http://%s:%d%s', state.host, state.port, path or '/')
end

-- Wait until the server is ready, then call cb(ok, err)
function M.wait_ready(cb)
  if state.ready then cb(true); return end
  table.insert(state.waiters, cb)
end

local function resolve_waiters(ok, err)
  local list = state.waiters
  state.waiters = {}
  for _, cb in ipairs(list) do
    pcall(cb, ok, err)
  end
end

-- ---------------------------------------------------------------------------
-- Start / stop
-- ---------------------------------------------------------------------------
function M.ensure_started(cb)
  cb = cb or function() end
  if state.ready then cb(true); return end
  if state.job_id then M.wait_ready(cb); return end

  local opts = config.get()
  local server_dir = M.server_dir()
  local entry = server_dir .. '/src/server.js'

  if vim.fn.filereadable(entry) == 0 then
    local msg = string.format('server entry not found at %s (did the plugin install run?)', entry)
    log.error(msg); cb(false, msg); return
  end
  if vim.fn.executable(opts.server.node) == 0 then
    local msg = 'node not found in PATH; install Node.js >= 18'
    log.error(msg); cb(false, msg); return
  end
  if vim.fn.isdirectory(server_dir .. '/node_modules') == 0 then
    local msg = 'server dependencies not installed; run: cd ' .. server_dir .. ' && npm install --omit=dev'
    log.error(msg); cb(false, msg); return
  end

  M.wait_ready(cb)

  local cmd = {
    opts.server.node, entry,
    '--host', opts.server.host,
    '--port', tostring(opts.server.port or 0),
  }

  state.job_id = vim.fn.jobstart(cmd, {
    cwd = server_dir,
    stdout_buffered = false,
    on_stdout = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        if line and line ~= '' then
          local host, port, pid = line:match('OWL_READY host=(%S+) port=(%d+) pid=(%d+)')
          if host then
            state.host  = host
            state.port  = tonumber(port)
            state.pid   = tonumber(pid)
            state.ready = true
            log.info(string.format('server ready on %s:%d (pid %d)', host, state.port, state.pid))
            resolve_waiters(true)
          else
            log.debug('server:', line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        if line and line ~= '' then log.warn('server stderr:', line) end
      end
    end,
    on_exit = function(_, code)
      log.info('server exited with code', code)
      state.job_id = nil; state.ready = false; state.pid = nil
      resolve_waiters(false, 'server exited early')
    end,
  })

  if state.job_id <= 0 then
    local msg = 'jobstart failed for node server'
    log.error(msg); resolve_waiters(false, msg)
  end
end

function M.stop()
  if state.job_id then
    pcall(vim.fn.jobstop, state.job_id)
    state.job_id = nil
  end
  state.ready = false
  state.pid = nil
end

-- ---------------------------------------------------------------------------
-- WS command channel (uses `curl` for simplicity — we don't need bidirectional
-- traffic from the nvim side, just fire-and-forget messages).
-- Actually the server WS expects a full WS handshake, so we use HTTP POST to
-- /control endpoints instead. Simpler and reliable.
-- ---------------------------------------------------------------------------
function M.post(path, body)
  if not state.ready then return end
  local url = M.url(path)
  vim.fn.jobstart({
    'curl', '-fsS', '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-d', vim.json.encode(body or {}),
    url,
  }, { detach = true })
end

return M
