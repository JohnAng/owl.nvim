// Unit tests for the markdown rendering pipeline.
// Run with: cd server && npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';

const HERE      = dirname(fileURLToPath(import.meta.url));
const FIXTURES  = join(HERE, '..', 'fixtures');
const SERVER    = join(HERE, '..', '..', 'server');
// createRequire anchored at server/package.json so nested deps resolve.
const require   = createRequire(join(SERVER, 'package.json'));
const render    = require(join(SERVER, 'src', 'render.js'));
const bib       = require(join(SERVER, 'src', 'bib.js'));

const md = (src, opts = {}) => render.markdown(src, opts);

test('renders basic headings and paragraphs', () => {
  const html = md('# Hi\n\nA paragraph.\n');
  assert.match(html, /<h1[^>]*>Hi<\/h1>/);
  assert.match(html, /<p[^>]*>A paragraph\.<\/p>/);
});

test('data-line attributes are injected for scroll-sync', () => {
  const html = md('# A\n\nSecond paragraph on line 2.\n');
  assert.match(html, /data-line="0"/);
  assert.match(html, /data-line="2"/);
  // owl-line class piggybacks on every block open
  assert.match(html, /class="[^"]*owl-line/);
});

test('renders inline math via KaTeX', () => {
  const html = md('inline $a^2 + b^2 = c^2$ here\n');
  assert.match(html, /class="katex"/);
});

test('renders block math via KaTeX', () => {
  const html = md('$$\n\\int_0^1 x\\,dx = \\frac{1}{2}\n$$\n');
  assert.match(html, /class="katex-display"/);
});

test('renders fenced code with hljs classes', () => {
  const html = md('```python\ndef f():\n    return 1\n```\n');
  assert.match(html, /class="hljs"/);
  assert.match(html, /class="language-python"/);
});

test('mermaid fence becomes <pre class="mermaid">', () => {
  const html = md('```mermaid\ngraph LR; A --> B\n```\n');
  assert.match(html, /<pre class="mermaid">/);
  assert.match(html, /A --&gt; B/);
});

test('task list checkboxes are input elements', () => {
  const html = md('- [x] done\n- [ ] todo\n');
  // task-lists plugin emits attrs in inconsistent order; check both flavours
  assert.match(html, /<input[^>]*checked[^>]*type="checkbox"|<input[^>]*type="checkbox"[^>]*checked/);
  // There should be at least one unchecked checkbox too
  assert.match(html, /class="task-list-item-checkbox"/);
  assert.match(html, /task-list-item enabled">[^<]*<label><input class="task-list-item-checkbox"type="checkbox"/);
});

test('footnotes render with backrefs', () => {
  const html = md('Text[^n]\n\n[^n]: A note.\n');
  assert.match(html, /class="footnote-ref"/);
  assert.match(html, /class="footnote-item"/);
});

test('container-style callout: ::: note ... :::', () => {
  const html = md(':::note\ninside\n:::\n');
  assert.match(html, /class="callout callout-note"/);
  assert.match(html, /callout-title/);
});

test('GitHub-alert callout via > [!warning]', () => {
  const html = md('> [!warning]\n> Careful now.\n');
  assert.match(html, /callout callout-warning|<blockquote[^>]*class="[^"]*callout/);
});

test('wikilinks are rewritten to anchor with wiki: scheme', () => {
  const html = md('See [[foo]] and [[bar|Bar Label]].\n');
  assert.match(html, /href="wiki:foo"/);
  assert.match(html, /href="wiki:bar"/);
  assert.match(html, />Bar Label</);
});

test('citations become superscript refs when bib is provided', () => {
  const bibPath = join(FIXTURES, 'sample.bib');
  const bibliography = bib.load(bibPath);
  const html = md('See [@knuth1984] and [@lamport1986].\n', { bibliography });
  assert.match(html, /class="citation"/);
  // Two distinct references numbered 1, 2 appear in output
  assert.match(html, /id="cite-1"/);
  assert.match(html, /id="cite-2"/);
  // References section is appended
  assert.match(html, /class="references"/);
  assert.match(html, /Donald E\. Knuth/);
  assert.match(html, /Leslie Lamport/);
});

test('unknown citation keys are left as literal text', () => {
  const bibliography = new Map();
  const html = md('See [@nowhere].\n', { bibliography });
  assert.match(html, /\[@nowhere\]/);
  assert.doesNotMatch(html, /class="citation"/);
});

test('tables render with proper structure', () => {
  const html = md('| A | B |\n|---|---|\n| 1 | 2 |\n');
  assert.match(html, /<table[^>]*>[\s\S]*<thead>[\s\S]*<th>A<\/th>[\s\S]*<th>B<\/th>[\s\S]*<td>1<\/td>[\s\S]*<td>2<\/td>/);
});

test('no citation section when bib is null/empty', () => {
  const html = md('Just some text.\n');
  assert.doesNotMatch(html, /class="references"/);
});

test('markdown-it typographer replaces -- with –', () => {
  const html = md('foo -- bar\n');
  assert.match(html, /–/);
});
