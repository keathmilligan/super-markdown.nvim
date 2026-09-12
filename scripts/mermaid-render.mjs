#!/usr/bin/env node
import { createHTMLWindow } from 'svgdom';

const theme = process.argv[2] === 'dark' ? 'dark' : 'default';

const window = createHTMLWindow();
globalThis.window = window;
globalThis.document = window.document;
globalThis.DOMParser = window.DOMParser;
globalThis.XMLSerializer = window.XMLSerializer;
globalThis.HTMLElement = window.HTMLElement;
globalThis.SVGElement = window.SVGElement;
globalThis.Element = window.Element;
globalThis.Node = window.Node;
globalThis.getComputedStyle = window.getComputedStyle
  ? window.getComputedStyle.bind(window)
  : () => ({ getPropertyValue: () => '', fontSize: '16px' });
globalThis.requestAnimationFrame = (cb) => setTimeout(cb, 0);
globalThis.cancelAnimationFrame = (id) => clearTimeout(id);

if (typeof globalThis.CSSStyleSheet === 'undefined') {
  globalThis.CSSStyleSheet = class CSSStyleSheet {
    constructor() {
      this.cssRules = [];
    }
    insertRule(rule, index = this.cssRules.length) {
      this.cssRules.splice(index, 0, { cssText: rule });
      return index;
    }
    replaceSync(text) {
      this.cssRules = [{ cssText: text }];
    }
  };
}

const box = () => ({ x: 0, y: 0, width: 100, height: 20, top: 0, left: 0, right: 100, bottom: 20 });
const install = (proto, name, fn) => {
  if (proto && typeof proto[name] !== 'function') {
    proto[name] = fn;
  }
};
for (const proto of [globalThis.Element?.prototype, globalThis.SVGElement?.prototype, globalThis.HTMLElement?.prototype]) {
  install(proto, 'getBBox', box);
  install(proto, 'getBoundingClientRect', box);
  install(proto, 'getComputedTextLength', function () {
    return (this.textContent || '').length * 8;
  });
  install(proto, 'getTotalLength', () => 100);
  install(proto, 'getPointAtLength', () => ({ x: 0, y: 0 }));
}

const chunks = [];
for await (const chunk of process.stdin) {
  chunks.push(chunk);
}
const source = Buffer.concat(chunks).toString('utf8').trim();
const fail = (err) => {
  const payload = {
    message: err && err.message ? err.message : String(err),
  };
  if (err && err.hash) {
    payload.text = err.hash.text;
    payload.token = err.hash.token;
    if (err.hash.loc) {
      payload.line = err.hash.loc.first_line;
      payload.column = (err.hash.loc.first_column || 0) + 1;
    }
  }
  console.error('MERMAID_ERROR ' + JSON.stringify(payload));
  process.exit(1);
};

if (!source) {
  fail(new Error('empty input'));
}

let mermaid;
try {
  mermaid = (await import('mermaid')).default;
} catch (err) {
  fail(new Error('cannot import mermaid (npm install in scripts/): ' + err.message));
}

mermaid.initialize({
  startOnLoad: false,
  theme,
  securityLevel: 'loose',
  htmlLabels: false,
  flowchart: { htmlLabels: false },
  // Browser mermaid draws an error SVG; svgdom cannot. Throw so Neovim
  // can show the parse error instead of sending an empty file to rsvg.
  suppressErrorRendering: true,
});

const extractSvg = (raw) => {
  if (typeof raw !== 'string') {
    return '';
  }
  const match = raw.match(/<svg[\s>][\s\S]*<\/svg>/i);
  return match ? match[0] : (/<svg[\s>]/i.test(raw) ? raw : '');
};

try {
  await mermaid.parse(source);
  const id = 'd' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  const result = await mermaid.render(id, source);
  let svg = extractSvg(result && result.svg);
  if (svg.length < 64) {
    const el = document.querySelector('svg');
    svg = extractSvg(el && el.outerHTML);
  }
  if (svg.length < 64) {
    fail(new Error('mermaid.render() produced no SVG'));
  }
  process.stdout.write(svg);
} catch (err) {
  fail(err);
}
