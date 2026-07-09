-- Unit tests for owl.util.os
local os_util = require('owl.util.os')

describe('owl.util.os', function()
  it('detects exactly one of windows/mac/linux', function()
    local w = os_util.is_windows()
    local m = os_util.is_mac()
    local l = os_util.is_linux()
    local count = (w and 1 or 0) + (m and 1 or 0) + (l and 1 or 0)
    eq(count, 1, 'exactly one OS flag must be true')
  end)

  it('is_wsl is boolean and stable across calls', function()
    local a = os_util.is_wsl()
    local b = os_util.is_wsl()
    truthy(type(a) == 'boolean')
    eq(a, b, 'is_wsl must return a stable cached value')
  end)

  it('executable() returns boolean', function()
    truthy(type(os_util.executable('sh')) == 'boolean')
  end)

  it('which() returns a path or nil', function()
    local p = os_util.which('sh')
    if p then truthy(#p > 0, 'sh path should be non-empty') end
  end)
end)
