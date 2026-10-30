#!/usr/bin/env bash
# Strict type check of the Rojo project without Studio (cloud sessions; needs Python 3).
# LUAU_LSP: path to a luau-lsp binary. DEFS: the globalTypes.d.luau from the SAME luau-lsp release
# (raw.githubusercontent.com/JohnnyMorganz/luau-lsp/<version>/scripts/globalTypes.d.luau);
# a newer types file uses syntax an older luau-lsp can't read, and it runs out of memory.
# On the owner's PC, `rojo sourcemap` replaces make_sourcemap.py.
# Cloud session: the binary is the release asset luau-lsp-linux.zip (not ...-linux-x86_64.zip, that
# name 404s), e.g. github.com/JohnnyMorganz/luau-lsp/releases/download/1.36.0/luau-lsp-linux.zip.
# The npm package "luau-lsp" is an empty placeholder.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${LUAU_LSP:?set LUAU_LSP}" "${DEFS:?set DEFS}"
python3 -I tools/make_sourcemap.py .
"$LUAU_LSP" analyze --platform roblox --definitions "$DEFS" --sourcemap sourcemap.json src
