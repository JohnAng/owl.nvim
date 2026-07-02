local M = {}

M.defaults = {
  -- Server
  server = {
    host = '127.0.0.1',
    port = 0,           -- 0 = auto-pick a free port
    node = 'node',      -- override with an absolute path if you have multiple
  },

  -- Preview window management
  window = {
    -- 'tiled'    : auto-tile terminal + browser 50/50 (Windows/WSL only for now)
    -- 'external' : just open the URL, user manages windows
    -- 'off'      : don't launch anything, print the URL
    mode = 'tiled',
    side = 'right',           -- 'right' | 'left' — where the preview sits
    width_percent = 50,       -- how much of the screen the preview takes
    -- Reserved for later per-OS tuning
    monitor = 'primary',      -- 'primary' | 'current' | 1..N
  },

  -- Plain fallback opener (used when window.mode ~= 'tiled')
  browser = {
    -- 'auto' picks per-OS default handler (start / open / xdg-open / wslview)
    cmd = 'auto',
    -- Override the plain-open command: 'brave.exe', 'firefox', etc.
    override = nil,
  },

  -- Markdown
  markdown = {
    -- Update on TextChanged (live) or on save (BufWritePost)
    trigger = 'live',       -- 'live' | 'save'
    -- Send cursor line on CursorMoved for scroll-sync
    scroll_sync = true,
    -- Auto-detect a *.bib in the same directory as the .md file
    auto_bib = true,
    -- Explicit bib path override
    bib = nil,
  },

  -- LaTeX
  latex = {
    -- 'auto' detects: sumatra (Win) > zathura (Linux) > skim (mac) > sioyek > browser
    viewer = 'auto',        -- 'auto' | 'browser' | 'sumatra' | 'zathura' | 'skim' | 'sioyek'
    -- latexmk args
    engine = 'xelatex',     -- 'xelatex' | 'pdflatex' | 'lualatex'
    latexmk_extra = {},
    -- Enable SyncTeX
    synctex = true,
    -- Auxiliary build directory (relative to the .tex file dir)
    aux_dir = '.owl-build',
  },

  -- Diagnostics: LaTeX compile errors go to a namespace
  diagnostics = {
    enabled = true,
    signs = true,
    virtual_text = { spacing = 2, prefix = '' },
  },

  -- Log level
  log_level = 'info',       -- 'trace' | 'debug' | 'info' | 'warn' | 'error'

  -- Cleanup behavior on VimLeavePre
  auto_shutdown = true,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(user)
  M.options = vim.tbl_deep_extend('force', M.defaults, user or {})
  return M.options
end

function M.get() return M.options end

return M
