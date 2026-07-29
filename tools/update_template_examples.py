#!/usr/bin/env python3
"""Update template META examples/defaults to realistic PBX values and keep Mustache-safe braces."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # Pocket-Provisioner
POCKET = ROOT / "assets" / "templates"
QUICK = ROOT.parent / "Quick-Provisioner" / "templates"

# Realistic hotel / AU site-style examples (safe demo values, not secrets).
COMMON = {
    "sip_server": {
        "example": "pbx.example.com",
        "default": "",
        "description": "Primary SIP registrar hostname or IP (your FreePBX / PBX address).",
    },
    "sip_port": {"example": "5060", "default": "5060"},
    "transport": {"example": "UDP", "default": "UDP"},
    "reg_expiry": {"example": "3600", "default": "3600"},
    "outbound_proxy_host": {"example": "", "default": ""},
    "outbound_proxy_port": {"example": "5060", "default": "5060"},
    "backup_server": {"example": "pbx-backup.example.com", "default": ""},
    "backup_port": {"example": "5060", "default": "5060"},
    "voicemail_number": {"example": "*97", "default": "*97"},
    "wallpaper_url": {
        "example": "http://pbx.example.com/admin/modules/quickprovisioner/media.php?file=logo.jpg",
        "default": "",
    },
    "ring_type": {"example": "Ring1.wav", "default": "Ring1.wav"},
    "ringtone_url": {
        "example": "http://pbx.example.com/admin/modules/quickprovisioner/media.php?file=HotelWake.wav",
        "default": "",
    },
    "screensaver_timeout": {"example": "120", "default": "0"},
    "admin_password": {"example": "ChangeMe!23", "default": ""},
    "web_ui_enabled": {"example": "1", "default": "1"},
    "voice_vlan_id": {"example": "100", "default": ""},
    "data_vlan_id": {"example": "1", "default": ""},
    "cdp_lldp_enabled": {"example": "1", "default": "1"},
    "auto_answer": {"example": "0", "default": "0"},
    "dnd_enabled": {"example": "0", "default": "0"},
    "call_waiting": {"example": "1", "default": "1"},
    "cfw_always": {"example": "", "default": ""},
    "cfw_busy": {"example": "voicemail", "default": ""},
    "cfw_no_answer": {"example": "voicemail", "default": ""},
    "ntp_server": {"example": "0.au.pool.ntp.org", "default": "0.au.pool.ntp.org"},
    "syslog_server": {"example": "syslog.example.com", "default": ""},
    "provisioning_url": {
        "example": "http://pbx.example.com/admin/modules/quickprovisioner",
        "default": "",
    },
    "firmware_url": {
        "example": "http://pbx.example.com/admin/modules/quickprovisioner/media.php?file=T54W.rom",
        "default": "",
    },
}

YEALINK_EXTRA = {
    "timezone": {"example": "+10", "default": "+10"},
    "dst_enable": {"example": "1", "default": "1"},
    "debug_level": {"example": "3", "default": "0"},
    "dial_plan": {
        "example": "([2-8]xx|9xx|*xx.|00x.T|0x.T)",
        "default": "",
        "description": "Yealink digitmap dial plan. Example covers 3-digit rooms, star codes, and outbound.",
    },
}

POLY_EXTRA = {
    "gmt_offset": {"example": "36000", "default": "36000"},
    "dial_plan": {
        "example": "[2-8]xx|9xx|*xx.|0T|00x.T",
        "default": "",
    },
}

CISCO_EXTRA = {
    "timezone": {"example": "GMT+10:00", "default": "GMT+10:00"},
    "web_ui_enabled": {"example": "Yes", "default": "Yes"},
    "cdp_lldp_enabled": {"example": "Yes", "default": "Yes"},
    "auto_answer": {"example": "No", "default": "No"},
    "dnd_enabled": {"example": "No", "default": "No"},
    "call_waiting": {"example": "Yes", "default": "Yes"},
    "debug_level": {"example": "NOTICE", "default": "NOTICE"},
    "dial_plan": {
        "example": "(*xx.|[2-8]xx|9xx|0xxxxxxx|00xxxxxxxxxxxx)",
        "default": "",
    },
}

# Sample button / contact examples for documentation inside META (optional UI later)
SAMPLE_PRESET = {
    "label": "Hotel front-desk demo",
    "notes": "Safe demo values for a typical hotel PBX. Load via Quick-Provisioner Settings → Load Examples.",
    "buttons": [
        {"index": 1, "type": "line", "value": "101", "label": "Front Desk"},
        {"index": 2, "type": "blf", "value": "102", "label": "Housekeeping"},
        {"index": 3, "type": "blf", "value": "103", "label": "Manager"},
        {"index": 4, "type": "speed_dial", "value": "*97", "label": "Voicemail"},
        {"index": 5, "type": "speed_dial", "value": "0", "label": "Operator"},
    ],
}


def mustache_safe_json(obj: dict) -> str:
    compact = json.dumps(obj, separators=(",", ":"), ensure_ascii=False)
    while "}}" in compact:
        compact = compact.replace("}}", "} }")
    json.loads(compact)  # validate
    return compact


def patch_variables(meta: dict, extra: dict) -> None:
    patch = {**COMMON, **extra}
    for var in meta.get("variables", []):
        name = var.get("name")
        if name not in patch:
            continue
        for k, v in patch[name].items():
            if v == "" and k == "example" and var.get("example"):
                # allow clearing intentionally when provided as ""
                var[k] = v
            elif v != "" or k in ("example", "default"):
                var[k] = v
    meta["sample_preset"] = SAMPLE_PRESET


def patch_file(path: Path, extra: dict) -> None:
    text = path.read_text(encoding="utf-8")
    m = re.search(r"(\{\{!\s*META:\s*)(\{[\s\S]*\})(\s*\}\})", text)
    if not m:
        raise SystemExit(f"No META in {path}")
    meta = json.loads(m.group(2))
    patch_variables(meta, extra)
    safe = mustache_safe_json(meta)
    new = text[: m.start()] + m.group(1) + safe + m.group(3) + text[m.end() :]
    path.write_text(new, encoding="utf-8", newline="\n")
    print(f"patched {path}")


def main() -> None:
    mapping = {
        "yealink_t4x.cfg.mustache": YEALINK_EXTRA,
        "polycom_vvx.xml.mustache": POLY_EXTRA,
        "cisco_88xx.xml.mustache": CISCO_EXTRA,
    }
    for name, extra in mapping.items():
        patch_file(POCKET / name, extra)
        patch_file(QUICK / name, extra)


if __name__ == "__main__":
    main()
