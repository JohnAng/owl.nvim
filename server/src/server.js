#!/usr/bin/env node
// owl.nvim preview server
// Serves markdown live-preview and coordinates LaTeX PDF hot-reload.
// Communicates with the nvim plugin via WebSocket.

'use strict';

const path    = require('path');
const fs      = require('fs');
const http    = require('http');
const express = require('express');
const { WebSocketServer } = require('ws');
const chokidar = require('chokidar');
const render   = require('./render');
const bib      = require('./bib');

// -----------------------------------------------------------------------------
// args: --port 0 (auto) --host 127.0.0.1
// -----------------------------------------------------------------------------
function parseArgs(argv) {
  const out = { port: 0, host: '127.0.0.1' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if ((a === '--port' || a === '-p') && argv[i+1]) { out.port = Number(argv[++i]) || 0; }
    else if ((a === '--host' || a === '-h') && argv[i+1]) { out.host = argv[++i]; }
  }
  return out;
}
const { port: PORT, host: HOST } = parseArgs(process.argv.slice(2));

// -----------------------------------------------------------------------------
// Session state (in-memory, single-process)
// -----------------------------------------------------------------------------
const state = {
  // Buffer id -> { mode: 'markdown'|'latex', filepath, dir, content, bibPath, watcher }
  buffers: new Map(),
  // WS clients per buffer id
  clients: new Map(), // id -> Set<WebSocket>
};

// -----------------------------------------------------------------------------
// Express app
// -----------------------------------------------------------------------------
const app = express();
app.use(express.json({ limit: '10mb' }));
app.use('/static', express.static(path.join(__dirname, '..', 'public'), { maxAge: '1d' }));

// Serve vendored CSS/JS from node_modules so the client works offline
// once `npm install` has been run.
const NM = path.join(__dirname, '..', 'node_modules');
function tryFile(res, ...candidates) {
  for (const c of candidates) if (fs.existsSync(c)) return res.sendFile(c);
  res.status(404).send('asset not found (did you run npm install?)');
}
app.get('/static/assets/katex.min.css', (req, res) =>
  tryFile(res, path.join(NM, 'katex', 'dist', 'katex.min.css')));
app.get('/static/assets/katex-fonts/:f', (req, res) =>
  tryFile(res, path.join(NM, 'katex', 'dist', 'fonts', req.params.f)));
app.get('/static/assets/hljs.css', (req, res) =>
  tryFile(res,
    path.join(NM, 'highlight.js', 'styles', 'atom-one-dark.css'),
    path.join(NM, 'highlight.js', 'styles', 'github-dark.css')));
app.get('/static/assets/mermaid.min.js', (req, res) =>
  tryFile(res, path.join(NM, 'mermaid', 'dist', 'mermaid.min.js')));

// Landing / router page
app.get('/', (req, res) => {
  res.redirect('/static/index.html');
});

// Markdown preview page (per buffer id)
app.get('/preview/md/:id', (req, res) => {
  const buf = state.buffers.get(req.params.id);
  if (!buf) return res.status(404).send('unknown buffer');
  res.sendFile(path.join(__dirname, '..', 'public', 'markdown.html'));
});

// LaTeX preview page (per buffer id) — serves the compiled PDF via /pdf/:id
app.get('/preview/tex/:id', (req, res) => {
  const buf = state.buffers.get(req.params.id);
  if (!buf) return res.status(404).send('unknown buffer');
  res.sendFile(path.join(__dirname, '..', 'public', 'latex.html'));
});

// Serve the compiled PDF for a buffer id
app.get('/pdf/:id', (req, res) => {
  const buf = state.buffers.get(req.params.id);
  if (!buf || buf.mode !== 'latex') return res.status(404).send('no pdf');
  const pdfPath = buf.pdfPath;
  if (!pdfPath || !fs.existsSync(pdfPath)) return res.status(404).send('pdf not compiled yet');
  res.setHeader('Cache-Control', 'no-store');
  res.sendFile(pdfPath);
});

// Return rendered markdown as JSON
app.post('/render/md', (req, res) => {
  try {
    const { content, dir, bibPath } = req.body || {};
    const html = render.markdown(content || '', {
      baseDir: dir,
      bibliography: bibPath ? bib.load(bibPath) : null,
    });
    res.json({ html });
  } catch (err) {
    res.status(500).json({ error: String(err.message || err) });
  }
});

// Health probe (used by nvim on startup)
app.get('/health', (req, res) => res.json({ ok: true, pid: process.pid }));

// -----------------------------------------------------------------------------
// HTTP + WebSocket
// -----------------------------------------------------------------------------
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

