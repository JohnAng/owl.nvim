-- Minimal self-contained test harness. No plenary dependency.
-- Usage: nvim --headless -l test/lua/harness.lua [spec1.lua spec2.lua ...]
-- Exit code is 0 on success, 1 on any failure.

local M = {}

M.passed = 0
M.failed = 0
M.failures = {}

local RED    = '\27[31m'
local GREEN  = '\27[32m'
local YELLOW = '\27[33m'
local DIM    = '\27[90m'
local RESET  = '\27[0m'

local function print_line(s) io.stdout:write(s .. '\n'); io.stdout:flush() end

function M.describe(name, body)
  print_line(YELLOW .. name .. RESET)
  body()
end

function M.it(name, body)
  local ok, err = pcall(body)
  if ok then
    M.passed = M.passed + 1
    print_line('  ' .. GREEN .. 'v' .. RESET .. ' ' .. name)
  else
    M.failed = M.failed + 1
    table.insert(M.failures, { name = name, err = err })
    print_line('  ' .. RED .. 'x' .. RESET .. ' ' .. name)
    print_line('    ' .. DIM .. tostring(err) .. RESET)
  end
end

function M.eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error(string.format('%s\n  expected: %s\n  actual:   %s', msg or 'not equal',
      vim.inspect(b), vim.inspect(a)), 2)
  end
end

function M.truthy(v, msg)
  if not v then error(msg or 'expected truthy, got ' .. vim.inspect(v), 2) end
end

function M.falsy(v, msg)
  if v then error(msg or 'expected falsy, got ' .. vim.inspect(v), 2) end
end

function M.contains(haystack, needle, msg)
  if type(haystack) == 'string' then
    if not haystack:find(needle, 1, true) then
      error(string.format('%s\n  expected substring: %s\n  in: %s',
        msg or 'no substring match', needle, haystack), 2)
    end
  else
    for _, v in ipairs(haystack) do
      if vim.deep_equal(v, needle) then return end
    end
    error(msg or ('missing ' .. vim.inspect(needle)), 2)
  end
end

-- Expose the API globally so specs can just call `it`, `eq`, etc.
_G.describe = M.describe
_G.it       = M.it
_G.eq       = M.eq
_G.truthy   = M.truthy
_G.falsy    = M.falsy
_G.contains = M.contains

-- Locate the plugin root (this file lives at <root>/test/lua/harness.lua)
local this_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
local plugin_root = vim.fn.fnamemodify(this_dir, ':h:h')
vim.opt.rtp:prepend(plugin_root)

-- Run each spec file passed on the command line
local args = _G.arg or {}
if #args == 0 then
  -- default: discover *_spec.lua in the same directory
  for _, f in ipairs(vim.fn.readdir(this_dir)) do
    if f:match('_spec%.lua$') then table.insert(args, this_dir .. '/' .. f) end
  end
end

for _, path in ipairs(args) do
  print_line('')
  print_line(DIM .. '~ ' .. path .. RESET)
  local chunk, err = loadfile(path)
  if not chunk then
    M.failed = M.failed + 1
    table.insert(M.failures, { name = path, err = err })
    print_line(RED .. 'load error: ' .. tostring(err) .. RESET)
  else
    local ok, e = pcall(chunk)
    if not ok then
      M.failed = M.failed + 1
      table.insert(M.failures, { name = path, err = e })
      print_line(RED .. 'exec error: ' .. tostring(e) .. RESET)
    end
  end
end

print_line('')
print_line(string.format('%s%d passed%s, %s%d failed%s',
  GREEN, M.passed, RESET, (M.failed > 0 and RED or DIM), M.failed, RESET))

if M.failed > 0 then vim.cmd('cq 1') else vim.cmd('qa!') end
