// owl.nvim client — WebSocket bridge to the Neovim plugin.
// Handles: initial state, live updates (markdown), scroll-sync, PDF hot-reload.

(function () {
  'use strict';

  // Buffer id encoded in the URL path: /preview/md/<id> or /preview/tex/<id>
  const parts = location.pathname.split('/').filter(Boolean);
  // ['preview', 'md'|'tex', '<id>']
  const mode = parts[1];
  const id   = parts[2];

  const $conn   = document.getElementById('conn-dot');
  const $status = document.getElementById('status');
  const $title  = document.getElementById('title');

  const setStatus = (text, pulse) => {
    if (!$status) return;
    $status.textContent = text || '';
    if (pulse) { $status.classList.add('pulse'); setTimeout(() => $status.classList.remove('pulse'), 800); }
  };
  const setConn = (state) => {
    if (!$conn) return;
    $conn.classList.remove('connected', 'connecting');
    if (state) $conn.classList.add(state);
  };

  // --------------------------------------------------------------------------
  // Markdown mode
  // --------------------------------------------------------------------------
  if (mode === 'md') {
    const $content = document.getElementById('content');
    let renderTimer = 0;
    let pendingContent = null;
    let lastRender = 0;

    const requestRender = async (content) => {
      pendingContent = content;
      clearTimeout(renderTimer);
      renderTimer = setTimeout(async () => {
        const body = pendingContent;
        pendingContent = null;
        try {
          const res = await fetch('/render/md', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ content: body }),
          });
          const json = await res.json();
          if (json.html !== undefined) {
            $content.innerHTML = json.html;
            initMermaid();
            setStatus(`updated ${new Date().toLocaleTimeString()}`, true);
          } else if (json.error) {
            setStatus('render error: ' + json.error);
          }
        } catch (e) {
          setStatus('render failed: ' + e.message);
        }
        lastRender = Date.now();
      }, 80);
    };

    const initMermaid = () => {
      if (window.mermaid && !initMermaid._done) {
        window.mermaid.initialize({ startOnLoad: false, theme: 'dark' });
        initMermaid._done = true;
      }
      if (window.mermaid) {
        try { window.mermaid.run({ querySelector: 'pre.mermaid' }); } catch {}
      }
    };

    const scrollToLine = (line) => {
      // Find nearest previous data-line
      const els = $content.querySelectorAll('[data-line]');
      let target = null;
      for (const el of els) {
        const l = Number(el.getAttribute('data-line'));
        if (l <= line) target = el;
        else break;
      }
      $content.querySelectorAll('.owl-cursor').forEach(e => e.classList.remove('owl-cursor'));
      if (target) {
        target.classList.add('owl-cursor');
        target.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    };

    connectWS({
      onInit: (msg) => {
        if (msg.mode === 'markdown') requestRender(msg.content);
        setStatus('connected');
      },
      onUpdate: (msg) => requestRender(msg.content),
      onScroll: (msg) => scrollToLine(msg.line || 0),
    });
  }

  // --------------------------------------------------------------------------
  // LaTeX mode — hot-reload the iframe src
  // --------------------------------------------------------------------------
  if (mode === 'tex') {
    const $iframe = document.getElementById('pdf');

    const reloadPdf = () => {
      $iframe.src = `/pdf/${id}?t=${Date.now()}`;
      setStatus(`reloaded ${new Date().toLocaleTimeString()}`, true);
    };

    connectWS({
      onInit: (msg) => {
        if (msg.pdfUrl) $iframe.src = msg.pdfUrl;
        setStatus('connected');
      },
      onReloadPdf: () => reloadPdf(),
    });
  }

  // --------------------------------------------------------------------------
  // WebSocket with automatic reconnect
  // --------------------------------------------------------------------------
  function connectWS(handlers) {
    let ws = null;
    let attempt = 0;

    function open() {
      setConn('connecting');
      ws = new WebSocket(`ws://${location.host}/ws`);

      ws.addEventListener('open', () => {
        attempt = 0;
        setConn('connected');
        ws.send(JSON.stringify({ type: 'attach', id, role: 'client' }));
      });

      ws.addEventListener('message', (ev) => {
        let msg = null;
        try { msg = JSON.parse(ev.data); } catch { return; }
        switch (msg.type) {
          case 'init':       handlers.onInit       && handlers.onInit(msg);       break;
          case 'update':     handlers.onUpdate     && handlers.onUpdate(msg);     break;
          case 'scroll':     handlers.onScroll     && handlers.onScroll(msg);     break;
          case 'reload-pdf': handlers.onReloadPdf  && handlers.onReloadPdf(msg);  break;
        }
      });

      ws.addEventListener('close', () => {
        setConn(null);
        setStatus('disconnected — reconnecting');
        const delay = Math.min(4000, 500 * 2 ** attempt++);
        setTimeout(open, delay);
      });

      ws.addEventListener('error', () => { try { ws.close(); } catch {} });
    }

    open();
  }
})();
