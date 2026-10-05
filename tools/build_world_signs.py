"""Shared physical sign geometry: Luau runtime and Blender galleries use the same cuboids."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/world-signs';OUT.mkdir(exist_ok=True)
FONT={
'A':['01110','10001','10001','11111','10001','10001','10001'],
'B':['11110','10001','10001','11110','10001','10001','11110'],
'C':['01111','10000','10000','10000','10000','10000','01111'],
'D':['11110','10001','10001','10001','10001','10001','11110'],
'E':['11111','10000','10000','11110','10000','10000','11111'],
'F':['11111','10000','10000','11110','10000','10000','10000'],
'G':['01111','10000','10000','10111','10001','10001','01111'],
'H':['10001','10001','10001','11111','10001','10001','10001'],
'I':['11111','00100','00100','00100','00100','00100','11111'],
'J':['00111','00010','00010','00010','10010','10010','01100'],
'K':['10001','10010','10100','11000','10100','10010','10001'],
'L':['10000','10000','10000','10000','10000','10000','11111'],
'M':['10001','11011','10101','10101','10001','10001','10001'],
'N':['10001','11001','11001','10101','10011','10011','10001'],
'O':['01110','10001','10001','10001','10001','10001','01110'],
'P':['11110','10001','10001','11110','10000','10000','10000'],
'Q':['01110','10001','10001','10001','10101','10010','01101'],
'R':['11110','10001','10001','11110','10100','10010','10001'],
'S':['01111','10000','10000','01110','00001','00001','11110'],
'T':['11111','00100','00100','00100','00100','00100','00100'],
'U':['10001','10001','10001','10001','10001','10001','01110'],
'V':['10001','10001','10001','10001','10001','01010','00100'],
'W':['10001','10001','10001','10101','10101','10101','01010'],
'X':['10001','10001','01010','00100','01010','10001','10001'],
'Y':['10001','10001','01010','00100','00100','00100','00100'],
'Z':['11111','00001','00010','00100','01000','10000','11111'],
'0':['01110','10001','10011','10101','11001','10001','01110'],
'1':['00100','01100','00100','00100','00100','00100','01110'],
'2':['01110','10001','00001','00010','00100','01000','11111'],
'3':['11110','00001','00001','01110','00001','00001','11110'],
'4':['00010','00110','01010','10010','11111','00010','00010'],
'5':['11111','10000','10000','11110','00001','00001','11110'],
'6':['01110','10000','10000','11110','10001','10001','01110'],
'7':['11111','00001','00010','00100','01000','01000','01000'],
'8':['01110','10001','10001','01110','10001','10001','01110'],
'9':['01110','10001','10001','01111','00001','00001','01110'],
"'":['00100','00100','01000','00000','00000','00000','00000'],
'?':['01110','10001','00001','00010','00100','00000','00100'],
'!':['00100','00100','00100','00100','00100','00000','00100'],
'-':['00000','00000','00000','11111','00000','00000','00000'],
'.':['00000','00000','00000','00000','00000','00100','00100'],
':':['00000','00100','00100','00000','00100','00100','00000'],
'$':['00100','01111','10100','01110','00101','11110','00100'],
'/':['00001','00001','00010','00100','01000','10000','10000'],
'+':['00000','00100','00100','11111','00100','00100','00000'],
}
NAVY=[24,37,62];CYAN=[49,214,240];CREAM=[255,239,201];GOLD=[255,192,44];GREEN=[106,229,142];PURPLE=[107,61,172]
def build(kind,w,h,accent=CYAN):
    parts=[]
    def box(name,x,y,z,sx,sy,sz,color):parts.append(dict(Name=name,Position=[round(x,5),round(y,5),round(z,5)],Size=[round(sx,5),round(sy,5),round(sz,5)],Color=color))
    def text(words,x,y,maxw,maxh,color=CREAM):
        lines=words.upper().split('\n');unit=min(maxw/max(1,max(len(l)*6-1 for l in lines)),maxh/(len(lines)*9-2))
        for ln,line in enumerate(lines):
            left=x-(len(line)*6-1)*unit/2;top=y+(len(lines)*9-2)*unit/2-ln*9*unit
            for ci,ch in enumerate(line):
                for row,bits in enumerate(FONT.get(ch,[]) if ch!=' ' else []):
                    for col,bit in enumerate(bits):
                        if bit=='1':box('Letter',left+(ci*6+col+.5)*unit,top-(row+.5)*unit,.54,unit*.96,unit*.96,.32,color)
    # Deep navy beams, separate raised accent courses and corner caps, never a painted GUI frame.
    thick=min(w,h)*.09
    for sy in (-1,1):
        box('Beam',0,sy*(h/2+thick*.35),.05,w+thick*1.1,thick,.62,NAVY)
        box('Trim',0,sy*(h/2-thick*.28),.39,w-thick,thick*.35,.18,accent)
    for sx in (-1,1):
        box('Beam',sx*(w/2+thick*.35),0,.05,thick,h,.62,NAVY)
        box('Trim',sx*(w/2-thick*.28),0,.39,thick*.35,h-thick,.18,accent)
        for sy in (-1,1):
            box('Corner',sx*(w/2-thick*.15),sy*(h/2-thick*.15),.25,thick*1.8,thick*1.8,.7,NAVY)
            box('Stud',sx*(w/2-thick*.15),sy*(h/2-thick*.15),.64,thick*.85,thick*.85,.18,accent)
    if kind=='UpgradeBase':
        x=-w*.34
        box('House',x,-.25,.48,1.5,1.4,.9,CREAM)
        for i in range(4):box('Roof',x,.5+i*.18,.5,2.1-i*.4,.2,1.1,GOLD)
        box('Door',x,-.57,1.02,.38,.72,.22,NAVY)
        for xx in (-.48,.48):box('Window',x+xx,-.03,1.02,.32,.38,.2,CYAN)
        for xx in (-w*.35,w*.35):box('Post',xx,-h/2-.8,-.22,.46,1.7,.6,NAVY)
    elif kind in ('CollectPad','SellSign'):
        # A stepped pill: three solid courses, cropped corners and contrasting raised studs.
        parts=[]
        for sz,xy,c in ((.26,0,NAVY),(.18,-.13,PURPLE if kind=='CollectPad' else GOLD),(.18,-.28,GREEN)):
            z={'CollectPad':.12,'SellSign':.12}[kind]+(0 if c==NAVY else .14 if c in (PURPLE,GOLD) else .29)
            box('Pill',0,0,z,w+xy,h+xy-.36,sz,c)
            box('PillStep',0,0,z,w+xy-.35,h+xy,sz,c)
        for sx in (-1,1):
            for sy in (-1,1):box('Stud',sx*(w/2-.39),sy*(h/2-.3),.44,.15,.15,.1,CREAM)
        if kind=='SellSign':
            for sx in (-1,1):
                box('EaselLeg',sx*w*.31,-h*.62,-.14,.24,h*.44,.32,NAVY)
                box('Foot',sx*w*.31,-h*.82,-.12,.65,.18,.65,GOLD)
    elif kind=='VaultOwner':
        # The roof and title occupy the top band; the lower face remains plain for the owner.
        text('VAULT',0,h*.25,w*.72,h*.37,CYAN)
        for i in range(4):box('Crown',0,h/2+.22+i*.24,-.01,w*.9-i*w*.15,.26,.65,NAVY)
        box('CrownStud',0,h/2+1,.42,.6,.55,.3,CYAN)
    elif kind=='HauntedWheel':text('HAUNTED\nWHEEL',0,h*.12,w*.82,h*.64,CYAN)
    elif kind=='FreeChestLabel':
        text('FREE\nCHEST',0,h*.2,w*.78,h*.58,CREAM)
        for sx in (-1,1):
            box('Sparkle',sx*w*.37,h/2+.5,.45,.22,.8,.3,GOLD)
            box('Sparkle',sx*w*.37,h/2+.5,.45,.8,.22,.3,GOLD)
    elif kind in ('ShopMortimer','ShopVesper'):
        text('KNIFE\nMERCHANT' if kind=='ShopMortimer' else 'INNOCENT\nPOWERS',0,0,w*.82,h*.8)
        for i in range(4):box('Crown',0,h/2+.15+i*.18,.03,w*.9-i*w*.17,.2,.6,NAVY)
    elif kind=='SafeZone':
        text('SAFE ZONE',0,0,w*.76,h*.66)
        for sx in (-1,1):
            for i in range(3):box('Shield',sx*w*.445,-i*.28,.4,1.6-i*.35,.4,.32,GREEN)
            box('ShieldPlus',sx*w*.445,.15,.65,.22,.7,.18,CYAN)
            box('ShieldPlus',sx*w*.445,.15,.65,.7,.22,.18,CYAN)
    elif kind=='EventBoard':
        for i in range(27):
            for sy in (-1,1):box('Stud',(-.45+i/30)*w,sy*(h/2-.32),.56,.7,.7,.28,CYAN)
    elif kind=='ProjectorScreen':
        text('KNIFE SALES - Q3',0,h*.35,w*.86,h*.16,NAVY)
        for i,v in enumerate((.25,.4,.35,.6,.15)):
            bh=v*h*.8;box('ChartBar',-w*.35+i*w*.16,-h*.37+bh/2,.48,w*.09,bh,.45,[220,50,50] if i==4 else [60,120,220])
    return dict(Width=w,Height=h,FaceColor=GREEN if kind in ('CollectPad','SellSign') else [247,247,241] if kind=='ProjectorScreen' else NAVY,Parts=parts)
specs={k:build(k,w,h,c) for k,w,h,c in [
('UpgradeBase',9,3.4,CYAN),('CollectPad',5.6,2.6,GREEN),('SellSign',4.6,1.5,GOLD),('VaultOwner',20,5,CYAN),
('HauntedWheel',6,2.4,CYAN),('FreeChestLabel',8,5,GREEN),('ShopMortimer',12,4,GOLD),('ShopVesper',12,4,[239,53,172]),
('SafeZone',40,5,GREEN),('EventBoard',52,15,CYAN),('GateHealth',10,2.3,[225,72,90]),('ProjectorScreen',10,6,CYAN)]}
(OUT/'geometry.json').write_text(json.dumps(dict(Signs=specs,Font=FONT),indent=2))
def lua(v):
    if isinstance(v,dict):return '{'+','.join('['+json.dumps(k)+']='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,list):return '{'+','.join(map(lua,v))+'}'
    return json.dumps(v)
folder=ROOT/'src/shared/Config/WorldSigns';folder.mkdir(exist_ok=True)
for name,spec in specs.items():
 (folder/(name+'.luau')).write_text('--!strict\n-- Shared physical cuboids, generated from the approved reference.\nreturn '+lua(spec)+'\n',encoding='utf-8')
config='--!strict\n-- Native geometry only; split modules stay below Roblox source-size limits.\nreturn { Signs = {'+','.join(name+'=require(script.Parent.WorldSigns.'+name+')' for name in specs)+'}, Font = '+lua(FONT)+' }\n'
(ROOT/'src/shared/Config/WorldSignGeometry.luau').write_text(config,encoding='utf-8')
print('Built',len(specs),'physical sign groups;',sum(len(s['Parts']) for s in specs.values()),'cuboids')
