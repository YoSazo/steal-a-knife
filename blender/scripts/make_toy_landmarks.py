"""Reconstruct the lair, shop, mystery-cube and plaza ImageGen references."""
from make_toy_knives import Design, DESIGNS, knives, write_designs, NAVY, SILVER, IVORY, GOLD

PALETTES=[
 ('Frank',(185,103,47),(99,59,36),(48,52,65),SILVER,(98,196,54)),
 ('Ivy',(235,229,187),(47,135,71),(38,110,66),IVORY,(255,148,184)),
 ('Sam',(134,128,164),(69,56,108),(49,42,75),SILVER,(82,227,241)),
 ('Leo',(219,192,135),(156,54,65),(114,80,45),GOLD,(255,218,90)),
 ('Ruby',(58,59,70),(206,42,48),(36,39,52),SILVER,(255,147,37)),
 ('Kate',(246,241,221),GOLD,(214,174,69),IVORY,(100,170,81)),
 ('Zoe',(247,251,255),(139,223,246),(83,183,218),GOLD,(255,219,103)),
 ('Nick',(36,44,70),(112,69,185),(21,29,50),SILVER,(75,225,253)),
]


def rivet(d,x,y,z,c=SILVER,s=.3): d.b('SquareBolt',(s,s,.12),(x,y,z),c)


def skull(d,x,y,z):
    d.b('Skull',(.95,1.0,.35),(x,y,z),IVORY)
    for side in (-1,1):
        d.b('SkullEye',(.22,.23,.055),(x+side*.23,y+.1,z-.20),NAVY)
        d.b('SkullJaw',(.18,.30,.34),(x+side*.23,y-.55,z),IVORY)


def planter(d,x,z,flower=False):
    d.b('Planter',(2.9,1.7,2.9),(x,1.65,z),(119,75,43))
    d.b('PlanterRim',(3.2,.26,3.2),(x,2.4,z),NAVY)
    d.b('PlanterSoil',(2.5,.12,2.5),(x,2.57,z),(83,62,37))
    for i,(dx,dz) in enumerate([(-.7,-.6),(0,.5),(.65,-.3),(.45,.6)]):
        h=1.1+(i%3)*.35
        d.b('PlantStem',(.35,h,.38),(x+dx,2.65+h/2,z+dz),(74,170,61))
        d.b('PlantLeaf',(.7,.3,.38),(x+dx+.1,3.1,z+dz),(94,199,75))
        if flower:
            for ox,oy in [(-.35,0),(.35,0),(0,.35),(0,-.35)]:
                d.b('FlowerPetal',(.34,.34,.24),(x+dx+ox,2.65+h+oy,z+dz-.2),(255,153,185))
            d.b('FlowerCenter',(.28,.28,.26),(x+dx,2.65+h,z+dz-.21),GOLD)


