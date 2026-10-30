# Ice Ray for Pets tools

Most of these need **Python 3 and Node 20**, which the owner's PC does not have (see the vault's Lessons, "no Python or Node on this machine"). They run in a **cloud session** only. Nothing in the game or the prototype needs them at runtime: they make art files and run tests.

| Tool | Runs on | What it does |
| --- | --- | --- |
| `fetch_pending.ps1` | Owner's PC (PowerShell) | Downloads the 4 full-size Sunny Beach concepts. Links expire about 2026-11-06. |
| `fetch_pending.sh` | Cloud (bash + curl) | Same as above, for a session that can reach www.figma.com. |
| `build_artifact.py` | Cloud | Builds `artifact.html` from `index.html` for publishing. |
| `lineup.py` | Cloud | Zone line-up image: concepts cut out, scaled by size class, cube tint, 48 px silhouettes. |
| `clean_3d_input.py` | Cloud | Removes stray floaters from a concept before image-to-3D. |
| `compare_3d.py` | Cloud | Side-by-side sheet: concept next to 3D renders. |
| `make_sprites.py` | Cloud | 256 px WebP pet sprites for the prototype. |
| `bot_summary.py` | Cloud | Summarises playtest bot runs. |
| `node/optimize.mjs` | Cloud | Trims a Rodin GLB under 7,500 triangles, textures to 1024 px. |
| `node/glb_to_json.mjs` | Cloud | GLB to embedded `.gltf.json` (artifacts don't serve `.glb`). |
| `node/inspect.mjs`, `node/render.mjs` | Cloud | Triangle counts and turntable renders of a GLB. |
| `node/play.mjs`, `node/tour.mjs` | Cloud | Headless playtest bot and the screenshot tour. |

On the owner's PC, serve this folder with the PowerShell static server the vault's Lessons name (`.claude/serve.ps1`, launch config "prototypes", port 8771; it lives on that PC, not in this repo). The playtest bot and timer panel are built into the page (`?bot=1`, key T), so they need no tools.
