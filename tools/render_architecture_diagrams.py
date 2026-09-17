#!/usr/bin/env python3
"""Render codeagent architecture diagrams.

Concept diagrams:
  Native uncompressed draw.io XML is the editable source of truth.
  This script bootstraps missing .drawio files and renders the supported
  native shapes to deterministic, accessible SVG without requiring draw.io.

Code diagrams:
  vignettes/diagrams/src/code-graphs.json is the curated source of truth.
  This script writes Graphviz DOT. tools/render_dot_svg.mjs renders DOT to SVG.

Usage:
  python3 tools/render_architecture_diagrams.py --init
  python3 tools/render_architecture_diagrams.py
"""

from __future__ import annotations

import argparse
import html
import json
import math
import re
import textwrap
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "vignettes" / "diagrams" / "src"
SVG = ROOT / "vignettes" / "diagrams" / "svg"
DOT = ROOT / "vignettes" / "diagrams" / "dot"
VERIFIED_COMMIT = "28c4ae6d5d9273a3a422575adeae448918edd097"

PALETTE = {
    "blue": ("#EAF2FF", "#3266CC", "#173B75"),
    "purple": ("#F3ECFF", "#7A4CC2", "#43256F"),
    "amber": ("#FFF4E5", "#C77800", "#6B3E00"),
    "green": ("#EAF8F0", "#2D7A50", "#194A30"),
    "red": ("#FDECEC", "#B42318", "#7A271A"),
    "gray": ("#F4F6F8", "#667085", "#344054"),
    "teal": ("#E8F8F7", "#17877F", "#125A55"),
}


def node(node_id, label, x, y, w=190, h=72, color="blue", shape="round", parent="1", note=None):
    fill, stroke, font = PALETTE[color]
    return {
        "id": node_id, "label": label, "x": x, "y": y, "w": w, "h": h,
        "fill": fill, "stroke": stroke, "font": font, "shape": shape,
        "parent": parent, "note": note,
    }


def frame(node_id, label, x, y, w, h, color="gray"):
    fill, stroke, font = PALETTE[color]
    return {
        "id": node_id, "label": label, "x": x, "y": y, "w": w, "h": h,
        "fill": fill, "stroke": stroke, "font": font, "shape": "frame",
        "parent": "1", "opacity": 35,
    }


def edge(edge_id, source, target, label="", color="#667085", dashed=False, points=None):
    return {
        "id": edge_id, "source": source, "target": target, "label": label,
        "color": color, "dashed": dashed, "points": points or [],
    }


