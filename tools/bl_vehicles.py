# Blender batch processor for vehicle models.
# Imports a free low-poly car model, normalizes scale/orientation, strips baked wheels,
# cuts out a hood (or front hatch), adds an engine bay and a generated interior,
# then exports a .glb plus a meta.json used by the game.
# Run: blender -b --python tools/bl_vehicles.py -- [vehicle_id ...]
import bpy, bmesh, json, os, sys, math
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = ROOT + "/tools/src_assets"
OUT = ROOT + "/assets/vehicles"
PSX = SRC + "/psx_style_cars_by_ggbot_august2023"
SOV = SRC + "/x_russian_vehicles_lowepoly_pixelart"
RGS = SRC + "/free_low_poly_vehicles_pack_by_rgsdev/Free Low Poly Vehicles Pack by Rgsdev"

# flip: rotate 180 deg so the front points to +Y.  length: target length in metres.
V = {
    "kombi":    dict(src=PSX+"/Car 01/Car.obj", tex=PSX+"/Car 01/car.png", variants=[PSX+"/Car 01/car_blue.png", PSX+"/Car 01/car_gray.png", PSX+"/Car 01/car_red.png"], length=4.15, flip=True, xscale=0.95),
    "klasyka":  dict(paint_wheels=True, src=SOV+"/vaz/vaz_klassika.obj", tex=SOV+"/vaz/vaz2106_albedo_blue.png", variants=[SOV+"/vaz/vaz2106_albedo_red.png", SOV+"/vaz/vaz2105_albedo_green.png", SOV+"/vaz/vaz2101_albedo_grey.png", SOV+"/vaz/vaz2101_albedo_yellow.png"], length=4.1, flip=True),
    "bobyk":    dict(paint_wheels=True, src=SOV+"/bobik/bobik.obj", tex=SOV+"/bobik/bobik_albedo.png", variants=[SOV+"/bobik/bobik_yellow_albedo.png"], length=4.0, flip=True),
    "bukhanka": dict(paint_wheels=True, src=SOV+"/buhanka/buhanka.obj", tex=SOV+"/buhanka/buhanka_albedo.png", variants=[SOV+"/buhanka/buhanka_grey_albedo.png"], length=4.4, flip=True),
    "hatch":    dict(src=PSX+"/Car 03/Car3.obj", tex=PSX+"/Car 03/car3.png", variants=[PSX+"/Car 03/car3_red.png", PSX+"/Car 03/car3_yellow.png"], length=3.8, flip=True, xscale=0.92),
    "sedan":    dict(src=PSX+"/Car 02/Car2.obj", tex=PSX+"/Car 02/car2.png", variants=[PSX+"/Car 02/car2_black.png", PSX+"/Car 02/car2_red.png"], length=4.6, flip=True, xscale=0.88),
    "cruiser":  dict(src=PSX+"/Car 05/Car5.obj", tex=None, length=5.3, flip=True),
    "minivan":  dict(src=PSX+"/Car 04/Car4.obj", tex=PSX+"/Car 04/car4.png", variants=[PSX+"/Car 04/car4_grey.png", PSX+"/Car 04/car4_lightorange.png"], length=4.8, flip=True, xscale=0.82),
    "stepvan":  dict(src=PSX+"/Car 08/Car8.obj", tex=PSX+"/Car 08/Car8.png", variants=[PSX+"/Car 08/Car8_mail.png", PSX+"/Car 08/Car8_grey.png"], length=5.6, flip=True, xscale=0.9),
    "pickup":   dict(src=RGS+"/Pickup/Pickup.fbx", tex=None, length=5.1, flip=True, xscale=0.72),
    "suv":      dict(src=RGS+"/SUV/SUV.fbx", tex=None, length=4.7, flip=True, xscale=0.74),
    "truck":    dict(src=RGS+"/Truck/Truck.fbx", tex=None, length=5.8, flip=True, xscale=0.8, add_bed=True),
}
OVR = {}  # filled from tools/vehicle_overrides.json if present
ovf = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vehicle_overrides.json")
if os.path.exists(ovf):
    OVR = json.load(open(ovf))


