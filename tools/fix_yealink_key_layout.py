#!/usr/bin/env python3
"""Fix Yealink visual_editor key order to match real T46U/T54W/T57W paging.

When >10 DSS keys are programmed, Yealink uses 3 pages of 9 keys:
  L1-5 / R6-9 + page switcher on bottom-right (not a linekey).
  Page2: 10-14 / 15-18
  Page3: 19-23 / 24-27

Refs: BitBlock T46U DSS layout KB; Yealink T54W QSG.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATHS = [
    ROOT / "assets" / "templates" / "yealink_t4x.cfg.mustache",
    ROOT.parent / "Quick-Provisioner" / "templates" / "yealink_t4x.cfg.mustache",
]

LEFT_YS = [52, 80, 108, 136, 164]
RIGHT_YS = [52, 80, 108, 136]  # 4 keys; bottom-right is page switcher


def build_yealink_physical_keys(max_keys: int = 27):
    keys = []
    idx = 1
    for page in (1, 2, 3):
        for y in LEFT_YS:
            if idx > max_keys:
                break
            keys.append(
                {
                    "index": idx,
                    "x": 12,
                    "y": y,
                    "width": 42,
                    "height": 22,
                    "page": page,
                    "side": "left",
                    "role": "line",
                }
            )
            idx += 1
        for y in RIGHT_YS:
            if idx > max_keys:
                break
            keys.append(
                {
                    "index": idx,
                    "x": 286,
                    "y": y,
                    "width": 42,
                    "height": 22,
                    "page": page,
                    "side": "right",
                    "role": "line",
                }
            )
            idx += 1
    return keys


def mustache_safe(obj: dict) -> str:
    compact = json.dumps(obj, separators=(",", ":"), ensure_ascii=False)
    while "}}" in compact:
        compact = compact.replace("}}", "} }")
    json.loads(compact)
    return compact


def patch(path: Path) -> None:
    if not path.exists():
        print("skip missing", path)
        return
    text = path.read_text(encoding="utf-8")
    m = re.search(r"(\{\{!\s*META:\s*)(\{[\s\S]*\})(\s*\}\})", text)
    if not m:
        raise SystemExit(f"no META in {path}")
    meta = json.loads(m.group(2))
    ve = meta.setdefault("visual_editor", {})
    ve["keys_per_page"] = 9
    ve["page_switcher"] = {
        "x": 286,
        "y": 164,
        "width": 42,
        "height": 22,
        "label": "Page",
    }
    ve["keys"] = build_yealink_physical_keys(27)
    ve["expandable_layout"] = False
    ve["expansion_modules"] = {
        "supported": True,
        "max_modules": 3,
        "keys_per_module": 60,
        "keys_per_page": 20,
        "pages_per_module": 3,
        "note": "EXP40/EXP50 style. Keys stored with role=expansion and module=1..N",
    }
    # Touch models keep grid semantics in model_info; physical use 9/page
    mi = ve.setdefault("model_info", {})
    for model in ("T54W", "T46U", "T57W"):
        mi[model] = {
            "type": "physical",
            "max_keys": 27,
            "keys_per_page": 9,
            "page_switcher": True,
        }
    for model in ("T48G", "T58W", "T58G"):
        if model in mi:
            continue
        mi[model] = {"type": "touchscreen", "max_keys": 29 if model == "T48G" else 27, "layout": "grid"}
    meta["max_line_keys"] = 29  # keep highest for touch; physical capped via model_info

    # Sample buttons: leave first key as Line (ext 101), rest BLF — matches hotel desk
    if "sample_preset" in meta and "buttons" in meta["sample_preset"]:
        # Ensure indices stay within page-1 programmable slots 1-9
        buttons = meta["sample_preset"]["buttons"]
        for b in buttons:
            if int(b.get("index", 0)) > 9:
                b["index"] = min(9, int(b["index"]))

    safe = mustache_safe(meta)
    path.write_text(text[: m.start()] + m.group(1) + safe + m.group(3) + text[m.end() :], encoding="utf-8", newline="\n")
    print(f"patched {path} keys={len(ve['keys'])} keys_per_page=9")


def main() -> None:
    for p in PATHS:
        patch(p)


if __name__ == "__main__":
    main()
