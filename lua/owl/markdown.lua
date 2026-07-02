-- Markdown live-preview module.
-- Owns a per-buffer state: registers with the server, pushes updates on
-- TextChanged (debounced) and cursor line on CursorMoved for scroll-sync.

local server  = require('owl.server')
local browser = require('owl.browser')
local config  = require('owl.config')
local log     = require('owl.util.log')

local M = {}

-- Track active buffers: bufnr -> { id, augroup, timer }
local active = {}

local function make_id(bufnr)
  return string.format('md-%d-%d', vim.fn.getpid(), bufnr)
end

local function buf_content(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
end

local function auto_bib(dir)
  local opts = config.get().markdown
  if opts.bib and vim.fn.filereadable(opts.bib) == 1 then return opts.bib end
  if not opts.auto_bib then return nil end
  local matches = vim.fn.glob(dir .. '/*.bib', false, true)
  if matches and #matches > 0 then return matches[1] end
  return nil
end

local function push_update(bufnr, entry)
  server.post('/nvim/update', {
    id      = entry.id,
    content = buf_content(bufnr),
    cursor  = vim.api.nvim_win_get_cursor(0)[1] - 1,
  })
end

local function push_scroll(entry)
  -- Suppress if we just applied an external scroll (anti ping-pong).
  if entry.suppress_until and vim.loop.hrtime() < entry.suppress_until then return end
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  entry.last_sent_line = line
  server.post('/nvim/scroll', { id = entry.id, line = line })
end

-- Callback for OWL_EVENT scroll from browser -> move cursor.
local function on_browser_scroll(entry, line_zero)
  local bufnr = entry.bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local target_line = math.max(1, (line_zero or 0) + 1)
  local last = vim.api.nvim_buf_line_count(bufnr)
  if target_line > last then target_line = last end

  -- Find a window showing this buffer (avoid tabpage churn)
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins == 0 then return end
  local win = wins[1]

  -- Suppress our own scroll re-emit for a beat
  entry.suppress_until = vim.loop.hrtime() + 220e6   -- 220ms in ns

  local cur = vim.api.nvim_win_get_cursor(win)
  if cur[1] ~= target_line then
    vim.api.nvim_win_set_cursor(win, { target_line, 0 })
    -- Center-ish scroll for pleasant UX
    vim.api.nvim_win_call(win, function() vim.cmd('normal! zz') end)
  end
end

function M.is_active(bufnr) return active[bufnr] ~= nil end

function M.start(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if active[bufnr] then
    log.info('preview already running for this buffer')
    return
  end
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == '' then
    log.warn('buffer has no filename; save it first')
    return
  end
  local dir = vim.fn.fnamemodify(filepath, ':p:h')
  local id  = make_id(bufnr)
  local opts = config.get().markdown

  server.ensure_started(function(ok, err)
    if not ok then log.error('server failed:', err); return end

    server.post('/nvim/register', {
      id       = id,
      mode     = 'markdown',
      filepath = filepath,
      dir      = dir,
      content  = buf_content(bufnr),
      bibPath  = auto_bib(dir),
    })

    -- Give the server a beat to register before browser attaches.
    vim.defer_fn(function()
      browser.open(id, server.url('/preview/md/' .. id))
    end, 150)
  end)

  local aug = vim.api.nvim_create_augroup('owl_md_' .. bufnr, { clear = true })
  local timer = vim.loop.new_timer()

  local function schedule_update()
    if not timer then return end
    timer:stop()
    timer:start(80, 0, vim.schedule_wrap(function()
      local e = active[bufnr]
      if e then push_update(bufnr, e) end
    end))
  end

  local trigger = opts.trigger == 'save' and { 'BufWritePost' } or { 'TextChanged', 'TextChangedI' }
  vim.api.nvim_create_autocmd(trigger, {
    group = aug, buffer = bufnr,
    callback = schedule_update,
  })

  if opts.scroll_sync then
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
      group = aug, buffer = bufnr,
      callback = function()
        local e = active[bufnr]
        if e then push_scroll(e) end
      end,
    })
  end

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufUnload' }, {
    group = aug, buffer = bufnr,
    callback = function() M.stop(bufnr) end,
  })

  local entry = { id = id, augroup = aug, timer = timer, filepath = filepath, bufnr = bufnr }
  active[bufnr] = entry

  -- Subscribe to server events (scroll from browser)
  entry.unsub = server.on_event(id, function(evt)
    if evt.type == 'scroll' then on_browser_scroll(entry, evt.line) end
  end)

  log.info('markdown preview started for', filepath)
end

function M.stop(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local entry = active[bufnr]
  if not entry then return end
  pcall(vim.api.nvim_del_augroup_by_id, entry.augroup)
  if entry.timer then entry.timer:stop(); entry.timer:close() end
  if entry.unsub then entry.unsub() end
  server.post('/nvim/unregister', { id = entry.id })
  browser.close(entry.id)
  active[bufnr] = nil
  log.info('markdown preview stopped')
end

function M.stop_all()
  for bufnr in pairs(active) do M.stop(bufnr) end
end

return M