CONCEPTS = {
    "agent-turn-lifecycle": {
        "title": "One codeagent turn",
        "desc": "Input safety, turn setup, model and tool rounds, final response safety, and persistence.",
        "audience": "User / Integrator",
        "scope": "One foreground turn; UI adapters are outside the core flow.",
        "sources": ["R/stream.R", "R/turn_pipeline.R", "R/input_gate.R", "R/output_gate.R", "R/sessions.R"],
        "size": [1660, 900],
        "nodes": [
            frame("f-main", "TURN PIPELINE", 25, 105, 1610, 250, "gray"),
            frame("f-tools", "MODEL-REQUEST TOOL LOOP", 435, 405, 830, 300, "purple"),
            frame("f-state", "STATE / PERSISTENCE", 1020, 720, 540, 165, "gray"),
            node("user-in", "User input\n+ attachments", 55, 190, 170, 80, "blue"),
            node("input-gate", "Input gate\nscan / redact / block", 270, 190, 190, 80, "amber"),
            node("turn-setup", "Turn setup\ncontext + reminders", 505, 190, 190, 80, "teal"),
            node("model", "ellmer Chat\nprovider request", 750, 180, 200, 100, "purple"),
            node("finalize", "Finalize\nfinish reason + citations", 1010, 190, 210, 80, "teal"),
            node("output-gate", "Output gate\nscan final response", 1265, 190, 190, 80, "amber"),
            node("user-out", "Safe reply\nUI / host callback", 1495, 190, 130, 80, "green"),
            node("preview", "Tool preview\nnot approval", 475, 485, 170, 72, "gray"),
            node("tool-gate", "Tool safety chain\npermission + Shield + hooks", 690, 470, 230, 100, "amber"),
            node("execute", "Tool execution", 965, 485, 150, 72, "green"),
            node("result", "Result normalization\nvalue + artifact + display", 690, 610, 230, 80, "blue"),
            node("teardown", "Turn teardown\nusage + hooks", 1060, 780, 190, 70, "gray"),
            node("session", "Session save\nlossless state\n+ presentation", 1300, 770, 220, 90, "gray"),
        ],
        "edges": [
            edge("e1", "user-in", "input-gate"), edge("e2", "input-gate", "turn-setup"),
            edge("e3", "turn-setup", "model"), edge("e4", "model", "finalize", "no more tools"),
            edge("e5", "finalize", "output-gate"), edge("e6", "output-gate", "user-out"),
            edge("e7", "model", "preview", "ContentToolRequest", points=[(850, 370), (560, 370)]),
            edge("e8", "preview", "tool-gate"), edge("e9", "tool-gate", "execute", "allow"),
            edge("e10", "execute", "result"),
            edge("e11", "result", "model", "next provider request", points=[(805, 585), (805, 330), (850, 330)]),
            edge("e12", "finalize", "teardown", "final text", dashed=True, points=[(1115, 330), (1165, 700)]),
            edge("e13", "teardown", "session", dashed=True, points=[(1265, 875), (1410, 875)]),
        ],
    },
    "tool-safety-pipeline": {
        "title": "Tool-call safety pipeline",
        "desc": "The preview is not authorization. The central gate remains authoritative; hooks and Data Shield are separate layers.",
        "audience": "Integrator / Maintainer",
        "scope": "One tool call, including rewritten-input recheck and result egress.",
        "sources": ["R/tools_gate.R", "R/tool_input_hook.R", "R/hooks.R", "R/data_shield.R", "R/stream.R"],
        "size": [1720, 980],
        "nodes": [
            frame("f-preview", "MODEL / UI", 25, 115, 1670, 145, "purple"),
            frame("f-authority", "AUTHORIZATION AUTHORITY", 25, 295, 1670, 250, "amber"),
            frame("f-extension", "EXTENSION + DATA POLICY", 25, 585, 1670, 155, "teal"),
            frame("f-exec", "EXECUTION + RESULT", 25, 780, 1670, 160, "green"),
            node("request", "Model tool request", 65, 155, 170, 65, "purple"),
            node("preview", "on_tool_request\npre-gate preview", 285, 145, 190, 82, "gray"),
            node("central", "Central gate\nmetadata + set + capability", 90, 360, 225, 90, "amber"),
            node("shield-in", "Data Shield ingress\nargs / tool policy", 365, 360, 210, 90, "amber"),
            node("decision", "allow / deny / ask", 625, 360, 180, 90, "amber", "diamond"),
            node("ask", "ask_fn / host approval", 855, 360, 200, 90, "blue"),
            node("prehook", "PreToolUse hooks", 1110, 360, 180, 90, "teal"),
            node("rewrite", "Arguments rewritten?", 1340, 360, 185, 90, "teal", "diamond"),
            node("reject", "Reject\nPermissionDenied", 1485, 150, 175, 75, "red"),
            node("recheck", "Re-run gate + Shield\non updated input", 720, 645, 240, 82, "amber"),
            node("execute", "Execute tool", 1370, 825, 170, 72, "green"),
            node("egress", "Data Shield egress\nfilter result", 1080, 815, 210, 90, "amber"),
            node("post", "PostToolUse hook", 800, 825, 190, 72, "teal"),
            node("normalize", "Normalize result\nvalue + artifact + display", 490, 815, 230, 90, "blue"),
            node("model", "Return to model\nthen UI callback", 150, 825, 190, 72, "purple"),
        ],
        "edges": [
            edge("e1", "request", "preview"), edge("e2", "preview", "central", "preview only", dashed=True, points=[(380, 275), (200, 275)]),
            edge("e3", "central", "shield-in"), edge("e4", "shield-in", "decision"),
            edge("e5", "decision", "reject", "deny", "#B42318", points=[(715, 330), (1570, 330)]),
            edge("e6", "decision", "ask", "ask"), edge("e7", "ask", "reject", "deny", "#B42318", points=[(955, 285), (1570, 285)]),
            edge("e8", "ask", "prehook", "approve"), edge("e9", "decision", "prehook", "allow", points=[(715, 500), (1200, 500)]),
            edge("e10", "prehook", "rewrite"), edge("e11", "rewrite", "recheck", "yes", points=[(1430, 555), (840, 555)]),
            edge("e12", "recheck", "central", "decision again", dashed=True, points=[(840, 575), (200, 575)]),
            edge("e13", "rewrite", "execute", "no"),
            edge("e14", "execute", "egress"), edge("e15", "egress", "post"),
            edge("e16", "post", "normalize"), edge("e17", "normalize", "model"),
        ],
    },
    "data-shield-end-to-end": {
        "title": "Data Shield: end-to-end LLM and tool safety loop",
        "desc": "Automatic policy is the main path; human approval is an optional ask + callback branch; missing callbacks fail safe.",
        "audience": "User / Integrator / Security reviewer",
        "scope": "Model-bound input and output, tool ingress and egress, optional human callbacks, and the provider tool loop.",
        "sources": ["R/input_gate.R", "R/output_gate.R", "R/tools_gate.R", "R/tool_input_hook.R", "R/data_shield.R", "R/stream.R"],
        "size": [1900, 1200],
        "nodes": [
            frame("edge1-frame", "EDGE 1 · LLM INPUT", 30, 115, 1200, 260, "blue"),
            frame("state-frame", "LOCAL SHIELD STATE · RAW DATA NEVER ENTERS THE MODEL DIRECTLY", 1260, 115, 610, 260, "gray"),
            frame("edge2-frame", "EDGE 2 · TOOL LOOP", 300, 395, 1570, 500, "amber"),
            frame("edge3-frame", "EDGE 3 · LLM OUTPUT", 30, 920, 1200, 220, "purple"),
            node("human-input", "Human / host input\ntext + text attachments", 60, 185, 220, 90, "blue"),
            node("input-gate", "LLM INPUT GATE\nvalue_match + regex\npass / redact / block\nask → redact (no dialog)", 340, 165, 300, 130, "amber"),
            node("safe-prompt", "Model-bound input\nunchanged or redacted", 700, 185, 220, 90, "teal"),
            node("input-block", "Turn stops\nsafe blocked notice", 700, 295, 220, 60, "red"),
            node("llm", "LLM / provider round\nsees only\nmodel-bound content\nchooses:\ntool call or final reply", 990, 155, 220, 160, "purple"),
            node("protected-data", "Registered protected data\nlocal R memory only", 1290, 165, 250, 100, "gray"),
            node("schema-only", "Filtered schema block\n+ DescribeData metadata", 1580, 165, 250, 100, "teal"),
            node("value-index", "Local value index\nprompt + tool args\nresult + reply scans", 1430, 280, 270, 80, "gray"),
            node("tool-request", "LLM tool request\nname + arguments", 990, 445, 220, 80, "purple"),
            node("ingress-gate", "TOOL INGRESS + AUTHORITY · AUTOMATIC\nShield policy → patterns → reviewer\nthen permission mode + rules\nallow / deny stay on main path\nask without ask_fn → deny", 650, 440, 300, 140, "amber"),
            node("permission-human", "OPTIONAL human permission\nonly ask + ask_fn\nApprove / Deny", 350, 445, 240, 110, "blue"),
            node("pre-hook", "PreToolUse\nallow / deny / rewrite", 670, 620, 240, 100, "amber"),
            node("rewrite-check", "Rewrite re-check\nscrub + ingress + permission\nnon-allow / ask → reject", 350, 610, 240, 115, "amber"),
            node("arg-scrub", "Final argument scrub\nscan_tool_args\nredact or reject", 970, 620, 240, 100, "amber"),
            node("execute", "Execute tool\nwith final scanned args", 1260, 620, 220, 100, "green"),
            node("egress-gate", "TOOL EGRESS · AUTOMATIC\ntool policy → row cap / value match\n→ custom scanners\npass / redact / block use main path\nask without callback / timeout\n→ automatic Redact", 1530, 535, 290, 175, "amber"),
            node("egress-human", "OPTIONAL human egress review\nonly ask + live callback\nRedact / Block / Raw once*", 1530, 750, 290, 110, "blue"),
            node("post-hook", "PostToolUse\nobserves gated result", 1230, 760, 240, 90, "gray"),
            node("rejected", "Rejected call\nfixed safe tool result", 640, 770, 210, 80, "red"),
            node("model-result", "Normalized model-bound result\npass / filtered / blocked notice\nor explicitly approved raw once*", 900, 750, 260, 110, "teal"),
            node("final-reply", "Final LLM reply\nbuffered — not shown yet", 930, 970, 260, 100, "purple"),
            node("output-gate", "LLM OUTPUT GATE\nvalue_match + regex\npass / redact / block\nask → redact (no dialog)", 620, 960, 250, 120, "amber"),
            node("visible-response", "User-visible response\nemitted once after scan", 340, 970, 220, 100, "teal"),
            node("human-output", "Human / browser\nsees gated response", 70, 975, 210, 90, "blue"),
            node("legend", "SOLID main path = automatic handling\nBLUE dashed = optional human callback\nAMBER = Shield / authorization\nPURPLE = LLM content\nTEAL = model-bound transformed value\nRED dashed = reject / fail-closed\n* Raw once is opt-in and audited", 1290, 935, 540, 175, "gray"),
        ],
        "edges": [
            edge("e1", "human-input", "input-gate", color="#3266CC"),
            edge("e2", "input-gate", "safe-prompt", color="#17877F"),
            edge("e3", "safe-prompt", "llm", "LLM input", "#17877F"),
            edge("e4", "input-gate", "input-block", color="#B42318", dashed=True),
            edge("e5", "protected-data", "schema-only", color="#667085", dashed=True),
            edge("e6", "protected-data", "value-index", color="#667085", dashed=True),
            edge("e7", "schema-only", "llm", color="#17877F", dashed=True, points=[(1705, 150), (1240, 150)]),
            edge("e8", "llm", "tool-request", "tool call", "#7A4CC2"),
            edge("e9", "tool-request", "ingress-gate", color="#7A4CC2"),
            edge("e10", "ingress-gate", "pre-hook", "automatic allow", "#2D7A50"),
            edge("e10b", "ingress-gate", "rejected", color="#B42318", dashed=True, points=[(950, 500), (950, 730), (850, 730)]),
            edge("e11", "ingress-gate", "permission-human", color="#3266CC", dashed=True),
            edge("e12", "permission-human", "pre-hook", "approve", "#3266CC", dashed=True),
            edge("e13", "permission-human", "rejected", "deny", "#B42318", dashed=True, points=[(320, 480), (320, 810), (620, 810)]),
            edge("e14", "pre-hook", "arg-scrub", color="#2D7A50"),
            edge("e15", "pre-hook", "rewrite-check", "rewrite", "#C77800"),
            edge("e16", "rewrite-check", "arg-scrub", "recheck allow", "#2D7A50", points=[(620, 735), (940, 735)]),
            edge("e17", "pre-hook", "rejected", color="#B42318", dashed=True),
            edge("e18", "rewrite-check", "rejected", color="#B42318", dashed=True),
            edge("e19", "rejected", "model-result", color="#B42318"),
            edge("e20", "arg-scrub", "execute", color="#2D7A50"),
            edge("e21", "execute", "egress-gate", color="#2D7A50"),
            edge("e22", "egress-gate", "post-hook", "auto result", "#17877F", points=[(1490, 700), (1490, 735), (1470, 735)]),
            edge("e23", "egress-gate", "egress-human", "ask + callback", "#3266CC", dashed=True),
            edge("e24", "egress-human", "post-hook", "human choice", "#3266CC", dashed=True, points=[(1500, 875), (1490, 875)]),
            edge("e25", "post-hook", "model-result", color="#667085"),
            edge("e26", "model-result", "llm", "next provider round", "#7A4CC2", points=[(1220, 815), (1220, 345), (1120, 345)]),
            edge("e27", "llm", "final-reply", color="#7A4CC2", points=[(1240, 340), (1240, 385), (1880, 385), (1880, 910), (1060, 910)]),
            edge("e28", "final-reply", "output-gate", color="#7A4CC2"),
            edge("e29", "output-gate", "visible-response", color="#17877F"),
            edge("e30", "visible-response", "human-output", color="#3266CC"),
        ],
    },
    "context-compaction-lifecycle": {
        "title": "Request-boundary context management",
        "desc": "Every provider request sees the pending turn exactly once; cheap controls run before summaries; PTL recovery drops complete rounds.",
        "audience": "Integrator / Maintainer",
        "scope": "on_request_start pipeline and provider prompt-too-long recovery.",
        "sources": ["R/compaction.R", "R/resource.R", "R/turn_pipeline.R"],
        "size": [1710, 980],
        "nodes": [
            frame("f-request", "BEFORE EVERY PROVIDER REQUEST: on_request_start(turns)", 25, 115, 1660, 585, "teal"),
            frame("f-recovery", "PROVIDER ERROR RECOVERY", 25, 745, 1660, 190, "red"),
            node("snapshot", "Outgoing turns\nincludes pending turn", 60, 200, 190, 82, "blue"),
            node("resource", "Replace large old\ntool results", 300, 200, 200, 82, "gray"),
            node("account", "Initial token account\nmodel-aware threshold", 550, 200, 210, 82, "teal"),
            node("micro", "Budget-aware\nmicro-snip", 810, 200, 185, 82, "amber"),
            node("rebuild", "Rebuild persisted history\n+ pending turn once", 1045, 195, 230, 92, "blue"),
            node("recount", "Fresh structural recount", 1325, 200, 210, 82, "teal"),
            node("over", "Still over threshold?", 1360, 380, 190, 90, "amber", "diamond"),
            node("incremental", "Incremental summary\nwhen eligible", 1025, 520, 210, 82, "purple"),
            node("full", "Full summary fallback\nwhen enabled / needed", 725, 520, 220, 82, "purple"),
            node("validate", "Pair / structure validation", 405, 520, 220, 82, "green"),
            node("request", "Send provider request", 110, 520, 200, 82, "green"),
            node("ptl", "Prompt too long / 413", 160, 795, 210, 75, "red"),
            node("drop", "Pair-safe PTL fallback\ndrop complete historical rounds", 500, 785, 270, 95, "red"),
            node("retry", "Validate + retry once", 930, 795, 210, 75, "amber"),
            node("surface", "Surface terminal error", 1280, 795, 210, 75, "red"),
        ],
        "edges": [
            edge("e1", "snapshot", "resource"), edge("e2", "resource", "account"), edge("e3", "account", "micro"),
            edge("e4", "micro", "rebuild"), edge("e5", "rebuild", "recount"), edge("e6", "recount", "over"),
            edge("e7", "over", "request", "no", points=[(1455, 470), (210, 470)]),
            edge("e8", "over", "incremental", "yes"), edge("e9", "incremental", "full", "still over / unavailable"),
            edge("e10", "full", "validate"), edge("e11", "validate", "request"),
            edge("e12", "request", "ptl", "provider PTL", "#B42318", points=[(210, 720), (265, 720)]),
            edge("e13", "ptl", "drop"), edge("e14", "drop", "retry"),
            edge("e15", "retry", "surface", "fails again", "#B42318"),
        ],
    },
}


