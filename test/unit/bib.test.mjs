// Unit tests for the BibTeX parser.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';

const HERE     = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(HERE, '..', 'fixtures');
const SERVER   = join(HERE, '..', '..', 'server');
const require  = createRequire(join(SERVER, 'package.json'));
const bib      = require(join(SERVER, 'src', 'bib.js'));

test('parses well-formed entries from a fixture', () => {
  const entries = bib.load(join(FIXTURES, 'sample.bib'));
  assert.equal(entries.size, 3);
  assert.ok(entries.has('knuth1984'));
  assert.ok(entries.has('lamport1986'));
});

test('extracts author and year from fields', () => {
  const entries = bib.load(join(FIXTURES, 'sample.bib'));
  const k = entries.get('knuth1984');
  assert.equal(k.fields.author, 'Donald E. Knuth');
  assert.equal(k.fields.year,   '1984');
});

test('strips outer braces from fields', () => {
  const entries = bib.load(join(FIXTURES, 'sample.bib'));
  const k = entries.get('knuth1984');
  // "The {TeX}book" -> outer braces stripped, inner {TeX} preserved
  assert.equal(k.fields.title, 'The {TeX}book');
});

test('captures entry type', () => {
  const entries = bib.load(join(FIXTURES, 'sample.bib'));
  assert.equal(entries.get('knuth1984').type, 'book');
  assert.equal(entries.get('lamport1986').type, 'article');
});

test('handles double-quoted values', () => {
  const text = '@article{k1, author = "Alice", title = "A title", year = 2020 }';
  const map = bib.parse(text);
  assert.equal(map.get('k1').fields.author, 'Alice');
  assert.equal(map.get('k1').fields.year, '2020');
});

test('ignores @string / @preamble / @comment entries', () => {
  const text = '@string{foo = "bar"}\n@article{k1, author = "A", }\n';
  const map = bib.parse(text);
  assert.ok(!map.has('foo'));
  assert.ok(map.has('k1'));
});

test('respects brace nesting inside values', () => {
  const text = '@article{k1, title = {a {nested {deep}} value}, }';
  const map = bib.parse(text);
  assert.equal(map.get('k1').fields.title, 'a {nested {deep}} value');
});

test('returns empty map on missing file', () => {
  const entries = bib.load('/no/such/file.bib');
  assert.equal(entries.size, 0);
});

test('skips %-comments', () => {
  const text = '% this is a comment\n@article{k1, author = {Bob}, }\n';
  const map = bib.parse(text);
  assert.equal(map.size, 1);
  assert.equal(map.get('k1').fields.author, 'Bob');
});
