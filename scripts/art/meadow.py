"""A deliberately composed garden: clear walking space, rich detail at its edges."""
import math
import random
from geometry import box, curve, ellipsoid, leaf_cloud, material, mesh, tube
from characters import lantern
from garden import garden_landscape


def path_x(z):
    return math.sin(z*.24)*1.35


GARDEN_PATH = [(0,13),(3.8,12),(6,9),(8.2,6),(9,6),(15.5,6),(18,6),(21,10),(24,17)]

def garden_path_distance(x,z):
    distance=100
    for (ax,az),(bx,bz) in zip(GARDEN_PATH,GARDEN_PATH[1:]):
        dx,dz=bx-ax,bz-az
        t=max(0,min(1,((x-ax)*dx+(z-az)*dz)/(dx*dx+dz*dz)))
        distance=min(distance,math.hypot(x-ax-dx*t,z-az-dz*t))
    return min(distance,math.hypot(x-24,z-17)-2.8)

def ground_height(x, z):
    # Keep the accessible play surface level. Hills frame it rather than obstruct it.
    distance = max(0, -x-39, x-28, abs(z-7)-19)
    return -.06 + min(1, distance*.13) * (1.5+math.sin(x*.28+z*.19)*.9+math.cos(z*.21)*.6)


def terrain(mats):
    vertices, faces = [], []
    n = 100
    for j in range(n+1):
        z = -35+j
        for i in range(n+1):
            x = -50+i
            vertices.append((x,ground_height(x,z),z))
            if i and j:
                k = j*(n+1)+i
                faces.append((k-1,k,k-n-1,k-n-2))
    obj = mesh('Meadow undulating earth',vertices,faces,mats['grass'])
    for mat in mats['meadow_tones']:
        obj.data.materials.append(mat)
    for face in obj.data.polygons:
        co = face.center
        face.material_index = int(abs(math.sin(co.x*.19+co.y*.13))*3)
    # A wide continuous curved path with softly contrasting shoulders.
    for width, height, name, mat in [(2.52,-.007,'Path soft shoulder',mats['sand_edge']),
                                     (2.23,.006,'Path warm sandstone',mats['sand'])]:
        verts, faces = [], []
        for j in range(110):
            z = -12+j*.30
            x = path_x(z)
            verts += [(x-width,height,z),(x+width,height,z)]
            if j:
                k = j*2
                faces.append((k-2,k-1,k+1,k))
        mesh(name,verts,faces,mat)
    for width,y,mat in ((1.45,-.004,mats['sand_edge']),(1.25,.009,mats['sand'])):
        verts,faces=[],[]
        for j,(x,z) in enumerate(GARDEN_PATH):
            before=GARDEN_PATH[max(0,j-1)]; after=GARDEN_PATH[min(len(GARDEN_PATH)-1,j+1)]
            dx,dz=after[0]-before[0],after[1]-before[1]; length=math.hypot(dx,dz)
            verts.extend([(x-dz/length*width,y,z+dx/length*width),(x+dz/length*width,y,z-dx/length*width)])
            if j:
                k=j*2;faces.append((k-2,k-1,k+1,k))
        mesh('Path garden branch',verts,faces,mat)
    verts=[(24,.011,17)]+[(24+math.cos(i*math.tau/64)*3.6,.011,17+math.sin(i*math.tau/64)*3.6) for i in range(64)]
    mesh('Path garden circle',verts,[(0,i+1,(i+1)%64+1) for i in range(64)],mats['sand'])