// Browser clients only. All nvim -> server traffic uses HTTP POST /nvim/*.
wss.on('connection', (ws, req) => {
  ws._owlId = null;

  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch { return; }
    if (!msg || typeof msg.type !== 'string') return;

    if (msg.type === 'attach') {
      ws._owlId = msg.id;
      if (!state.clients.has(msg.id)) state.clients.set(msg.id, new Set());
      state.clients.get(msg.id).add(ws);
      const buf = state.buffers.get(msg.id);
      if (buf) sendInitial(ws, buf);
    } else if (msg.type === 'browser-scroll' && ws._owlId) {
      // Browser tells us the user scrolled to a line. Emit an event line
      // on stdout so the nvim plugin (which owns the server process) can
      // read it via jobstart on_stdout and move the cursor.
      const line = Math.max(0, parseInt(msg.line, 10) || 0);
      process.stdout.write(`OWL_EVENT type=scroll id=${ws._owlId} line=${line}\n`);
    }
  });

  ws.on('close', () => {
    if (ws._owlId) {
      const set = state.clients.get(ws._owlId);
      if (set) { set.delete(ws); if (set.size === 0) state.clients.delete(ws._owlId); }
    }
  });
});

// -----------------------------------------------------------------------------
// Neovim control endpoints (HTTP POST)
// -----------------------------------------------------------------------------
app.post('/nvim/register', (req, res) => {
  registerBuffer(req.body || {});
  res.json({ ok: true });
});

app.post('/nvim/update', (req, res) => {
  const { id, content, cursor } = req.body || {};
  const buf = state.buffers.get(id);
  if (!buf) return res.status(404).json({ ok: false, error: 'not registered' });
  buf.content = content;
  buf.cursor  = cursor;
  broadcast(id, { type: 'update', content: buf.content, cursor: buf.cursor, mode: buf.mode });
  res.json({ ok: true });
});

app.post('/nvim/scroll', (req, res) => {
  const { id, line } = req.body || {};
  broadcast(id, { type: 'scroll', line });
  res.json({ ok: true });
});

app.post('/nvim/reload-pdf', (req, res) => {
  const { id } = req.body || {};
  broadcast(id, { type: 'reload-pdf' });
  res.json({ ok: true });
});

app.post('/nvim/unregister', (req, res) => {
  const { id } = req.body || {};
  unregisterBuffer(id);
  res.json({ ok: true });
});

function sendInitial(ws, buf) {
  ws.send(JSON.stringify({
    type: 'init',
    mode: buf.mode,
    content: buf.content || '',
    cursor: buf.cursor || 0,
    pdfUrl: buf.mode === 'latex' ? `/pdf/${buf.id}?t=${Date.now()}` : null,
  }));
}

function broadcast(id, obj, exclude) {
  const set = state.clients.get(id);
  if (!set) return;
  const payload = JSON.stringify(obj);
  for (const ws of set) {
    if (ws === exclude) continue;
    if (ws.readyState === 1) ws.send(payload);
  }
}

// -----------------------------------------------------------------------------
// Buffer registration + file-watching (for LaTeX PDF hot-reload)
// -----------------------------------------------------------------------------
function registerBuffer(msg) {
  const { id, mode, filepath, dir, content, bibPath, pdfPath } = msg;
  if (!id || !mode) return;

  unregisterBuffer(id);

  const buf = {
    id, mode, filepath, dir: dir || (filepath ? path.dirname(filepath) : process.cwd()),
    content: content || '', bibPath: bibPath || null, pdfPath: pdfPath || null,
    watcher: null, cursor: 0,
  };

  // If LaTeX, watch the PDF file for changes -> broadcast reload
  if (mode === 'latex' && pdfPath) {
    buf.watcher = chokidar.watch(pdfPath, {
      ignoreInitial: true, awaitWriteFinish: { stabilityThreshold: 200, pollInterval: 100 },
    });
    buf.watcher.on('add',    () => broadcast(id, { type: 'reload-pdf' }));
    buf.watcher.on('change', () => broadcast(id, { type: 'reload-pdf' }));
  }

  state.buffers.set(id, buf);
}

function unregisterBuffer(id) {
  const buf = state.buffers.get(id);
  if (!buf) return;
  if (buf.watcher) try { buf.watcher.close(); } catch {}
  state.buffers.delete(id);
  const set = state.clients.get(id);
  if (set) {
    for (const ws of set) try { ws.close(); } catch {}
    state.clients.delete(id);
  }
}

// -----------------------------------------------------------------------------
// Start
// -----------------------------------------------------------------------------
server.listen(PORT, HOST, () => {
  const addr = server.address();
  // Line format is parsed by the nvim plugin.
  process.stdout.write(`OWL_READY host=${addr.address} port=${addr.port} pid=${process.pid}\n`);
});

// Graceful shutdown
function shutdown(sig) {
  for (const id of state.buffers.keys()) unregisterBuffer(id);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 500).unref();
}
process.on('SIGINT',  () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
