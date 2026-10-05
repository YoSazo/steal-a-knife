"""Build all 13 block-built training wheels from the concept boards.

Normal Python writes the Roblox geometry and audit manifest. Blender additionally
saves the editable collection, GLBs, and renders with --render after --.
Coordinates are Roblox coordinates, relative to the axle (6.6 studs above ground).
"""
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "wheels"
NAMES = ["Creaky", "Iron", "Steam", "Haunted", "Cursed", "Bone", "Thief Moon",
         "Phantom", "Infernal", "Olympian", "Angelic", "Celestial", "Cosmic"]
# Body, shadow, trim, tread, inset: color belongs to the tier, not the owner's vault.
PALETTES = [
    [(157,101,53),(87,55,32),(67,72,77),(196,143,76),(226,180,105)],
    [(82,99,116),(35,44,58),(178,190,202),(114,132,147),(221,231,238)],
    [(172,88,42),(49,44,43),(229,164,71),(122,63,35),(100,222,212)],
    [(58,44,80),(29,25,43),(107,84,142),(47,54,61),(112,255,184)],
    [(55,32,78),(24,21,36),(129,69,157),(50,29,65),(226,76,255)],
    [(226,215,181),(70,63,60),(255,242,206),(181,167,138),(122,96,72)],
    [(36,47,82),(19,25,44),(243,190,64),(106,34,53),(255,221,120)],
    [(120,222,242),(35,28,64),(194,250,255),(43,107,132),(66,236,255)],
    [(58,52,56),(27,25,31),(151,58,33),(92,35,25),(255,126,35)],
    [(237,232,212),(88,96,123),(232,179,65),(205,200,183),(255,229,121)],
    [(250,244,216),(146,155,180),(240,198,92),(222,226,239),(255,243,169)],
    [(39,66,124),(24,29,64),(180,222,246),(108,145,186),(83,225,255)],
    [(65,37,110),(24,21,48),(237,189,82),(56,38,85),(248,103,232)],
]


