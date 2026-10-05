"""Reconstruct the 24 ImageGen references as named cuboids, not uploaded meshes.

Run with ordinary Python. The manifest is also the input to the Blender renderer.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/toy-redesign'
CONFIG = ROOT / 'src/shared/Config/ToyGeometry'
DESIGNS = {}


class Design:
    def __init__(self, name, group):
        self.name, self.group, self.rows = name, group, []

    def b(self, name, size, pos, color, role=None, angle=0):
        self.rows.append(dict(Name=name, Size=list(size), Offset=list(pos), Color=list(color), Role=role, Angle=angle))

    def save(self):
        DESIGNS[self.name] = dict(Name=self.name, Group=self.group, Parts=self.rows)


def write_designs():
    CONFIG.mkdir(parents=True, exist_ok=True)
    names = []
    for name, design in DESIGNS.items():
        lines = ['--!strict', '-- Generated from the block reconstruction; edit the Python design source.', 'return {']
        for p in design['Parts']:
            size = ', '.join(f'{v:.6g}' for v in p['Size'])
            pos = ', '.join(f'{v:.6g}' for v in p['Offset'])
            color = ', '.join(str(int(v)) for v in p['Color'])
            role = f', Role = "{p["Role"]}"' if p['Role'] else ''
            angle = f', Angle = {p["Angle"]:.6g}' if p['Angle'] else ''
            lines.append(f'\t{{ Name = "{p["Name"]}", Size = Vector3.new({size}), Offset = Vector3.new({pos}), Color = Color3.fromRGB({color}){role}{angle} }},')
        lines.append('}')
        (CONFIG / f'{name}.luau').write_text('\n'.join(lines)+'\n')
        names.append(f'\t{name} = require(script.Parent.ToyGeometry.{name}),')
    (CONFIG.parent / 'ToyGeometryData.luau').write_text('--!strict\nreturn {\n'+'\n'.join(names)+'\n}\n')
    (OUT / 'geometry.json').write_text(json.dumps(dict(Designs=list(DESIGNS.values())), indent=2))


SILVER=(222,230,240); IVORY=(255,242,206); GOLD=(255,205,55); NAVY=(28,38,60)
CATALOG = [
 ('RustyShank',2.0,.58,(214,115,44),(65,68,76),(110,63,35)),
 ('KitchenKnife',2.3,.85,SILVER,(32,36,45),(32,36,45)),
 ('PocketKnife',1.8,.62,SILVER,(162,35,42),(226,48,49)),
 ('HunterBlade',2.5,.8,SILVER,(219,167,70),(127,70,32)),
 ('Switchblade',2.3,.55,(114,208,255),(26,57,108),(41,114,220)),
 ('ThornDagger',2.7,.62,(106,218,78),(36,107,52),(107,63,34)),
 ('Cleaver',2.0,1.65,SILVER,(58,65,81),(188,49,53)),
 ('Machete',3.0,.95,(185,117,255),(63,31,99),(91,170,65)),
 ('BoneCarver',2.8,.7,(241,229,200),(136,128,114),(80,68,58)),
 ('GoldenDagger',2.6,.78,GOLD,(216,43,63),(89,47,29)),
 ('Katana',3.5,.58,(255,171,208),GOLD,(63,28,68)),
 ('Reaper',2.8,.75,(59,61,78),GOLD,(30,26,37)),
 ('InfernoFang',3.0,.9,(255,118,30),(42,28,31),(166,37,38)),
 ('MagmaCleaver',2.2,1.7,(255,101,32),(45,31,33),(38,28,30)),
 ('DemonHorn',3.2,.68,(223,35,48),(33,19,29),(95,24,36)),
 ('ZeusBolt',3.3,.7,(255,228,47),IVORY,(55,119,239)),
 ('AthenaBlade',2.9,.92,(246,246,255),GOLD,(62,105,198)),
 ('OlympusEdge',3.2,.96,(255,131,201),GOLD,(255,247,228)),
 ('HaloBlade',3.2,.74,(255,246,216),GOLD,(242,244,255)),
 ('SeraphSword',3.5,.82,(151,235,255),(255,221,127),(248,250,255)),
 ('AngelFeather',3.0,.64,(251,253,255),(134,218,255),(255,210,106)),
 ('VoidEdge',3.2,.84,(149,68,248),(28,27,44),(73,26,123)),
 ('StarCleaver',2.3,1.8,(95,219,255),(55,32,91),(255,225,115)),
 ('GalaxyKatana',3.6,.6,(251,76,214),(61,219,255),(28,18,52)),
]


def knives():
    for name,L,W,B,G,H in CATALOG:
        d=Design(name,'knives'); b=d.b
        T=.3 if 'Cleaver' not in name else .4
        # Grip origin is precisely zero. Visible grip surrounds the invisible Handle.
        b('Grip',(.42,1.05,.44),(0,0,0),H,'Grip')
        for i in range(4):
            y=-.40+i*.27
            if name in ('KitchenKnife','PocketKnife','RustyShank','HunterBlade','Switchblade','Cleaver'):
                b(f'GripPanel{i}',(.44,.23,.47),(0,y,0),H,'GripDetail')
                b(f'GripRivet{i}',(.09,.10,.045),(0,y,-.258),IVORY if name!='RustyShank' else SILVER,'Guard')
            else:
                wrap=G if name not in ('Katana','GalaxyKatana') else ((255,159,201) if name=='Katana' else (117,62,227))
                b(f'GripBand{i}',(.47,.075,.50),(0,y,0),wrap,'GripDetail')
                if name=='Katana':
                    b(f'WrapDiagonal{i}',(.38,.08,.04),(0,y+.1,-.27),wrap,'GripDetail',-28)
        pommel=B if name in ('GoldenDagger','ZeusBolt','BoneCarver','InfernoFang','AngelFeather','AthenaBlade') else G
        b('Pommel',(.66,.55,.65),(0,-.79,0),pommel,'Guard')
        b('PommelInset',(.29,.30,.035),(0,-.79,-.342),B,'Inlay')
        guardW=max(1.05,W+.66)
        b('Guard',(guardW,.26,.57),(0,.65,0),G,'Guard')
        for x in (-guardW/2,guardW/2):
            b('GuardCuff',(.27,.40,.65),(x,.65,0),G,'Guard')
        start=.79
        # Blade is a full-height solid central spine so existing flame/trail code measures +Y.
        spineW=.22 if name not in ('Cleaver','MagmaCleaver','StarCleaver') else .27
        b('Blade',(spineW,L,T),(0,start+L/2,0),B,'Blade')
        def slice_block(i,x,width,y,height,col=B,role='Blade'):
            b(f'BladeBlock{i}',(width,height-.009,T),(x,start+y+height/2,0),col,role)
        if name in ('RustyShank','KitchenKnife','PocketKnife','HunterBlade','Switchblade','Machete','Katana','GalaxyKatana'):
            n=8
            for i in range(n):
                width=W*(1 if i<5 else [1,.82,.58,.3][i-4])
                x=(width-spineW)/2 if name in ('RustyShank','KitchenKnife','PocketKnife','Machete','Katana','GalaxyKatana') else .07*(i/max(n-1,1))
                slice_block(i,x,width,i*L/n,L/n)
            edge=IVORY if name in ('KitchenKnife','HunterBlade','Katana') else ((59,225,255) if name=='GalaxyKatana' else (169,230,255) if name=='Switchblade' else B)
            for i in range(8):
                b(f'CuttingEdge{i}',(.065,L/8-.012,T+.018),(-spineW/2-.032,start+(i+.5)*L/8,0),edge,'CuttingEdge')
            if name=='RustyShank':
                for i,y in enumerate((.35,1.0,1.65)):
                    b(f'RustPatch{i}',(.19,.28,.035),(.2,start+y,-T/2-.02),(157,75,31),'Inlay')
            if name=='PocketKnife':
                b('Pivot',(.22,.22,.055),(0,.38,-.3),IVORY,'Guard')
            if name=='GalaxyKatana':
                for i,y in enumerate((.6,1.55,2.45)):
                    x=.18;z=-T/2-.027
                    b(f'StarCore{i}',(.15,.15,.04),(x,start+y,z),IVORY,'Inlay')
                    b(f'StarVertical{i}',(.06,.30,.04),(x,start+y,z),IVORY,'Inlay')
                    b(f'StarHorizontal{i}',(.30,.06,.04),(x,start+y,z),IVORY,'Inlay')
            if name in ('Katana','GalaxyKatana'):
                # Square tsuba, built from four separate border rails rather than a round disc.
                for z in (-.36,.36): b('TsubaRail',(1.1,.18,.18),(0,.68,z),G,'Guard')
                for x in (-.46,.46): b('TsubaSide',(.18,.18,.65),(x,.68,0),G,'Guard')
        elif name in ('Cleaver','MagmaCleaver','StarCleaver'):
            for i in range(4):
                for j in range(3):
                    col=B
                    if name=='MagmaCleaver' and i==3: col=NAVY
                    if name=='StarCleaver' and i==3 and j==2: col=(101,59,167)
                    height=L/4-.012
                    y=start+L*(i+.5)/4
                    if name=='Cleaver' and i==3 and j==1:height-=.14;y-=.07
                    if name=='StarCleaver' and i==3:height-=j*.13;y-=j*.065
                    b(f'CleaverPanel{i}_{j}',(W/3-.012,height,T),(W*(j+.5)/3-W*.15,y,0),col,'Blade')
            if name=='Cleaver':
                b('SquareInset',(.22,.25,.045),(W*.58,start+L*.8,-T/2-.025),NAVY,'Inlay')
            if name=='MagmaCleaver':
                for i in range(3):
                    for j in range(5):
                        b(f'LavaChannel{i}_{j}',(.10,L*.13,.05),(.19+i*.40+(j%2)*.1,start+.35+j*L*.13,-T/2-.029),(255,222,53),'Inlay')
                        if j<4:b(f'LavaElbow{i}_{j}',(.2,.10,.05),(.24+i*.40,start+.49+j*L*.13,-T/2-.029),(255,222,53),'Inlay')
            if name=='StarCleaver':
                for i in range(3):
                    x=.30+i*.39;y=start+.45+i*.46
                    b(f'StarV{i}',(.06,.26,.045),(x,y,-T/2-.027),IVORY,'Inlay')
                    b(f'StarH{i}',(.26,.06,.045),(x,y,-T/2-.027),IVORY,'Inlay')
        elif name=='ZeusBolt':
            # Jagged silhouette with two deliberately wide lightning elbows.
            profile=[(0,.65),(.13,.67),(.28,.70),(-.15,1.4),(.06,.67),(.24,.70),(-.18,1.36),(.01,.60),(.19,.48),(.19,.30)]
            for i,(x,w) in enumerate(profile): slice_block(i,x,w,i*L/10,L/10)
        elif name=='Reaper':
            # Continuous C-shaped hook; no teeth or detached silhouette blocks.
            d.rows[-1]['Offset'][0]=-.21
            for i,(x,w) in enumerate([(-.05,.66),(-.12,.60),(-.20,.46),(-.22,.44),(-.22,.44),(-.20,.47),(-.12,.58),(0,.75),(.16,1.0),(.20,1.08)]):
                slice_block(i,x,w,i*L/10,L/10)
                b(f'GoldEdge{i}',(.09,L/10-.012,T+.02),(x-w/2-.04,start+(i+.5)*L/10,0),G,'CuttingEdge')
            b('HookTip',(.25,.44,T),(.66,start+L-.22,0),B,'Blade')
            b('HookGoldCap',(.34,.12,T+.04),(.66,start+L-.02,0),G,'CuttingEdge')
            for side in (-1,1):b('GuardHorn',(.20,.36,.58),(side*.7,.9,0),G,'Guard')
        elif name=='DemonHorn':
            # A curved horn made from touching shifted blocks and a pink stepped edge.
            d.rows[-1]['Size'][1]=L*.65
            d.rows[-1]['Offset']=[.05,start+L*.325,0]
            profile=[(0,.68),(-.05,.68),(-.1,.68),(-.07,.68),(0,.66),(.13,.62),(.26,.55),(.37,.47),(.47,.37),(.54,.24)]
            for i,(x,w) in enumerate(profile):
                slice_block(i,x,w,i*L/10,L/10)
                b(f'HornEdge{i}',(.07,L/10-.01,T+.01),(x+w/2+.03,start+(i+.5)*L/10,0),(255,137,155),'CuttingEdge')
            for side in (-1,1):
                for i in range(3):b('GuardHorn',(.25,.25,.5),(side*(.6+i*.17),.7+i*.17,0),G if i<2 else B,'Guard')
        elif name in ('ThornDagger','BoneCarver','InfernoFang','DemonHorn','Reaper','AngelFeather','VoidEdge'):
            for i in range(10):
                ratio=1 if i<7 else (1,.70,.4,.22)[i-6]
                x=0
                if name in ('DemonHorn','Reaper'): x=max(0,i-3)*.07
                if name=='AngelFeather': x=.1
                slice_block(i,x,W*ratio,i*L/10,L/10)
            if name in ('DemonHorn','Reaper'):
                for i in range(4):
                    b(f'Hook{i}',(.20,.22,T),(.38+i*.16,start+L-.14-i*.11,0),B,'Blade')
            for i in range(3 if name in ('BoneCarver','VoidEdge') else 5):
                y=start+.26+i*L*.15
                sides=(1,) if name in ('BoneCarver','AngelFeather') else (-1,1)
                for side in sides:
                    x=side*(W/2+.08)
                    b(f'Tooth{i}_{side}',(.22,.22,T),(x,y,0),B,'Blade')
                    if name=='AngelFeather':
                        b(f'FeatherTip{i}',(.20,.14,T),(x+.15,y+.13,0),B,'Blade')
            accent=(255,218,64) if name in ('InfernoFang','Reaper') else ((255,125,141) if name=='DemonHorn' else (186,145,255) if name=='VoidEdge' else (139,222,255) if name=='AngelFeather' else B)
            for i in range(8):
                x=.09 if name not in ('DemonHorn','Reaper') else max(0,i-2)*.07
                b(f'InsetSpine{i}',(.11,L/9,.035),(x,start+(i+.5)*L/8,-T/2-.022),accent,'Inlay')
            if name in ('ThornDagger','DemonHorn','InfernoFang'):
                for side in (-1,1):
                    for i in range(3):
                        b(f'GuardHorn{i}_{side}',(.22,.22,.5),(side*(guardW/2+i*.12),.70+i*.17,0),G if i<2 else B,'Guard')
        else:
            for i in range(10):
                ratio=(.85,1,1,1,1,.86,.74,.6,.43,.24)[i]
                slice_block(i,0,W*ratio,i*L/10,L/10)
            for i in range(8):
                b(f'RaisedSpine{i}',(.11,L/9,.04),(0,start+(i+.5)*L/8,-T/2-.025),IVORY if name in ('GoldenDagger','SeraphSword','OlympusEdge') else G,'Inlay')
            if name in ('SeraphSword','OlympusEdge'):
                for side in (-1,1):
                    for i in range(4):
                        b(f'WingGuard{i}_{side}',(.3,.19,.5),(side*(.48+i*.20),.68+i*.14,0),G,'Guard')
            if name=='HaloBlade':
                for y in (.45,1.05): b('HaloRail',(1.35,.16,.48),(0,y,0),G,'Guard')
                for x in (-.6,.6): b('HaloSide',(.16,.6,.48),(x,.75,0),G,'Guard')
            if name=='AthenaBlade': b('GuardShield',(.57,.48,.62),(0,.65,0),G,'Guard')
        d.save()


if __name__=='__main__':
    knives(); write_designs()
