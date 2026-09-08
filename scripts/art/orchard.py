"""Lantern Orchard: silver-blue leaves, honey light, an owl and a moon harp."""
import math
from geometry import box, curve, ellipsoid, empty, lathe, leaf_cloud, material, mesh, tube
from characters import lantern

PATH=[(0,13),(-8,11),(-14,8),(-20,1),(-28,0),(-31,6)]

def palette():
    return dict(bark=material('Orchard • silver bark',(.26,.24,.33),.9),
      leaves=[material('Orchard • moon leaves '+str(i),c,.9) for i,c in enumerate([(.19,.31,.43),(.30,.43,.55),(.46,.53,.65)])],
      stone=material('Orchard • pale limestone',(.68,.69,.70),.92),
      gold=material('Orchard • warm brass',(.65,.39,.10),.3,.65),
      glow=material('Orchard • warm lantern glass',(1,.62,.14),.25,emission=1.6),
      ink=material('Orchard • midnight blue',(.025,.07,.15),.72),
      path=material('Orchard • pearl path',(.61,.65,.72),.94))

def orchard():
    m=palette()
    for width,y,mat in ((1.9,.005,m['ink']),(1.6,.018,m['path'])):
      verts=[];faces=[]
      for i,(x,z) in enumerate(PATH):
        a=PATH[max(0,i-1)];b=PATH[min(len(PATH)-1,i+1)];dx,dz=b[0]-a[0],b[1]-a[1];d=math.hypot(dx,dz)
        verts.extend([(x-dz/d*width,y,z+dx/d*width),(x+dz/d*width,y,z-dx/d*width)])
        if i: k=i*2;faces.append((k-2,k-1,k+1,k))
      mesh('Path orchard approach',verts,faces,mat)
    # The clearing and south branch stay broad and flat for touch movement.
    for cx,cz,r in [(-28,1,7),(-34,-5,3)]:
      verts=[(cx,.019,cz)]+[(cx+math.cos(a*math.tau/64)*r,.019,cz+math.sin(a*math.tau/64)*r) for a in range(64)]
      mesh('Path orchard clearing',verts,[(0,a+1,(a+1)%64+1) for a in range(64)],m['path'])
    for i,(x,z) in enumerate([(-19,10),(-28,13),(-36,10),(-38,3),(-37,-9),(-28,-10),(-21,-7)]):
      tube('Orchard silver trunk',[(x,0,z),(x+.2,2,z),(x,4.8,z)],[.45,.30,.10],m['bark'])
      for j in range(4):
        a=j*2.4;end=(x+math.cos(a)*1.5,4.3+j*.35,z+math.sin(a)*1.5)
        tube('Orchard branch',[(x,2.7,z),end],[.18,.025],m['bark'])
        leaf_cloud('Orchard individual blue leaves',end,(2.8,1.7,2.8),280,m['leaves'],800+i*7+j)
      lantern((x+.7,2.0,z-.6),.48,m['gold'],m['glow'])
    for i in range(10):
      a=i*math.tau/10;x=-29+math.cos(a)*8;z=2+math.sin(a)*9
      for j in range(3):
        box('Orchard border stone',(x+j*.27,.15,z),(.55,.30,.55),m['stone'],.12)
    for x,z in [(-11,10),(-17,6),(-24,-1),(-32,-6)]:
      tube('Orchard lantern stand',[(x,0,z),(x,1.35,z)],[.06,.06],m['gold'],sides=8)
      lantern((x,1.32,z),.44,m['gold'],m['glow'])

