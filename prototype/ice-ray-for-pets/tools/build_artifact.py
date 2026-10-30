"""Build artifact.html from index.html for publishing as a claude.ai Artifact.

The artifact host wraps the page in its own doctype/html/head/body with charset and
viewport metas, so those are stripped here. Everything else is kept as is.
Usage: python3 tools/build_artifact.py   (run from prototype/ice-ray-for-pets)
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = (root / "index.html").read_text(encoding="utf-8")

drop = [
    r"<!doctype html>\s*",
    r"<html[^>]*>\s*",
    r"</html>\s*",
    r"<head>\s*",
    r"</head>\s*",
    r"<body[^>]*>\s*",
    r"</body>\s*",
    r'<meta charset="[^"]*">\s*',
    r'<meta name="viewport"[^>]*>\s*',
]
out = src
for pat in drop:
    out = re.sub(pat, "", out, flags=re.IGNORECASE)

if not out.lstrip().startswith("<title>"):
    sys.exit("title is not first after stripping; check index.html")

(root / "artifact.html").write_text(out.rstrip() + "\n", encoding="utf-8")
print(f"artifact.html written, {len(out):,} chars")
