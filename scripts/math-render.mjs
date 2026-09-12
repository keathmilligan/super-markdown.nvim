#!/usr/bin/env node
import { mathjax } from 'mathjax-full/js/mathjax.js';
import { TeX } from 'mathjax-full/js/input/tex.js';
import { SVG } from 'mathjax-full/js/output/svg.js';
import { liteAdaptor } from 'mathjax-full/js/adaptors/liteAdaptor.js';
import { RegisterHTMLHandler } from 'mathjax-full/js/handlers/html.js';
import { AllPackages } from 'mathjax-full/js/input/tex/AllPackages.js';

const display = process.argv[2] !== 'inline';
const color = process.argv[3] || '#1f2328';

const chunks = [];
for await (const chunk of process.stdin) {
  chunks.push(chunk);
}
const tex = Buffer.concat(chunks).toString('utf8').trim();
if (!tex) {
  console.error('super-markdown math: empty input');
  process.exit(1);
}

try {
  const adaptor = liteAdaptor();
  RegisterHTMLHandler(adaptor);
  const input = new TeX({ packages: AllPackages });
  const output = new SVG({ fontCache: 'local' });
  const html = mathjax.document('', { InputJax: input, OutputJax: output });
  const node = html.convert(tex, { display });
  let svg = adaptor.innerHTML(node);
  svg = svg.replace(/currentColor/g, color);
  process.stdout.write(svg);
} catch (err) {
  console.error('super-markdown math failed: ' + (err && err.message ? err.message : String(err)));
  process.exit(1);
}
