"""Prepare detached Studio audits and exports from the actual current sources."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/vaults/plates"
OUT.mkdir(exist_ok=True)

def source(path):
    return (ROOT / path).read_text(encoding="utf-8")

map_source = source("src/server/Services/MapService.luau")
style = map_source[map_source.index("function MapService.SetVaultTier"):map_source.index("-- Rebuild only when the tier changes")]
style = style.replace("base: BaseSite", "base: any")
style = 'local VaultModel = require(script.Parent.VaultModel)\nlocal MapService = {}\n' + style + '\nreturn MapService'
walls = source("src/server/Services/VaultWalls.luau").replace("require(ReplicatedStorage.Shared.VaultModel)", "require(script.Parent.VaultModel)")
modules = {
    "VaultModel": source("src/shared/VaultModel.luau"),
    "VaultWalls": walls,
    "MapStyle": style,
    "Audit": source("tests/VaultDetails.studio.luau"),
    "Export": source("tools/export_vaults.studio.luau"),
}
code = 'local root = Instance.new("Folder")\nlocal function module(name, source)\nlocal m=Instance.new("ModuleScript") m.Name=name m.Source=source m.Parent=root end\n'
for name, body in modules.items():
    code += f'module("{name}", [====[{body}]====])\n'
code += '''
local ok, result = xpcall(function()
    local audit = require(root.Audit)
    local scenes = require(root.Export)
    local encoded = game:GetService("HttpService"):JSONEncode(scenes)
    _G.CodexPlateExport = encoded
    return { Audit = audit, Bytes = #encoded }
end, debug.traceback)
root:Destroy()
return { Ok = ok, Result = result }
'''
(OUT / "studio-runner.json").write_text(json.dumps({"code": code}), encoding="utf-8")
print("Prepared detached current-source audit/export runner")
