# Procedurally models car parts, tools and props in Blender and exports each as .glb
# Run: blender -b --python tools/bl_parts.py
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

OUT = "/home/user/rusty_roads/assets/parts"
OUTP = "/home/user/rusty_roads/assets/props"
os.makedirs(OUT, exist_ok=True)
os.makedirs(OUTP, exist_ok=True)

MATS = {}


def M(name, col, rough=0.6, metal=0.0, emit=None):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    MATS[name] = m
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def _fin(o, mat, bevel=0.0, smooth=False):
    o.data.materials.append(mat)
    if bevel > 0:
        md = o.modifiers.new("b", 'BEVEL')
        md.width = bevel
        md.segments = 2
        md.limit_method = 'ANGLE'
    if smooth:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    return o


def box(c, s, mat, bevel=0.01, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=c, rotation=rot)
    o = bpy.context.active_object
    o.scale = s
    bpy.ops.object.transform_apply(scale=True)
    return _fin(o, mat, bevel)


def cyl(c, r, d, mat, axis='Z', seg=20, bevel=0.005, r2=None):
    rot = {'Z': (0, 0, 0), 'X': (0, math.pi / 2, 0), 'Y': (math.pi / 2, 0, 0)}[axis]
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=r, depth=d, location=c, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=seg, radius1=r, radius2=r2, depth=d, location=c, rotation=rot)
    o = bpy.context.active_object
    _fin(o, mat, bevel)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    return o


def torus(c, R, r, mat, axis='X', seg=32, mseg=12):
    rot = {'Z': (0, 0, 0), 'X': (0, math.pi / 2, 0), 'Y': (math.pi / 2, 0, 0)}[axis]
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=seg, minor_segments=mseg, location=c, rotation=rot)
    o = bpy.context.active_object
    _fin(o, mat)
    bpy.ops.object.shade_smooth()
    return o


def export(name, folder=OUT):
    for o in bpy.context.scene.objects:
        for md in list(o.modifiers):
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=md.name)
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active = bpy.context.scene.objects[0]
    if len(bpy.context.scene.objects) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.ops.export_scene.gltf(filepath=os.path.join(folder, name + ".glb"), export_format='GLB', export_yup=True)
    print("PART", name, len(o.data.polygons))


IRON = lambda: M("cast_iron", (0.22, 0.22, 0.23), 0.55, 0.85)
ALU = lambda: M("aluminium", (0.62, 0.63, 0.64), 0.35, 1.0)
BLACK = lambda: M("black_plastic", (0.03, 0.03, 0.035), 0.6)
RUBBER = lambda: M("rubber", (0.025, 0.025, 0.025), 0.9)
STEEL = lambda: M("steel", (0.5, 0.5, 0.52), 0.3, 1.0)
PAINT_R = lambda: M("red_paint", (0.55, 0.06, 0.04), 0.4, 0.2)
PAINT_B = lambda: M("blue_paint", (0.06, 0.12, 0.35), 0.45, 0.2)
COPPER = lambda: M("copper", (0.7, 0.35, 0.15), 0.35, 1.0)
CERAM = lambda: M("ceramic", (0.92, 0.9, 0.85), 0.3)
YEL = lambda: M("yellow_paint", (0.8, 0.55, 0.05), 0.45)


# ---------- engine blocks (origin at bottom centre; X = across car, -Y glTF... Blender +Y = front)
def engine(name, L, scale=1.0, cyls=4, valve=PAINT_R):
    reset()
    s = scale
    box((0, 0, 0.27 * s), (0.30 * s, L, 0.34 * s), IRON(), 0.02)           # block
    box((0, 0, 0.06 * s), (0.26 * s, L * 0.9, 0.12 * s), IRON(), 0.02)    # oil pan
    box((0, 0, 0.49 * s), (0.27 * s, L * 0.95, 0.12 * s), ALU(), 0.015)   # head
    box((0, 0, 0.58 * s), (0.22 * s, L * 0.88, 0.07 * s), valve(), 0.02)  # valve cover
    cyl((0, 0.1 * L, 0.63 * s), 0.03 * s, 0.05 * s, BLACK())               # oil cap
    cyl((0, L / 2 + 0.03, 0.22 * s), 0.1 * s, 0.05 * s, STEEL(), 'Y')      # pulley
    cyl((0, L / 2 + 0.06, 0.40 * s), 0.07 * s, 0.03 * s, STEEL(), 'Y')
    box((0, L / 2 + 0.045, 0.31 * s), (0.02 * s, 0.015, 0.22 * s), RUBBER(), 0.0)  # belt
    for i in range(cyls):  # exhaust manifold runners
        y = -L / 2 + L * (i + 0.5) / cyls
        cyl((0.17 * s, y, 0.42 * s), 0.025 * s, 0.09 * s, IRON(), 'X')
    box((0.22 * s, 0, 0.36 * s), (0.05 * s, L * 0.8, 0.06 * s), IRON(), 0.01)
    for i in range(cyls):  # intake runners
        y = -L / 2 + L * (i + 0.5) / cyls
        cyl((-0.17 * s, y, 0.46 * s), 0.022 * s, 0.09 * s, ALU(), 'X')
    box((-0.23 * s, 0, 0.47 * s), (0.05 * s, L * 0.5, 0.06 * s), ALU(), 0.01)
    export(name)