def lairs():
    for name,wall,trim,dark,bolt,accent in PALETTES:
        d=Design('Lair'+name,'lairs');b=d.b
        # Original 42x14 collision stage is retained by GuardService. Tiles sit on its .8 top.
        for ix in range(14):
            for iz in range(4):
                floor=trim if name in ('Frank','Leo') else wall
                if name=='Nick':floor=(57,70,94)
                b('StageTile',(2.97,.08,3.47),(-19.5+ix*3,.84,-5.25+iz*3.5),floor)
        for ix in range(14):
            b('StageFascia',(2.96,.7,.28),(-19.5+ix*3,.4,-7.05),trim)
            rivet(d,-19.5+ix*3,.45,-7.23,bolt,.30)
        # Plank / masonry back; signs remain separate existing UI canvases.
        for ix in range(14):
            if name in ('Frank','Ivy'):
                b('WallPlank',(2.95,17.8,.70),(-19.5+ix*3,9.75,6.6),wall)
            else:
                for iy in range(6):
                    b('WallPanel',(2.95,2.96,.70),(-19.5+ix*3,2.3+iy*3,6.6),wall)
        for x in (-20,20):
            for z in (6,-5):
                b('PostFoot',(2.5,.55,2.5),(x,1.0,z),dark)
                for iy in range(5):
                    b('PostBlock',(1.35,3.45,1.4),(x,2.75+iy*3.5,z),dark if name not in ('Kate','Zoe') else wall)
                for y in (1.7,9.0,17.6):
                    b('PostCollar',(1.8,.62,1.9),(x,y,z),trim)
                    rivet(d,x,y,z-1.04,bolt,.38)
                b('PostCap',(2.6,.55,2.7),(x,18.2,z),trim)
        if name in ('Frank','Ivy','Ruby','Kate'):
            for ix in range(19):
                x=-21+ix*2.333
                y=18.4+(1-abs(x)/22)*4.2
                for z in (4.3,6.6): b('RoofStep',(2.5,.55,2.8),(x,y,z),trim)
                if name in ('Frank','Ivy'):
                    b('GablePlank',(2.30,max(.3,y-18),.65),(x,18+(y-18)/2,6.6),wall)
        elif name=='Sam':
            for ix in range(15):
                x=-14+ix*2;y=18.6+(1-abs(x)/14)*3.8
                b('CryptArch',(2.05,.75,1.1),(x,y,6.2),trim)
                if y>19:b('CryptCrown',(1.97,y-18.5,.65),(x,18.5+(y-18.5)/2,6.6),wall)
        else:
            for ix in range(14):b('TopBeamSegment',(2.96,1.1,1.4),(-19.5+ix*3,18.55,6.4),trim)
        for y in (8.0,17.6):
            b('WallStrap',(39,.46,.28),(0,y,6.05),trim if name!='Frank' else dark)
            for x in range(-18,19,3):rivet(d,x,y,5.86,bolt,.25)
        # Exact back-wall sign/ribbon reserve: no block covers the existing art's front face.
        for x in (-13.4,13.4):b('SignSide',(.55,6.0,.55),(x,14.2,5.5),dark)
        for y in (11.3,17.1):b('SignRail',(27.3,.40,.55),(0,y,5.5),trim)
        for x in (-13.4,13.4):
            for y in (11.3,17.1):rivet(d,x,y,5.17,bolt,.35)
        if name in ('Frank','Ivy'):
            planter(d,-18,-4,name=='Ivy');planter(d,18,-4,name=='Ivy')
            if name=='Frank':
                b('RakeHandle',(.3,5.5,.3),(-18,4,3.0),(144,91,48),None,-14)
                b('RakeHead',(2.1,.32,.45),(-17.4,1.4,3.0),dark)
                for i in range(6):b('RakeTooth',(.16,.6,.3),(-18.3+i*.35,1.05,3.0),dark)
                for x in (-18,18):
                    for y in (1.6,3.4):
                        b('ToolCrate',(2.8,1.7,2.8),(x,y,3.2),trim)
                        b('CrateStrap',(3.0,.28,3.0),(x,y,3.2),dark)
            else:
                for x in (-18,18):planter(d,x,2.8,True)
        elif name=='Sam':
            for x in (-18,-10,10,18):
                b('CryptButtress',(1.8,15,1.3),(x,8.3,5.6),dark)
                skull(d,x,14.4,4.82)
                for y in (5.4,7.4,9.4):
                    b('RuneV',(.14,.85,.06),(x,y,4.9),accent)
                    b('RuneH',(.6,.14,.06),(x,y,4.9),accent)
            for x in (-18,18):
                b('CryptPillar',(2.1,9,2.1),(x,5.3,-4.8),trim)
                skull(d,x,8.1,-5.9)
        elif name=='Leo':
            for x in (-18,-10,10,18):
                b('GalleryColumn',(1.8,16,1.6),(x,8.8,5.5),trim)
                b('ColumnCapital',(2.7,.7,2),(x,17.2,5.5),GOLD)
                for y in (3,7,11,15):rivet(d,x,y,4.58,GOLD,.34)
            for x in (-18,18):
                b('TreasureBox',(2.8,1.5,2.5),(x,1.6,-4.5),GOLD)
                b('TreasureInset',(2.2,.8,.12),(x,1.6,-5.8),trim)
        elif name=='Ruby':
            for x in (-18,-11,11,18):
                b('LavaColumn',(1.7,14,1.6),(x,7.8,5.4),dark)
                for y in range(2,15,2):b('LavaWindow',(.65,1.92,.12),(x,y,4.54),accent)
            for x in (-14,14):
                for y in (20,22.5,25):b('Chimney',(3.1,2.45,2.7),(x,y,6.2),dark)
                b('ChimneyCap',(3.8,.7,3.3),(x,26.6,6.2),dark)
                b('ChimneyWindow',(.9,4.9,.12),(x,23.6,4.79),accent)
            for x in (-18,18):
                b('ForgePlinth',(3.3,1.5,3.1),(x,1.6,-4),trim)
                b('AnvilFoot',(2.3,.45,2.0),(x,2.55,-4),dark)
                b('AnvilWaist',(1.5,1.0,1.6),(x,3.25,-4),dark)
                b('AnvilTop',(3.9,.5,2.2),(x,4.0,-4),SILVER)
        elif name=='Kate':
            for x in (-18,-10,10,18):
                b('ShrineColumn',(1.7,15.2,1.7),(x,8.4,5.5),wall)
                for dx in (-.55,0,.55):b('ColumnFlute',(.19,14,.15),(x+dx,8.4,4.58),IVORY)
                for y in (1.5,16.3):b('GoldCapital',(2.8,.72,2.8),(x,y,5.5),GOLD)
            for x in (-18,18):planter(d,x,-4,False)
        elif name=='Zoe':
            for x in (-18,18):
                for i in range(5):
                    b('CloudBlock',(3.0,1.1,2.5),(x-(1 if x>0 else -1)*(i%3)*.8,3.0+i*.8,4.7),wall)
                for y in (8,11,14):
                    b('StarV',(.25,1.0,.12),(x,y,4.6),GOLD)
                    b('StarH',(1.0,.25,.12),(x,y,4.6),GOLD)
            for i in range(5):b('CrownBlock',(1.5,1.0+(2-abs(i-2))*.7,1),(i*1.6-3.2,19.5,6.1),GOLD)
        elif name=='Nick':
            for x in (-18,-10,10,18):
                b('PodFrame',(1.6,15.5,1.6),(x,8.6,5.5),dark)
                for y in (4,8,12,16):b('PodChannel',(.3,3.5,.13),(x,y,4.64),accent)
            for x in (-20,20):
                b('ExhaustPod',(3.5,7.5,3.5),(x,13,4.1),dark)
                for y in (10,16):b('PodCollar',(3.9,.6,3.9),(x,y,4.1),SILVER)
                for y in (12,13,14):b('PodVent',(2.4,.28,.12),(x,y,2.24),accent)
            for x in range(-18,19,6):b('DeckChannel',(3.5,.3,.15),(x,.5,-7.24),trim)
        d.save()
        # Five native pedestal models use the original Stone centre and height.
        p=Design('LairPlate'+name,'plates');pb=p.b
        pb('PlateFoot',(4.4,.25,4.4),(0,.125,0),dark)
        pb('PlateBody',(3.8,1.05,3.8),(0,.775,0),trim)
        pb('PlateCollar',(4.55,.22,4.55),(0,1.41,0),dark)
        pb('PlateInset',(3.65,.08,3.65),(0,1.56,0),accent)
        for x in (-2.05,2.05):
            for z in (-2.05,2.05):pb('PlateCorner',(.42,.38,.42),(x,1.35,z),bolt)
        p.save()


