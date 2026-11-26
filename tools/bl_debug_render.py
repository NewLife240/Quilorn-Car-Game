import bpy, sys, os, math
from mathutils import Vector
args=sys.argv[sys.argv.index("--")+1:]
out=args[0]
for f in args[1:]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=f)
    for o in bpy.context.scene.objects:
        if o.name.startswith("hood"):
            o.rotation_mode='XYZ'; o.rotation_euler.x += math.radians(65) if True else 0
    objs=[o for o in bpy.context.scene.objects if o.type=='MESH']
    s=bpy.context.scene; s.render.engine='BLENDER_WORKBENCH'
    s.display.shading.color_type='TEXTURE'; s.display.shading.light='STUDIO'
    s.render.resolution_x=640; s.render.resolution_y=400
    for vi,(loc) in enumerate([(4.5,5.5,2.6),(-0.3,-0.35,1.25),(0,0.01,9)]):
        cam=bpy.data.objects.new("c",bpy.data.cameras.new("c")); s.collection.objects.link(cam)
        if vi==1:
            import json
            meta=json.load(open(os.path.join(os.path.dirname(f),"meta.json")))
            e=meta["eye"]; cam.location=Vector((e[0],-e[2],e[1])); cam.rotation_euler=(math.radians(82),0,0); cam.data.lens=18
        else:
            cam.location=Vector(loc); cam.rotation_euler=(Vector((0,0,0.6))-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.lens=35
        if vi==2: cam.data.type='ORTHO'; cam.data.ortho_scale=7
        s.camera=cam
        s.render.filepath=os.path.join(out,os.path.basename(f)[:-4]+"_%d.png"%vi)
        bpy.ops.render.render(write_still=True)
