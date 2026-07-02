-- LaTeX live-preview module.
-- Runs `latexmk -pvc` in the background, watches PDF via native viewer
-- (auto-detects Sumatra/zathura/Skim/sioyek) or falls back to the browser.

local server  = require('owl.server')
local browser = require('owl.browser')
local config  = require('owl.config')
local os_util = require('owl.util.os')
local log     = require('owl.util.log')

local M = {}

local ns = vim.api.nvim_create_namespace('owl_latex')
local active = {}  -- bufnr -> { id, augroup, latexmk_job, viewer, pdf_path, aux_dir, filepath }

local function make_id(bufnr)
  return string.format('tex-%d-%d', vim.fn.getpid(), bufnr)
end

-- ---------------------------------------------------------------------------
-- Viewer detection
-- ---------------------------------------------------------------------------
local function detect_viewer()
  local override = config.get().latex.viewer
  if override and override ~= 'auto' then return override end

  if os_util.is_windows() then
    if os_util.executable('SumatraPDF') or os_util.executable('SumatraPDF.exe') then return 'sumatra' end
  elseif os_util.is_mac() then
    -- Skim isn't a CLI; check for its bundle path.
    if vim.fn.isdirectory('/Applications/Skim.app') == 1 then return 'skim' end
  else
    -- Linux / WSL
    if os_util.executable('zathura') then return 'zathura' end
  end
  if os_util.executable('sioyek') then return 'sioyek' end
  return 'browser'
end

-- ---------------------------------------------------------------------------
-- SyncTeX forward: jump from source line -> PDF page/pos
-- ---------------------------------------------------------------------------
local function synctex_forward(entry, line)
  if not config.get().latex.synctex then return end
  local pdf = entry.pdf_path
  if not pdf or vim.fn.filereadable(pdf) == 0 then return end
  local src = entry.filepath

  local viewer = entry.viewer
  if viewer == 'zathura' then
    vim.fn.jobstart({ 'zathura', '--synctex-forward', line .. ':1:' .. src, pdf }, { detach = true })
  elseif viewer == 'skim' then
    vim.fn.jobstart({
      '/Applications/Skim.app/Contents/SharedSupport/displayline',
      '-r', tostring(line), pdf, src
    }, { detach = true })
  elseif viewer == 'sumatra' then
    vim.fn.jobstart({
      'SumatraPDF', '-reuse-instance', '-forward-search', src, tostring(line), pdf
    }, { detach = true })
  elseif viewer == 'sioyek' then
    vim.fn.jobstart({
      'sioyek', '--reuse-window', '--forward-search-file', src,
      '--forward-search-line', tostring(line), pdf
    }, { detach = true })
  end
end

-- ---------------------------------------------------------------------------
-- Diagnostics from latexmk .log
-- ---------------------------------------------------------------------------
local function parse_log(log_path, filepath)
  local f = io.open(log_path, 'r')
  if not f then return {} end
  local text = f:read('*a') or ''; f:close()

  local diagnostics = {}
  -- ! Error message  followed by  l.NN
  for msg, line in text:gmatch('!%s([^\n]+)\n[^\n]-l%.(%d+)') do
    table.insert(diagnostics, {
      lnum = tonumber(line) - 1, col = 0,
      severity = vim.diagnostic.severity.ERROR,
      message = msg, source = 'latexmk',
    })
  end
  -- Warnings
  for msg, line in text:gmatch('LaTeX Warning:%s([^\n]+)line (%d+)') do
    table.insert(diagnostics, {
      lnum = tonumber(line) - 1, col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = msg, source = 'latexmk',
    })
  end
  return diagnostics
end

local function update_diagnostics(entry)
  if not config.get().diagnostics.enabled then return end
  local logf = entry.aux_dir .. '/' .. vim.fn.fnamemodify(entry.filepath, ':t:r') .. '.log'
  local diags = parse_log(logf, entry.filepath)
  local ok_buf, bufnr = pcall(vim.fn.bufnr, entry.filepath)
  if not ok_buf or bufnr == -1 then return end
  vim.diagnostic.set(ns, bufnr, diags)
end

-- ---------------------------------------------------------------------------
-- latexmk continuous compile
-- ---------------------------------------------------------------------------
local function start_latexmk(entry)
  local opts = config.get().latex
  local file = entry.filepath
  local dir  = vim.fn.fnamemodify(file, ':p:h')
  local base = vim.fn.fnamemodify(file, ':t')
  local aux  = entry.aux_dir

  vim.fn.mkdir(aux, 'p')

  local engine_flag = '-' .. opts.engine   -- -xelatex / -pdflatex / -lualatex
  local args = {
    'latexmk',
    engine_flag,
    '-pvc',                        -- preview-continuous
    '-view=none',                  -- we manage the viewer ourselves
    '-interaction=nonstopmode',
    '-halt-on-error',
    '-file-line-error',
    '-output-directory=' .. aux,
  }
  if opts.synctex then table.insert(args, '-synctex=1') end
  for _, extra in ipairs(opts.latexmk_extra) do table.insert(args, extra) end
  table.insert(args, base)

  log.debug('latexmk cmd:', table.concat(args, ' '))

  entry.latexmk_job = vim.fn.jobstart(args, {
    cwd = dir,
    on_stdout = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        if line and line ~= '' then log.debug('latexmk:', line) end
      end
    end,
    on_stderr = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        if line and line ~= '' then log.debug('latexmk err:', line) end
      end
    end,
    on_exit = function(_, code)
      log.info('latexmk exited', code)
      entry.latexmk_job = nil
    end,
  })