engine("engine_i4", 0.46)
engine("engine_i4_sport", 0.46, 1.0, 4, PAINT_B)
engine("engine_diesel", 0.62, 1.25, 6, lambda: M("green_paint", (0.15, 0.28, 0.14), 0.5))

# carburettor
reset()
box((0, 0, 0.05), (0.09, 0.08, 0.1), ALU(), 0.008)
cyl((0, 0, 0.12), 0.035, 0.05, ALU())
cyl((0.06, 0, 0.06), 0.012, 0.05, STEEL(), 'X')
box((0, 0, 0.005), (0.11, 0.1, 0.01), STEEL(), 0.002)
export("carburetor")

# air filter (pancake)
reset()
cyl((0, 0, 0.04), 0.14, 0.07, BLACK(), seg=32)
cyl((0, 0, 0.085), 0.03, 0.025, STEEL())
cyl((0, 0, 0.04), 0.142, 0.03, M("filter_paper", (0.75, 0.68, 0.3), 0.9), seg=32)
export("air_filter")

# spark plugs (set of 4 on a card)
reset()
for i in range(4):
    x = -0.06 + i * 0.04
    cyl((x, 0, 0.02), 0.009, 0.04, STEEL())
    cyl((x, 0, 0.06), 0.008, 0.04, CERAM())
    cyl((x, 0, 0.085), 0.004, 0.012, STEEL())
box((0, 0, 0.003), (0.17, 0.05, 0.006), M("cardboard", (0.55, 0.4, 0.22), 0.9), 0)
export("spark_plugs")

# ignition coil
reset()
cyl((0, 0, 0.07), 0.03, 0.14, BLACK())
cyl((0, 0, 0.15), 0.033, 0.02, M("bakelite", (0.1, 0.05, 0.02), 0.5))
box((0, -0.035, 0.07), (0.05, 0.012, 0.08), STEEL(), 0.003)
export("ignition_coil")

# alternator
reset()
cyl((0, 0, 0.08), 0.075, 0.12, ALU(), 'Y', 24)
cyl((0, 0.075, 0.08), 0.04, 0.02, STEEL(), 'Y')
box((0, 0, 0.01), (0.06, 0.1, 0.02), ALU(), 0.003)
export("alternator")

# starter
reset()
cyl((0, 0, 0.05), 0.045, 0.18, IRON(), 'Y')
cyl((0.05, 0.02, 0.09), 0.025, 0.09, STEEL(), 'Y')
cyl((0, 0.1, 0.05), 0.025, 0.04, STEEL(), 'Y')
export("starter")

# radiator
reset()
box((0, 0, 0.22), (0.62, 0.05, 0.4), M("rad_core", (0.18, 0.18, 0.17), 0.7, 0.6), 0.004)
box((0, 0, 0.44), (0.64, 0.07, 0.04), ALU(), 0.005)
box((0, 0, 0.01), (0.64, 0.07, 0.03), ALU(), 0.005)
cyl((0.2, 0, 0.48), 0.025, 0.03, STEEL())
for i in range(14):
    box((-0.28 + i * 0.043, 0.027, 0.22), (0.006, 0.004, 0.38), M("fins", (0.3, 0.3, 0.3), 0.5, 0.8), 0)
export("radiator")

# battery
reset()
box((0, 0, 0.09), (0.24, 0.17, 0.18), BLACK(), 0.008)
box((0, 0, 0.185), (0.235, 0.165, 0.012), M("battery_lid", (0.12, 0.12, 0.14), 0.5), 0.004)
cyl((-0.08, 0.05, 0.2), 0.012, 0.025, M("lead", (0.45, 0.45, 0.45), 0.6, 0.7))
cyl((0.08, 0.05, 0.2), 0.012, 0.025, M("lead", (0.45, 0.45, 0.45), 0.6, 0.7))
box((0.08, 0.05, 0.215), (0.02, 0.02, 0.002), PAINT_R(), 0)
export("battery")