def g(v):  # blender -> godot coords
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color, rough=0.8, metal=0.0, img=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
    b.inputs['Base Color'].default_value = (*color, 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if img:
        for n in [n for n in nt.nodes if n.type == 'TEX_IMAGE']:
            nt.nodes.remove(n)
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(img, check_existing=True)
        t.interpolation = 'Closest'
        nt.links.new(t.outputs[0], b.inputs['Base Color'])
    return m


def import_model(cfg):
    f = cfg["src"]
    if f.endswith(".obj"):
        bpy.ops.wm.obj_import(filepath=f, forward_axis='NEGATIVE_Z', up_axis='Y')
    elif f.endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=f)
    else:
        bpy.ops.import_scene.gltf(filepath=f)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    wheel_objs = [o for o in meshes if "wheel" in o.name.lower()]
    body_objs = [o for o in meshes if o not in wheel_objs]
    # apply transforms
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    wheels = []
    for o in wheel_objs:
        vs = [o.matrix_world @ v.co for v in o.data.vertices]
        wheels.append(bbox(vs))
    for o in wheel_objs:
        bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in body_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body_objs[0]
    if len(body_objs) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "body"
    return body, wheels


def bbox(pts):
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def islands(bm):
    seen = set()
    res = []
    for f in bm.faces:
        if f.index in seen:
            continue
        st = [f]
        isl = []
        seen.add(f.index)
        while st:
            x = st.pop()
            isl.append(x)
            for e in x.edges:
                for y in e.link_faces:
                    if y.index not in seen:
                        seen.add(y.index)
                        st.append(y)
        res.append(isl)
    return res


def detect_wheels_islands(body):
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.faces.ensure_lookup_table()
    allv = [v.co.copy() for v in bm.verts]
    mn, mx = bbox(allv)
    W, L, H = mx.x - mn.x, mx.y - mn.y, mx.z - mn.z
    found = []
    kill = []
    for isl in islands(bm):
        pts = [v.co for f in isl for v in f.verts]
        a, b = bbox(pts)
        if (a.z - mn.z) < 0.07 * H and (b.x - a.x) < 0.3 * W and (b.y - a.y) < 0.3 * L and (b.y - a.y) > 0.07 * L and (b.z - a.z) < 0.5 * H and (abs(a.x) > 0.15 * W or abs(b.x) > 0.15 * W):
            found.append((a, b))
            kill.extend(isl)
    # group into wheels by side/axle
    groups = {}
    for a, b in found:
        c = (a + b) / 2
        key = (1 if c.x > 0 else -1, round(c.y / (0.12 * L)))
        groups.setdefault(key, []).append((a, b))
    wheels = []
    for k, lst in groups.items():
        a = Vector((min(p[0].x for p in lst), min(p[0].y for p in lst), min(p[0].z for p in lst)))
        b = Vector((max(p[1].x for p in lst), max(p[1].y for p in lst), max(p[1].z for p in lst)))
        wheels.append((a, b))
    bmesh.ops.delete(bm, geom=list(set(kill)), context='FACES')
    bm.to_mesh(body.data)
    bm.free()
    return wheels