class Wheel:
    def __init__(self, tier):
        self.tier = tier
        self.rotor = []
        self.stand = []

    def box(self, name, size, pos, color=0, rot=(0,0,0), fixed=False, glow=False):
        row = [name] + [round(v,4) for v in (*size,*pos,*rot)] + [color+1,glow]
        (self.stand if fixed else self.rotor).append(row)

    def radial(self, name, size, x, r, a, color=0, fixed=False, glow=False):
        self.box(name,size,(x,r*math.cos(a),r*math.sin(a)),color,(a,0,0),fixed,glow)

    def pixel(self, name, pattern, x, y, z, unit, color, fixed=True, glow=False):
        h, w = len(pattern), len(pattern[0])
        for row, line in enumerate(pattern):
            # Merge horizontal runs; keep the stepped silhouette without excess instances.
            k = 0
            while k < w:
                if line[k] != "#":
                    k += 1
                    continue
                end = k+1
                while end < w and line[end] == "#":
                    end += 1
                self.box(name,(0.19,unit*0.96,(end-k)*unit-0.02),
                         (x,y+(h/2-row-0.5)*unit,z+((k+end)/2-w/2)*unit),
                         color,fixed=fixed,glow=glow)
                k = end

    def crystal(self, x, y, z, color=4):
        for dz, height in [(-0.55,1.0),(0,1.65),(0.55,0.8)]:
            self.box("CrystalRoot",(.55,.25,.55),(x,y+.125,z+dz),2,fixed=True)
            self.box("CrystalPrism",(.35,height,.35),(x,y+.25+height/2,z+dz),color,fixed=True)
            self.box("CrystalTip",(.24,.24,.24),(x,y+.25+height,z+dz),color,
                     (0,0,math.pi/4),True)

    def chain(self, x, z0, z1, y0, y1, color=2):
        for j in range(7):
            t = j/6
            y = y0*(1-t)+y1*t-0.85*math.sin(t*math.pi)
            z = z0*(1-t)+z1*t
            # Square links, alternating depth, individually modeled holes.
            for dy,dz,sy,sz in [(0,.2,.45,.09),(0,-.2,.45,.09),(.2,0,.09,.45),(-.2,0,.09,.45)]:
                self.box("ChainLink",(.1,sy,sz),(x+(j%2)*.08,y+dy,z+dz),color,fixed=True)

    def build(self):
        tier = self.tier
        segs = 24
        pitch = 2*math.pi/segs
        for k in range(segs):
            a = k*pitch
            for side in [-1,1]:
                x = side*3.4
                self.radial("RimSegment",(.68,.85,1.56),x,6,a,0)
                self.radial("InnerRimLiner",(.72,.16,1.41),x,5.49,a,2 if tier>=10 else 1)
                self.radial("RimArmor",(.18,.67,1.23),x+side*.44,6.05,a,2 if k%3==0 or tier in [2,3,10,11] else 0)
                self.radial("SquareRivet",(.13,.21,.21),x+side*.58,6.08,a,2)
                if tier in [1,2,3,6,7,10,11,12,13]:
                    self.radial("RimPlateEndBolt",(.13,.16,.16),x+side*.58,6.08,a+.075,2)
                if tier in [4,5,8,9,12,13] and k%3==0:
                    self.radial("RuneSocket",(.12,.27,.72),x+side*.51,6.02,a,1)
                    self.radial("RuneInset",(.14,.12,.45),x+side*.59,6.02,a,4,glow=True)
                if tier == 6 and k%2==0:
                    self.radial("VertebraJoint",(.85,.33,.62),x,6.30,a,2)
                    for dz in [-.28,.28]:
                        self.radial("BoneKnuckle",(.92,.45,.25),x,6.31,a+dz/6,2)
                if tier == 5 and k%4==0:
                    self.radial("CursedSpikeBase",(.66,.3,.65),x,6.39,a,1)
                    for step in range(3):
                        self.radial("CursedSpike",(.48-step*.12,.24,.48-step*.12),x,6.66+step*.22,a,2)
                if tier == 8 and k%3==0:
                    self.radial("PhantomShard",(.42,.42,.85),x,6.58,a+.06,4)
            # Wide tread boards with physically separated grooves and grips.
            for strip in [-1,0,1]:
                self.radial("TreadBlock",(2.13,.24,1.44),strip*2.18,5.76,a,3 if k%2==0 else 0)
            for x in [-2.5,2.5]:
                self.radial("TreadGrip",(.34,.12,.90),x,5.58,a,2)
            if tier >= 4:
                self.radial("TreadInlay",(3.6,.08,.12),0,5.58,a,4,glow=tier!=6 and tier!=7)
            elif tier == 1 and k%4==0:
                self.radial("PlankPatch",(.8,.12,.48),.6,5.58,a,4)
            elif tier == 3 and k%3==0:
                for x in [-1,0,1]:
                    self.radial("SteamVent",(.12,.09,.65),x,5.58,a,1)
            # Visible exterior panel relief from the concept, as well as interior grips.
            if tier in [1,6]:
                for strip in [-1,0,1]:
                    self.radial("PlankGrain",(.85,.025,.025),strip*2.18+.3,5.897,a+.03,1)
                    self.radial("PlankNail",(.08,.04,.08),strip*2.18-.65,5.915,a-.07,2)
            elif tier == 3:
                self.radial("CopperGrillePanel",(5.5,.12,1.1),0,5.97,a,0)
                for xx in [-2,-1,0,1,2]:
                    self.radial("GrilleSlot",(.16,.03,.68),xx,6.05,a,1)
            elif tier in [4,5,7,8,9,12,13]:
                self.radial("TreadPanelFrame",(5.5,.10,1.1),0,5.97,a,1 if tier!=12 else 2)
                self.radial("TreadPanelInset",(5.0,.12,.83),0,6.04,a,3 if tier not in [8,9] else 4,glow=tier in [8,9])
                if tier in [4,5,13]:
                    self.radial("PanelCircuit",(2.8,.025,.11),0,6.12,a,4,glow=True)
        # Match the open drum in the boards. Bearing stubs never cross the running lane.
        for side in [-1,1]:
            x = side*3.9
            for extent, depth, col in [(1.8,.4,1),(1.4,.32,2),(1.05,.30,0),(.55,.16,2)]:
                self.box("AxlePlate",(depth,extent,extent),(x,0,0),col)
                x += side*(depth/2+.10)

            # Four brick feet and gusseted axle supports; these do not rotate.
            x = side*4.6
            for z in [-2.1,2.1]:
                self.box("Foot",(1.7,.40,2.0),(x,-6.2,z),1,fixed=True)
                self.box("FootCap",(1.45,.20,1.7),(x,-5.9,z),0,fixed=True)
                self.box("FootBolt",(.22,.16,.22),(x,-5.71,z+.46),2,fixed=True)
                if tier < 10:
                    self.box("Gusset",(.5,5.75,.55),(x,-3.1,z/2),0,
                             (math.atan2(-z,5.6),0,0),True)
                else:
                    self.box("Column",(.95,4.6,.85),(x,-3.4,z/2),0,fixed=True)
                    for dz in [-.26,0,.26]:
                        self.box("ColumnFlute",(.13,4.2,.10),(x+side*.52,-3.4,z/2+dz),3,fixed=True)
            self.box("Upright",(1.10,5.4,1.25),(x,-3.25,0),0,fixed=True)
            for y in [-5.4,-2.2,-.9]:
                self.box("PostCollar",(1.1,.28,1.24),(x,y,0),2,fixed=True)
            self.box("BearingHousing",(1.0,2.1,2.1),(x,-.10,0),0 if tier==6 or tier>=10 else 1,fixed=True)
            self.box("BearingFace",(.18,1.75,1.75),(x+side*.61,-.10,0),2,fixed=True)
            self.details(side)
            self.finishing(side)
        # Three approach steps and a frame, copied from the premium reference bases.
        # Decorative only: the original training plate remains the collision surface.
        if tier >= 10:
            for j in range(3):
                self.box("ApproachStep",(5.5,.18,0.65),(0,-6.3+j*.18,-6.0+j*.65),3,fixed=True)
                self.box("StepNosing",(5.5,.12,.12),(0,-6.18+j*.18,-6.29+j*.65),2,fixed=True)
        return self

    def finishing(self, side):
        """Distinct silhouette and layers visible in the approved reference boards."""
        t, x = self.tier, side*5.44
        if t in [1,2,3]:
            for z in [-2.1,2.1]:
                for dz in [-.52,0,.52]:
                    self.box("FootBrick",(.48,.43,.48),(side*4.6,-5.60,z+dz),0,fixed=True)
            if t == 1:
                for y in [-4.8,-3.7,-2.6]:
                    self.box("BoardJoint",(.10,.04,.80),(x,y,0),1,fixed=True)
        if t in [4,5,8,9]:
            for y in [-4.8,-4.0,-3.2]:
                self.box("PostBrickCourse",(.12,.045,.94),(x,y,0),1,fixed=True)
            for z in [-2.1,2.1]:
                self.box("PedestalTile",(1.15,.28,1.35),(side*4.6,-5.6,z),0,fixed=True)
        if t == 6:
            for z in [-.3,.3]:
                self.box("FemurShaft",(.5,4.8,.35),(side*4.7,-3.5,z),0,fixed=True)
            for z in [-2.1,2.1]:
                for j in range(3):
                    self.box("BonePile",(.42,.38,.48),(side*4.6+(j-1)*.45,-5.55,z),2,fixed=True)
        if t == 7:
            for z in [-3.2,3.2]:
                for dz in [-.52,0,.52]:
                    self.box("Battlement",(.55,.52,.32),(side*4.6,-2.9,z+dz),0,fixed=True)
            self.pixel("MoonStar",["..#..",".###.","#####",".###.","..#.."],x+side*.14,0,.38,.16,4)
        if t >= 10:
            for z in [-2.1,2.1]:
                for j in range(3):
                    width=1.8-j*.20
                    self.box("PremiumPlinth",(width,.24,2-j*.22),(side*4.6,-5.6+j*.24,z),2 if j==1 else 0,fixed=True)
        if t == 10:
            # A layered shield and tall paired laurel branches, not a tiny flat icon.
            self.pixel("ShieldBorder",[".#####.","#######","#######","#######",".#####.","..###..","...#..."],x,.05,0,.40,2)
            self.pixel("ShieldFace",[".###.","#####","#####","#####",".###.","..#.."],x+side*.12,.15,0,.39,0)
            self.pixel("ShieldBolt",["...##","..##.",".##..","####.","..##.",".##..","##..."],x+side*.24,.12,0,.26,2)
            for zside in [-1,1]:
                for j in range(7):
                    z=zside*(1.55+j*.14)
                    self.box("LaurelStem",(.15,.40,.15),(x,.3+j*.44,z),2,fixed=True)
                    for branch in [-1,1]:
                        self.box("LaurelLeaf",(.20,.35,.50),(x,.45+j*.44,z+branch*.24),2,(branch*.6,0,0),True)
        elif t == 11:
            # Individual stepped voxel feathers form the large spread wings in the image.
            for zside in [-1,1]:
                for col in range(7):
                    for row in range(5):
                        yy=6.1-col*.47-row*.72
                        zz=zside*(1.1+col*.49)
                        self.box("WingVoxel",(.46,.52,.47),(x,yy,zz),0 if row<4 else 2,fixed=True)
            for z in [-2.1,2.1]:
                for j in range(3):
                    self.box("CloudBlock",(.70,.45,.70),(side*4.6+(j-1)*.6,-5.65+(j%2)*.30,z),3,fixed=True)
            # Halo is horizontal above the drum, held by two small gold posts.
            if side == 1:
                for k in range(28):
                    a=k*math.pi/14
                    self.box("CrownHalo",(.55,.20,.55),(3.2*math.cos(a),7.30,3.2*math.sin(a)),2,fixed=True)
                for zz in [-2.6,2.6]:
                    self.box("HaloPillar",(.18,.9,.18),(0,6.75,zz),2,fixed=True)
        elif t == 12:
            # Four large tiered crystal towers and a layered star bearing face.
            for z in [-3.1,3.1]:
                for j in range(5):
                    self.box("AzureCrystalStep",(.80-j*.10,.8,.80-j*.10),(side*4.6,-4.8+j*.75,z),4,fixed=True)
            self.pixel("StarBorder",["...#...",".#.#.#.","..###..","#######","..###..",".#.#.#.","...#..."],x,.1,0,.43,2)
            self.pixel("StarCenter",[".#.","###",".#."],x+side*.16,.1,0,.36,4,glow=True)
        elif t == 13:
            # The two gold orbital braces surround the drum and carry cube satellites.
            if side == 1:
                for orbit in [-1,1]:
                    for k in range(40):
                        a=k*math.pi/20
                        xx=7.0*math.cos(a)
                        zz=5.7*math.sin(a)
                        yy=2.9+orbit*xx*.22
                        self.box("OrbitLink",(.45,.18,.45),(xx,yy,zz),2,fixed=True)
                    for k in [3,13,23,33]:
                        a=k*math.pi/20
                        xx,zz=7*math.cos(a),5.7*math.sin(a)
                        yy=2.9+orbit*xx*.22
                        self.box("SatelliteFrame",(.75,.75,.75),(xx,yy,zz),1,fixed=True)
                        self.box("SatelliteSocket",(.14,.42,.42),(xx+.45,yy,zz),4 if k%3 else 4,fixed=True,glow=True)

    def details(self, side):
        t = self.tier
        x = side*5.24
        if t == 1:
            for y in [-4.6,-3.4,-2.2]:
                self.box("WoodGrain",(.06,.07,.68),(x,y,0),1,fixed=True)
            self.box("RepairStrap",(.15,.38,1.15),(x,-3.9,0),2,fixed=True)
        elif t == 2:
            for z in [-.47,.47]:
                for y in [-.55,.35]:
                    self.box("HousingBolt",(.14,.20,.20),(x,y,z),4,fixed=True)
            for y in [-4.8,-3.6,-2.4]:
                self.box("SteelVent",(.12,.16,.56),(x,y,0),1,fixed=True)
        elif t == 3:
            bx,z = side*4.6,3.65
            for y,w in [(-5.55,1.45),(-4.8,1.2),(-4.05,1.2),(-3.3,1.2),(-2.55,1.2)]:
                self.box("BoilerSection",(w,.66,1.35),(bx,y,z),0,fixed=True)
            for y in [-5.1,-3.65,-2.15]:
                self.box("BoilerBand",(1.45,.16,1.55),(bx,y,z),2,fixed=True)
            self.box("Chimney",(.65,2.1,.65),(bx,-.97,z),0,fixed=True)
            self.box("ChimneyCap",(.94,.24,.94),(bx,.2,z),1,fixed=True)
            self.box("PipeRise",(.3,2.5,.3),(bx,-4.7,2.5),2,fixed=True)
            self.box("PipeElbow",(.34,.34,1.8),(bx,-3.45,1.68),2,fixed=True)
            self.box("PistonRod",(.25,2.2,.25),(x,-2.7,.7),2,fixed=True)
            self.box("PistonSleeve",(.6,1.1,.6),(x,-4,.7),1,fixed=True)
            self.box("GaugeFrame",(.22,.9,.9),(x,-2,3.6),2,fixed=True)
            self.box("GaugeFace",(.12,.68,.68),(x+side*.18,-2,3.6),4,fixed=True)
            self.box("GaugeNeedle",(.13,.4,.07),(x+side*.26,-1.91,3.6),1,(math.pi/4,0,0),True)
        elif t in [4,5,7,8,9]:
            for z in [-3.2,3.2]:
                self.box("DecorPedestal",(1.1,.45,1.1),(side*4.6,-5.7,z),0,fixed=True)
                if t == 4 or t == 7:
                    self.box("LanternPole",(.2,3.4,.2),(side*4.6,-3.8,z),2,fixed=True)
                    self.box("LanternGlow",(.65,.9,.65),(side*4.6,-1.9,z),4,fixed=True,glow=True)
                    for y in [-2.5,-1.3]:
                        self.box("LanternRoof",(.95,.20,.95),(side*4.6,y,z),1,fixed=True)
                    for dz in [-.35,.35]:
                        self.box("LanternBar",(.12,1.1,.12),(side*4.6,-1.9,z+dz),0,fixed=True)
                elif t in [5,8]:
                    self.crystal(side*4.6,-5.45,z)
                else:
                    for y in [-5.1,-4.45,-3.8]:
                        self.box("FurnaceBrick",(1.0,.6,1.0),(side*4.6,y,z),0,fixed=True)
                    for dz in [-.27,0,.27]:
                        self.box("FurnaceSlit",(.16,1.3,.12),(x,-4.6,z+dz),4,fixed=True,glow=True)
                    for y in [-3.2,-2.6,-2.0]:
                        self.box("ForgeStack",(.5,.55,.5),(side*4.6,y,z),2,fixed=True)
            if t == 4:
                self.pixel("GhostFace",[".###.","#####","#.#.#","#####",".#.#."],x+side*.3,0,0,.34,4,glow=True)
            elif t == 5:
                self.pixel("CurseSeal",["..#..",".#.#.","#.#.#",".#.#.","..#.."],x+side*.3,0,0,.34,4,glow=True)
                self.chain(x,0,3.2,-1,-4.9)
            elif t == 7:
                self.pixel("MoonEmblem",["..####.",".###...","###....","##.....","###....",".###...","..####."],x+side*.4,0,0,.48,2)
                self.chain(x,0,3.2,-1,-4.6)
                for z in [-3.2,3.2]:
                    self.box("Banner",(.15,2.3,1.15),(x,-4.2,z),3,fixed=True)
                    self.pixel("BannerMoon",[".##","##.","##.",".##"],x+side*.12,-4.2,z,.20,2)
            elif t == 8:
                self.pixel("PhantomHood",["..###..",".##.##.","##...##","##.#.##","##...##",".##.##.","..###.."],x+side*.3,0,0,.43,2)
                self.pixel("PhantomEyes",["#.#"],x+side*.4,0,0,.33,4,glow=True)
            else:
                for zside in [-1,1]:
                    for j in range(5):
                        self.box("HornBlock",(.5,.48,.46),(x,.4+j*.43,zside*(.6+j*.20)),2,fixed=True)
                    self.box("HornTip",(.27,.43,.27),(x,2.64,zside*1.5),4,fixed=True)
        elif t == 6:
            self.box("Skull",(.8,2.2,2.4),(x+side*.25,.1,0),0,fixed=True)
            self.box("SkullBrow",(.20,.35,2.55),(x+side*.7,.92,0),2,fixed=True)
            for z in [-.62,.62]:
                self.box("EyeSocket",(.12,.65,.56),(x+side*.71,.24,z),1,fixed=True)
            self.box("NoseSocket",(.14,.40,.32),(x+side*.72,-.38,0),1,fixed=True)
            self.box("Jaw",(.62,.28,2.1),(x+side*.28,-1.38,0),0,fixed=True)
            for j in range(7):
                self.box("Tooth",(.25,.40,.20),(x+side*.73,-1.05,(j-3)*.30),2,fixed=True)
            for y in [-4.9,-3.8,-2.7]:
                self.box("BoneJoint",(1.14,.38,1.3),(side*4.6,y,0),2,fixed=True)
        elif t == 10:
            for z in [-.38,.38]:
                self.box("ColumnFlute",(.16,4.1,.17),(x,-3.4,z),2,fixed=True)
            for j in range(3):
                self.box("CapitalStep",(1.1+j*.18,.22,1.5+j*.18),(side*4.6,-.8+j*.22,0),2,fixed=True)
            self.pixel("Lightning",["...##","..##.",".##..","####.","..##.",".##..","##..."],x+side*.16,.15,0,.25,2)
            for zside in [-1,1]:
                for j in range(4):
                    self.box("LaurelLeaf",(.17,.25,.46),(x,.05+j*.30,zside*(.8-j*.12)),2,(zside*.4,0,0),True)
        elif t == 11:
            # The complete individual feather voxels are added in finishing().
            for k in range(12):
                self.radial("HaloBlock",(.18,.19,.52),x,1.55,k*math.pi/6,2,fixed=True)
        elif t == 12:
            self.pixel("StarCrest",["...#...",".#.#.#.","..###..","#######","..###..",".#.#.#.","...#..."],x+side*.12,0,0,.27,4,glow=True)
            for z in [-2.8,2.8]:
                self.crystal(side*4.6,-5.7,z,2)
            for y in [-4.6,-3.6,-2.6]:
                self.box("ConstellationStud",(.17,.17,.17),(x,y,0),4,fixed=True,glow=True)
        elif t == 13:
            for ring,r in enumerate([1.3,1.7,2.1]):
                for k in range(16):
                    self.radial("PortalBlock",(.18,.22,.48),x+side*ring*.13,r,k*math.pi/8,
                                2 if ring!=1 else 4,fixed=True,glow=ring==1)
            self.pixel("VoidCore",[".###.","#####","#####","#####",".###."],x+side*.1,0,0,.23,1)
            for z in [-3.1,3.1]:
                self.crystal(side*4.6,-5.7,z)
            for y in [-4.8,-3.6,-2.4]:
                self.box("CircuitPanel",(.16,.65,.72),(x,y,0),1,fixed=True)
                self.box("CircuitTrace",(.18,.12,.55),(x+side*.11,y,0),4,fixed=True,glow=True)


