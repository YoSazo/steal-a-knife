"""Replace only the lair title mounts; retain the old SurfaceGui branch for comparison."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
path=ROOT/'src/server/Services/GuardService.luau'
text=path.read_text()
needle='local ToyBlockModel = require(ReplicatedStorage.Shared.ToyBlockModel)'
assert text.count(needle)==1
text=text.replace(needle,needle+'\nlocal BossTitleModel = require(ReplicatedStorage.Shared.BossTitleModel)\n\n-- Retained for side-by-side verification; production lair titles use physical voxel meshes.\nlocal USE_LEGACY_2D_TITLES = false')
start=text.index('\t-- The art-pack sign',text.index('local function buildLair'))
end=text.index('\t-- Torches at both front corners',start)
old=text[start:end]
body=old[old.index('\tlocal signWidth'):]
replacement='''\t-- Mount canvases keep the original dimensions and frames, including transparent margins.
\tlocal signWidth = math.min(W - 6, 26)
\tlocal signSize = CartoonArt.LairSignSize
\tlocal ribbonWidth = signWidth * 0.62
\tlocal ribbonSize = CartoonArt.BossRibbonSize
\tlocal ribbonHeight = ribbonWidth * ribbonSize.Y / ribbonSize.X
\tif USE_LEGACY_2D_TITLES then
'''
# The old artPart/SurfaceGui implementation remains intact behind the disabled switch.
replacement+=''.join('\t'+line+'\n' for line in body.splitlines() if not line.startswith('\tlocal signWidth') and not line.startswith('\tlocal signSize') and not line.startswith('\tlocal ribbonWidth') and not line.startswith('\tlocal ribbonSize') and not line.startswith('\tlocal ribbonHeight'))
replacement+='''\telse
\t\tlocal function mount(name: string, size: Vector3, cframe: CFrame): Part
\t\t\tlocal part = block(model, name, size, cframe, Color3.new())
\t\t\tpart.Transparency = 1
\t\t\tpart.CanCollide, part.CanQuery, part.CanTouch = false, false, false
\t\t\tpart.CastShadow = false
\t\t\tpart:SetAttribute("BossTitleMount", true)
\t\t\treturn part
\t\tend
\t\tlocal sign = mount(
\t\t\t"Sign",
\t\t\tVector3.new(signWidth, signWidth * signSize.Y / signSize.X, 0.2),
\t\t\tat(0, PLATFORM + 14, wallZ - 1.2)
\t\t)
\t\tlocal ribbon = mount(
\t\t\t"SignRibbon",
\t\t\tVector3.new(ribbonWidth, ribbonHeight, 0.2),
\t\t\tat(0, PLATFORM + 14 - signWidth * signSize.Y / signSize.X / 2 - ribbonHeight / 2 + 0.3, wallZ - 1.3)
\t\t)
\t\tlocal titles = BossTitleModel.Build(config.Boss, sign, ribbon)
\t\tif titles then
\t\t\ttitles.Parent = model
\t\tend
\tend
'''
text=text[:start]+replacement+text[end:]
needle='\t-- How high a rig\'s root sits so feet touch the floor'
assert text.count(needle)==1
text=text.replace(needle,'\tif not USE_LEGACY_2D_TITLES then\n\t\tBossTitleModel.Preload()\n\tend\n\n'+needle)
path.write_text(text)
print('Mounted block titles; original 2D code retained behind a false switch')
