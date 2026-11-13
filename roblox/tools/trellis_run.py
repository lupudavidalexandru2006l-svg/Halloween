# trellis_run.py <painting.png> <out_raw.glb>: one TRELLIS run (default settings) on the owner's Hugging Face login,
# no browser and no drag: HF_TOKEN from the environment, the Space's Gradio queue API, the same steps the page
# does (start_session, preprocess_image, generate_and_extract_glb). Run it with Blender's Python (no other Python here):
#   "C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" -I trellis_run.py <png> <raw.glb>
# fn_index / trigger ids come from the Space's /config (dependencies); re-check them if the Space changes.
import json, os, sys, uuid, urllib.request

S = "https://trellis-community-trellis.hf.space/gradio_api"
AUTH = {"Authorization": "Bearer " + os.environ["HF_TOKEN"]}
SESSION = uuid.uuid4().hex[:11]
FN = {"start_session": 4, "preprocess_image": 8, "generate_and_extract_glb": 11}
TRIG = {"start_session": 0, "preprocess_image": 6, "generate_and_extract_glb": 30}


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


img, out = sys.argv[1], sys.argv[2]
bnd = uuid.uuid4().hex
raw = open(img, "rb").read()
body = (b"--" + bnd.encode() + b'\r\nContent-Disposition: form-data; name="files"; filename="'
        + os.path.basename(img).encode() + b'"\r\nContent-Type: image/png\r\n\r\n' + raw
        + b"\r\n--" + bnd.encode() + b"--\r\n")
path = json.load(req(S + "/upload", body, {"Content-Type": "multipart/form-data; boundary=" + bnd}))[0]
run("start_session", [])
fd = {"path": path, "meta": {"_type": "gradio.FileData"}, "orig_name": os.path.basename(img)}
pre = run("preprocess_image", [fd])[0]
res = run("generate_and_extract_glb", [pre, [], None, 0, 7.5, 12, 3.0, 12, "stochastic", 0.95, 1024])
glb = next(x["url"] for x in res[1:] if isinstance(x, dict) and str(x.get("url", "")).endswith(".glb"))
with req(glb) as r, open(out, "wb") as f:
    f.write(r.read())
print("SAVED", out, os.path.getsize(out))