def style_string(n):
    if n["shape"] == "frame":
        return (
            "swimlane;html=1;rounded=1;startSize=34;horizontal=1;"
            f"fillColor={n['fill']};strokeColor={n['stroke']};fontColor={n['font']};"
            "fontStyle=1;fontSize=14;opacity=35;whiteSpace=wrap;"
        )
    shape = "rhombus" if n["shape"] == "diamond" else "rounded=1;arcSize=16"
    return (
        f"{shape};whiteSpace=wrap;html=1;fillColor={n['fill']};"
        f"strokeColor={n['stroke']};fontColor={n['font']};strokeWidth=1.5;"
        "fontFamily=Helvetica;fontSize=14;align=center;verticalAlign=middle;spacing=8;"
    )


def write_drawio(name, spec):
    path = SRC / f"{name}.drawio"
    if path.exists():
        return
    mxfile = ET.Element("mxfile", {"host": "app.diagrams.net", "agent": "codeagent", "version": "24.7.17"})
    diagram = ET.SubElement(mxfile, "diagram", {"id": name, "name": "Page-1"})
    w, h = spec["size"]
    model = ET.SubElement(diagram, "mxGraphModel", {
        "dx": str(w), "dy": str(h), "grid": "1", "gridSize": "10", "guides": "1",
        "tooltips": "1", "connect": "1", "arrows": "1", "fold": "1",
        "page": "1", "pageScale": "1", "pageWidth": str(w), "pageHeight": str(h),
        "math": "0", "shadow": "0", "defaultFontFamily": "Helvetica",
    })
    root = ET.SubElement(model, "root")
    ET.SubElement(root, "mxCell", {"id": "0"})
    ET.SubElement(root, "mxCell", {"id": "1", "parent": "0"})
    title = ET.SubElement(root, "mxCell", {
        "id": "diagram-title", "value": spec["title"],
        "style": "text;html=1;strokeColor=none;fillColor=none;fontSize=26;fontStyle=1;fontColor=#1D2939;align=left;verticalAlign=middle;fontFamily=Helvetica;",
        "vertex": "1", "parent": "1",
    })
    ET.SubElement(title, "mxGeometry", {"x": "30", "y": "25", "width": str(w - 60), "height": "42", "as": "geometry"})
    subtitle = ET.SubElement(root, "mxCell", {
        "id": "diagram-subtitle", "value": spec["desc"],
        "style": "text;html=1;strokeColor=none;fillColor=none;fontSize=13;fontColor=#667085;align=left;verticalAlign=middle;fontFamily=Helvetica;",
        "vertex": "1", "parent": "1",
    })
    ET.SubElement(subtitle, "mxGeometry", {"x": "30", "y": "65", "width": str(w - 60), "height": "30", "as": "geometry"})
    for n in spec["nodes"]:
        cell = ET.SubElement(root, "mxCell", {
            "id": n["id"], "value": n["label"].replace("\n", "<br>"),
            "style": style_string(n), "vertex": "1", "parent": n.get("parent", "1"),
        })
        ET.SubElement(cell, "mxGeometry", {
            "x": str(n["x"]), "y": str(n["y"]), "width": str(n["w"]), "height": str(n["h"]), "as": "geometry"
        })
    for e in spec["edges"]:
        style = (
            "edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;"
            f"html=1;strokeColor={e['color']};strokeWidth=1.6;endArrow=block;endFill=1;"
            f"fontSize=12;fontColor={e['color']};labelBackgroundColor=#FFFFFF;"
        )
        if e["dashed"]:
            style += "dashed=1;dashPattern=6 4;"
        cell = ET.SubElement(root, "mxCell", {
            "id": e["id"], "value": e["label"], "style": style,
            "edge": "1", "parent": "1", "source": e["source"], "target": e["target"],
        })
        geo = ET.SubElement(cell, "mxGeometry", {"relative": "1", "as": "geometry"})
        if e["points"]:
            arr = ET.SubElement(geo, "Array", {"as": "points"})
            for x, y in e["points"]:
                ET.SubElement(arr, "mxPoint", {"x": str(x), "y": str(y)})
    ET.indent(mxfile, space="  ")
    path.write_text(ET.tostring(mxfile, encoding="unicode") + "\n", encoding="utf-8")