def oak(m):
    # One continuous hand-shaped trunk, visible twisting roots and spreading boughs.
    tube('Old oak living trunk', [(0,-.2,17),(-.2,1.1,17),(.15,2.7,17.1),
         (-.15,4.1,17.25),(.2,5.7,17.2),(.8,7.6,17.1)], [1.70,1.4,1.13,.97,.67,.19], m['bark'], sides=28)
    rng = random.Random(12)
    for i in range(9):
        a = i*math.tau/9
        if math.sin(a) < -.55:
            continue
        tip=(math.cos(a)*3.4,.05,17+math.sin(a)*2.5)
        tube('Oak root', [(.2,.9,17),(math.cos(a)*1.5,.3,17+math.sin(a)*1.4),tip], [.48,.35,.025],m['bark'],sides=12)
    for i in range(13):
        a = i*2.399
        r = 3.1+(i%3)*.8
        end=(math.cos(a)*r,6.5+(i%4)*.65,17+math.sin(a)*r*.78)
        start=(.1,3.5+(i%4)*.55,17)
        mid=(end[0]*.58,5.6+(i%3)*.30,17+(end[2]-17)*.52)
        tube('Oak sweeping bough', [start,mid,end], [.40,.24,.045],m['bark'],sides=12)
        leaf_cloud('Oak individual leaves',end,(3.0,1.8,2.8),650,m['leaves'],100+i)
        for k in (-1,1):
            branch=(end[0]+k*.85,end[1]+.25,end[2]+k*.6)
            tube('Oak twig',[mid,branch],[.10,.012],m['bark'],sides=8)
    # Bark follows the growth direction. Shallow dark grooves survive glTF export.
    for i in range(23):
        a = i*math.tau/23
        pts=[]
        for j in range(7):
            h=.22+j*.76
            r=1.55-h*.115
            pts.append((math.cos(a+math.sin(j)*.075)*r + math.sin(h*2)*.09,h,17+math.sin(a+math.sin(j)*.075)*r))
        curve('Flowing bark grain',pts,.025,m['bark_light'])
    # Arched little door and stone surround are large, obvious destinations.
    door_z=15.65
    for i in range(3):
        box('Door limestone step',(0,.04+i*.05,14.9+i*.22),(2.2-i*.12,.13,.48),m['sand_edge'],.07)
    for i in range(13):
        a=i*math.pi/12
        x=math.cos(a)*.99
        h=1.62+math.sin(a)*.96
        stone=box('Oak door arch stone',(x,h,door_z-.035),(.29,.29,.25),m['stone'],.08)
        stone.rotation_euler.y=-a
    for sign in (-1,1):
        for i in range(5):
            box('Door jamb stone',(sign*.99,.2+i*.30,door_z-.025),(.30,.31,.26),m['stone'],.07)
    # Fitted plank tops follow the arch. Closed door is inviting, not an unexplained portal.
    for i in range(9):
        x=(i-4)*.194
        top=1.6+math.sqrt(max(0,.83**2-x*x))
        box('Rounded oak door plank',(x,top/2,door_z-.12),(.187,top,.12),m['door'],.035)
    for h in (.43,1.34):
        box('Door forged hinge',(-.5,h,door_z-.21),(.7,.055,.035),m['iron'],.018)
    ellipsoid('Door brass knob',(.55,1.1,door_z-.26),(.07,.07,.055),m['gold'])
    # Round glowing windows, each with a substantial carved wooden rim.
    for x,h in ((-1.42,2.86),(1.1,3.3)):
        ring=[(x+math.cos(a*math.tau/32)*.39,h+math.sin(a*math.tau/32)*.39,15.92) for a in range(33)]
        curve('Window carved surround',ring,.075,m['bark_light'])
        ellipsoid('Oak warm window',(x,h,15.94),(.36,.36,.04),m['glow'])
        for dx,dy in ((.36,0),(0,.36)):
            curve('Window crossbar',[(x-dx,h-dy,15.865),(x+dx,h+dy,15.865)],.035,m['bark'])
    for x,h,z in ((-2.6,2.8,15.7),(2.5,3.3,15.4),(-3.7,3.8,17.3)):
        curve('Lantern hanging cord',[(x,h+.9,z),(x,h+.15,z)],.017,m['iron'])
        lantern((x,h-.45,z),.48,m['gold'],m['glow'])


def forest_tree(x,z,scale,seed,m):
    h=ground_height(x,z)
    tube('Woodland trunk',[(x,h,z),(x+.1,h+2.6*scale,z),(x-.2,h+5.2*scale,z+.2)], [.38*scale,.26*scale,.04],m['bark'])
    for i in range(5):
        a=i*2.4
        end=(x+math.cos(a)*1.7*scale,h+(3.9+i*.42)*scale,z+math.sin(a)*1.4*scale)
        tube('Woodland branch',[(x,h+2.3*scale,z),end],[.16*scale,.015],m['bark'],sides=8)
        leaf_cloud('Woodland canopy',end,(2.1*scale,1.5*scale,2.0*scale),230,m['leaves'],seed+i)