def write_geometry(wheels):
    OUT.mkdir(parents=True,exist_ok=True)
    data = []
    for w in wheels:
        data.append(dict(Name=NAMES[w.tier-1]+" Wheel", Palette=PALETTES[w.tier-1],
                         Rotor=w.rotor, Stand=w.stand))
    (OUT/"geometry.json").write_text(json.dumps(data,separators=(",",":")),encoding="utf-8")
    tier_dir = ROOT/"src/shared/Config/WheelTiers"
    tier_dir.mkdir(exist_ok=True)
    header = ["--!strict", "-- Generated by blender/scripts/make_wheels.py; edit the builder, then regenerate."]
    index = header + ["export type Row = { any }", "export type Tier = { Name: string, Palette: { Color3 }, Rotor: { Row }, Stand: { Row } }", "local tiers: { Tier } = {"]
    for i,tier in enumerate(data):
        tier_key = f"{i+1:02d}"+NAMES[i].replace(" ","")
        index.append(f'require(script.Parent.WheelTiers["{tier_key}"]),')
        lines = header + ["-- Row: name, size XYZ, axle-relative position XYZ, rotation XYZ, palette index, neon.",
                          "local tier: { Name: string, Palette: { Color3 }, Rotor: { { any } }, Stand: { { any } } } = {",
                          "Name="+json.dumps(tier["Name"])+",Palette={"+",".join("Color3.fromRGB(%s,%s,%s)"%tuple(c) for c in tier["Palette"])+"},"]
        for key in ["Rotor","Stand"]:
            lines.append(key+"={")
            for row in tier[key]:
                lines.append("{"+",".join(json.dumps(v) if isinstance(v,str) else str(v).lower() if isinstance(v,bool) else str(v) for v in row)+"},")
            lines.append("},")
        lines += ["}", "return tier"]
        (tier_dir/(tier_key+".luau")).write_text("\n".join(lines)+"\n",encoding="utf-8")
    index += ["}", "return tiers"]
    (ROOT/"src/shared/Config/WheelGeometry.luau").write_text("\n".join(index)+"\n",encoding="utf-8")
    print(json.dumps({d["Name"]:{"Rotor":len(d["Rotor"]),"Stand":len(d["Stand"])} for d in data},indent=2))
    return data


