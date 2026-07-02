local M = {}

M.uname = (function()
  local ok, s = pcall(vim.loop.os_uname)
  if ok then return s end
  return { sysname = 'Linux' }
end)()

function M.is_windows() return M.uname.sysname == 'Windows_NT' end
function M.is_mac()     return M.uname.sysname == 'Darwin' end
function M.is_linux()   return M.uname.sysname == 'Linux' end

M._wsl = nil
function M.is_wsl()
  if M._wsl ~= nil then return M._wsl end
  if not M.is_linux() then M._wsl = false; return false end
  if vim.env.WSL_DISTRO_NAME and vim.env.WSL_DISTRO_NAME ~= '' then M._wsl = true; return true end
  local f = io.open('/proc/version', 'r')
  if f then
    local s = f:read('*a') or ''; f:close()
    if s:lower():find('microsoft') then M._wsl = true; return true end
  end
  M._wsl = false
  return false
end

function M.executable(name)
  return vim.fn.executable(name) == 1
end

function M.which(name)
  local out = vim.fn.exepath(name)
  if out and out ~= '' then return out end
  return nil
end

return M