def borders(m):
    rng=random.Random(54)
    grass_vertices,grass_faces=[],[]
    petals=[([],[]) for _ in range(3)]
    centers_v,centers_f=[],[]
    for i in range(6000):
        z=rng.uniform(-15,30)
        x=rng.uniform(-18,28)
        if abs(x-path_x(z)) < 2.9 or garden_path_distance(x,z)<1.7 or (x*x+(z-17)**2 < 12) or (9<x<15.8):
            continue
        y=ground_height(x,z)+.04
        for k in range(3):
            a=rng.uniform(0,math.tau)
            length=rng.uniform(.14,.41)
            dx,dz=math.cos(a),math.sin(a)
            n=len(grass_vertices)
            grass_vertices.extend([(x-dz*.026,y,z+dx*.026),(x+dz*.026,y,z-dx*.026),
                                   (x+dx*.07+dz*.012,y+length*.68,z+dz*.07-dx*.012),
                                   (x+dx*.14,y+length,z+dz*.14)])
            grass_faces.extend([(n,n+1,n+2),(n,n+2,n+3)])
        if i%11:
            continue
        height=rng.uniform(.27,.62)
        n=len(grass_vertices)
        grass_vertices.extend([(x-.018,y,z),(x+.018,y,z),(x+.013,y+height,z),(x-.013,y+height,z)])
        grass_faces.append((n,n+1,n+2,n+3))
        color=rng.randrange(3)
        verts,faces=petals[color]
        # Open cupped flowers with broad petals, dark centers and clear silhouettes.
        for p in range(7):
            a=p*math.tau/7
            ca,sa=math.cos(a),math.sin(a)
            n=len(verts)
            verts.extend([(x,y+height,z),(x+ca*.13-sa*.08,y+height+.01,z+sa*.13+ca*.08),
                          (x+ca*.24,y+height+.07,z+sa*.24),
                          (x+ca*.13+sa*.08,y+height+.01,z+sa*.13-ca*.08)])
            faces.append((n,n+1,n+2,n+3))
        n=len(centers_v)
        centers_v.append((x,y+height+.028,z))
        for j in range(8):
            centers_v.append((x+math.cos(j*math.tau/8)*.064,y+height+.014,z+math.sin(j*math.tau/8)*.064))
            centers_f.append((n,n+j+1,n+(j+1)%8+1))
    mesh('Fine meadow grasses',grass_vertices,grass_faces,m['blades'],smooth=False)
    for (v,f),mat in zip(petals,m['flowers']):
        mesh('Meadow flowers',v,f,mat)
    mesh('Flower pollen hearts',centers_v,centers_f,m['pollen'])
    # A few deliberately large foreground flower heads and ferns, never scattered on the path.
    for sign in (-1,1):
        for j in range(11):
            x=sign*(3.4+rng.random()*1.2)+path_x(j*2-7)
            z=j*2-7
            for i in range(5):
                angle=i*math.tau/5
                curve('Fern stem',[(x,0,z),(x+math.cos(angle)*.26,.4,z+math.sin(angle)*.26),
                                   (x+math.cos(angle)*.48,.43,z+math.sin(angle)*.48)],.016,m['blades'])
                leaf_cloud('Fern leaflets',(x+math.cos(angle)*.25,.34,z+math.sin(angle)*.25),(.33,.25,.33),12,[m['blades']],j*30+i)


