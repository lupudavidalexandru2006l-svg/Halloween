"""Make a Rojo-style sourcemap.json from default.project.json without Rojo installed.
Usage: python3 make_sourcemap.py <project dir>  (writes <project dir>/sourcemap.json)"""
import json
import sys
from pathlib import Path

proj = Path(sys.argv[1]).resolve()
tree = json.loads((proj / "default.project.json").read_text())["tree"]


def file_node(path: Path):
    name = path.name
    for suffix, cls in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if name.endswith(suffix):
            return {"name": name[: -len(suffix)], "className": cls, "filePaths": [str(path.relative_to(proj))]}
    return None


def dir_node(path: Path, name: str):
    init = next((path / f for f in ("init.server.luau", "init.client.luau", "init.luau") if (path / f).exists()), None)
    node = file_node(init) if init else {"name": name, "className": "Folder", "filePaths": []}
    node["name"] = name
    kids = []
    for child in sorted(path.iterdir()):
        if init and child == init:
            continue
        if child.is_dir():
            kids.append(dir_node(child, child.name))
        else:
            n = file_node(child)
            if n:
                kids.append(n)
    node["children"] = kids
    return node


def walk(name, spec):
    if "$path" in spec:
        p = proj / spec["$path"]
        node = dir_node(p, name) if p.is_dir() else (file_node(p) if p.exists() else None)
        node = node or {"name": name, "className": "Folder", "children": []}
        node["name"] = name
    else:
        node = {"name": name, "className": spec.get("$className", "Folder"), "children": []}
    for k, v in spec.items():
        if not k.startswith("$"):
            node.setdefault("children", []).append(walk(k, v))
    return node


root = walk("IceRayForPets", tree)
root["className"] = "DataModel"
(proj / "sourcemap.json").write_text(json.dumps(root, indent=1))
print("sourcemap.json written")