def parse_style(raw):
    out = {}
    for part in raw.split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k] = v
    return out


def plain_label(value):
    value = re.sub(r"<br\s*/?>", "\n", value or "", flags=re.I)
    value = re.sub(r"<[^>]+>", "", value)
    return html.unescape(value)


def geom(cell):
    g = cell.find("mxGeometry")
    return {k: float(g.get(k, "0")) for k in ("x", "y", "width", "height")}


def boundary_point(r, toward):
    cx, cy = r["x"] + r["width"] / 2, r["y"] + r["height"] / 2
    dx, dy = toward[0] - cx, toward[1] - cy
    if dx == 0 and dy == 0:
        return cx, cy
    scale_x = (r["width"] / 2) / abs(dx) if dx else float("inf")
    scale_y = (r["height"] / 2) / abs(dy) if dy else float("inf")
    scale = min(scale_x, scale_y)
    return cx + dx * scale, cy + dy * scale


def edge_path(a, b, points):
    ac = (a["x"] + a["width"] / 2, a["y"] + a["height"] / 2)
    bc = (b["x"] + b["width"] / 2, b["y"] + b["height"] / 2)
    if points:
        start = boundary_point(a, points[0])
        end = boundary_point(b, points[-1])
        pts = [start] + points + [end]
    elif abs(ac[0] - bc[0]) > abs(ac[1] - bc[1]):
        sx = a["x"] + a["width"] if bc[0] >= ac[0] else a["x"]
        tx = b["x"] if bc[0] >= ac[0] else b["x"] + b["width"]
        sy, ty = ac[1], bc[1]
        mid = (sx + tx) / 2
        pts = [(sx, sy), (mid, sy), (mid, ty), (tx, ty)]
    else:
        sy = a["y"] + a["height"] if bc[1] >= ac[1] else a["y"]
        ty = b["y"] if bc[1] >= ac[1] else b["y"] + b["height"]
        sx, tx = ac[0], bc[0]
        mid = (sy + ty) / 2
        pts = [(sx, sy), (sx, mid), (tx, mid), (tx, ty)]
    d = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in pts)
    return d, pts[len(pts) // 2]


def svg_text(label, x, y, w, h, color, size=14, bold=False):
    lines = label.split("\n")
    line_h = size * 1.25
    start = y + h / 2 - (len(lines) - 1) * line_h / 2 + size * 0.35
    chunks = [f'<text x="{x + w/2:.1f}" y="{start:.1f}" text-anchor="middle" fill="{color}" font-family="Inter,Arial,sans-serif" font-size="{size}" font-weight="{700 if bold else 500}">']
    for i, line in enumerate(lines):
        dy = 0 if i == 0 else line_h
        chunks.append(f'<tspan x="{x + w/2:.1f}" dy="{dy:.1f}">{html.escape(line)}</tspan>')
    chunks.append("</text>")
    return "".join(chunks)


def render_drawio(path, spec):
    tree = ET.parse(path)
    model = tree.find(".//mxGraphModel")
    w = int(float(model.get("pageWidth")))
    h = int(float(model.get("pageHeight")))
    cells = {c.get("id"): c for c in model.findall("./root/mxCell")}
    vertices = {i: geom(c) for i, c in cells.items() if c.get("vertex") == "1"}
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-labelledby="title desc">',
        f'<title id="title">{html.escape(spec["title"])}</title>',
        f'<desc id="desc">{html.escape(spec["desc"])} Audience: {html.escape(spec["audience"])}. Scope: {html.escape(spec["scope"])}</desc>',
        '<defs><marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L8,4 L0,8 z" fill="context-stroke"/></marker><filter id="shadow" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="2" stdDeviation="3" flood-color="#101828" flood-opacity="0.08"/></filter></defs>',
        '<rect width="100%" height="100%" fill="#FFFFFF"/>',
    ]
    # Frames first.
    for cid, c in cells.items():
        if c.get("vertex") != "1":
            continue
        st = parse_style(c.get("style", ""))
        if "swimlane" not in c.get("style", ""):
            continue
        g = vertices[cid]
        out.append(f'<rect x="{g["x"]}" y="{g["y"]}" width="{g["width"]}" height="{g["height"]}" rx="16" fill="{st.get("fillColor", "#F4F6F8")}" fill-opacity="0.45" stroke="{st.get("strokeColor", "#98A2B3")}" stroke-width="1.2"/>')
        out.append(svg_text(plain_label(c.get("value")), g["x"] + 12, g["y"] + 3, g["width"] - 24, 30, st.get("fontColor", "#344054"), 13, True))
    # Edges behind regular nodes.
    for cid, c in cells.items():
        if c.get("edge") != "1":
            continue
        s, t = c.get("source"), c.get("target")
        if s not in vertices or t not in vertices:
            continue
        st = parse_style(c.get("style", ""))
        pts = []
        arr = c.find("./mxGeometry/Array")
        if arr is not None:
            pts = [(float(p.get("x")), float(p.get("y"))) for p in arr.findall("mxPoint")]
        d, label_at = edge_path(vertices[s], vertices[t], pts)
        dash = ' stroke-dasharray="7 5"' if st.get("dashed") == "1" else ""
        color = st.get("strokeColor", "#667085")
        out.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="1.7" stroke-linejoin="round" marker-end="url(#arrow)"{dash}/>' )
        label = plain_label(c.get("value"))
        if label:
            lx, ly = label_at
            tw = max(70, len(label) * 6.5)
            out.append(f'<rect x="{lx-tw/2:.1f}" y="{ly-12:.1f}" width="{tw:.1f}" height="20" rx="6" fill="#FFFFFF" fill-opacity="0.94"/>')
            out.append(f'<text x="{lx:.1f}" y="{ly+2:.1f}" text-anchor="middle" fill="{color}" font-family="Inter,Arial,sans-serif" font-size="11.5">{html.escape(label)}</text>')
    # Regular nodes and title text cells.
    for cid, c in cells.items():
        if c.get("vertex") != "1":
            continue
        st_raw = c.get("style", "")
        if "swimlane" in st_raw:
            continue
        g = vertices[cid]
        st = parse_style(st_raw)
        label = plain_label(c.get("value"))
        if st_raw.startswith("text;"):
            align_left = st.get("align") == "left"
            x = g["x"] if align_left else g["x"] + g["width"] / 2
            anchor = "start" if align_left else "middle"
            out.append(f'<text x="{x:.1f}" y="{g["y"] + g["height"]*0.7:.1f}" text-anchor="{anchor}" fill="{st.get("fontColor", "#1D2939")}" font-family="Inter,Arial,sans-serif" font-size="{st.get("fontSize", "14")}" font-weight="{700 if st.get("fontStyle") == "1" else 400}">{html.escape(label)}</text>')
            continue
        fill, stroke, font = st.get("fillColor", "#FFF"), st.get("strokeColor", "#667085"), st.get("fontColor", "#1D2939")
        if "rhombus" in st_raw:
            pts = f'{g["x"]+g["width"]/2},{g["y"]} {g["x"]+g["width"]},{g["y"]+g["height"]/2} {g["x"]+g["width"]/2},{g["y"]+g["height"]} {g["x"]},{g["y"]+g["height"]/2}'
            out.append(f'<polygon points="{pts}" fill="{fill}" stroke="{stroke}" stroke-width="1.5" filter="url(#shadow)"/>')
        else:
            out.append(f'<rect x="{g["x"]}" y="{g["y"]}" width="{g["width"]}" height="{g["height"]}" rx="14" fill="{fill}" stroke="{stroke}" stroke-width="1.5" filter="url(#shadow)"/>')
        out.append(svg_text(label, g["x"], g["y"], g["width"], g["height"], font, 13.5, True))
    # Diagram metadata footer.
    sources = " · ".join(spec["sources"])
    out.append(f'<text x="30" y="{h-24}" fill="#667085" font-family="Inter,Arial,sans-serif" font-size="11">Verified {VERIFIED_COMMIT[:8]} · {html.escape(spec["audience"])} · {html.escape(sources)}</text>')
    out.append("</svg>")
    (SVG / f"{path.stem}.drawio.svg").write_text("\n".join(out) + "\n", encoding="utf-8")