# gearbox
reset()
cyl((0, 0.08, 0.17), 0.17, 0.14, ALU(), 'Y', 24, r2=None)
box((0, -0.15, 0.15), (0.17, 0.34, 0.2), ALU(), 0.03)
cyl((0, -0.35, 0.13), 0.04, 0.08, STEEL(), 'Y')
cyl((0, -0.1, 0.27), 0.012, 0.12, STEEL())
export("gearbox")

# fuel tank
reset()
box((0, 0, 0.13), (0.8, 0.45, 0.24), M("tank_steel", (0.25, 0.26, 0.24), 0.6, 0.7), 0.04)
cyl((0.36, 0.15, 0.27), 0.03, 0.06, STEEL())
for x in (-0.25, 0.25):
    box((x, 0, 0.255), (0.03, 0.47, 0.01), STEEL(), 0)
export("fuel_tank")

# exhaust / muffler
reset()
cyl((0, 0, 0.1), 0.1, 0.5, M("exhaust", (0.25, 0.2, 0.17), 0.8, 0.6), 'Y', 18)
cyl((0, 0.45, 0.1), 0.025, 0.45, M("exhaust", (0.25, 0.2, 0.17), 0.8, 0.6), 'Y')
cyl((0, -0.33, 0.1), 0.025, 0.2, M("exhaust", (0.25, 0.2, 0.17), 0.8, 0.6), 'Y')
export("exhaust")


# ---------- wheels: radius 0.33 nominal, width 0.2, origin at hub centre, axle along X
def wheel(name, tread='road', r=0.33, w=0.2, rim_col=(0.35, 0.36, 0.38)):
    reset()
    # tyre via lathe profile
    bm = bmesh.new()
    prof = []
    rr = r * (0.62 if tread != 'truck' else 0.58)
    n = 10
    for i in range(n + 1):
        t = i / n
        a = math.pi * t
        x = -w / 2 + w * t
        bulge = math.sin(a)
        rad = rr + (r - rr) * (0.55 + 0.45 * bulge ** 0.35)
        prof.append((x, rad))
    prof = [(-w / 2 + 0.01, rr)] + prof + [(w / 2 - 0.01, rr)]
    seg = 40
    rings = []
    for j in range(seg):
        ang = 2 * math.pi * j / seg
        ring = []
        for k, (x, rad) in enumerate(prof):
            tr = rad
            if tread != 'road' and 2 < k < len(prof) - 3:
                blk = (j % 2 == 0) if tread == 'offroad' else (j % 3 != 0)
                off = ((k + (j % 4)) % 3 == 0)
                if blk or off:
                    tr = rad + (0.022 if tread == 'offroad' else 0.012)
            elif tread == 'road' and 3 < k < len(prof) - 4:
                if k % 3 == 0:
                    tr = rad - 0.004
            ring.append(bm.verts.new((x, math.cos(ang) * tr, math.sin(ang) * tr)))
        rings.append(ring)
    for j in range(seg):
        a, b = rings[j], rings[(j + 1) % seg]
        for k in range(len(prof) - 1):
            bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
    me = bpy.data.meshes.new("tyre")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    o = bpy.data.objects.new("tyre", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(RUBBER())
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))
    # rim (steel wheel)
    rimm = M("rim_" + name, rim_col, 0.35, 0.9)
    cyl((0, 0, 0), rr * 0.98, w * 0.8, rimm, 'X', 28)
    cyl((w * 0.32, 0, 0), rr * 0.6, 0.02, rimm, 'X', 28)
    cyl((w * 0.36, 0, 0), rr * 0.2, 0.04, STEEL(), 'X', 16)
    for i in range(5):
        a = 2 * math.pi * i / 5
        cyl((w * 0.39, math.cos(a) * rr * 0.12, math.sin(a) * rr * 0.12), 0.008, 0.02, STEEL(), 'X', 8)
    for i in range(6):  # vent holes look
        a = 2 * math.pi * i / 6 + 0.3
        cyl((w * 0.33, math.cos(a) * rr * 0.42, math.sin(a) * rr * 0.42), rr * 0.09, 0.025, M("hole", (0.02, 0.02, 0.02), 0.9), 'X', 10)
    export(name)


wheel("wheel_road", 'road', rim_col=(0.42, 0.43, 0.45))
wheel("wheel_offroad", 'offroad', w=0.24, rim_col=(0.18, 0.25, 0.16))
wheel("wheel_truck", 'truck', w=0.26, rim_col=(0.5, 0.1, 0.08))
wheel("wheel_sport", 'road', w=0.21, rim_col=(0.75, 0.75, 0.78))

