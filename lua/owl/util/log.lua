local M = {}

local LEVELS = { trace = 0, debug = 1, info = 2, warn = 3, error = 4 }
M.level = LEVELS.info

function M.set_level(name)
  M.level = LEVELS[name] or LEVELS.info
end

local function emit(lvl, name, ...)
  if LEVELS[lvl] < M.level then return end
  local args = { ... }
  local parts = {}
  for i = 1, select('#', ...) do
    local v = args[i]
    parts[i] = type(v) == 'string' and v or vim.inspect(v)
  end
  local msg = '[owl] ' .. table.concat(parts, ' ')
  vim.schedule(function()
    vim.notify(msg, vim.log.levels[name] or vim.log.levels.INFO)
  end)
end

function M.debug(...) emit('debug', 'DEBUG', ...) end
function M.info (...) emit('info',  'INFO',  ...) end
function M.warn (...) emit('warn',  'WARN',  ...) end
function M.error(...) emit('error', 'ERROR', ...) end

return M
