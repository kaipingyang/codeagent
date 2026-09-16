#!/usr/bin/env python3
"""Validate codeagent architecture diagram sources and generated SVGs."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "vignettes" / "diagrams" / "src"
SVG = ROOT / "vignettes" / "diagrams" / "svg"
DOT = ROOT / "vignettes" / "diagrams" / "dot"


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def rect(cell):
    g = cell.find("mxGeometry")
    return tuple(float(g.get(x, "0")) for x in ("x", "y", "width", "height"))


def overlaps(a, b, pad=5):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return not (
        ax + aw + pad <= bx or bx + bw + pad <= ax or
        ay + ah + pad <= by or by + bh + pad <= ay
    )


def check_drawio(path):
    errors = 0
    try:
        tree = ET.parse(path)
    except Exception as err:
        return fail(f"{path}: invalid XML: {err}")
    model = tree.find(".//mxGraphModel")
    if model is None:
        return fail(f"{path}: missing mxGraphModel")
    cells = {c.get("id"): c for c in model.findall("./root/mxCell")}
    if "0" not in cells or "1" not in cells:
        errors += fail(f"{path}: missing root cells 0/1")
    regular = []
    for cid, cell in cells.items():
        if cell.get("vertex") == "1":
            if cell.find("mxGeometry") is None:
                errors += fail(f"{path}: vertex {cid} missing geometry")
            style = cell.get("style", "")
            value = re.sub(r"<[^>]+>", " ", cell.get("value", "")).strip()
            if not value:
                errors += fail(f"{path}: vertex {cid} has no label")
            if not style.startswith("text;") and "swimlane" not in style:
                regular.append((cid, rect(cell)))
        if cell.get("edge") == "1":
            if cell.find("mxGeometry") is None:
                errors += fail(f"{path}: edge {cid} missing geometry")
            for attr in ("source", "target"):
                if cell.get(attr) not in cells:
                    errors += fail(f"{path}: edge {cid} unknown {attr}={cell.get(attr)}")
    for i, (aid, ar) in enumerate(regular):
        for bid, br in regular[i + 1:]:
            if overlaps(ar, br):
                errors += fail(f"{path}: node overlap {aid} / {bid}")
    return errors


def check_svg(path):
    errors = 0
    if not path.exists():
        return fail(f"missing SVG: {path}")
    try:
        root = ET.parse(path).getroot()
    except Exception as err:
        return fail(f"{path}: invalid SVG XML: {err}")
    text = path.read_text(encoding="utf-8")
    if "<title" not in text or "<desc" not in text:
        errors += fail(f"{path}: missing accessible title/desc")
    if 'role="img"' not in text or "viewBox=" not in text:
        errors += fail(f"{path}: missing role=img or viewBox")
    if len(list(root.iter())) < 10:
        errors += fail(f"{path}: unexpectedly empty SVG")
    return errors


def symbol_exists(symbol, file_hint):
    if not symbol:
        return True
    candidates = []
    if file_hint and " / " not in file_hint:
        candidate = ROOT / file_hint
        if candidate.exists():
            candidates = [candidate]
    if not candidates:
        candidates = list((ROOT / "R").glob("*.R"))
    pattern = re.compile(rf"(?<![A-Za-z0-9_.]){re.escape(symbol)}(?![A-Za-z0-9_.])")
    return any(pattern.search(p.read_text(encoding="utf-8", errors="replace")) for p in candidates)


def main():
    errors = 0
    concept_files = sorted(SRC.glob("*.drawio"))
    if len(concept_files) != 3:
        errors += fail(f"expected 3 concept drawio files, found {len(concept_files)}")
    for path in concept_files:
        errors += check_drawio(path)
        errors += check_svg(SVG / f"{path.stem}.drawio.svg")

    manifest_path = SRC / "code-graphs.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if manifest["verified_commit"] != head:
        errors += fail(
            f"manifest verified_commit {manifest['verified_commit']} != HEAD {head}; "
            "review diagrams and update deliberately"
        )
    if len(manifest["graphs"]) != 3:
        errors += fail("expected 3 code graphs")
    for graph in manifest["graphs"]:
        node_ids = {n["id"] for n in graph["nodes"]}
        if len(node_ids) != len(graph["nodes"]):
            errors += fail(f"{graph['id']}: duplicate node ids")
        for node in graph["nodes"]:
            if not symbol_exists(node.get("symbol"), node.get("file")):
                errors += fail(
                    f"{graph['id']}: symbol not found: {node.get('symbol')} "
                    f"({node.get('file')})"
                )
        for edge in graph["edges"]:
            if edge["from"] not in node_ids or edge["to"] not in node_ids:
                errors += fail(f"{graph['id']}: dangling edge {edge}")
            if edge.get("type") not in manifest["edge_types"]:
                errors += fail(f"{graph['id']}: unknown edge type {edge.get('type')}")
        dot = DOT / f"{graph['id']}.dot"
        if not dot.exists() or "digraph" not in dot.read_text(encoding="utf-8"):
            errors += fail(f"{graph['id']}: missing/invalid DOT")
        errors += check_svg(SVG / f"{graph['id']}.svg")

    if errors:
        raise SystemExit(f"diagram validation failed with {errors} finding(s)")
    print(
        f"PASS: {len(concept_files)} draw.io concepts + "
        f"{len(manifest['graphs'])} code graphs; XML, geometry, symbols, DOT, SVG accessibility"
    )


if __name__ == "__main__":
    main()