def separate_faces(body, pred, name):
    bm = bmesh.new()
    bm.from_mesh(body.data)
    sel = [f for f in bm.faces if pred(f)]
    if not sel:
        bm.free()
        return None
    me = bpy.data.meshes.new(name)
    bm2 = bmesh.new()
    vmap = {}
    uvl = bm.loops.layers.uv.active
    uvl2 = bm2.loops.layers.uv.new("UVMap") if uvl else None
    for f in sel:
        vs = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = bm2.verts.new(v.co)
            vs.append(vmap[v])
        try:
            nf = bm2.faces.new(vs)
            nf.material_index = f.material_index
            nf.smooth = f.smooth
            if uvl:
                for l1, l2 in zip(f.loops, nf.loops):
                    l2[uvl2].uv = l1[uvl].uv
        except ValueError:
            pass
    bm2.to_mesh(me)
    bm2.free()
    bmesh.ops.delete(bm, geom=sel, context='FACES')
    bm.to_mesh(body.data)
    bm.free()
    o = bpy.data.objects.new(name, me)
    for m in body.data.materials:
        me.materials.append(m)
    bpy.context.scene.collection.objects.link(o)
    return o


def set_origin(o, p):
    o.data.transform(Matrix.Translation(-p))
    o.location = p


def add_box(bm, c, s, inward=False, skip_top=False):
    r = bmesh.ops.create_cube(bm, size=1.0)
    vs = r['verts']
    for v in vs:
        v.co = Vector((c[0] + v.co.x * s[0], c[1] + v.co.y * s[1], c[2] + v.co.z * s[2]))
    faces = list({f for v in vs for f in v.link_faces})
    if skip_top:
        top = [f for f in faces if f.normal.z > 0.9]
        bmesh.ops.delete(bm, geom=top, context='FACES')
        faces = [f for f in faces if f.is_valid]
    if inward:
        bmesh.ops.reverse_faces(bm, faces=faces)
    return faces


def mk_obj(name, bm, materials):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in materials:
        me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o



def wheel_paint_regions(body, wheels):
    """For textures that have wheels painted on the body sides: returns per-face affine maps
    (yz -> uv) and the wheel circles that overlap them."""
    import numpy as np
    me = body.data
    uvl = me.uv_layers.active.data
    regions = []
    for poly in me.polygons:
        if abs(poly.normal.x) < 0.8:
            continue
        idx = list(poly.loop_indices)
        P = [me.vertices[me.loops[i].vertex_index].co for i in idx]
        U = [uvl[i].uv for i in idx]
        ys = [p.y for p in P]
        zs = [p.z for p in P]
        for w in wheels:
            c, r = w["c"], w["r"] * 1.08
            if (c.x > 0) != (poly.normal.x > 0):
                continue
            if c.y + r < min(ys) or c.y - r > max(ys) or c.z + r < min(zs) or c.z - r > max(zs):
                continue
            # affine fit uv = M @ [y, z, 1] (least squares over the polygon corners)
            A = np.array([[p.y, p.z, 1.0] for p in P])
            B = np.array([[u.x, u.y] for u in U])
            M, *_ = np.linalg.lstsq(A, B, rcond=None)
            regions.append((M, (c.y, c.z), r, (min(ys), max(ys), min(zs), max(zs))))
    return regions


def paint_regions(img_path, regions, out_path):
    import numpy as np
    img = bpy.data.images.load(img_path, check_existing=False)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    for M, (cy, cz), r, (y0, y1, z0, z1) in regions:
        # sample the wheel disc densely in yz and stamp into uv space
        n = 160
        for i in range(n):
            for j in range(n):
                y = cy - r + 2 * r * i / (n - 1)
                z = cz - r + 2 * r * j / (n - 1)
                d = ((y - cy) ** 2 + (z - cz) ** 2) ** 0.5
                if d > r or not (y0 <= y <= y1 and z0 <= z <= z1):
                    continue
                u, v = np.array([y, z, 1.0]) @ M
                x = int((u % 1.0) * w)
                yy = int((v % 1.0) * h)
                px[max(0, yy - 1):yy + 2, max(0, x - 1):x + 2, :3] = (1.0, 0.0, 1.0)   # cut-out marker (see tools/cutout.py)
    img.pixels[:] = px.ravel()
    img.filepath_raw = out_path
    img.file_format = 'PNG'
    img.save()
    return img


