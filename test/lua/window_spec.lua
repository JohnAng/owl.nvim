-- Unit tests for owl.window (path resolution + tracking API)
local config = require('owl.config')
local window = require('owl.window')
local server = require('owl.server')

describe('owl.window', function()
  it('server.plugin_root() resolves to a real directory containing scripts/', function()
    local root = server.plugin_root()
    truthy(root and #root > 0)
    truthy(vim.fn.isdirectory(root .. '/scripts') == 1,
      'expected ' .. root .. '/scripts to exist')
    truthy(vim.fn.filereadable(root .. '/scripts/tile-window.ps1') == 1,
      'tile-window.ps1 must live under scripts/')
  end)

  it('tile() returns false when mode = external / off', function()
    config.setup({ window = { mode = 'external' } })
    eq(window.tile('t-external', 'http://localhost/x'), false)
    config.setup({ window = { mode = 'off' } })
    eq(window.tile('t-off', 'http://localhost/x'), false)
    config.setup({})   -- restore defaults for other specs
  end)

  it('close() is a no-op for unknown ids (no error)', function()
    window.close('nonexistent-id-xxx')
    truthy(true, 'should not raise')
  end)

  it('close_all() is safe when nothing tracked', function()
    window.close_all()
    truthy(true, 'should not raise')
  end)
end)