def water_and_bridge(m):
    # River is on the eastern boundary, with readable stone edging and a quiet bridge landmark.
    verts,faces=[],[]
    for i in range(90):
        z=-18+i*.6
        center=12+math.sin(z*.14)*1.25
        verts += [(center-1.9,-.015,z),(center+1.9,-.015,z)]
        if i:
            k=i*2
            faces.append((k-2,k-1,k+1,k))
    mesh('Water turquoise surface',verts,faces,m['water'])
    rng=random.Random(77)
    for i in range(85):
        z=-17+i*.57
        for sign in (-1,1):
            x=12+math.sin(z*.14)*1.25+sign*2.0
            ellipsoid('Riverbank stone',(x,.05,z),(.36+rng.random()*.18,.19+rng.random()*.16,.45),m['stone'],segments=16)
    for i in range(45):
        z=rng.uniform(-15,30)
        x=12+math.sin(z*.14)*1.25+rng.uniform(-1.4,1.4)
        curve('Water glints',[(x-.15,.006,z),(x+.08,.006,z+.012),(x+.3,.006,z-.006)],.009,m['water_glint'])
    # Small arched footbridge, side rails and individually fitted stones.
    for j in range(19):
        x=9+j*.34
        h=.10+math.sin(j/18*math.pi)*.68
        box('Bridge dressed stone',(x,h,6),(.35,.26,2.05),m['stone'],.055)
        for sign in (-1,1):
            box('Bridge parapet',(x,h+.45,6+sign*1.02),(.35,.82,.27),m['stone'],.065)
    for sign in (-1,1):
        pts=[(9+j*.34,.66+math.sin(j/18*math.pi)*.68,6+sign*1.02) for j in range(19)]
        curve('Bridge smooth coping',pts,.15,m['sand_edge'])


def meadow():
    m={
        'grass':material('Ground • sage meadow',(.17,.29,.12)),
        'meadow_tones':[material('Ground • meadow variation '+str(i),c) for i,c in enumerate([(.20,.32,.135),(.22,.34,.15),(.19,.30,.12)])],
        'sand':material('Path • warm limestone',(.67,.54,.34),.95),
        'sand_edge':material('Path • pale shoulder',(.76,.67,.46),.95),
        'bark':material('Oak • chestnut bark',(.15,.075,.032),.94),
        'bark_light':material('Oak • warm grain',(.25,.135,.059),.93),
        'door':material('Oak • painted teal door',(.028,.17,.16),.77),
        'iron':material('Oak • dark iron',(.038,.043,.039),.5,.35),
        'gold':material('Lantern • aged brass',(.54,.31,.065),.35,.6),
        'glow':material('Lantern • honey glass',(1,.51,.105),.3,emission=1.8),
        'stone':material('Stone • warm grey',(.38,.39,.31),.95),
        'leaves':[material('Leaves • '+str(i),c,.9) for i,c in enumerate([(.13,.27,.073),(.20,.37,.10),(.30,.43,.12),(.38,.46,.15)])],
        'blades':material('Grass • emerald blades',(.13,.28,.07),.95),
        'flowers':[material('Flowers • '+n,c,.83) for n,c in [('ivory',(.95,.86,.65)),('coral',(.80,.21,.12)),('blue',(.26,.35,.63))]],
        'pollen':material('Flowers • ochre hearts',(.65,.34,.035),.9),
        'water':material('Water • jade stream',(.028,.28,.29),.16,.25),
        'water_glint':material('Water • quiet reflections',(.38,.66,.59),.3)
    }
    terrain(m)
    oak(m)
    garden_landscape(m)
    for i in range(18):
        angle=i*math.tau/18
        x=math.cos(angle)*25
        z=13+math.sin(angle)*25
        forest_tree(x,z,.9+(i%4)*.15,i*15,m)
    # Far hills are large smooth silhouettes with low contrast, not a black void.
    for i in range(9):
        ellipsoid('Distant woodland hill',(-44+i*11,-2,47+(i%2)*7),(13,7+(i%3)*2,13),m['grass'],segments=32)
    water_and_bridge(m)
    borders(m)
    rng=random.Random(25)
    for i in range(50):
        z=rng.uniform(-10,30)
        x=path_x(z)+rng.choice([-1,1])*rng.uniform(3,8)
        if x*x+(z-17)**2<10 or garden_path_distance(x,z)<1.8:
            continue
        ellipsoid('Mossy path boulder',(x,ground_height(x,z)+.06,z),(rng.uniform(.25,.7),rng.uniform(.18,.40),rng.uniform(.3,.6)),m['stone'],segments=16)