# ---------- tools / containers
reset()
box((0, 0, 0.17), (0.17, 0.32, 0.34), M("jerry_green", (0.15, 0.3, 0.12), 0.45, 0.3), 0.02)
box((0, 0, 0.36), (0.06, 0.2, 0.03), M("jerry_green", (0.15, 0.3, 0.12), 0.45, 0.3), 0.01)
cyl((0, 0.13, 0.37), 0.02, 0.05, STEEL())
export("jerrycan")

reset()
box((0, 0, 0.11), (0.1, 0.16, 0.22), M("oil_bottle", (0.85, 0.65, 0.05), 0.4), 0.02)
cyl((0, 0.05, 0.25), 0.02, 0.05, BLACK())
export("oil_bottle")

reset()
box((0, 0, 0.11), (0.1, 0.16, 0.22), M("coolant_bottle", (0.1, 0.55, 0.65), 0.4), 0.02)
cyl((0, 0.05, 0.25), 0.02, 0.05, M("white_cap", (0.9, 0.9, 0.9), 0.5))
export("coolant_bottle")

# ---------- props
reset()
box((0, 0, 0.3), (0.6, 0.6, 0.6), M("crate_wood", (0.55, 0.4, 0.22), 0.85), 0.01)
for z in (0.05, 0.55):
    box((0, 0, z), (0.62, 0.62, 0.08), M("crate_wood_dark", (0.4, 0.28, 0.15), 0.85), 0.005)
export("crate", OUTP)

reset()
for i in range(5):
    box((-0.5 + i * 0.25, 0, 0.13), (0.14, 1.2, 0.022), M("pallet", (0.6, 0.48, 0.3), 0.9), 0.003)
for x in (-0.5, 0, 0.5):
    box((x, 0, 0.06), (0.1, 1.2, 0.1), M("pallet", (0.6, 0.48, 0.3), 0.9), 0.003)
export("pallet", OUTP)

reset()
cyl((0, 0, 0.45), 0.3, 0.9, M("barrel_blue", (0.08, 0.2, 0.5), 0.5, 0.4), 'Z', 20)
for z in (0.25, 0.65):
    torus((0, 0, z), 0.3, 0.012, M("barrel_blue", (0.08, 0.2, 0.5), 0.5, 0.4), 'Z', 24, 6)
export("barrel", OUTP)

reset()
cyl((0, 0, 0), 0.18, 4.0, M("log_bark", (0.33, 0.24, 0.16), 0.9), 'Y', 12)
cyl((0, 2.0, 0), 0.165, 0.01, M("log_end", (0.75, 0.6, 0.4), 0.8), 'Y', 12)
cyl((0, -2.0, 0), 0.165, 0.01, M("log_end", (0.75, 0.6, 0.4), 0.8), 'Y', 12)
export("log", OUTP)

reset()
box((0, 0, 0.35), (1.0, 1.2, 0.7), M("sack", (0.82, 0.75, 0.55), 0.95), 0.08)
export("sacks", OUTP)

reset()
for i in range(6):
    box((0, 0, 0.04 + i * 0.075), (1.0, 3.0, 0.07), M("plank", (0.78, 0.62, 0.42), 0.85), 0.004)
export("planks", OUTP)

# workbench
reset()
box((0, 0, 0.88), (2.0, 0.75, 0.06), M("bench_top", (0.45, 0.32, 0.2), 0.8), 0.005)
for x in (-0.92, 0.92):
    for y in (-0.32, 0.32):
        box((x, y, 0.43), (0.06, 0.06, 0.86), M("bench_leg", (0.2, 0.22, 0.25), 0.5, 0.7), 0)
box((0, 0, 0.18), (1.9, 0.7, 0.03), M("bench_top", (0.45, 0.32, 0.2), 0.8), 0.003)
box((0, 0.36, 1.4), (2.0, 0.03, 1.0), M("pegboard", (0.55, 0.45, 0.3), 0.9), 0)
export("workbench", OUTP)

# fuel pump
reset()
box((0, 0, 0.9), (0.7, 0.45, 1.8), M("pump_red", (0.7, 0.1, 0.06), 0.45, 0.2), 0.03)
box((0, -0.23, 1.25), (0.5, 0.02, 0.35), M("pump_glass", (0.05, 0.07, 0.08), 0.1), 0)
box((0, 0, 1.85), (0.75, 0.5, 0.12), M("pump_white", (0.9, 0.9, 0.88), 0.4), 0.02)
cyl((0.38, 0, 1.0), 0.04, 0.25, BLACK())
export("fuel_pump", OUTP)
