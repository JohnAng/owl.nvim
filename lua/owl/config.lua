local M = {}

M.defaults = {
  -- Server
  server = {
    host = '127.0.0.1',
    port = 0,           -- 0 = auto-pick a free port
    node = 'node',      -- override with an absolute path if you have multiple
  },

  -- Browser
  browser = {
    -- 'auto' picks per-OS default:
    --   Windows -> start (default handler)
    --   macOS   -> open
    --   Linux   -> xdg-open
    --   WSL     -> wslview if present, else PowerShell start
    cmd = 'auto',
    -- If set, will be used verbatim: 'brave.exe', 'msedge.exe', 'firefox', 'chromium', etc.
    override = nil,
    -- Open the preview in a new window (--new-window equivalents where supported).
    new_window = false,
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
