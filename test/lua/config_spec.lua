-- Unit tests for owl.config
local config = require('owl.config')

describe('owl.config', function()
  it('exposes sensible defaults', function()
    config.setup({})
    local o = config.get()
    eq(o.window.mode, 'tiled')
    eq(o.window.side, 'right')
    eq(o.window.width_percent, 50)
    eq(o.markdown.trigger, 'live')
    eq(o.markdown.scroll_sync, true)
    eq(o.latex.viewer, 'auto')
    eq(o.latex.engine, 'xelatex')
    eq(o.latex.synctex, true)
    eq(o.auto_shutdown, true)
  end)

  it('merges user overrides deeply', function()
    config.setup({
      window = { side = 'left', width_percent = 60 },
      markdown = { trigger = 'save' },
      log_level = 'debug',
    })
    local o = config.get()
    eq(o.window.side, 'left')
    eq(o.window.width_percent, 60)
    eq(o.window.mode, 'tiled')            -- untouched default preserved
    eq(o.markdown.trigger, 'save')
    eq(o.markdown.scroll_sync, true)      -- deep-merged, sibling default kept
    eq(o.log_level, 'debug')
  end)

  it('re-running setup replaces previous overrides', function()
    config.setup({ window = { side = 'left' } })
    eq(config.get().window.side, 'left')
    config.setup({})
    eq(config.get().window.side, 'right') -- back to default
  end)
end)