def owl():
    m=palette();cream=material('Luma • soft ivory feathers',(.87,.83,.70),.94);blue=material('Luma • indigo feathers',(.08,.17,.28),.88);gold=m['gold'];dark=material('Luma • velvet pupils',(.01,.018,.03),.5);white=material('Luma • eye glints',(1,.97,.88),.25)
    root=empty('Luma');body=empty('Torso',parent=root)
    ellipsoid('Luma pear shaped body',(0,.68,0),(.54,.62,.36),blue,body)
    ellipsoid('Luma feathered bib',(0,.72,.26),(.39,.47,.16),cream,body)
    for row in range(4):
      for col in range(3):
        x=(col-1)*.16+(row%2)*.025;y=.47+row*.13
        curve('Luma scalloped feather',[(x-.05,y,.406),(x,y-.05,.43),(x+.05,y,.406)],.013,m['bark'],body)
    head=empty('Head',(0,1.32,0),root)
    ellipsoid('Luma head',(0,.05,0),(.60,.46,.37),blue,head)
    for sign,side in [(-1,'L'),(1,'R')]:
      ellipsoid('Luma heart face',(sign*.24,.04,.22),(.31,.32,.17),cream,head)
      eye=empty('Eye.'+side,(sign*.235,.10,.369),head)
      ellipsoid('Luma amber iris',(0,0,0),(.15,.18,.041),gold,eye)
      ellipsoid('Luma black pupil',(0,0,.035),(.079,.12,.015),dark,eye)
      ellipsoid('Luma bright eye',(-.035,.058,.051),(.036,.042,.013),white,eye)
      tube('Luma brow feather',[(sign*.12,.29,.27),(sign*.45,.32,.10),(sign*.56,.48,-.01)],[.07,.10,.004],blue,head)
      wing=empty('Arm.'+side,(sign*.47,.99,0),root)
      ellipsoid('Luma wing',(sign*.05,-.26,-.015),(.19,.40,.25),blue,wing)
      for j in range(3):curve('Luma wing etching',[(sign*.14,-.12,-.04+j*.10),(sign*.17,-.35,-.02+j*.08),(sign*.07,-.58,.02+j*.04)],.016,m['leaves'][1],wing)
      for toe in [-.08,0,.08]:tube('Luma little talon',[(sign*.22,.13,.10),(sign*.22+toe,.05,.28)],[.04,.025],gold,root,sides=8)
    tube('Luma beak',[(0,-.05,.39),(0,-.20,.44)],[.09,.004],gold,head)
    lathe('Luma blue scarf',[(1.00,.36,.30,0),(1.10,.39,.31,0),(1.15,.34,.29,0)],m['leaves'][1],body)
    lantern((.38,.54,.32),.22,gold,m['glow'],root)
    return root

def moon_harp():
    m=palette();root=empty('MoonHarp')
    lathe('Harp stone base',[(0,.72,.57,0),(.16,.77,.60,0),(.25,.58,.43,0)],m['stone'],root)
    for sign in [-1,1]:
      pts=[(sign*(.63+math.sin(j/12*math.pi)*.42),.25+j*.24,0) for j in range(13)]
      curve('Harp crescent frame',pts,.12,m['gold'],root)
    curve('Harp crown',[(-.63,3.13,0),(0,3.46,0),(.63,3.13,0)],.11,m['gold'],root)
    for i in range(7):
      x=-.48+i*.16;curve('Harp luminous string',[(x,.43,.025),(x,3.05,.025)],.014,m['glow'],root)
      ellipsoid('Harp tuning gem',(x,.45,.06),(.048,.07,.05),m['leaves'][i%3],root)
    lantern((0,3.15,0),.29,m['gold'],m['glow'],root)
    return root

def moon_seed():
    m=palette();root=empty('MoonSeed');lathe('Moon seed',[(.1,.02,.02,0),(.2,.22,.19,0),(.5,.30,.24,0),(.80,.15,.13,0),(.95,.005,.005,0)],m['glow'],root)
    for sign in [-1,1]:curve('Seed silver wings',[(0,.5,0),(sign*.38,.75,0),(sign*.48,.96,0)],.05,m['leaves'][2],root)
    return root

def lantern_nest():
    m=palette();root=empty('LanternNest')
    lathe('Nest pedestal',[(0,.65,.65,0),(.3,.57,.57,0),(.9,.39,.39,0),(1.15,.8,.8,0),(1.30,.84,.84,0)],m['stone'],root)
    for i in range(4):
      pts=[(math.cos(j*math.tau/40)*(.70+i*.015),1.33+i*.07,math.sin(j*math.tau/40)*(.70+i*.015)) for j in range(41)]
      curve('Nest woven silver branch',pts,.045,m['bark'],root)
    ellipsoid('Nest soft moss',(0,1.33,0),(.64,.11,.64),m['leaves'][0],root)
    return root

def orchard_gate():
    m=palette();root=empty('OrchardGate')
    # A clear arch across the path, broad enough for both friends.
    for sign in [-1,1]:
      tube('Orchard arch post',[(0,0,sign*1.8),(0,2.8,sign*1.8)],[.16,.12],m['bark'],root)
      lantern((0,1.5,sign*1.8),.38,m['gold'],m['glow'],root)
    pts=[(0,2.7+math.sin(j*math.pi/24)*1.1,math.cos(j*math.pi/24)*1.8) for j in range(25)]
    curve('Orchard silver arch',pts,.13,m['bark'],root)
    for i in range(5):ellipsoid('Orchard arch moon',(0,3.05+math.sin(i*math.pi/4)*.6,-1.2+i*.6),(.10,.18,.13),m['glow'],root)
    return root
