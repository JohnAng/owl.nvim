// Integration tests for the preview server.
// Spawns a real node process, hits the routes, and asserts the WS flow.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { setTimeout as sleep } from 'node:timers/promises';
import { createRequire } from 'node:module';

const HERE     = dirname(fileURLToPath(import.meta.url));
const SERVER_DIR = join(HERE, '..', '..', 'server');
const SERVER    = join(SERVER_DIR, 'src', 'server.js');
// Load 'ws' from the server's node_modules (test files live outside).
const require   = createRequire(join(SERVER_DIR, 'package.json'));
const { WebSocket } = require('ws');

let child;
let baseUrl;
let wsUrl;

before(async () => {
  await new Promise((resolve, reject) => {
    child = spawn('node', [SERVER, '--port', '0'], { stdio: ['ignore', 'pipe', 'pipe'] });
    const t = setTimeout(() => reject(new Error('server did not become ready in 5s')), 5000);
    child.stdout.on('data', (buf) => {
      const line = buf.toString();
      const m = line.match(/OWL_READY host=(\S+) port=(\d+)/);
      if (m) {
        baseUrl = `http://${m[1]}:${m[2]}`;
        wsUrl   = `ws://${m[1]}:${m[2]}/ws`;
        clearTimeout(t);
        resolve();
      }
    });
    child.stderr.on('data', (d) => process.stderr.write('[server] ' + d));
    child.on('exit', (code) => {
      if (!baseUrl) reject(new Error('server exited before ready with code ' + code));
    });
  });
});

after(() => { if (child) { child.kill('SIGTERM'); } });

async function post(path, body) {
  const res = await fetch(baseUrl + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}

async function get(path) {
  const res = await fetch(baseUrl + path);
  return { status: res.status, text: await res.text() };
}

function openWS(id) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const messages = [];
    ws.on('open', () => {
      ws.send(JSON.stringify({ type: 'attach', id, role: 'client' }));
    });
    ws.on('message', (buf) => { messages.push(JSON.parse(buf.toString())); });
    ws.on('error', reject);
    // Give it a moment to attach + receive initial message
    setTimeout(() => resolve({ ws, messages }), 300);
  });
}

// ---------------------------------------------------------------------------
test('GET /health returns { ok: true }', async () => {
  const r = await get('/health');
  assert.equal(r.status, 200);
  const j = JSON.parse(r.text);
  assert.equal(j.ok, true);
  assert.ok(typeof j.pid === 'number');
});

test('POST /render/md returns HTML', async () => {
  const r = await post('/render/md', { content: '# Hi\n' });
  assert.equal(r.status, 200);
  assert.match(r.body.html, /<h1[^>]*>Hi<\/h1>/);
});

test('POST /nvim/register + /nvim/update broadcasts to WS clients', async () => {
  const id = 'test-md-1';
  await post('/nvim/register', { id, mode: 'markdown', content: '# initial' });

  const { ws, messages } = await openWS(id);
  // initial 'init' message
  assert.ok(messages.length >= 1);
  const init = messages.find(m => m.type === 'init');
  assert.ok(init, 'expected an init message');
  assert.equal(init.mode, 'markdown');
  assert.equal(init.content, '# initial');

  // Send an update from "nvim"
  await post('/nvim/update', { id, content: '# updated', cursor: 3 });
  await sleep(150);
  const upd = messages.find(m => m.type === 'update');
  assert.ok(upd, 'expected an update broadcast');
  assert.equal(upd.content, '# updated');

  ws.close();
  await post('/nvim/unregister', { id });
});

test('POST /nvim/scroll broadcasts scroll to WS clients', async () => {
  const id = 'test-md-2';
  await post('/nvim/register', { id, mode: 'markdown', content: 'x' });
  const { ws, messages } = await openWS(id);

  await post('/nvim/scroll', { id, line: 42 });
  await sleep(150);
  const scroll = messages.find(m => m.type === 'scroll');
  assert.ok(scroll, 'expected scroll broadcast');
  assert.equal(scroll.line, 42);

  ws.close();
  await post('/nvim/unregister', { id });
});

test('WS browser-scroll message emits OWL_EVENT to server stdout', async () => {
  const id = 'test-md-3';
  await post('/nvim/register', { id, mode: 'markdown', content: 'x' });

  // Buffer stdout to catch the OWL_EVENT line
  let stdoutBuf = '';
  const listener = (buf) => { stdoutBuf += buf.toString(); };
  child.stdout.on('data', listener);

  const ws = new WebSocket(wsUrl);
  await new Promise((r) => ws.on('open', r));
  ws.send(JSON.stringify({ type: 'attach', id, role: 'client' }));
  await sleep(100);
  ws.send(JSON.stringify({ type: 'browser-scroll', line: 7 }));
  await sleep(200);

  child.stdout.off('data', listener);
  ws.close();
  await post('/nvim/unregister', { id });

  assert.match(stdoutBuf, /OWL_EVENT type=scroll id=test-md-3 line=7/);
});

test('LaTeX PDF change fires reload-pdf broadcast', async () => {
  const id = 'test-tex-1';
  const dir = mkdtempSync(join(tmpdir(), 'owl-test-'));
  const pdfPath = join(dir, 'x.pdf');
  writeFileSync(pdfPath, 'PDF-DATA-v1');

  await post('/nvim/register', { id, mode: 'latex', pdfPath, filepath: join(dir, 'x.tex') });

  const { ws, messages } = await openWS(id);
  // Trigger a real file change so chokidar fires
  await sleep(200);
  writeFileSync(pdfPath, 'PDF-DATA-v2');
  await sleep(500);

  const reload = messages.find(m => m.type === 'reload-pdf');
  assert.ok(reload, 'expected reload-pdf broadcast from chokidar');

  ws.close();
  await post('/nvim/unregister', { id });
});
