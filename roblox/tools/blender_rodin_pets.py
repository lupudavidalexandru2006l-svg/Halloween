# Run inside Blender (Scripting > Python console), MCP for Blender addon enabled:
#   exec(open(r"C:\Users\Lupu David\Documents\GitHub\Halloween\roblox\tools\blender_rodin_pets.py").read())
# Turns each approved pet concept into a textured GLB: roblox/assets/pets/<key>.glb (image-to-3D,
# Pet Rules 5). Provider: Tripo (default; key from the addon's preferences: Edit > Preferences >
# Add-ons > MCP for Blender > Tripo API Key) or Rodin (the addon's Hyper3D key).
# Set before exec() if needed:  PETS3D_PROVIDER = "rodin"   PETS3D_ONLY = ["waddles"]
# Runs in a background thread so Blender stays usable; progress in rodin_log.txt next to the GLBs.
# Pets that already have a GLB are skipped, so it is safe to run again after a stop.
import json, os, threading, time
import bpy, requests
import blender_mcp as addon

REPO = r"C:\Users\Lupu David\Documents\GitHub\Halloween"
CONCEPTS = os.path.join(REPO, "prototype", "ice-ray-for-pets", "pets")
OUT = os.path.join(REPO, "roblox", "assets", "pets")
os.makedirs(OUT, exist_ok=True)
LOG = os.path.join(OUT, "rodin_log.txt")

# key -> concept file (cleaned 3D inputs where they exist)
PETS = {
    "waddles": "waddles-v1.png", "mittenkit": "mittenkit-v1.png", "pupcicle": "pupcicle-v1.png",
    "blizzard_yeti": "blizzard-yeti-3d-input-v1.png", "aurora_owl": "aurora-owl-3d-input-v1.png",
    "snowglobe_drake": "snowglobe-drake-3d-input-v1.png", "conehog": "conehog-v1.png",
    "hopsprout": "hopsprout-v1.png", "capmouse": "capmouse-v1.png", "mossfawn": "mossfawn-v1.png",
    "lanternbug": "lanternbug-v1.png", "mapleguard_bear": "mapleguard-bear-v1.png",
    "bloomhorn_stag": "bloomhorn-stag-v2.png", "glowshroom_mammoth": "glowshroom-mammoth-v1.png",
}
PROVIDER = globals().get("PETS3D_PROVIDER", "tripo")
ONLY = globals().get("PETS3D_ONLY") or globals().get("RODIN_ONLY")

def log(msg):
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(time.strftime("%H:%M:%S ") + msg + "\n")

# keys and settings are read here, on Blender's main thread; the thread below only does HTTP
_prefs = addon.get_blendermcp_addon_preferences()
def _setting(scene_attr, pref_attr, env):
    v = getattr(_prefs, pref_attr, "") if _prefs else ""
    return v or getattr(bpy.context.scene, scene_attr, "") or os.getenv(env, "")

if PROVIDER == "tripo":
    TRIPO_KEY = _setting("blendermcp_tripo_api_key", "tripo_api_key", "BLENDERMCP_TRIPO_API_KEY")
    TRIPO_MODEL = getattr(bpy.context.scene, "blendermcp_tripo_model", addon.TRIPO_DEFAULT_MODEL) or addon.TRIPO_DEFAULT_MODEL
    TRIPO_HEAD = {**addon.TRIPO_HEADERS, "Authorization": f"Bearer {TRIPO_KEY}"}
else:
    RODIN_KEY = _setting("blendermcp_hyper3d_api_key", "hyper3d_api_key", "BLENDERMCP_HYPER3D_API_KEY")
    RODIN_HEAD = {"Authorization": f"Bearer {RODIN_KEY}"}

def tripo_data(r):
    p = r.json()
    if r.status_code == 401 or p.get("code") in (1000, 1001):
        raise RuntimeError("refused: Tripo rejected the API key")
    if p.get("code") not in (0, None):
        raise RuntimeError(f"refused: Tripo code {p.get('code')}: {p.get('message')}")
    return p["data"]

def tripo_make(key, path):
    with open(path, "rb") as f:
        up = tripo_data(requests.post(f"{addon.TRIPO_API_BASE}/files", headers=TRIPO_HEAD, files={"file": (os.path.basename(path), f, "image/png")}, timeout=(10, 60)))
    task = tripo_data(requests.post(f"{addon.TRIPO_API_BASE}/generation/image-to-model", headers=TRIPO_HEAD,
        json={"model": TRIPO_MODEL, "input": up["file_token"], "texture": True, "pbr": True}, timeout=(10, 60)))["task_id"]
    log(f"{key}: submitted {task}")
    for _ in range(180):  # up to 15 minutes
        d = tripo_data(requests.get(f"{addon.TRIPO_API_BASE}/tasks/{task}", headers=TRIPO_HEAD, timeout=(10, 60)))
        if d.get("status") == "success":
            out = d.get("output") or {}
            return out.get("model_url") or out.get("pbr_model") or out.get("model")
        if d.get("status") in ("failed", "cancelled", "banned", "expired"):
            raise RuntimeError(f"task {d.get('status')}")
        time.sleep(5)
    raise RuntimeError("timed out")

def rodin_make(key, path):
    with open(path, "rb") as f:
        img = f.read()
    files = [("images", ("0000.png", img)), ("tier", (None, "Sketch")), ("mesh_mode", (None, "Raw")), ("texture_mode", (None, "high"))]
    data = requests.post("https://hyperhuman.deemos.com/api/v2/rodin", headers=RODIN_HEAD, files=files, timeout=90).json()
    if "uuid" not in data:
        raise RuntimeError(f"refused: {json.dumps(data)[:300]}")
    log(f"{key}: submitted {data['uuid']}")
    for _ in range(120):
        jobs = requests.post("https://hyperhuman.deemos.com/api/v2/status", headers=RODIN_HEAD, json={"subscription_key": data["jobs"]["subscription_key"]}, timeout=30).json().get("jobs", [])
        states = [j["status"] for j in jobs]
        if states and all(s == "Done" for s in states):
            break
        if "Failed" in states:
            raise RuntimeError("task failed")
        time.sleep(5)
    for item in requests.post("https://hyperhuman.deemos.com/api/v2/download", headers=RODIN_HEAD, json={"task_uuid": data["uuid"]}, timeout=30).json().get("list", []):
        if item["name"].endswith(".glb"):
            return item["url"]
    raise RuntimeError("no GLB in the download list")

def run():
    log(f"start: {PROVIDER}, {len(ONLY) if ONLY else len(PETS)} pets")
    for key, filename in PETS.items():
        if ONLY and key not in ONLY:
            continue
        dest = os.path.join(OUT, key + ".glb")
        if os.path.exists(dest):
            log(f"{key}: already done")
            continue
        try:
            url = (tripo_make if PROVIDER == "tripo" else rodin_make)(key, os.path.join(CONCEPTS, filename))
            g = requests.get(url, timeout=(10, 180))
            g.raise_for_status()
            with open(dest, "wb") as f:
                f.write(g.content)
            log(f"{key}: done ({len(g.content) // 1024} KB)")
        except Exception as e:
            log(f"{key}: ERROR {e}")
            if "refused" in str(e):
                break  # bad key or out of credits: stop instead of hammering
    log("finished")

if PROVIDER == "tripo" and not TRIPO_KEY:
    print("No Tripo API key yet: Edit > Preferences > Add-ons > MCP for Blender > Tripo API Key")
else:
    threading.Thread(target=run, daemon=True).start()
    print("Pet 3D started; progress in", LOG)