def shops():
    for name,mystic in [('Mortimer',False),('Vesper',True)]:
        d=Design('Shop'+name,'shops');b=d.b
        wood=(129,78,43) if not mystic else (103,56,163)
        color=(44,134,85) if not mystic else (137,66,220)
        b('CounterBody',(10,3.4,2.4),(0,1.7,-3),wood)
        for ix in range(10):
            for iy in range(3):b('CounterPanel',(.98,.96,.10),(-4.5+ix, .5+iy,-4.26),wood)
        b('CounterTop',(10.6,.4,3),(0,3.6,-3),wood)
        b('KeeperStep',(7,.45,2.4),(0,.225,.2),wood)
        for x in (-5,5):
            for z in (-4,2.5):
                b('PostBase',(1.2,.35,1.2),(x,.18,z),NAVY)
                for iy in range(5):b('PostBlock',(.8,1.94,.8),(x,1+iy*2,z),NAVY if mystic else wood)
                for y in (1,3.3,8.1,10):
                    b('PostCollar',(1.12,.45,1.12),(x,y,z),NAVY)
                    rivet(d,x,y,z-.64,GOLD,.27)
        for x in (-4.6,-2.6,2.6,4.6):
            b('CounterStrap',(.32,3.3,.16),(x,1.7,-4.34),NAVY)
            for y in (.4,2.8):rivet(d,x,y,-4.45,GOLD,.22)
        for ix in range(6):
            x=-5.5+(ix+.5)*11/6
            for iz in range(7):
                z=-4.4+iz*1.2;y=10.05+iz*.22
                b('CanopyStep',(11/6-.025,.45,1.3),(x,y,z),color if ix%2==0 else IVORY)
            b('Valance',(11/6-.06,.70,.4),(x,9.45,-4.75),color)
            b('ValanceTip',(11/6-.24,.18,.4),(x,9.02,-4.75),color)
        # The original TitleAnchor / BillboardGui remains at (0,12.5,-1).
        b('ShopSignBack',(6.8,2.2,.28),(0,12.5,-1),IVORY)
        for y in (11.3,13.7):b('SignRail',(7.4,.30,.44),(0,y,-1.05),NAVY)
        for x in (-3.55,3.55):
            b('SignSide',(.30,2.7,.44),(x,12.5,-1.05),NAVY)
            for y in (11.3,13.7):rivet(d,x,y,-1.34,GOLD,.35)
        if mystic:
            # A squared crescent crest with a clean central cutout.
            for x,y in [(-.8,14.3),(-1.1,14.7),(-1.1,15.1),(-.8,15.5),(-.4,15.8),(-.3,14.0),(.2,14.0),(.6,14.2)]:
                b('MoonPixel',(.45,.4,.4),(x,y,-1),GOLD)
            for x in (-2.5,-1.85,-3.1):
                for i in range(3):b('CrystalStep',(.62-i*.16,.45,.62-i*.16),(x,4.02+i*.45,-3),color)
                b('CrystalFoot',(.85,.2,.85),(x,3.89,-3),GOLD)
            for x,h in [(2.5,1.2),(3.2,.8),(3.9,1.6)]:
                b('Candle',(.4,h,.4),(x,3.8+h/2,-3),IVORY)
                b('CandleFlame',(.24,.30,.24),(x,3.8+h+.15,-3),GOLD)
        else:
            b('CrestBack',(3.6,2.4,.4),(0,14.6,1.5),wood)
            for side in (-1,1):
                b('CrestBlade',(.44,1.8,.3),(side*.35,15,1.1),SILVER,None,-side*38)
                b('CrestGuard',(.8,.18,.38),(side*.80,14.3,1.1),NAVY,None,-side*38)
                b('CrestGrip',(.3,.8,.35),(side*1.1,13.9,1.1),NAVY,None,-side*38)
        b('KnifeBoard',(8,4.5,.4),(0,6,2.3),wood)
        d.save()