end

-- ---------------------------------------------------------------------------
-- PDF watcher: on change, refresh viewer + parse log + push reload to browser
-- ---------------------------------------------------------------------------
local function watch_pdf(entry)
  local pdf = entry.pdf_path
  local timer = vim.loop.new_timer()
  local last_mtime = 0

  local function check()
    local stat = vim.loop.fs_stat(pdf)
    if stat and stat.mtime.sec ~= last_mtime then
      last_mtime = stat.mtime.sec
      update_diagnostics(entry)
      -- Broadcast to any browser client watching this buffer
      server.post('/nvim/reload-pdf', { id = entry.id })
      -- If viewer is a native one, they auto-reload on file change themselves.
    end
  end

  timer:start(500, 500, vim.schedule_wrap(check))
  entry.pdf_timer = timer
end

-- ---------------------------------------------------------------------------
-- Launch viewer (once, sticky)
-- ---------------------------------------------------------------------------
local function launch_viewer(entry)
  local viewer = entry.viewer
  local pdf    = entry.pdf_path

  if viewer == 'browser' then
    server.ensure_started(function(ok, err)
      if not ok then log.error('server start failed:', err); return end
      server.post('/nvim/register', {
        id       = entry.id,
        mode     = 'latex',
        filepath = entry.filepath,
        dir      = vim.fn.fnamemodify(entry.filepath, ':p:h'),
        pdfPath  = pdf,
      })
      vim.defer_fn(function()
        browser.open(entry.id, server.url('/preview/tex/' .. entry.id))
      end, 150)
    end)
    return
  end

  if viewer == 'zathura' then
    vim.fn.jobstart({ 'zathura', pdf }, { detach = true })
  elseif viewer == 'sumatra' then
    vim.fn.jobstart({ 'SumatraPDF', '-reuse-instance', pdf }, { detach = true })
  elseif viewer == 'skim' then
    vim.fn.jobstart({ 'open', '-a', 'Skim', pdf }, { detach = true })
  elseif viewer == 'sioyek' then
    vim.fn.jobstart({ 'sioyek', pdf }, { detach = true })
  else
    log.warn('unknown viewer:', viewer)
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function M.is_active(bufnr) return active[bufnr] ~= nil end

function M.start(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if active[bufnr] then log.info('latex preview already running'); return end
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == '' or not filepath:match('%.tex$') then
    log.warn('current buffer is not a .tex file (saved to disk)')
    return
  end
  if not os_util.executable('latexmk') then
    log.error('latexmk not found; install TeX Live / MikTeX')
    return
  end

  local dir  = vim.fn.fnamemodify(filepath, ':p:h')
  local base = vim.fn.fnamemodify(filepath, ':t:r')
  local aux  = dir .. '/' .. config.get().latex.aux_dir
  local pdf  = aux .. '/' .. base .. '.pdf'

  local viewer = detect_viewer()
  log.info('using viewer:', viewer)

  local entry = {
    id = make_id(bufnr),
    filepath = filepath,
    aux_dir = aux,
    pdf_path = pdf,
    viewer = viewer,
    latexmk_job = nil,
  }

  active[bufnr] = entry

  start_latexmk(entry)

  -- Wait until PDF appears, then launch viewer
  vim.defer_fn(function()
    launch_viewer(entry)
    watch_pdf(entry)
  end, 800)

  local aug = vim.api.nvim_create_augroup('owl_tex_' .. bufnr, { clear = true })
  entry.augroup = aug

  -- Forward SyncTeX on cursor move if enabled
  if config.get().latex.synctex then
    vim.api.nvim_create_autocmd('CursorHold', {
      group = aug, buffer = bufnr,
      callback = function()
        local line = vim.api.nvim_win_get_cursor(0)[1]
        synctex_forward(entry, line)
      end,
    })
  end

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufUnload' }, {
    group = aug, buffer = bufnr,
    callback = function() M.stop(bufnr) end,
  })
end

function M.stop(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local entry = active[bufnr]
  if not entry then return end
  if entry.latexmk_job then pcall(vim.fn.jobstop, entry.latexmk_job) end
  if entry.pdf_timer   then entry.pdf_timer:stop(); entry.pdf_timer:close() end
  if entry.augroup     then pcall(vim.api.nvim_del_augroup_by_id, entry.augroup) end
  if entry.viewer == 'browser' then
    server.post('/nvim/unregister', { id = entry.id })
    browser.close(entry.id)
  end
  vim.diagnostic.reset(ns, bufnr)
  active[bufnr] = nil
  log.info('latex preview stopped')
end

function M.stop_all()
  for bufnr in pairs(active) do M.stop(bufnr) end
end

-- SyncTeX forward, invoked on demand from the user
function M.synctex_here()
  local bufnr = vim.api.nvim_get_current_buf()
  local entry = active[bufnr]
  if not entry then log.warn('no preview running'); return end
  synctex_forward(entry, vim.api.nvim_win_get_cursor(0)[1])
end

return M
