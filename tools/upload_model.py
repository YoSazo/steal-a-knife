"""Upload a model/mesh file to Roblox via Open Cloud and print the asset id.

Usage:  python tools/upload_model.py blender/exports/knife_basic.fbx "Basic Knife"
Needs ROBLOX_API_KEY and ROBLOX_USER_ID (or ROBLOX_GROUP_ID) in .env.
The printed asset id can then be inserted into Studio (Studio MCP `insert_asset`).
"""

import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = "https://apis.roblox.com/assets/v1"

CONTENT_TYPES = {
    ".fbx": "model/fbx",
    ".glb": "model/gltf-binary",
    ".gltf": "model/gltf+json",
    ".obj": "model/obj",
    ".rbxm": "model/x-rbxm",
    ".png": "image/png",
    ".jpg": "image/jpeg",
}


def load_env():
    env_file = ROOT / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())


def request(method, url, api_key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", api_key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} from {url}: {e.read().decode(errors='replace')}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    load_env()
    api_key = os.environ.get("ROBLOX_API_KEY")
    if not api_key:
        sys.exit("ROBLOX_API_KEY missing - copy .env.example to .env and fill it in")

    path = Path(sys.argv[1])
    name = sys.argv[2] if len(sys.argv) > 2 else path.stem
    ext = path.suffix.lower()
    asset_type = "Decal" if ext in (".png", ".jpg") else "Model"

    group_id = os.environ.get("ROBLOX_GROUP_ID")
    creator = {"groupId": group_id} if group_id else {"userId": os.environ["ROBLOX_USER_ID"]}
    meta = {
        "assetType": asset_type,
        "displayName": name[:50],
        "description": f"Steal a Knife - {name}",
        "creationContext": {"creator": creator},
    }

    boundary = uuid.uuid4().hex
    file_type = CONTENT_TYPES.get(ext) or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n"
        f"Content-Type: application/json\r\n\r\n{json.dumps(meta)}\r\n"
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{path.name}\"\r\n"
        f"Content-Type: {file_type}\r\n\r\n"
    ).encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()

    op = request("POST", f"{API}/assets", api_key, body, f"multipart/form-data; boundary={boundary}")
    op_id = op["path"].split("/")[-1]
    print(f"Uploading {path.name} as {asset_type} (operation {op_id})...")

    for _ in range(60):
        op = request("GET", f"{API}/operations/{op_id}", api_key)
        if op.get("done"):
            if "error" in op:
                sys.exit(f"Upload failed: {op['error']}")
            asset_id = op["response"]["assetId"]
            print(f"ASSET_ID={asset_id}")
            log = ROOT / "blender" / "uploaded_assets.json"
            data = json.loads(log.read_text()) if log.exists() else {}
            data[name] = {"assetId": asset_id, "file": str(path.as_posix()), "uploaded": time.strftime("%Y-%m-%d %H:%M")}
            log.write_text(json.dumps(data, indent=2))
            return
        time.sleep(2)
    sys.exit("Timed out waiting for Roblox to process the upload (it may still finish - check Creator Hub)")


if __name__ == "__main__":
    main()