def lucky():
    colors=[('Rare',(60,112,249),NAVY,SILVER),('Epic',(159,65,233),(62,34,104),SILVER),
            ('Legendary',(255,177,29),NAVY,GOLD),('Mythic',(237,45,49),(37,39,48),(255,173,36)),
            ('Godly',(255,134,197),IVORY,GOLD),('Celestial',(88,220,243),IVORY,GOLD),
            ('Cosmic',(134,59,241),NAVY,(72,222,255))]
    # Five-by-seven pixel glyph; closed curved head, neck and detached dot.
    glyph=['01110','11011','10001','00011','00110','00000','00100']
    for name,body,rail,cap in colors:
        d=Design('Lucky'+name,'lucky');b=d.b
        b('CubeCore',(2.88,2.88,2.88),(0,0,0),body)
        for x in (-1.45,1.45):
            for y in (-1.45,1.45):
                for z in (-1.45,1.45):b('CornerCap',(.46,.46,.46),(x,y,z),cap if name!='Mythic' else rail)
        for a in (-1.42,1.42):
            for c in (-1.42,1.42):
                b('RailX',(2.65,.20,.22),(0,a,c),rail)
                b('RailY',(.22,2.65,.22),(a,0,c),rail)
                b('RailZ',(.22,.20,2.65),(a,c,0),rail)
        for side in (-1,1):
            for face in ('Z','X'):
                for row,line in enumerate(glyph):
                    for col,pixel in enumerate(line):
                        if pixel!='1':continue
                        u=(col-2)*.255;v=(3-row)*.255
                        pos=(u,v,side*1.49) if face=='Z' else (side*1.49,v,u)
                        size=(.25,.25,.15) if face=='Z' else (.15,.25,.25)
                        b('QuestionPixel',size,pos,IVORY)
                for u in (-1.03,1.03):
                    for v in (-1.03,1.03):
                        pos=(u,v,side*1.47) if face=='Z' else (side*1.47,v,u)
                        size=(.16,.16,.13) if face=='Z' else (.13,.16,.16)
                        b('FaceBolt',size,pos,cap if name!='Mythic' else rail)
        for x,z in [(0,0),(-.75,-.75),(.75,-.75),(-.75,.75),(.75,.75)]:
            b('TopStud',(.25,.13,.25),(x,1.51,z),IVORY if name in ('Epic','Cosmic') else cap)
        if name=='Mythic':
            for x in (-1.23,1.23):
                b('LavaSeam',(.10,2.35,.07),(x,0,-1.47),cap)
                b('LavaTop',(2.3,.07,.10),(0,1.47,x),cap)
        d.save()


