// Markdown rendering pipeline.
// SSR HTML with source-line data attributes so the client can do scroll-sync.

'use strict';

const MarkdownIt = require('markdown-it');
const footnote   = require('markdown-it-footnote');
const taskLists  = require('markdown-it-task-lists');
const deflist    = require('markdown-it-deflist');
const mark       = require('markdown-it-mark');
const emojiMod   = require('markdown-it-emoji');
const container  = require('markdown-it-container');
const attrs      = require('markdown-it-attrs');
const katex      = require('@vscode/markdown-it-katex').default;
const hljs       = require('highlight.js');

// Some markdown-it plugins expose { default } under ESM, others don't.
const emoji = emojiMod.full || emojiMod;

// -----------------------------------------------------------------------------
// Base instance with source-line tracking
// -----------------------------------------------------------------------------
function baseMd() {
  const md = new MarkdownIt({
    html: true,
    linkify: true,
    typographer: true,
    breaks: false,
    highlight(code, lang) {
      if (lang && hljs.getLanguage(lang)) {
        try {
          return `<pre class="hljs"><code class="language-${lang}">${
            hljs.highlight(code, { language: lang, ignoreIllegals: true }).value
          }</code></pre>`;
        } catch {}
      }
      return `<pre class="hljs"><code>${md.utils.escapeHtml(code)}</code></pre>`;
    },
  });

  md.use(footnote);
  md.use(taskLists, { enabled: true, label: true });
  md.use(deflist);
  md.use(mark);
  md.use(emoji);
  md.use(attrs);
  md.use(katex, { throwOnError: false, output: 'html' });

  // Callouts: > [!note], > [!warning], > [!tip], > [!info]
  const CALLOUT_TYPES = ['note', 'tip', 'warning', 'info', 'important', 'caution'];
  for (const kind of CALLOUT_TYPES) {
    md.use(container, kind, {
      validate: (params) => params.trim() === kind,
      render(tokens, idx) {
        if (tokens[idx].nesting === 1) {
          return `<div class="callout callout-${kind}"><div class="callout-title">${kind}</div>\n`;
        }
        return `</div>\n`;
      },
    });
  }

  // Mermaid code fences -> pass through as <pre class="mermaid">
  const defaultFence = md.renderer.rules.fence.bind(md.renderer.rules);
  md.renderer.rules.fence = function (tokens, idx, options, env, self) {
    const token = tokens[idx];
    if (token.info.trim() === 'mermaid') {
      return `<pre class="mermaid">${md.utils.escapeHtml(token.content)}</pre>\n`;
    }
    return defaultFence(tokens, idx, options, env, self);
  };

  // Wikilinks: [[name]] -> anchor
  md.core.ruler.after('inline', 'wikilink', (state) => {
    for (const tok of state.tokens) {
      if (tok.type !== 'inline') continue;
      for (const child of tok.children || []) {
        if (child.type !== 'text') continue;
        if (!child.content.includes('[[')) continue;
        child.content = child.content.replace(
          /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g,
          (_, target, label) => `[${label || target}](wiki:${encodeURIComponent(target)})`
        );
      }
    }
  });

  // GitHub-alerts syntax: > [!NOTE] on first line of blockquote
  md.core.ruler.after('block', 'gh-alerts', (state) => {
    for (let i = 0; i < state.tokens.length; i++) {
      const t = state.tokens[i];
      if (t.type !== 'blockquote_open') continue;
      const paragraph = state.tokens[i + 2];
      if (!paragraph || paragraph.type !== 'inline') continue;
      const m = /^\[!(NOTE|TIP|WARNING|IMPORTANT|CAUTION|INFO)\]\s*$/i.exec(paragraph.content.split('\n')[0] || '');
      if (!m) continue;
      const kind = m[1].toLowerCase();
      t.attrJoin('class', `callout callout-${kind}`);
      // strip the first line so it doesn't render literally
      paragraph.content = paragraph.content.replace(/^\[![^\]]+\]\s*\n?/i, '');
      if (paragraph.children && paragraph.children.length) {
        paragraph.children[0].content = paragraph.children[0].content.replace(/^\[![^\]]+\]\s*\n?/i, '');
      }
    }
  });

  // Inject data-line attributes for scroll-sync
  const injectLine = (tokens) => {
    for (const tok of tokens) {
      if (tok.map && tok.level === 0 && tok.type.endsWith('_open')) {
        tok.attrJoin('class', 'owl-line');
        tok.attrSet('data-line', String(tok.map[0]));
      }
    }
  };
  md.core.ruler.push('owl-inject-lines', (state) => injectLine(state.tokens));

  return md;
}

const md = baseMd();

// -----------------------------------------------------------------------------
// Citations
// Inline `[@key]` -> superscript numbered anchor. Bibliography rendered at the end.
// -----------------------------------------------------------------------------
function processCitations(source, bibliography) {
  if (!bibliography || bibliography.size === 0) return { source, references: [] };
  const cited = new Map();
  const nextIdx = () => cited.size + 1;

  const patched = source.replace(/\[@([A-Za-z0-9_\-:.+]+)\]/g, (full, key) => {
    if (!bibliography.has(key)) return full;
    if (!cited.has(key)) cited.set(key, nextIdx());
    const n = cited.get(key);
    return `[<sup class="citation" id="cite-${n}"><a href="#ref-${n}">${n}</a></sup>]`;
  });

  const references = [];
  for (const [key, n] of cited) {
    references.push({ n, key, entry: bibliography.get(key) });
  }
  references.sort((a, b) => a.n - b.n);
  return { source: patched, references };
}

function renderReferences(refs) {
  if (!refs.length) return '';
  const items = refs.map(({ n, entry }) => {
    const fields = entry.fields || {};
    const author = fields.author || '';
    const title  = fields.title  || '';
    const year   = fields.year   || '';
    const journal = fields.journal || fields.booktitle || '';
    const parts = [];
    if (author) parts.push(escapeHtml(author));
    if (year)   parts.push(`(${escapeHtml(year)})`);
    if (title)  parts.push(`<em>${escapeHtml(title)}</em>`);
    if (journal) parts.push(escapeHtml(journal));
    return `<li id="ref-${n}"><span class="ref-num">${n}.</span> ${parts.join('. ')}.</li>`;
  }).join('\n');
  return `\n<section class="references"><h2>References</h2><ol>${items}</ol></section>\n`;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, ch => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[ch]));
}

// -----------------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------------
exports.markdown = function (source, opts = {}) {
  const { references: _, source: sourceWithCitations } = { source, references: [] };
  const { source: src, references } = processCitations(source, opts.bibliography);
  const html = md.render(src);
  return html + renderReferences(references);
};
