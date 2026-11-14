# trellis_run.py <out_raw.glb> <view.png> [<view.png> ...]: one TRELLIS run (default settings) on the owner's
# Hugging Face login, no browser and no drag: HF_TOKEN from the environment, the Space's Gradio queue API, the
# same steps the page does, in one session. One image: start_session, preprocess_image, generate_and_extract_glb.
# Several views of one pet (e.g. split_turnaround.ps1's front/left/back/right): the "Multiple Images" tab
# (multi_tab sets the session's is_multiimage state), preprocess_images, then generate from all of them.
# Run it with Blender's Python (there is no other Python on David's PC):
#   "C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" -I trellis_run.py <raw.glb> <png> ...
# fn_index / trigger ids come from the Space's /config (dependencies); re-check them if the Space changes.
import json, os, sys, uuid, urllib.request

S = "https://trellis-community-trellis.hf.space/gradio_api"
# GUEST=1 runs without the login (its own small daily quota, by IP)
AUTH = {} if os.environ.get("GUEST") else {"Authorization": "Bearer " + os.environ["HF_TOKEN"]}
SESSION = uuid.uuid4().hex[:11]
# MODE=multidiffusion: the other way the Space blends several views (stochastic is the default); SEED=<n> for
# a different try of the same input (Scarabit 2026-11-14: stochastic put its horns on the sides, bottom white)
MODE = os.environ.get("MODE", "stochastic")
SEED = int(os.environ.get("SEED", "0"))
FN = {"start_session": 4, "multi_tab": 7, "preprocess_image": 8, "preprocess_images": 9, "generate_and_extract_glb": 11}
TRIG = {"start_session": 0, "multi_tab": 7, "preprocess_image": 6, "preprocess_images": 8, "generate_and_extract_glb": 30}
CRLF = b"\r\n"


def req(url, data=None, headers=None):
    h = dict(AUTH, **(headers or {}))
    return urllib.request.urlopen(urllib.request.Request(url, data=data, headers=h), timeout=600)


def run(name, data):
    body = json.dumps({"data": data, "fn_index": FN[name], "trigger_id": TRIG[name],
                       "session_hash": SESSION, "event_data": None}).encode()
    eid = json.load(req(S + "/queue/join", body, {"Content-Type": "application/json"}))["event_id"]
    with req(S + "/queue/data?session_hash=" + SESSION) as r:
        for line in r:
            line = line.decode().strip()
            if not line.startswith("data:"):
                continue
            m = json.loads(line[5:])
            if m.get("event_id") not in (None, eid):
                continue
            if m.get("msg") in ("estimation", "progress", "process_starts"):
                print(name, m.get("msg"), m.get("rank", ""), flush=True)
            if m.get("msg") == "process_completed":
                if not m.get("success"):
                    sys.exit("%s failed: %s" % (name, json.dumps(m)[:600]))
                return m["output"]["data"]


def upload(img):
    bnd = uuid.uuid4().hex.encode()
    name = os.path.basename(img).encode()
    body = (b"--" + bnd + CRLF + b'Content-Disposition: form-data; name="files"; filename="' + name + b'"' + CRLF
            + b"Content-Type: image/png" + CRLF + CRLF + open(img, "rb").read() + CRLF + b"--" + bnd + b"--" + CRLF)
    path = json.load(req(S + "/upload", body, {"Content-Type": "multipart/form-data; boundary=" + bnd.decode()}))[0]
    return {"path": path, "meta": {"_type": "gradio.FileData"}, "orig_name": os.path.basename(img)}


out, imgs = sys.argv[1], sys.argv[2:]
if out.lower().endswith(".png"):  # the old order: <painting.png> <out_raw.glb>
    imgs, out = [out], imgs[0]
fds = [upload(i) for i in imgs]
run("start_session", [])
if len(fds) == 1:
    pre = run("preprocess_image", [fds[0]])[0]
    res = run("generate_and_extract_glb", [pre, [], None, SEED, 7.5, 12, 3.0, 12, MODE, 0.95, 1024])
else:
    run("multi_tab", [])
    gal = run("preprocess_images", [[{"image": f, "caption": None} for f in fds]])[0]
    res = run("generate_and_extract_glb", [None, gal, None, SEED, 7.5, 12, 3.0, 12, MODE, 0.95, 1024])
glb = next(x["url"] for x in res[1:] if isinstance(x, dict) and str(x.get("url", "")).endswith(".glb"))
with req(glb) as r, open(out, "wb") as f:
    f.write(r.read())
print("SAVED", out, os.path.getsize(out))