def plaza():
    d=Design('FreeChest','plaza');b=d.b
    red=(224,43,55)
    for i in range(5):b('Wood',(2.8,.27,1.9),(0,-.72+i*.29,0),red)
    for i in range(3):b('LidPanel',(2.95-i*.13,.21,2.02-i*.10),(0,.71+i*.22,0),red)
    b('Seam',(2.95,.12,2.04),(0,.56,0),GOLD)
    for x in (-.95,.95):
        for y in (-.35,.2,.81):b('Iron',(.27,.56,2.1),(x,y,0),GOLD)
        b('ChestFoot',(.55,.20,2.03),(x,-.75,0),GOLD)
    for x in (-1.4,1.4):
        for y in (-.7,.54,1.17):
            for z in (-.94,.94):b('Corner',(.30,.28,.3),(x,y,z),GOLD)
    for x in (-1.43,1.43):
        for y in (-.28,.93):b('SideInset',(.035,.44,1.38),(x,y,0),NAVY)
    b('Lock',(.58,.62,.19),(0,.4,-1.07),GOLD)
    b('KeyholeHead',(.15,.18,.035),(0,.44,-1.183),NAVY)
    b('KeyholeStem',(.075,.16,.035),(0,.31,-1.183),NAVY)
    d.save()
    d=Design('EventBoardDecor','plaza');b=d.b
    # World-relative y values agree with ManorDecor.eventBoard; local z=0 is the existing canvas.
    for x in (-29,29):
        for i in range(9):b('BoardPost',(2.0,3.95,2.5),(x,2+i*4,.7),NAVY)
        for y in (1,7,29,35.5):
            b('PostCollar',(3.0,1.0,3.3),(x,y,.7),IVORY)
            rivet(d,x,y,-1.02,GOLD,.65)
        for y,w in [(0.3,7),(1.0,5.5),(1.6,4)]:b('BoardFoot',(w,.6,5),(x,y,.7),NAVY if y<1 else IVORY)
    for i in range(15):b('BoardTruss',(3.97,1.6,2.8),(-28+i*4,36,.7),NAVY)
    for y in (14.0,30.6):
        b('BoardRail',(54,.65,2.0),(0,y,.45),IVORY)
        b('RailInset',(51.5,.16,.09),(0,y,-.6),GOLD)
    for x in (-26.7,26.7):
        b('BoardSide',(.65,17.1,2.0),(x,22.3,.45),IVORY)
        for y in (14.0,30.6):
            b('BoardCorner',(2.0,2.0,2.3),(x,y,.4),NAVY)
            rivet(d,x,y,-.80,GOLD,.62)
    for x in (-23,-14,-5,5,14,23):
        for i in range(5):
            b('ChainSegment',(.32,.88,.45),(x,31.1+i*1.0,.3),NAVY)
            b('ChainCuff',(.48,.18,.6),(x,31.5+i*1.0,.3),GOLD)
    b('BeaconFoot',(4,.5,2),(0,31.15,.25),NAVY)
    b('Beacon',(1.5,1.5,1.5),(0,32.1,.25),(234,58,65))
    b('BeaconCap',(1.8,.3,1.8),(0,33,.25),IVORY)
    d.save()


if __name__=='__main__':
    knives();lairs();shops();lucky();plaza();write_designs()