def dot_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def write_code_dots(manifest):
    colors = {k: v for k, v in PALETTE.items()}
    for graph in manifest["graphs"]:
        rankdir = graph.get("rankdir", "LR")
        lines = [
            f'digraph "{graph["id"]}" {{',
            f'  graph [rankdir={rankdir}, bgcolor="transparent", pad="0.3", nodesep="0.48", ranksep="0.75", splines=polyline, fontname="Arial", labeljust="l"];',
            '  node [shape=box, style="rounded,filled", fontname="Arial", fontsize=11.5, margin="0.16,0.10", penwidth=1.3];',
            '  edge [fontname="Arial", fontsize=9.5, color="#667085", fontcolor="#475467", arrowsize=0.75, penwidth=1.2];',
        ]
        groups = {}
        for n in graph["nodes"]:
            groups.setdefault(n.get("group", "Other"), []).append(n)
        for gi, (group, nodes) in enumerate(groups.items()):
            lines += [f'  subgraph cluster_{gi} {{', f'    label="{dot_escape(group)}";', '    color="#D0D5DD"; style="rounded,dashed"; fontcolor="#475467"; fontsize=11;']
            for n in nodes:
                fill, stroke, font = colors[n.get("color", "gray")]
                label = n["label"]
                if n.get("file"):
                    label += "\n" + n["file"]
                lines.append(f'    "{n["id"]}" [label="{dot_escape(label)}", fillcolor="{fill}", color="{stroke}", fontcolor="{font}"];')
            lines.append("  }")
        edge_styles = {
            "calls": ("solid", "#3266CC"), "callback": ("dashed", "#7A4CC2"),
            "state": ("dotted", "#17877F"), "spawns": ("bold", "#C77800"),
            "persists": ("dashed", "#667085"), "guards": ("bold", "#B42318"),
            "returns": ("dashed", "#2D7A50"),
        }
        for e in graph["edges"]:
            style, color = edge_styles.get(e.get("type", "calls"), ("solid", "#667085"))
            label = e.get("label", e.get("type", ""))
            lines.append(f'  "{e["from"]}" -> "{e["to"]}" [label="{dot_escape(label)}", style="{style}", color="{color}", fontcolor="{color}"];')
        lines += [
            f'  labelloc="t"; label="{dot_escape(graph["title"])}\\n{dot_escape(graph["desc"])}";',
            "}",
        ]
        (DOT / f'{graph["id"]}.dot').write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--init", action="store_true", help="create missing native draw.io sources")
    args = parser.parse_args()
    SRC.mkdir(parents=True, exist_ok=True)
    SVG.mkdir(parents=True, exist_ok=True)
    DOT.mkdir(parents=True, exist_ok=True)
    if args.init:
        for name, spec in CONCEPTS.items():
            write_drawio(name, spec)
    for name, spec in CONCEPTS.items():
        path = SRC / f"{name}.drawio"
        if not path.exists():
            raise SystemExit(f"Missing concept source: {path}; run with --init")
        render_drawio(path, spec)
    manifest = json.loads((SRC / "code-graphs.json").read_text(encoding="utf-8"))
    write_code_dots(manifest)
    print(f"Rendered {len(CONCEPTS)} draw.io SVGs and {len(manifest['graphs'])} DOT files")


if __name__ == "__main__":
    main()
