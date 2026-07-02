# owl.nvim

**Universal, high-performance Markdown & LaTeX live preview for Neovim** — one plugin, one keymap, cross-platform.

## Why

Existing markdown/LaTeX previewers in the Neovim ecosystem tend to:
- Focus on one format only (markdown OR LaTeX)
- Require substantial per-machine setup
- Bring niche dependencies (Deno, browser controllers, terminal image protocols)
- Feel bolted-on rather than integrated

owl.nvim gives you **one command (`:OwlPreview`)** that:
- **For markdown**: opens a live browser preview with KaTeX math, Mermaid diagrams, syntax-highlighted code, footnotes, callouts, task lists, wikilinks, and citations resolved from a sibling `.bib` file
- **For LaTeX**: runs `latexmk -pvc` in the background, opens your platform's best PDF viewer (Sumatra / zathura / Skim / sioyek) with SyncTeX enabled, and streams compile errors as native Neovim diagnostics

Live scroll-sync between editor cursor and preview (markdown), forward SyncTeX (LaTeX), auto-reload, incremental updates. Single shared Node process — one port, one browser tab, low RAM.

## Requirements

- **Neovim >= 0.10**
- **Node.js >= 18** — powers the bundled preview server
- **Markdown**: nothing else (all rendering deps installed via `build` hook)
- **LaTeX**: a TeX distribution with `latexmk` and your chosen engine (`xelatex` default), plus at least one PDF viewer

### Recommended PDF viewers by OS

| OS | Viewer | Install |
|----|--------|---------|
| Windows | **Sumatra PDF** | `winget install SumatraPDF.SumatraPDF` |
| Linux | **zathura** + mupdf plugin | `sudo apt-get install zathura zathura-pdf-mupdf` |
| macOS | **Skim** | `brew install --cask skim` |
| Any (cross-platform) | **sioyek** | https://github.com/ahrm/sioyek/releases |

If none are installed, owl.nvim falls back to browser-based `pdf.js` (still works, minus SyncTeX).

## Install (lazy.nvim)

```lua
{
  'JohnAng/owl.nvim',
  build = function()
    local sep = package.config:sub(1, 1)
    if sep == '\\' then
      vim.fn.system({ 'powershell', '-ExecutionPolicy', 'Bypass', '-File', 'scripts/postinstall.ps1' })
    else
      vim.fn.system({ 'bash', 'scripts/postinstall.sh' })
    end
  end,
  ft = { 'markdown', 'md', 'quarto', 'rmarkdown', 'tex', 'latex' },
  keys = {
    { '<leader>op', function() require('owl').toggle() end, desc = 'owl: toggle preview' },
  },
  opts = {
    -- see :help owl-config for the full list
  },
}
```

## Quick start

```
:e paper.md              # or paper.tex
<leader>op               # start preview
<leader>op               # again to stop
```

Run `:checkhealth owl` to verify prerequisites per OS.

## Commands

| Command | What it does |
|---------|--------------|
| `:OwlPreview` | Start preview for current buffer |
| `:OwlStop` | Stop preview for current buffer |
| `:OwlToggle` | Toggle preview |
| `:OwlStopAll` | Stop everything, shut server down |
| `:OwlSyncTexHere` | Force forward-SyncTeX to current cursor position |
| `:OwlServerUrl` | Print server URL |

## Configuration

Defaults — pass overrides to `setup({...})`.

```lua
require('owl').setup({
  server = { host = '127.0.0.1', port = 0, node = 'node' },
  browser = {
    cmd = 'auto',      -- 'auto' | 'start' | 'open' | 'xdg-open' | 'wslview'
    override = nil,    -- e.g. 'brave.exe', 'firefox'
    new_window = false,
  },
  markdown = {
    trigger = 'live',  -- 'live' (TextChanged) | 'save' (BufWritePost)
    scroll_sync = true,
    auto_bib = true,   -- pick up a *.bib next to the .md
    bib = nil,         -- explicit override
  },
  latex = {
    viewer = 'auto',   -- 'auto' | 'browser' | 'sumatra' | 'zathura' | 'skim' | 'sioyek'
    engine = 'xelatex',
    synctex = true,
    aux_dir = '.owl-build',
  },
  diagnostics = { enabled = true, signs = true, virtual_text = { spacing = 2, prefix = '' } },
  log_level = 'info',
  auto_shutdown = true,
})
```

## Markdown features

- **Math**: `$inline$`, `$$block$$` via KaTeX (SSR, fast)
- **Diagrams**: ```` ```mermaid ```` fenced blocks
- **Code**: highlight.js, all common languages
- **Footnotes**: `[^1]`
- **Task lists**: `- [ ]` / `- [x]`
- **Tables**: GFM
- **Callouts**: `> [!note]` blockquote-style OR `::: note ... :::` container-style
- **Wikilinks**: `[[name]]` and `[[name|label]]`
- **Citations**: `[@key]` resolved from `sibling.bib` (auto-detected)
- **Emoji**: `:smile:`
- **Definition lists, strikethrough, attribute lists** — all supported

## LaTeX features

- Continuous compile via `latexmk -pvc`
- Auxiliary files isolated in `.owl-build/`
- Auto-reload PDF (viewer file-watch + browser iframe reload)
- Forward SyncTeX (source → PDF)
- Compile errors → native `vim.diagnostic` in the source buffer

## Architecture

```
Neovim  ──HTTP──▶  Node preview server  ──WS──▶  Browser / PDF viewer
   │                                              (+ native viewer via file-watch)
   └── latex module ── latexmk ─▶ PDF ────────────┘
```

The Node server is a single shared process for the whole Neovim session. All rendering deps (markdown-it, KaTeX, Mermaid, highlight.js) live in `node_modules/`, installed once by the plugin manager's `build` hook.

## License

MIT © 2026 JohnAng
