-- :checkhealth owl
local os_util = require('owl.util.os')
local server  = require('owl.server')
local config  = require('owl.config')

local M = {}

local h = vim.health or require('health')
local start = h.start or h.report_start
local ok    = h.ok    or h.report_ok
local warn  = h.warn  or h.report_warn
local error_ = h.error or h.report_error
local info  = h.info  or h.report_info

local function per_os_hint(cmd_map)
  if os_util.is_windows() then return cmd_map.windows or '' end
  if os_util.is_mac()     then return cmd_map.mac     or '' end
  if os_util.is_wsl()     then return cmd_map.wsl     or cmd_map.linux or '' end
  return cmd_map.linux or ''
end

function M.check()
  start('owl.nvim — core')

  -- Node
  if os_util.executable(config.get().server.node) then
    local out = vim.fn.system(config.get().server.node .. ' --version'):gsub('%s+$', '')
    ok('node found: ' .. out)
  else
    error_('node not found in PATH', {
      'install Node.js >= 18',
      per_os_hint({
        windows = 'winget install OpenJS.NodeJS',
        mac     = 'brew install node',
        linux   = 'sudo apt-get install nodejs npm',
      }),
    })
  end

  -- Server dir + node_modules
  local sd = server.server_dir()
  if vim.fn.filereadable(sd .. '/src/server.js') == 1 then
    ok('server bundled at: ' .. sd)
  else
    error_('server entry missing: ' .. sd .. '/src/server.js')
  end
  if vim.fn.isdirectory(sd .. '/node_modules') == 1 then
    ok('server dependencies installed')
  else
    error_('server dependencies not installed', {
      'run: cd ' .. sd .. ' && npm install --omit=dev',
      'this normally happens automatically via the plugin manager `build` hook',
    })
  end

  start('owl.nvim — markdown')
  info('trigger: ' .. config.get().markdown.trigger)
  info('scroll_sync: ' .. tostring(config.get().markdown.scroll_sync))
  info('auto_bib: ' .. tostring(config.get().markdown.auto_bib))

  start('owl.nvim — latex')
  -- latexmk
  if os_util.executable('latexmk') then
    ok('latexmk found')
  else
    warn('latexmk not found', {
      'required for LaTeX preview',
      per_os_hint({
        windows = 'winget install MiKTeX.MiKTeX  (then install latexmk via MiKTeX Console)',
        mac     = 'brew install --cask mactex-no-gui  # or basictex + tlmgr install latexmk',
        linux   = 'sudo apt-get install texlive-latex-extra latexmk',
      }),
    })
  end

  -- Engine
  local engine = config.get().latex.engine
  if os_util.executable(engine) then
    ok(engine .. ' found')
  else
    warn(engine .. ' not found', {
      'either install it or set opts.latex.engine to one you have (pdflatex/xelatex/lualatex)',
    })
  end

  -- Viewer detection
  local detected = {
    sumatra = os_util.executable('SumatraPDF') or os_util.executable('SumatraPDF.exe'),
    zathura = os_util.executable('zathura'),
    skim    = vim.fn.isdirectory('/Applications/Skim.app') == 1,
    sioyek  = os_util.executable('sioyek'),
  }
  local any = false
  for name, present in pairs(detected) do
    if present then ok('viewer available: ' .. name); any = true end
  end
  if not any then
    warn('no native PDF viewer detected; falling back to browser (pdf.js)', {
      per_os_hint({
        windows = 'winget install SumatraPDF.SumatraPDF',
        mac     = 'brew install --cask skim',
        linux   = 'sudo apt-get install zathura zathura-pdf-mupdf',
      }),
      'or install sioyek for a cross-platform option: https://github.com/ahrm/sioyek',
    })
  end

  start('owl.nvim — runtime')
  if server.is_ready() then
    local a = server.address()
    ok(string.format('server running at %s:%d', a.host, a.port))
  else
    info('server not started (starts on first :OwlPreview)')
  end
end

return M
