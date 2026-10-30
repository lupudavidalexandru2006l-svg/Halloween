#!/usr/bin/env bash
# Download generated art that this cloud session could not fetch (www.figma.com was blocked
# and the Figma Starter plan ran out of MCP calls). Run from any machine or session that can
# reach www.figma.com. The links were made on 2026-10-30 and expire after 7 days.
set -euo pipefail
cd "$(dirname "$0")/../pets"
get() { curl -fL -o "$1" "https://www.figma.com/api/mcp/asset/$2.png" && echo "saved $1"; }
get glowfin-v1.png          7bbe1899-25ea-4460-ad01-fa3873da4590
get reefback-turtle-v1.png  4b125f50-8af2-493d-8f9a-9a6bf10f85d2
get prismapus-v1.png        2d290e2a-9ffc-4312-940f-a4236822bbf9
get beacon-orca-v1.png      fe1414f2-5dde-4f03-9bd6-05709267dca4
# Waddles 3D (Rodin V2, prediction f700b615-bd5b-40f2-85bf-8a343bc50609): its download link
# can only be read with the Figma MCP tool weave_get_model_run_output once the limit resets.