def process(vid, cfg):
    reset()
    ov = OVR.get(vid, {})
    cfg = {**cfg, **ov}
    body, wheel_boxes = import_model(cfg)
    # orientation
    if cfg.get("flip"):
        body.data.transform(Matrix.Rotation(math.pi, 4, 'Z'))
        wheel_boxes = [(Vector((-b.x, -b.y, a.z)), Vector((-a.x, -a.y, b.z))) for a, b in wheel_boxes]
    if not wheel_boxes:
        wheel_boxes = detect_wheels_islands(body)
    mn, mx = bbox([v.co for v in body.data.vertices] + [p for wb in wheel_boxes for p in wb])
    s = cfg["length"] / (mx.y - mn.y)
    off = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    T = Matrix.Diagonal((s * cfg.get("xscale", 1.0), s, s, 1.0)) @ Matrix.Translation(-off)
    body.data.transform(T)
    wheel_boxes = [(T @ a, T @ b) for a, b in wheel_boxes]
    mn, mx = bbox([v.co for v in body.data.vertices])
    W, L, H = mx.x - mn.x, mx.y - mn.y, mx.z
    # wheels
    wheels = []
    for a, b in wheel_boxes:
        c = (a + b) / 2
        r = max(b.z - a.z, b.y - a.y) / 2
        wheels.append(dict(c=c, r=r, w=max(0.16, b.x - a.x)))
    wheels.sort(key=lambda w: (-w["c"].y, w["c"].x))
    ys = sorted({round(w["c"].y, 1) for w in wheels}, reverse=True)
    fa = max(w["c"].y for w in wheels)
    ra = min(w["c"].y for w in wheels)
    wr = sum(w["r"] for w in wheels) / len(wheels)
    # ---- paint out wheels drawn into the body texture
    painted = {}
    if cfg.get("paint_wheels") and cfg.get("tex"):
        regions = wheel_paint_regions(body, wheels)
        out = os.path.join(OUT, vid)
        os.makedirs(out, exist_ok=True)
        for pth in [cfg["tex"]] + cfg.get("variants", []):
            dst = os.path.join(out, os.path.basename(pth).lower().replace(" ", "_"))
            paint_regions(pth, regions, dst)
            painted[pth] = dst
        cfg = {**cfg, "tex": painted[cfg["tex"]]}
        print("painted wheel regions", vid, len(regions))
    # ---- materials
    bm_body = mat("body", (1, 1, 1), 0.55, 0.0, cfg.get("tex"))
    if cfg.get("tex"):
        body.data.materials.clear()
        body.data.materials.append(bm_body)
    else:
        for i, m in enumerate(body.data.materials):
            if m:
                m.name = "body" if i == 0 else "body_%d" % i
    # ---- optional truck bed (extend chassis behind cab)
    # cabin rear from roof profile
    allv = [v.co.copy() for v in body.data.vertices]
    high = [v for v in allv if v.z > 0.86 * H and abs(v.x) < 0.3 * W]
    cab_rear_auto = min(v.y for v in high) if high else mn.y + 0.25
    bed = None
    if cfg.get("add_bed"):
        bed = dict(y0=cab_rear_auto - 0.05, y1=mn.y - 1.2)
    # ---- hood
    hood_kind = "hood"
    hy0 = cfg.get("hood_y0", fa - 0.30 * (fa - ra))
    hz0 = cfg.get("hood_z0", 0.38 * H)
    hz1 = cfg.get("hood_z1", 0.74 * H)
    hood = None
    if not cfg.get("no_hood"):
        hood = separate_faces(body, lambda f: f.normal.z > cfg.get("hood_nz", 0.55) and f.calc_center_median().y > hy0 and hz0 < f.calc_center_median().z < hz1 and abs(f.calc_center_median().x) < 0.47 * W, "hood")
    if hood is None or sum(f.area for f in hood.data.polygons) < 0.35:
        if hood:
            bpy.data.objects.remove(hood)
            hood = None
        hood_kind = "hatch"
        hz0 = cfg.get("hatch_z0", 0.28 * H)
        hz1 = cfg.get("hatch_z1", 0.55 * H)
        hood = separate_faces(body, lambda f: f.normal.y > 0.55 and f.calc_center_median().y > mx.y - 0.45 and hz0 < f.calc_center_median().z < hz1 and abs(f.calc_center_median().x) < 0.42 * W, "hood")
    if hood is None:
        raise RuntimeError("no hood/hatch for " + vid)
    hmn, hmx = bbox([v.co for v in hood.data.vertices])
    if hood_kind == "hood":
        hinge = Vector((0, hmn.y, max(v.co.z for v in hood.data.vertices if v.co.y < hmn.y + 0.15)))
        bay_y0, bay_y1 = hmn.y + 0.02, min(hmx.y, mx.y - 0.12)
        bay_z1 = hmn.z - 0.02
        bay_x = min(0.42 * W, (hmx.x - hmn.x) / 2 - 0.02)
    else:
        hinge = Vector((0, hmx.y, hmx.z))
        bay_y1 = hmn.y - 0.03
        bay_y0 = bay_y1 - 0.95
        bay_z1 = hmx.z + 0.15
        bay_x = 0.40 * W
    bay_z0 = max(0.22, wr * 0.75)
    set_origin(hood, hinge)
    # ---- engine bay box (inward, open top for hood)
    bmb = bmesh.new()
    add_box(bmb, ((0), (bay_y0 + bay_y1) / 2, (bay_z0 + bay_z1) / 2), (2 * bay_x, bay_y1 - bay_y0, bay_z1 - bay_z0), inward=True, skip_top=(hood_kind == "hood"))
    if hood_kind == "hatch":
        # open the front face for the hatch
        fr = [f for f in bmb.faces if f.normal.y < -0.9]
        bmesh.ops.delete(bmb, geom=fr, context='FACES')
    bay = mk_obj("bay", bmb, [mat("bay", (0.08, 0.08, 0.085), 0.9, 0.2)])
    # ---- interior
    dash_y = cfg.get("dash_y", (hmn.y - 0.02) if hood_kind == "hood" else (mx.y - 0.55))
    belt = cfg.get("belt_z", (hmx.z + 0.02) if hood_kind == "hood" else 0.55 * H)
    floor = cfg.get("floor_z", max(0.30, wr * 1.05))
    rear = cfg.get("cab_rear", max(mn.y + 0.25, cab_rear_auto - 0.05))
    side = [abs(v.x) for v in allv if floor + 0.1 < v.z < belt - 0.12 and rear < v.y < dash_y]
    iw = cfg.get("inner_w", (max(side) * 2 if side else W) - 0.14) / 2
    rtop = [v.z for v in allv if rear < v.y < dash_y - 0.4 and abs(v.x) < 0.3 * W]
    roof = cfg.get("roof_z", (max(rtop) if rtop else H) - 0.07)
    pickup_bed = (rear - mn.y) > 1.0 and not bed
    if bed:
        rear = max(rear, bed["y0"])
    drv_x = -iw * 0.5
    seat_y = dash_y - cfg.get("seat_dist", 0.95)
    seat_z = floor + 0.25
    eye = Vector((drv_x, seat_y + 0.05, min(seat_z + 0.66, roof - 0.16)))
    bmi = bmesh.new()
    F = lambda c, s: add_box(bmi, c, s)
    mats = [mat("int_plastic", (0.06, 0.06, 0.065), 0.7), mat("int_fabric", (0.35, 0.12, 0.08), 0.95), mat("int_metal", (0.5, 0.5, 0.52), 0.4, 0.8), mat("gauge", (1, 1, 1), 0.5), mat("int_liner", (0.28, 0.27, 0.25), 0.95)]
    # floor + firewall + liner
    for f in F((0, (dash_y + rear) / 2, floor - 0.02), (2 * iw, dash_y - rear, 0.04)):
        f.material_index = 0
    for f in F((0, dash_y + 0.05, (floor + belt) / 2), (2 * iw, 0.06, belt - floor)):
        f.material_index = 0
    roof_front = dash_y - cfg.get("ws_depth", 0.38)
    for f in F((0, (roof_front + rear) / 2, roof + 0.01), (2 * iw, roof_front - rear, 0.03)):
        f.material_index = 4
    # dashboard
    dd = 0.32
    for f in F((0, dash_y - dd / 2, belt - 0.12), (2 * iw, dd, 0.24)):
        f.material_index = 0
    # door cards & lower side panels
    for sx in (-1, 1):
        for f in F((sx * (iw - 0.02), (dash_y + rear) / 2, (floor + belt) / 2), (0.05, dash_y - rear, belt - floor)):
            f.material_index = 0 if sx > 0 else 0
        # A pillar (approx, vertical-ish stack)
        p0 = Vector((sx * (iw - 0.04), dash_y, belt))
        p1 = Vector((sx * (iw - 0.04), roof_front, roof))
        ln = (p1 - p0).length
        fs = F(((p0 + p1) / 2).to_tuple(), (0.04, 0.06, ln + 0.04))
        ang = math.atan2(-(p1.y - p0.y), p1.z - p0.z)
        vs = list({v for f in fs for v in f.verts})
        bmesh.ops.rotate(bmi, verts=vs, cent=(p0 + p1) / 2, matrix=Matrix.Rotation(ang, 3, 'X'))
        for f in fs:
            f.material_index = 4
        # B pillar
        by = cfg.get("b_pillar", seat_y - 0.28)
        if by > rear + 0.2:
            for f in F((sx * (iw - 0.04), by, (belt + roof) / 2), (0.07, 0.12, roof - belt)):
                f.material_index = 4
        # C pillar
        for f in F((sx * (iw - 0.04), rear + 0.06, (belt + roof) / 2), (0.07, 0.12, roof - belt)):
            f.material_index = 4
    if bed or pickup_bed or cfg.get("cab_wall"):
        for f in F((0, rear, (floor + roof) / 2), (2 * iw, 0.05, roof - floor)):
            f.material_index = 0
    # seats
    for sx in (-1, 1):
        x = sx * iw * 0.5
        for f in F((x, seat_y, seat_z), (0.48, 0.5, 0.12)):
            f.material_index = 1
        for f in F((x, seat_y - 0.27, seat_z + 0.33), (0.48, 0.12, 0.6)):
            f.material_index = 1
        for f in F((x, seat_y - 0.29, seat_z + 0.73), (0.25, 0.1, 0.18)):
            f.material_index = 1
    if seat_y - 1.0 > rear + 0.3 and not bed and not pickup_bed:
        ry = seat_y - 0.95
        for f in F((0, ry, seat_z), (2 * iw - 0.15, 0.5, 0.12)):
            f.material_index = 1
        for f in F((0, ry - 0.27, seat_z + 0.33), (2 * iw - 0.15, 0.12, 0.6)):
            f.material_index = 1
    # gear lever with a knob and a rubber boot
    for f in F((0, seat_y + 0.55, floor + 0.04), (0.14, 0.14, 0.06)):
        f.material_index = 0
    for f in F((0, seat_y + 0.55, floor + 0.25), (0.02, 0.02, 0.4)):
        f.material_index = 2
    res = bmesh.ops.create_icosphere(bmi, subdivisions=1, radius=0.035)
    for v in res["verts"]:
        v.co += Vector((0, seat_y + 0.55, floor + 0.47))
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = 0
    # steering column
    col_c = Vector((drv_x, dash_y - 0.30, belt - 0.12))
    for f in F((drv_x, dash_y - 0.22, belt - 0.12), (0.06, 0.22, 0.06)):
        f.material_index = 0
    # gauge faces (disc) on dash face toward driver
    gauges = {}
    def disc(c, r, mi):
        res = bmesh.ops.create_circle(bmi, cap_ends=True, radius=r, segments=24)
        vs = res['verts']
        for v in vs:
            v.co = Vector((c.x + v.co.x, c.y, c.z + v.co.y))
        fs = list({f for v in vs for f in v.link_faces})
        uvl = bmi.loops.layers.uv.active or bmi.loops.layers.uv.new("UVMap")
        for fc in fs:
            fc.material_index = mi
            if fc.normal.y > 0:
                pass
            for l in fc.loops:
                l[uvl].uv = (0.5 + (l.vert.co.x - c.x) / (2 * r), 0.5 + (l.vert.co.z - c.z) / (2 * r))
        bmesh.ops.reverse_faces(bmi, faces=fs) if fs[0].normal.y > 0 else None
        return fs
    gy = dash_y - dd - 0.005
    gz = belt - 0.10
    gauges["speed"] = Vector((drv_x - 0.085, gy, gz))
    gauges["rpm"] = Vector((drv_x + 0.085, gy, gz))
    disc(gauges["speed"], 0.07, 3)
    disc(gauges["rpm"], 0.07, 3)
    gauges["fuel"] = Vector((drv_x + 0.22, gy, gz - 0.02))
    gauges["temp"] = Vector((drv_x + 0.32, gy, gz - 0.02))
    disc(gauges["fuel"], 0.04, 3)
    disc(gauges["temp"], 0.04, 3)
    interior = mk_obj("interior", bmi, mats)
    # gauge face texture UVs: separate per gauge type is done in godot by material override; keep one material
    # needles
    needles = []
    for k, p in gauges.items():
        bmn = bmesh.new()
        ln = 0.06 if k in ("speed", "rpm") else 0.034
        add_box(bmn, (0, -0.004, ln / 2 - 0.01), (0.006, 0.004, ln))
        o = mk_obj("needle_" + k, bmn, [mat("needle", (0.95, 0.35, 0.1), 0.5)])
        o.location = p + Vector((0, -0.006, 0))
        needles.append(o)
    # steering wheel (torus + spokes), origin at hub, facing driver
    bms = bmesh.new()
    bmesh.ops.create_circle(bms, segments=24, radius=0.19)
    tor = bpy.data.meshes.new("tmp")
    bpy.ops.mesh.primitive_torus_add(major_radius=0.18, minor_radius=0.018, major_segments=28, minor_segments=8)
    t_o = bpy.context.active_object
    bms.free()
    bms = bmesh.new()
    bms.from_mesh(t_o.data)
    bpy.data.objects.remove(t_o)
    for a in (0, 2.1, 4.2):
        fs = add_box(bms, (0.09, 0, 0), (0.17, 0.03, 0.015))
        vs = list({v for f in fs for v in f.verts})
        bmesh.ops.rotate(bms, verts=vs, cent=(0, 0, 0), matrix=Matrix.Rotation(a - math.pi / 2, 3, 'Z'))
    add_box(bms, (0, 0, -0.01), (0.07, 0.07, 0.05))
    # torus is in XY plane; rotate so the wheel faces -Y (toward driver), tilt
    bms.transform(Matrix.Rotation(math.radians(90 - 25), 4, 'X'))
    steer = mk_obj("steer", bms, [mat("int_plastic", (0.06, 0.06, 0.065), 0.7)])
    steer_pos = Vector((drv_x, dash_y - 0.42, belt - 0.03))
    steer.location = steer_pos
    # ---- truck bed
    bed_obj = None
    cargo = cfg.get("cargo")
    if bed:
        bmt = bmesh.new()
        bz = wr * 2 + 0.1
        add_box(bmt, (0, (bed["y0"] + bed["y1"]) / 2, bz - 0.15), (W * 0.95, bed["y0"] - bed["y1"], 0.15))
        add_box(bmt, (0, (bed["y0"] + bed["y1"]) / 2, bz - 0.45), (W * 0.55, bed["y0"] - bed["y1"], 0.35))
        for sx in (-1, 1):
            for i in range(4):
                y = bed["y0"] - 0.2 - i * (bed["y0"] - bed["y1"] - 0.4) / 3
                add_box(bmt, (sx * W * 0.45, y, bz + 0.5), (0.1, 0.1, 1.1))
        add_box(bmt, (0, bed["y0"] - 0.05, bz + 0.6), (W * 0.95, 0.1, 1.3))
        bed_obj = mk_obj("bed", bmt, [mat("bed_metal", (0.18, 0.2, 0.17), 0.6, 0.6)])
        cargo = dict(c=[0, (bed["y0"] + bed["y1"]) / 2, bz + 0.0], s=[W * 0.85, bed["y0"] - bed["y1"] - 0.3, 1.2], capacity=10, kind="flatbed")
    elif pickup_bed and not cargo:
        bz = max(v.z for v in allv if mn.y + 0.3 < v.y < rear - 0.3 and abs(v.x) < 0.2 * W and v.z < 0.6 * H) if any(mn.y + 0.3 < v.y < rear - 0.3 and abs(v.x) < 0.2 * W and v.z < 0.6 * H for v in allv) else wr * 2
        cargo = dict(c=[0, (mn.y + 0.2 + rear - 0.1) / 2, bz], s=[iw * 1.6, rear - mn.y - 0.4, 0.6], capacity=4, kind="bed")
    # export
    out = os.path.join(OUT, vid)
    os.makedirs(out, exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, vid + ".glb"), export_format='GLB', export_apply=False, export_yup=True, export_image_format='AUTO')
    # textures for paint variants
    import shutil
    variants = []
    for p in ([cfg["tex"]] if cfg.get("tex") else []) + cfg.get("variants", []):
        dst = os.path.join(out, os.path.basename(p).lower().replace(" ", "_"))
        if os.path.abspath(p) != os.path.abspath(dst) and p not in painted:
            shutil.copy(p, dst)
        variants.append(os.path.basename(dst))
    axles = sorted({round(w["c"].y, 2) for w in wheels}, reverse=True)
    meta = dict(
        id=vid, length=L, width=W, height=H,
        wheels=[dict(pos=g(w["c"]), radius=round(w["r"], 3), width=round(w["w"], 3), axle=axles.index(round(w["c"].y, 2)), side=(1 if w["c"].x > 0 else -1)) for w in wheels],
        hood=dict(kind=hood_kind, hinge=g(hinge), size=g(hmx - hmn)),
        bay=dict(min=g(Vector((-bay_x, bay_y1, bay_z0))), max=g(Vector((bay_x, bay_y0, bay_z1)))),
        eye=g(eye), steer=g(steer_pos), dash_y=-dash_y, seat=g(Vector((drv_x, seat_y, seat_z))),
        exit=g(Vector((-W / 2 - 0.7, seat_y, 0.3))), rear=g(Vector((0, mn.y - 0.6, 0.5))),
        gauges={k: g(v) for k, v in gauges.items()},
        variants=variants, cargo=cargo, cutout=bool(painted),
    )
    json.dump(meta, open(os.path.join(out, "meta.json"), "w"), indent=1)
    if painted:
        import subprocess
        subprocess.run(["python3", os.path.join(os.path.dirname(os.path.abspath(__file__)), "cutout.py")] + [os.path.join(out, v) for v in variants])
    print("OK", vid, "L=%.2f W=%.2f H=%.2f wheels=%d hood=%s hood_area=%.2f" % (L, W, H, len(wheels), hood_kind, sum(f.area for f in hood.data.polygons)))


ids = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for vid, cfg in V.items():
    if ids and vid not in ids:
        continue
    try:
        process(vid, cfg)
    except Exception as e:
        import traceback
        traceback.print_exc()
        print("FAIL", vid, e)
