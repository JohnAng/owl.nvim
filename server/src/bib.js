// Minimal BibTeX parser — enough for @article / @book / @inproceedings / @misc entries
// commonly used in academic markdown. Not a full spec implementation; ignores strings/macros.

'use strict';

const fs = require('fs');

function stripBraces(s) {
  s = s.trim();
  while (s.startsWith('{') && s.endsWith('}')) s = s.slice(1, -1).trim();
  if (s.startsWith('"') && s.endsWith('"')) s = s.slice(1, -1).trim();
  return s;
}

function parseEntries(text) {
  const entries = new Map();
  // Strip comments (lines starting with %)
  text = text.replace(/^\s*%[^\n]*$/gm, '');

  const re = /@(\w+)\s*\{\s*([^,\s]+)\s*,\s*([\s\S]*?)\n\}/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    const type = m[1].toLowerCase();
    if (type === 'string' || type === 'preamble' || type === 'comment') continue;
    const key = m[2];
    const body = m[3];
    const fields = parseFields(body);
    entries.set(key, { type, key, fields });
  }
  return entries;
}

function parseFields(body) {
  const fields = {};
  // Walk the body char-by-char to respect brace nesting.
  const len = body.length;
  let i = 0;
  while (i < len) {
    // skip whitespace and commas
    while (i < len && /[\s,]/.test(body[i])) i++;
    // read key
    let key = '';
    while (i < len && /[A-Za-z0-9_-]/.test(body[i])) key += body[i++];
    if (!key) break;
    // skip until =
    while (i < len && body[i] !== '=') i++;
    if (body[i] !== '=') break;
    i++;
    while (i < len && /\s/.test(body[i])) i++;
    // read value: either {...} balanced, "..." or bare word
    let value = '';
    if (body[i] === '{') {
      let depth = 1; i++;
      while (i < len && depth > 0) {
        if (body[i] === '{') depth++;
        else if (body[i] === '}') { depth--; if (depth === 0) { i++; break; } }
        value += body[i++];
      }
    } else if (body[i] === '"') {
      i++;
      while (i < len && body[i] !== '"') value += body[i++];
      if (body[i] === '"') i++;
    } else {
      while (i < len && !/[,\s]/.test(body[i])) value += body[i++];
    }
    fields[key.toLowerCase()] = stripBraces(value);
  }
  return fields;
}

// Public API
exports.load = function (bibPath) {
  try {
    const text = fs.readFileSync(bibPath, 'utf8');
    return parseEntries(text);
  } catch {
    return new Map();
  }
};

exports.parse = parseEntries;
