#!/usr/bin/env node

// Render curated architecture DOT files to SVG without a system Graphviz install.
// Tool dependency is intentionally external to the R package:
//   npm install --prefix /tmp/codeagent-diagram-tools --no-save --ignore-scripts \
//     @viz-js/viz@3.24.0
//   node tools/render_dot_svg.mjs

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = process.cwd();
const modulePath = process.env.VIZJS_MODULE ||
  "/tmp/codeagent-diagram-tools/node_modules/@viz-js/viz/dist/viz.js";
if (!fs.existsSync(modulePath)) {
  throw new Error(`Viz.js module not found: ${modulePath}`);
}
const { instance } = await import(pathToFileURL(modulePath).href);
const viz = await instance();

const manifestPath = path.join(root, "vignettes/diagrams/src/code-graphs.json");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const dotDir = path.join(root, "vignettes/diagrams/dot");
const svgDir = path.join(root, "vignettes/diagrams/svg");
fs.mkdirSync(svgDir, { recursive: true });

function escapeXml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

for (const graph of manifest.graphs) {
  const dotPath = path.join(dotDir, `${graph.id}.dot`);
  const svgPath = path.join(svgDir, `${graph.id}.svg`);
  const dot = fs.readFileSync(dotPath, "utf8");
  let svg = viz.renderString(dot, { format: "svg", engine: "dot" });
  svg = svg.replace(
    /<svg\b([^>]*)>/,
    `<svg$1 role="img" aria-labelledby="${graph.id}-title ${graph.id}-desc">`
  );
  // Replace Graphviz's graph-name title; node/edge titles are retained.
  svg = svg.replace(
    /<title>[^<]*<\/title>/,
    `<title id="${graph.id}-title">${escapeXml(graph.title)}</title>`
  );
  svg = svg.replace(
    /(<title id="[^"]+-title">[^<]*<\/title>)/,
    `$1\n<desc id="${graph.id}-desc">${escapeXml(graph.desc)} Audience: ${escapeXml(graph.audience)}. Scope: ${escapeXml(graph.scope)}. Verified commit ${manifest.verified_commit}.</desc>`
  );
  svg = svg.replace(
    /<svg([^>]*)>/,
    `<svg$1 style="max-width:100%;height:auto;background:transparent">`
  );
  fs.writeFileSync(svgPath, svg.endsWith("\n") ? svg : `${svg}\n`);
  console.log(`rendered ${path.relative(root, svgPath)}`);
}
