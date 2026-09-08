"""New large, readable landmarks for the river and lantern garden chapter."""
import math
import bpy
from geometry import box, curve, ellipsoid, lathe, material, mesh, tube
from characters import lantern


def river_bell():
    teal=material('Bell • painted teal',(.035,.23,.23),.5)
    gold=material('Bell • brushed gold',(.70,.39,.075),.26,.65)
    cream=material('Bell • limestone',(.74,.64,.43),.9)
    dark=material('Bell • warm interior',(.20,.11,.025),.7,.3)
    box('Bell plinth',(0,.12,0),(1.5,.24,1.1),cream,.12)
    for x in (-.65,.65):
        box('Carved bell post',(x,1.15,0),(.17,2.1,.20),teal,.055)
        ellipsoid('Post brass finial',(x,2.28,0),(.15,.15,.15),gold)
    curve('Bell sweeping yoke',[(-.72,2.05,0),(0,2.37,0),(.72,2.05,0)],.12,teal)
    curve('Bell suspension',[(0,2.3,0),(0,1.91,0)],.043,gold)
    lathe('Singing brass bell',[(.82,.62,.62,0),(.91,.65,.65,0),(1.02,.49,.49,0),(1.38,.31,.31,0),(1.73,.26,.26,0),(1.86,.10,.10,0)],gold)
    ellipsoid('Bell dark opening',(0,.825,0),(.56,.028,.56),dark)
    tube('Bell tongue',[(0,.85,0),(0,.62,0)],[.07,.10],gold)
    for h,r in ((.9,.62),(1.63,.275)):
        curve('Bell decorative rim',[(math.cos(i*math.tau/40)*r,h,math.sin(i*math.tau/40)*r) for i in range(41)],.025,cream)


def lantern_flower():
    jade=material('Flower • jade stem',(.055,.22,.14),.72)
    ivory=material('Flower • ivory petals',(.95,.77,.40),.47)
    coral=material('Flower • apricot petals',(.89,.29,.105),.46)
    gold=material('Flower • gold center',(.85,.48,.10),.33,.25)
    glow=material('Flower • luminous heart',(1,.63,.15),.35,emission=1)
    tube('Flower curling stem',[(0,0,0),(-.15,1,0),(.13,2.1,0),(0,3,0)],[.22,.17,.13,.15],jade)
    for side,h in ((-1,1.05),(1,1.6)):
        verts=[(0,h,0),(side*.45,h+.52,.15),(side*1.25,h+.6,0),(side*.6,h+.04,-.20)]
        obj=mesh('Flower broad leaf',verts,[(0,1,2,3)],jade)
        solid=obj.modifiers.new('Leaf thickness','SOLIDIFY'); solid.thickness=.045
        bevel=obj.modifiers.new('Rounded leaf','BEVEL'); bevel.width=.10; bevel.segments=3
    # Sweeping cupped petals form a flower lantern with an open golden heart.
    for layer in range(2):
        for i in range(9):
            a=(i+layer*.5)*math.tau/9
            ca,sa=math.cos(a),math.sin(a)
            verts=[]
            for j in range(7):
                t=j/6; r=.24+t*1.20; h=2.55+math.sin(t*math.pi*.76)*.51+layer*.08
                width=math.sin(t*math.pi)*.44+.035
                for side in (-1,1): verts.append((ca*r-sa*width*side,h-.10*abs(side),sa*r+ca*width*side))
            faces=[(j*2,j*2+1,j*2+3,j*2+2) for j in range(6)]
            obj=mesh('Flower sculpted petal',verts,faces,ivory if layer else coral)
            solid=obj.modifiers.new('Petal thickness','SOLIDIFY'); solid.thickness=.07
            sub=obj.modifiers.new('Petal softness','SUBSURF'); sub.levels=2
    ellipsoid('Flower seed heart',(0,2.78,0),(.53,.33,.53),gold)
    lantern((0,2.84,0),.63,gold,glow)


def garden_star():
    gold=material('Star • honey gold',(1,.62,.10),.28,.24,emission=.16)
    cream=material('Star • cream glints',(1,.91,.6),.35)
    vertices=[]
    for z in (-.14,.14):
        for i in range(10):
            a=math.pi/2+i*math.tau/10;r=.66 if i%2==0 else .34
            vertices.append((math.cos(a)*r,.78+math.sin(a)*r,z))
    faces=[tuple(reversed(range(10))),tuple(range(10,20))]
    faces += [(i,(i+1)%10,(i+1)%10+10,i+10) for i in range(10)]
    obj=mesh('Garden wishing star',vertices,faces,gold,smooth=False)
    bevel=obj.modifiers.new('Rounded star edges','BEVEL'); bevel.width=.075;bevel.segments=4
    obj.modifiers.new('Star soft normals','WEIGHTED_NORMAL')
    ellipsoid('Star glint',(-.14,.93,.16),(.09,.15,.015),cream)


def garden_landscape(m):
    cream=m['sand_edge']; wood=m['door']; gold=m['gold']
    # The flower clearing is open, with a raised planting border outside its walking space.
    for radius in (3.8,4.25):
        for i in range(32):
            a=i*math.tau/32
            if math.sin(a)<-.80: continue
            x,z=24+math.cos(a)*radius,17+math.sin(a)*radius
            obj=box('Garden curved planter',(x,.18,z),(.74,.36,.38),cream,.08)
            obj.rotation_euler.z=-a-math.pi/2
    # A prominent sunflower arch marks the far end of the bridge.
    for z in (4.55,7.45):
        box('Garden arch post',(17,1.4,z),(.22,2.8,.22),wood,.06)
        ellipsoid('Arch golden finial',(17,2.87,z),(.20,.20,.20),gold)
    curve('Garden arch crown',[(17,2.75,4.5),(17,3.5,6),(17,2.75,7.5)],.15,wood)
    for z,h in ((4.55,2.4),(7.45,2.4),(6,3.47)):
        for i in range(10):
            a=i*math.tau/10
            petal=ellipsoid('Arch sunflower petal',(16.83,h+math.sin(a)*.31,z+math.cos(a)*.31),(.07,.22,.12),m['glow'],segments=16)
            petal.rotation_euler.x=a
        ellipsoid('Arch sunflower heart',(16.79,h,z),(.09,.18,.18),m['gold'],segments=16)
    # A generous seat and large planters give the new bank a sense of place.
    for x in (20.8,27.2):
        for z in (15.5,18.8):
            box('Garden bench leg',(x,.24,z),(.15,.48,.16),wood,.04)
        for j in range(4):
            box('Garden bench seat',(x+(j-1.5)*.16,.55,17.15),(.145,.12,3.6),m['bark_light'],.04)
    for i in range(10):
        a=i*math.tau/10
        if math.sin(a)<-.8:continue
        x,z=24+math.cos(a)*4,17+math.sin(a)*4
        tube('Garden lantern stalk',[(x,0,z),(x-.12,1.1,z),(x,1.6,z)],[.07,.06,.025],m['blades'],sides=8)
        lantern((x,1.48,z),.29,gold,m['glow'])
