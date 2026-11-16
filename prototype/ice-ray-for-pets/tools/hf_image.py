# hf_image.py: one painting from the free FLUX.1 schnell Space on Hugging Face (same login and ZeroGPU quota
# as TRELLIS). Run with Blender's Python:  python -I hf_image.py <out.png> <prompt.txt> [<prompt.txt> ...] [WxH]
# The prompt files are joined with a space (style block + pet block). HF_TOKEN from the environment.
# The Space returns WebP; the result is converted to a real PNG with Blender's image module when possible.
import json, os, sys, urllib.request

S = "https://black-forest-labs-flux-1-schnell.hf.space/gradio_api"
AUTH = {"Authorization": "Bearer " + os.environ["HF_TOKEN"]}
args = sys.argv[1:]
out = args.pop(0)
size = args.pop() if args and "x" in args[-1] and not args[-1].endswith(".txt") else "1536x768"
w, h = (int(v) for v in size.split("x"))
prompt = " ".join(open(p, encoding="utf-8").read().strip() for p in args)
seed = int(os.environ.get("SEED", "0"))


def req(url, data=None, headers=None):
    return urllib.request.urlopen(urllib.request.Request(url, data=data, headers=dict(AUTH, **(headers or {}))), timeout=600)


body = json.dumps({"data": [prompt, seed, seed == 0, w, h, 4]}).encode()
eid = json.load(req(S + "/call/infer", body, {"Content-Type": "application/json"}))["event_id"]
ev = None
with req(S + "/call/infer/" + eid) as r:
    for line in r:
        line = line.decode().strip()
        if line.startswith("event:"):
            ev = line[6:].strip()
        elif line.startswith("data:") and ev in ("complete", "error"):
            if ev == "error":
                sys.exit("FLUX failed: " + line[5:][:500])
            img = json.loads(line[5:])[0]
            url = img.get("url") or (S + "/file=" + img["path"])
            raw = req(url).read()
            tmp = out + ".webp"
            open(tmp, "wb").write(raw)
            print("SAVED", tmp, len(raw))
            break
