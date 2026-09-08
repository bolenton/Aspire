"""Run with Blender --background --python scripts/art/build_assets.py -- [all|explorer|fox|meadow]."""
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector

SCRIPT = Path(__file__).resolve().parent
sys.path.insert(0,str(SCRIPT))
from geometry import export, join_static, point, reset
from characters import explorer, fox, acorn
from meadow import meadow
from garden import river_bell, lantern_flower, garden_star
from orchard import orchard, owl, moon_harp, moon_seed, lantern_nest, orchard_gate

ROOT=SCRIPT.parent.parent
OUT=ROOT/'Clients/Lantern.Unity/Assets/StreamingAssets/Meadow'
PREVIEW=ROOT/'.artifacts/art'
OUT.mkdir(parents=True,exist_ok=True)
PREVIEW.mkdir(parents=True,exist_ok=True)


def light(name,kind,pos,energy,color,size=5):
    data=bpy.data.lights.new(name,kind)
    data.energy=energy
    data.color=color
    if kind=='AREA':
        data.shape='DISK'
        data.size=size
    obj=bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(obj)
    obj.location=point(pos)
    return obj


def render(name,camera_pos,target,world=False):
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.samples=32 if world else 48
    scene.cycles.use_denoising=True
    scene.render.resolution_x=1600 if world else 1200
    scene.render.resolution_y=1000
    scene.render.resolution_percentage=100
    scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.40,.56,.68,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
    sun=light('Late afternoon sun','SUN',(0,10,0),2.4,(1,.84,.62))
    sun.rotation_euler=(math.radians(-35),math.radians(-24),math.radians(-12))
    sun.data.angle=.12
    if not world:
        from geometry import material, box
        box('Studio floor',(0,-.035,0),(200,.05,200),material('Studio sage',(.12,.19,.18)),0)
        fill=light('Softbox','AREA',(-3,4,3),450,(.72,.85,1),5)
        fill.rotation_euler=(point(target)-fill.location).to_track_quat('-Z','Y').to_euler()
        rim=light('Warm rim','AREA',(3,3,-3),650,(1,.75,.43),3)
        rim.rotation_euler=(point(target)-rim.location).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('Preview camera')
    camera=bpy.data.objects.new('Preview camera',data)
    bpy.context.collection.objects.link(camera)
    camera.location=point(camera_pos)
    camera.rotation_euler=(point(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    data.lens=42 if world else 57
    scene.camera=camera
    scene.view_settings.view_transform='AgX'
    scene.render.image_settings.file_format='PNG'
    scene.render.filepath=str(PREVIEW/(name+'.png'))
    bpy.ops.wm.save_as_mainfile(filepath=str(PREVIEW/(name+'.blend')))
    bpy.ops.render.render(write_still=True)


args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['all']
choice=args[0] if args else 'all'
for name,factory,cam,target in [
    ('Explorer',explorer,(3.1,2.5,5.7),(0,1.08,0)),
    ('Ember',fox,(2.4,1.9,4.5),(0,.85,0)),
    ('Acorn',acorn,(1.5,1.5,2.4),(0,.6,0)),
    ('RiverBell',river_bell,(3,2.5,4),(0,1.3,0)),
    ('LanternFlower',lantern_flower,(4,4.5,5),(0,1.9,0)),
    ('GardenStar',garden_star,(1.5,1.5,3),(0,.8,0)),
    ('Orchard',orchard,(-16,5,-8),(-29,3,4)),
    ('Luma',owl,(2.8,2.2,4),(0,1,0)),
    ('MoonHarp',moon_harp,(3,3,5),(0,1.7,0)),
    ('MoonSeed',moon_seed,(2,1.5,3),(0,.5,0)),
    ('LanternNest',lantern_nest,(3,2.5,4),(0,.9,0)),
    ('OrchardGate',orchard_gate,(5,3,1),(0,2,0)),
    ('Meadow',meadow,(7,4.5,-9),(0,3.4,17))]:
    if choice not in ('all',name.lower(),'fox' if name=='Ember' else name.lower()) and not (choice=='orchard-set' and name in ('Orchard','Luma','MoonHarp','MoonSeed','LanternNest','OrchardGate')) and not (choice=='expansion' and name in ('Meadow','RiverBell','LanternFlower','GardenStar')):
        continue
    reset()
    factory()
    if name in ('Meadow','Orchard'):
        join_static()
    export(OUT/(name+'.glb'))
    if '--export-only' not in args:
        render(name,cam,target,name=='Meadow')