def blender_build(data, render):
    import bpy
    from mathutils import Vector
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    # Roblox X,Y,Z -> Blender X,-Z,Y: right-handed coordinates, same physical geometry.
    def convert(v):
        return (v[0],-v[2],v[1])
    cube = bpy.data.meshes.new("SharedBlock")
    verts = [(x,y,z) for x in [-.5,.5] for y in [-.5,.5] for z in [-.5,.5]]
    cube.from_pydata(verts,[],[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)])
    collections = []
    for idx,tier in enumerate(data):
        coll = bpy.data.collections.new(f"{idx+1:02d} {tier['Name']}")
        bpy.context.scene.collection.children.link(coll)
        collections.append(coll)
        mats = []
        for ci,c in enumerate(tier["Palette"]):
            mat=bpy.data.materials.new(f"{idx+1:02d} Finish {ci+1}")
            def linear(v):
                s=v/255
                return s/12.92 if s<=.04045 else ((s+.055)/1.055)**2.4
            mat.diffuse_color=tuple(linear(v) for v in c)+(1,)
            mat.use_nodes=True
            bsdf=mat.node_tree.nodes.get("Principled BSDF")
            bsdf.inputs["Base Color"].default_value=mat.diffuse_color
            bsdf.inputs["Roughness"].default_value=.65
            mats.append(mat)
        for group in ["Rotor","Stand"]:
            for row in tier[group]:
                mesh=cube.copy()
                mesh.materials.append(mats[row[10]-1])
                obj=bpy.data.objects.new(group+"_"+row[0],mesh)
                coll.objects.link(obj)
                obj.location=convert(row[4:7])
                sx,sy,sz=row[1:4]
                obj.scale=(sx,sz,sy)
                ax,ay,az=row[7:10]
                obj.rotation_euler=(ax,-az,ay)
                obj["WheelGroup"]=group
                if row[11]:
                    obj["RobloxMaterial"]="Neon"
        for obj in bpy.context.selected_objects:
            obj.select_set(False)
        for obj in coll.objects:
            obj.select_set(True)
        export=OUT/"models"
        export.mkdir(exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=str(export/f"{idx+1:02d}-{NAMES[idx].lower().replace(' ','-')}.glb"),use_selection=True)
        for obj in coll.objects:
            obj.select_set(False)
    scene=bpy.context.scene
    scene.render.engine="CYCLES"
    scene.cycles.samples=24
    scene.render.resolution_x=768
    scene.render.resolution_y=768
    scene.render.resolution_percentage=100
    scene.world.use_nodes=True
    scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value=(.8,.8,.8,1)
    scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value=.7
    scene.view_settings.view_transform="Standard"
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-6.42))
    floor=bpy.context.object
    floor.name="PreviewGround"
    mat=bpy.data.materials.new("Backdrop")
    mat.diffuse_color=(.78,.80,.83,1)
    floor.data.materials.append(mat)
    bpy.ops.object.camera_add(location=(26,-14,9))
    cam=bpy.context.object
    cam.rotation_euler=(Vector((0,0,.0))-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=19
    scene.camera=cam
    for loc,power,size in [((3,-10,18),2200,10),((-12,-1,10),1700,10),((0,12,12),1800,8)]:
        bpy.ops.object.light_add(type="AREA",location=loc)
        light=bpy.context.object
        light.data.energy=power
        light.data.shape="DISK"
        light.data.size=size
        light.rotation_euler=(Vector((0,0,0))-light.location).to_track_quat('-Z','Y').to_euler()
    for coll in collections:
        coll.hide_render=True
        coll.hide_viewport=True
    for idx,coll in enumerate(collections):
        if render:
            coll.hide_render=False
            scene.render.filepath=str(OUT/f"{idx+1:02d}-preview.png")
            bpy.ops.render.render(write_still=True)
            coll.hide_render=True
    collections[0].hide_viewport=False
    collections[0].hide_render=False
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/"wheel-upgrades.blend"))


if __name__ == "__main__":
    data=write_geometry([Wheel(tier).build() for tier in range(1,14)])
    try:
        import bpy
    except ImportError:
        pass
    else:
        blender_build(data,"--render" in sys.argv)
