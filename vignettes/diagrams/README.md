# Architecture diagrams

This directory contains the canonical architecture diagrams embedded in the
pkgdown articles.

## Source and generated files

```text
vignettes/diagrams/
├── src/
│   ├── *.drawio          editable source for concept diagrams
│   └── code-graphs.json  curated source for code dependency diagrams
├── dot/                  generated Graphviz sources
└── svg/                  generated, pkgdown-ready SVG files
```

- Concept diagrams: native uncompressed draw.io XML is the source of truth.
- Code diagrams: `src/code-graphs.json` is the source of truth. DOT and SVG are
  generated artifacts.
- Rmd articles embed SVG only; they do not copy graph source.

## Render and validate

The concept renderer requires only Python. Code graph rendering uses a pinned
Graphviz WASM package outside the R package dependency graph.

```sh
npm install --prefix /tmp/codeagent-diagram-tools --no-save --ignore-scripts \
  @viz-js/viz@3.24.0

python3 tools/render_architecture_diagrams.py --init  # first run only
python3 tools/render_architecture_diagrams.py
node tools/render_dot_svg.mjs
python3 tools/check_architecture_diagrams.py
```

After the first run, edit `.drawio` files in draw.io and run the render command
without `--init`. The repository renderer supports the shapes used by these
sources. If a diagram starts using unsupported draw.io shapes, export its SVG
with draw.io and extend the checker before merging.

## Visual language

| Meaning | Color | Edge |
|---|---|---|
| user / host / entry | blue | normal call |
| model / provider / summary | purple | callback/event may be dashed |
| security / policy gate | amber or red | guards use a heavy red line |
| successful execution / safe output | green | return paths use green |
| context / internal state | teal or gray | ownership/state is dotted |
| process/worker spawn | amber | bold line |

Concept diagrams use a polished technical-light style, transparent-friendly
surfaces, rounded cards, restrained shadows, and orthogonal connectors. They
must remain legible without color.

## Diagram contracts

| ID | Audience | Scope | Primary sources |
|---|---|---|---|
| `agent-turn-lifecycle` | User / Integrator | one foreground turn | `R/stream.R`, `R/turn_pipeline.R`, gates, sessions |
| `tool-safety-pipeline` | Integrator / Maintainer | one tool call | `R/tools_gate.R`, hooks, Data Shield |
| `context-compaction-lifecycle` | Integrator / Maintainer | request-boundary context controls | `R/compaction.R`, `R/resource.R` |
| `entrypoint-call-map` | Maintainer / Integrator | top-level entrypoints | query, repl, stream, ui, sessions |
| `core-module-dependencies` | Maintainer | foreground turn modules | turn core + cross-cutting modules |
| `multi-agent-ownership` | Maintainer / Security reviewer | state/process ownership | agent, team, board, background runtime |

## Maintenance rules

1. Do not encode volatile counts, model names, package versions, or thresholds in
   a diagram.
2. Each diagram records a verified commit. A source-file change does not imply
   the diagram changed, but it requires an explicit review.
3. Edge types describe semantics (`calls`, `callback`, `state`, `spawns`,
   `persists`, `guards`, `returns`); they are not all direct static calls.
4. Codegraph/LSP is authoring evidence, not a build dependency. Dynamic R6,
   callback, S7, and process edges are curated in the manifest.
5. English and Chinese articles reuse the same SVG. Each article provides a
   language-specific textual summary below the image.
6. Generated SVGs must contain an accessible `<title>` and `<desc>` and pass the
   repository checker.
7. Run `pkgdown::check_pkgdown()` after adding or removing architecture articles.
