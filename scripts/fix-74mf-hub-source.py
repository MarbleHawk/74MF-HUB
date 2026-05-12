#!/usr/bin/env python3
"""
Fix common 74mf Hub v3 source issues before obfuscation:

1. Corrupted normKey (YouTube URL accidentally pasted into :gsub chain).
2. Optional: set canonical YouTube @ handle URL.
3. Replace invalid Roblox pattern Instance.new("UICorner", parent).CornerRadius = ...
   with proper Instance.new + .Parent assignment.

Usage:
  python3 scripts/fix-74mf-hub-source.py path/to/your-hub.lua -o 74mf-hub-v3-source.lua
  python3 scripts/fix-74mf-hub-source.py path/to/your-hub.lua --in-place
"""

from __future__ import annotations

import argparse
import re
import sys

CANONICAL_YT = "https://www.youtube.com/@74MF_FreeScripts"

# Broken paste: URL accidentally inserted before gsub (Lua parser error near ':')
NORMKEY_BROKEN_FRAGMENTS = (
    ":https://www.youtube.com/@74MF_FreeScriptsgsub",
    ":http://www.youtube.com/@74MF_FreeScriptsgsub",
)

UICORNER_RE = re.compile(
    r'^(\s*)Instance\.new\("UICorner",\s*([^)]+)\)\.CornerRadius\s*=\s*(UDim\.new\([^)]+\))\s*$',
    re.MULTILINE,
)


def fix_normkey(text: str) -> str:
    for frag in NORMKEY_BROKEN_FRAGMENTS:
        if frag in text:
            return text.replace(frag, ":gsub", 1)
    # Fallback: any :https...gsub splice before string.gsub call
    t, n = re.subn(
        r'(tostring\(s or ""\)):\s*https?://[^\n]+?gsub',
        r"\1:gsub",
        text,
        count=1,
    )
    return t if n else text


def fix_youtube_constant(text: str) -> str:
    text, n = re.subn(
        r'local\s+HUB_YOUTUBE_URL\s*=\s*"[^"]*"',
        f'local HUB_YOUTUBE_URL = "{CANONICAL_YT}"',
        text,
        count=1,
    )
    return text


def fix_uicorners(text: str) -> str:
    def repl(m: re.Match) -> str:
        indent, parent, udim = m.group(1), m.group(2).strip(), m.group(3).strip()
        return (
            f"{indent}do\n"
            f"{indent}\tlocal _corner = Instance.new(\"UICorner\")\n"
            f"{indent}\t_corner.CornerRadius = {udim}\n"
            f"{indent}\t_corner.Parent = {parent}\n"
            f"{indent}end"
        )

    return UICORNER_RE.sub(repl, text)


def strip_trailing_rage(text: str) -> str:
    for junk in (
        "THIS IS THE FUCKING HUB STUPID ROBOT",
        "fix this im getting errors",
    ):
        text = text.replace(junk, "")
    return text.rstrip() + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="Path to hub .lua source")
    ap.add_argument("-o", "--output", help="Write fixed source here (default: stdout)")
    ap.add_argument("--in-place", action="store_true", help="Overwrite input file")
    args = ap.parse_args()

    path = args.input
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()

    before = text
    text = strip_trailing_rage(text)
    text = fix_normkey(text)
    text = fix_youtube_constant(text)
    text = fix_uicorners(text)

    if text == before:
        print("warning: no changes applied (already fixed or patterns not found)", file=sys.stderr)

    out = path if args.in_place else args.output
    if args.in_place:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"wrote in-place: {path}", file=sys.stderr)
    elif out:
        with open(out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"wrote: {out}", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
