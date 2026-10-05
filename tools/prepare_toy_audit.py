"""Package detached old/new builder copies to compare interaction/UI contracts in Studio."""
import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/toy-redesign'
def source(name,old=False):
    p=OUT/(name+'.before.txt') if old else ROOT/'src/server/Services'/(name+'.luau')
    return p.read_text(encoding='utf-8')
def between(s,a,b):return s[s.index(a):s.index(b,s.index(a))]
shared='''local GameConfig=require(script.Parent.Config.GameConfig)
local ToyBlockModel=require(script.Parent.ToyBlockModel)
local Props=require(script.Parent.Props)
local Toy=require(script.Parent.Toy)
local SignTheme=require(script.Parent.SignTheme)
local CartoonArt=require(script.Parent.Config.CartoonArt)
local KnifeModel=require(script.Parent.KnifeModel)
local KnifeAura={Mount=function() end}
local ManorDecor={ClearArea=function() end}
local function torchStyle() return {} end
local folder
local rgb=Color3.fromRGB
'''
modules={}
for old in (True,False):
    suffix='Old' if old else 'New'
    s=source('GuardService',old)
    helper=between(s,'local function block(', 'local function billboard(')
    body=between(s,'local function buildLair(', '-- Chasing ')
    modules['Lair'+suffix]=shared+'local PLATFORM=.8\nlocal HEIGHT=3\n'+helper+body+'''return function(index)
folder=Instance.new("Folder")
local boss=buildLair(index,{},GameConfig.Zones[index])
boss.Folder.Parent=nil
folder:Destroy()
return boss
end
'''
    s=source('ShopNPCs',old)
    helper=between(s,'local function block(', '-- The stall:')
    body=between(s,'local function buildStall(', 'local function buildKeeper(')
    modules['Shop'+suffix]=shared+helper+body+'''return function(panel)
local parent=Instance.new("Folder")
local spec={Name=if panel=="Shop" then "Mortimer" else "Madame Vesper",Panel=panel,
Title=if panel=="Shop" then "Knife Merchant" else "Power Mystic",
Color=if panel=="Shop" then Color3.fromRGB(70,200,90) else Color3.fromRGB(170,90,255)}
buildStall(parent,spec,CFrame.new(4500,0,4500)*CFrame.Angles(0,.6,0))
return parent
end
'''
    s=source('ManorDecor',old)
    helper=between(s,'local function block(', '-- Walk-through decoration')
    body=between(s,'local function eventBoard(', '-- Build ')
    modules['Board'+suffix]=shared+helper+'local function at(x,y,z) return CFrame.new(x,y,z) end\n'+body+'''return function()
folder=Instance.new("Folder")
eventBoard(-4,160)
return folder
end
'''
    s=source('Rewards',old)
    body=between(s,'local function buildChest(', '-- Index rewards')
    at=re.search(r'local CHEST_AT = (.*)',s)[1]
    modules['Chest'+suffix]=shared+'local CHEST_AT='+at+'\nlocal function claimFreeChest() end\n'+body+'''return function()
local parent=Instance.new("Folder")
buildChest(parent)
return parent
end
'''
modules['ToyAssetsAudit']=(ROOT/'tests/ToyAssets.studio.luau').read_text()
(OUT/'audit-fixtures.json').write_text(json.dumps(modules,ensure_ascii=False))
