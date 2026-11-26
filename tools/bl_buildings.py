# Procedural buildings, trees and props for Rusty Roads.
# Every building: front faces +Y (Godot -Z), origin on the ground at the centre.
# Material names are keys of the in-game material library (scripts/world/matlib.gd).
# Empties named IP_<name> mark interaction points; objects ending in -colonly become collision.
# Run: blender -b --python tools/bl_buildings.py [-- kind ...]
import bpy, bmesh, math, os, sys, random
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = ROOT + "/assets/buildings"
OUTN = ROOT + "/assets/nature"
os.makedirs(OUT, exist_ok=True)
os.makedirs(OUTN, exist_ok=True)
random.seed(7)

COLORS = {
    "plaster_white": (0.93, 0.92, 0.88), "plaster_blue": (0.45, 0.62, 0.85), "plaster_yellow": (0.93, 0.82, 0.5), "plaster_pink": (0.9, 0.72, 0.66),
    "plaster_green": (0.62, 0.78, 0.6), "bricks": (0.6, 0.3, 0.22), "bricks_white": (0.85, 0.83, 0.78), "concrete": (0.62, 0.62, 0.6),
    "facade_panel": (0.8, 0.78, 0.72), "slate": (0.55, 0.56, 0.55), "tin": (0.5, 0.55, 0.6), "tin_green": (0.25, 0.45, 0.32),
    "tin_red": (0.55, 0.2, 0.15), "tiles": (0.5, 0.22, 0.15), "wood": (0.5, 0.36, 0.22), "wood_dark": (0.3, 0.2, 0.12),
    "wood_blue": (0.3, 0.45, 0.7), "wood_green": (0.3, 0.5, 0.3), "metal": (0.45, 0.47, 0.5), "metal_red": (0.65, 0.12, 0.08), "metal_white": (0.9, 0.9, 0.9),
    "metal_yellow": (0.85, 0.65, 0.1), "metal_blue": (0.15, 0.3, 0.6), "rust": (0.45, 0.25, 0.12), "glass": (0.2, 0.25, 0.3), "gold": (0.85, 0.65, 0.2),
    "dome_blue": (0.15, 0.4, 0.75), "window_khata": (1, 1, 1), "window_plain": (1, 1, 1), "door_wood": (1, 1, 1), "gate_steel": (1, 1, 1),
    "gravel_pad": (0.5, 0.48, 0.45), "asphalt_pad": (0.3, 0.3, 0.3), "rubber": (0.05, 0.05, 0.05), "bark": (0.4, 0.3, 0.2), "bark_birch": (0.9, 0.9, 0.86),
    "leaves": (0.25, 0.45, 0.15), "leaves_dark": (0.15, 0.3, 0.12), "leaves_light": (0.4, 0.55, 0.2), "needles": (0.12, 0.25, 0.12), "leaves_willow": (0.4, 0.55, 0.3),
    "leaves_apple": (0.3, 0.5, 0.2), "apples": (0.75, 0.15, 0.1), "lamp": (1, 0.95, 0.8), "black_box": (0.05, 0.05, 0.05), "hay": (0.85, 0.75, 0.45), "dirt_pile": (0.45, 0.38, 0.3),
}
SIGNS = ["shop", "gas", "parts", "market", "carmarket", "sawmill", "bakery", "warehouse", "mill", "oil", "furniture", "quarry", "busstop", "lumber", "farm", "junk", "garage", "village"]


def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    col = COLORS.get(name, (0.8, 0.8, 0.8)) if not name.startswith("sign_") else (1, 1, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*col, 1)
    return m


class B:
    def __init__(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.mats = []
        self.cols = []
        self.ips = []

    def mi(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def _uv_box(self, faces, scale=1.0):
        for f in faces:
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for l in f.loops:
                c = l.vert.co
                if ax == 0:
                    u, v = c.y * (1 if n.x > 0 else -1), c.z
                elif ax == 1:
                    u, v = c.x * (-1 if n.y > 0 else 1), c.z
                else:
                    u, v = c.x, c.y
                l[self.uv].uv = (u * scale, v * scale)

    def box(self, m, c, s, rot=0.0, col=False, uv=True, bevel=0.0):
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        vs = r["verts"]
        R = Matrix.Rotation(rot, 4, 'Z')
        for v in vs:
            v.co = R @ Vector((v.co.x * s[0], v.co.y * s[1], v.co.z * s[2])) + Vector(c)
        fs = list({f for v in vs for f in v.link_faces})
        idx = self.mi(m)
        for f in fs:
            f.material_index = idx
        self.bm.normal_update()
        if uv:
            self._uv_box(fs)
        if col:
            self.cols.append((c, s, rot))
        return fs

    def cyl(self, m, c, r, h, seg=12, col=False, r2=None, axis='Z'):
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
        vs = res["verts"]
        M = Matrix.Identity(4) if axis == 'Z' else (Matrix.Rotation(math.pi / 2, 4, 'X') if axis == 'Y' else Matrix.Rotation(math.pi / 2, 4, 'Y'))
        for v in vs:
            v.co = M @ v.co + Vector(c)
        fs = list({f for v in vs for f in v.link_faces})
        idx = self.mi(m)
        self.bm.normal_update()
        ax = Vector((0, 0, 1)) if axis == 'Z' else (Vector((0, 1, 0)) if axis == 'Y' else Vector((1, 0, 0)))
        for f in fs:
            f.material_index = idx
            f.smooth = abs(f.normal.dot(ax)) < 0.5
        self._uv_box(fs)
        if col:
            self.cols.append((c, (r * 1.6, r * 1.6, h), 0.0))
        return fs

    def tyre(self, c, R=0.36, r=0.13, axis='Z'):
        res = bmesh.ops.create_cone(self.bm, cap_ends=False, segments=16, radius1=R, radius2=R, depth=2 * r)
        fs = list({f for v in res["verts"] for f in v.link_faces})
        # inner + side rings: a simple chunky tyre (outer tread + sidewalls)
        M = Matrix.Identity(4) if axis == 'Z' else Matrix.Rotation(math.pi / 2, 4, 'Y')
        for v in res["verts"]:
            v.co = M @ v.co + Vector(c)
        res2 = bmesh.ops.create_circle(self.bm, cap_ends=False, segments=16, radius=R)
        idx = self.mi("rubber")
        for f in fs:
            f.material_index = idx
            f.smooth = True
        for z in (-r, r):
            ring_o = [self.bm.verts.new(M @ Vector((math.cos(a) * R, math.sin(a) * R, z)) + Vector(c)) for a in [2 * math.pi * k / 16 for k in range(16)]]
            ring_i = [self.bm.verts.new(M @ Vector((math.cos(a) * R * 0.55, math.sin(a) * R * 0.55, z)) + Vector(c)) for a in [2 * math.pi * k / 16 for k in range(16)]]
            for k in range(16):
                q = [ring_o[k], ring_o[(k + 1) % 16], ring_i[(k + 1) % 16], ring_i[k]]
                f = self.bm.faces.new(q if z > 0 else q[::-1])
                f.material_index = idx
        for v in res2["verts"]:
            self.bm.verts.remove(v)
        self.bm.normal_update()

    def quad(self, m, p0, p1, p2, p3, uv=((1, 0), (0, 0), (0, 1), (1, 1))):   # u runs left->right as seen from the front
        vs = [self.bm.verts.new(p) for p in (p0, p1, p2, p3)]
        f = self.bm.faces.new(vs)
        f.material_index = self.mi(m)
        for l, t in zip(f.loops, uv):
            l[self.uv].uv = t
        self.bm.normal_update()
        return f

    def wall_quad(self, m, cx, cy, cz, w, h, facing, uvfull=True):
        # vertical quad facing direction 'facing' (+y, -y, +x, -x), slightly off the wall
        if facing == "+y":
            return self.quad(m, (cx - w / 2, cy, cz - h / 2), (cx + w / 2, cy, cz - h / 2), (cx + w / 2, cy, cz + h / 2), (cx - w / 2, cy, cz + h / 2))
        if facing == "-y":
            return self.quad(m, (cx + w / 2, cy, cz - h / 2), (cx - w / 2, cy, cz - h / 2), (cx - w / 2, cy, cz + h / 2), (cx + w / 2, cy, cz + h / 2))
        if facing == "+x":
            return self.quad(m, (cx, cy + w / 2, cz - h / 2), (cx, cy - w / 2, cz - h / 2), (cx, cy - w / 2, cz + h / 2), (cx, cy + w / 2, cz + h / 2))
        return self.quad(m, (cx, cy - w / 2, cz - h / 2), (cx, cy + w / 2, cz - h / 2), (cx, cy + w / 2, cz + h / 2), (cx, cy - w / 2, cz + h / 2))

    def gable(self, m, c, sx, sy, h, over=0.4, along='x', gable_mat=None):
        # ridge along 'along' axis
        x0, y0, z0 = c
        if along == 'x':
            ax, ay = sx / 2 + over, sy / 2 + over
            pts = [(-ax, -ay, 0), (ax, -ay, 0), (ax, 0, h), (-ax, 0, h), (-ax, ay, 0), (ax, ay, 0)]
        else:
            ax, ay = sx / 2 + over, sy / 2 + over
            pts = [(-ax, -ay, 0), (0, -ay, h), (0, ay, h), (-ax, ay, 0), (ax, -ay, 0), (ax, ay, 0)]
        P = [Vector((x0 + p[0], y0 + p[1], z0 + p[2])) for p in pts]
        vs = [self.bm.verts.new(p) for p in P]
        idx = self.mi(m)
        if along == 'x':
            faces = [(vs[0], vs[1], vs[2], vs[3]), (vs[5], vs[4], vs[3], vs[2])]
            ends = [(vs[0], vs[3], vs[4]), (vs[1], vs[5], vs[2])]
        else:
            faces = [(vs[0], vs[3], vs[2], vs[1]), (vs[4], vs[1], vs[2], vs[5])]
            ends = [(vs[0], vs[1], vs[4]), (vs[3], vs[5], vs[2])]
        fs = []
        for fv in faces:
            f = self.bm.faces.new(fv)
            f.material_index = idx
            fs.append(f)
        gi = self.mi(gable_mat or m)
        for fv in ends:
            f = self.bm.faces.new(fv)
            f.material_index = gi
            fs.append(f)
        # thickness underside
        self.bm.normal_update()
        for f in fs:
            if f.normal.z < -0.1 or (abs(f.normal.z) < 0.1 and False):
                pass
        bmesh.ops.recalc_face_normals(self.bm, faces=fs)
        self._uv_box(fs)
        # make roof double sided by duplicating reversed
        dup = bmesh.ops.duplicate(self.bm, geom=fs)
        dfs = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMFace)]
        bmesh.ops.reverse_faces(self.bm, faces=dfs)
        for f in dfs:
            for v in f.verts:
                pass
        return fs

    def hip(self, m, c, sx, sy, h, over=0.45):
        x0, y0, z0 = c
        ax, ay = sx / 2 + over, sy / 2 + over
        r = max(0.0, (sx - sy) / 2) if sx > sy else 0.0
        ry = max(0.0, (sy - sx) / 2) if sy > sx else 0.0
        P = [(-ax, -ay, 0), (ax, -ay, 0), (ax, ay, 0), (-ax, ay, 0), (-r, -ry, h), (r, -ry, h), (r, ry, h), (-r, ry, h)]
        vs = [self.bm.verts.new((x0 + p[0], y0 + p[1], z0 + p[2])) for p in P]
        idx = self.mi(m)
        quads = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        fs = []
        for q in quads:
            vv = [vs[i] for i in q]
            if (vv[2].co - vv[3].co).length < 0.01:
                vv = vv[:3]
            try:
                f = self.bm.faces.new(vv)
                f.material_index = idx
                fs.append(f)
            except ValueError:
                pass
        self.bm.normal_update()
        for f in fs:
            if f.normal.z < 0:
                f.normal_flip()
        # underside (soffit)
        f = self.bm.faces.new([vs[3], vs[2], vs[1], vs[0]])
        f.material_index = self.mi("wood_dark")
        self.bm.normal_update()
        self._uv_box(fs)
        return fs

    def dome(self, m, c, r, h):
        # onion dome by lathe
        prof = []
        for i in range(9):
            t = i / 8
            rad = r * (math.sin(t * math.pi * 0.9 + 0.25) * (1 - t) ** 0.6 * 1.15)
            prof.append((max(rad, 0.02), t * h))
        seg = 16
        rings = []
        for j in range(seg):
            a = 2 * math.pi * j / seg
            rings.append([self.bm.verts.new((c[0] + math.cos(a) * pr, c[1] + math.sin(a) * pr, c[2] + pz)) for pr, pz in prof])
        idx = self.mi(m)
        fs = []
        for j in range(seg):
            A, Bv = rings[j], rings[(j + 1) % seg]
            for k in range(len(prof) - 1):
                f = self.bm.faces.new((A[k], Bv[k], Bv[k + 1], A[k + 1]))
                f.material_index = idx
                f.smooth = True
                fs.append(f)
        self.bm.normal_update()
        self._uv_box(fs)
        # cross
        self.box("gold", (c[0], c[1], c[2] + h + 0.5), (0.06, 0.06, 1.0), uv=False)
        self.box("gold", (c[0], c[1], c[2] + h + 0.7), (0.5, 0.06, 0.06), uv=False)

    def sign(self, key, c, w, h, facing="+y", posts=False):
        if facing == "+y":
            self.box("metal", (c[0], c[1] - 0.04, c[2]), (w + 0.1, 0.06, h + 0.1), uv=False)
            self.wall_quad("sign_" + key, c[0], c[1] + 0.001, c[2], w, h, "+y")
        else:
            self.box("metal", (c[0] - 0.04, c[1], c[2]), (0.06, w + 0.1, h + 0.1), uv=False)
            self.wall_quad("sign_" + key, c[0] + 0.001, c[1], c[2], w, h, "+x")
        if posts:
            for dx in (-w * 0.4, w * 0.4):
                self.box("metal", (c[0] + dx, c[1] - 0.06, (c[2] - h / 2) / 2), (0.1, 0.1, c[2] - h / 2), uv=False)

    def door(self, cx, cy, cz, w, h, facing):
        # real door: frame + recessed panel + handle (no more paper-thin quads)
        nrm = {"+y": Vector((0, 1, 0)), "-y": Vector((0, -1, 0)), "+x": Vector((1, 0, 0)), "-x": Vector((-1, 0, 0))}[facing]
        along_x = facing in ("+y", "-y")
        c = Vector((cx, cy, cz))
        fw = (w + 0.24, 0.1, h + 0.12) if along_x else (0.1, w + 0.24, h + 0.12)
        b0 = c + nrm * 0.03
        self.box("wood_dark", (b0.x, b0.y, b0.z + 0.06), fw, uv=True)
        pw = (w, 0.07, h) if along_x else (0.07, w, h)
        p0 = c + nrm * 0.07
        self.box("door_wood", (p0.x, p0.y, p0.z), pw, uv=False)
        self.wall_quad("door_wood", p0.x + nrm.x * 0.036, p0.y + nrm.y * 0.036, p0.z, w, h, facing)
        hx = (w * 0.35, 0, 0) if along_x else (0, w * 0.35, 0)
        hp = c + nrm * 0.12 + Vector(hx)
        self.box("metal", (hp.x, hp.y, hp.z - 0.1), (0.05, 0.05, 0.05), uv=False)
        # step
        st = c + nrm * 0.35
        self.box("concrete", (st.x, st.y, cz - h / 2 - 0.05), (w + 0.6 if along_x else 0.7, 0.7 if along_x else w + 0.6, 0.2))

    def roof_sign(self, key, c, w, h):
        # double-sided board on two posts, readable from every direction
        for dx in (-w * 0.4, w * 0.4):
            self.box("metal", (c[0] + dx, c[1], c[2] - h / 2 - 0.45), (0.08, 0.08, 0.9), uv=False)
        self.box("metal", (c[0], c[1], c[2]), (w + 0.12, 0.08, h + 0.12), uv=False)
        self.wall_quad("sign_" + key, c[0], c[1] + 0.045, c[2], w, h, "+y")
        self.wall_quad("sign_" + key, c[0], c[1] - 0.045, c[2], w, h, "-y")

    def window(self, c, w, h, facing, kind="window_plain"):
        self.wall_quad(kind, c[0], c[1], c[2], w, h, facing)

    def ip(self, name, p):
        self.ips.append((name, p))

    def col(self, c, s, rot=0.0):
        self.cols.append((c, s, rot))

    def export(self, name, folder=OUT):
        me = bpy.data.meshes.new(name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=0.0005)
        self.bm.to_mesh(me)
        for m in self.mats:
            me.materials.append(mat(m))
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        for i, (c, s, rot) in enumerate(self.cols):
            bm2 = bmesh.new()
            r = bmesh.ops.create_cube(bm2, size=1.0)
            R = Matrix.Rotation(rot, 4, 'Z')
            for v in r["verts"]:
                v.co = R @ Vector((v.co.x * s[0], v.co.y * s[1], v.co.z * s[2])) + Vector(c)
            m2 = bpy.data.meshes.new("c%d" % i)
            bm2.to_mesh(m2)
            co = bpy.data.objects.new("col%d-colonly" % i, m2)
            bpy.context.scene.collection.objects.link(co)
        for n, p in self.ips:
            e = bpy.data.objects.new("IP_" + n, None)
            e.location = p
            bpy.context.scene.collection.objects.link(e)
        bpy.ops.export_scene.gltf(filepath=os.path.join(folder, name + ".glb"), export_format='GLB', export_yup=True, export_extras=False)
        print("BUILT", name, len(me.polygons), "cols", len(self.cols))


# ======================================================================= buildings
def khata(name, wall="plaster_white", roof="slate", sx=9.0, sy=6.0, hw=2.7, porch=False, bed=False):
    b = B()
    b.box("plaster_blue", (0, 0, -0.8), (sx + 0.15, sy + 0.15, 2.6))       # plinth (pryzba) going into the ground
    b.box(wall, (0, 0, hw / 2 + 0.2), (sx, sy, hw), col=True)
    b.hip(roof, (0, 0, hw + 0.2), sx, sy, 2.4)
    b.box("bricks", (sx * 0.22, -sy * 0.1, hw + 2.0), (0.6, 0.6, 2.4))     # chimney
    win = "window_khata"
    for x in (-sx * 0.3, sx * 0.02):
        b.window((x, sy / 2 + 0.01, 1.7), 1.5, 1.5, "+y", win)
    for x in (-sx * 0.25, sx * 0.25):
        b.window((x, -sy / 2 - 0.01, 1.7), 1.4, 1.4, "-y", win)
    for y in (-sy * 0.22, sy * 0.22):
        b.window((sx / 2 + 0.01, y, 1.7), 1.4, 1.4, "+x", win)
        b.window((-sx / 2 - 0.01, y, 1.7), 1.4, 1.4, "-x", win)
    b.door(sx * 0.33, sy / 2 + 0.01, 1.25, 1.0, 2.1, "+y")
    b.door(-sx * 0.05, -sy / 2 - 0.01, 1.25, 0.9, 2.0, "-y")
    # porch with steps and small roof
    b.box("concrete", (sx * 0.33, sy / 2 + 0.6, 0.0), (1.8, 1.2, 0.55))
    b.gable(roof, (sx * 0.33, sy / 2 + 0.7, 2.45), 1.6, 1.2, 0.5, over=0.15, along='y')
    for dx in (-0.8, 0.8):
        b.box("wood", (sx * 0.33 + dx, sy / 2 + 1.2, 1.25), (0.1, 0.1, 2.4))
    if porch:
        b.box("wood", (0, sy / 2 + 1.5, 0.2), (sx * 0.9, 2.5, 0.2))
        for dx in (-sx * 0.42, -sx * 0.14, sx * 0.14, sx * 0.42):
            b.box("wood_blue", (dx, sy / 2 + 2.6, 1.4), (0.14, 0.14, 2.6))
        b.box(roof, (0, sy / 2 + 1.5, 2.75), (sx * 0.95, 2.8, 0.08))
    if bed:
        b.ip("bed", (sx * 0.33, sy / 2 + 1.1, 1.0))
    b.export(name)


def garage():
    b = B()
    W, D, H = 8.6, 8.0, 3.3
    wt = 0.25
    m = "bricks_white"
    b.box("concrete", (0, 0, -0.25), (W, D, 0.7), col=True)                                 # floor slab (top at z=0.1)
    b.box(m, (-W / 2 + wt / 2, 0, H / 2), (wt, D, H), col=True)
    b.box(m, (W / 2 - wt / 2, 0, H / 2), (wt, D, H), col=True)
    b.box(m, (0, -D / 2 + wt / 2, H / 2), (W, wt, H), col=True)
    dw = 3.8
    side = (W - dw) / 2
    b.box(m, (-W / 2 + side / 2, D / 2 - wt / 2, H / 2), (side, wt, H), col=True)
    b.box(m, (W / 2 - side / 2, D / 2 - wt / 2, H / 2), (side, wt, H), col=True)
    b.box(m, (0, D / 2 - wt / 2, H - 0.3), (dw, wt, 0.6), col=True)
    b.box("tin", (0, -0.2, H + 0.12), (W + 0.6, D + 1.0, 0.12), rot=0.0, col=True)
    # gates swung open
    for sx in (-1, 1):
        x = sx * (dw / 2 + 0.05)
        b.box("gate_steel", (x + sx * 0.04, D / 2 + 0.9, 1.35), (0.05, 1.8, 2.7))
    b.sign("garage", (0, D / 2 + 0.01, H - 0.3), 1.6, 0.32)
    # workbench along the left wall
    bx = -W / 2 + 0.7
    b.box("wood", (bx, 1.6, 0.92), (0.8, 2.2, 0.07), col=True)
    for y in (0.6, 2.6):
        for x in (bx - 0.32, bx + 0.32):
            b.box("metal", (x, y, 0.45), (0.06, 0.06, 0.9))
    b.box("wood", (bx, 1.6, 0.25), (0.75, 2.1, 0.04))
    b.box("wood_dark", (-W / 2 + wt + 0.02, 1.6, 1.6), (0.03, 2.2, 1.2))   # pegboard
    for i in range(6):
        b.box("metal", (-W / 2 + wt + 0.06, 0.8 + i * 0.32, 1.5 + (i % 2) * 0.25), (0.04, 0.03, 0.25))
    # one small shelf on the right wall, lamp
    b.box("metal", (W / 2 - 0.45, -2.2, 1.4), (0.6, 2.0, 0.05))
    for y in (-3.1, -1.3):
        b.box("metal", (W / 2 - 0.45, y, 0.7), (0.05, 0.05, 1.4))
    b.box("lamp", (0, 0, H - 0.08), (1.2, 0.12, 0.06))
    # battery charger at the back end of the bench
    b.box("metal_red", (bx, 0.72, 1.08), (0.32, 0.25, 0.26))
    b.box("black_box", (bx + 0.17, 0.72, 1.12), (0.02, 0.16, 0.08))
    b.ip("charger", (bx, 0.72, 1.1))
    b.ip("light", (0, 0, H - 0.3))
    b.export("garage")


def shed():
    b = B()
    b.box("wood", (0, 0, 1.2), (4.0, 3.0, 2.4), col=True)
    b.gable("tin", (0, 0, 2.4), 4.0, 3.0, 1.0, 0.3, 'x', "wood")
    b.door(0.8, 1.51, 1.05, 0.9, 2.0, "+y")
    b.export("shed")


def fence_run():
    b = B()
    L = 18.0
    for i in range(9):
        x = -L / 2 + i * L / 8
        b.box("wood_dark", (x, 0, 0.7), (0.1, 0.1, 1.4))
    b.box("wood", (0, 0, 0.45), (L, 0.05, 0.08))
    b.box("wood", (0, 0, 1.1), (L, 0.05, 0.08))
    n = 70
    for i in range(n):
        x = -L / 2 + (i + 0.5) * L / n
        if abs(x - 3.0) < 1.6:   # gap for gate
            continue
        h = 1.2 + 0.05 * math.sin(i * 1.7)
        b.box("wood_blue" if True else "wood", (x, 0.04, h / 2), (0.09, 0.02, h), uv=True)
    b.col((0, 0, 0.7), (L, 0.15, 1.4))
    b.export("fence_run")


def shop_village():
    b = B()
    b.box("concrete", (0, 0, -0.9), (10.2, 7.2, 2.0))
    b.box("plaster_yellow", (0, 0, 1.7), (10, 7, 3.4), col=True)
    b.box("slate", (0, 0, 3.5), (10.6, 7.6, 0.25))
    b.sign("shop", (0, 3.52, 2.9), 4.0, 0.75)
    b.roof_sign("shop", (0, 0, 4.8), 3.6, 0.8)
    b.window((-2.8, 3.51, 1.5), 2.4, 1.5, "+y")
    b.window((2.8, 3.51, 1.5), 2.4, 1.5, "+y")
    b.door(0, 3.51, 1.1, 1.2, 2.2, "+y")
    b.box("concrete", (0, 4.0, 0.1), (3, 1.2, 0.2))
    b.ip("shop_general", (0, 4.2, 1.0))
    b.ip("deliver", (5.0, 8.0, 0.5))
    b.export("shop_village")


def church():
    b = B()
    b.box("concrete", (0, 0, -1.0), (8.4, 20, 2.0))
    b.box("plaster_white", (0, -2, 4), (8, 14, 8), col=True)
    b.gable("tin_green", (0, -2, 8), 8, 14, 3.0, 0.4, 'y', "plaster_white")
    b.box("plaster_white", (0, 6.5, 6), (5, 5, 12), col=True)
    b.box("plaster_white", (0, 6.5, 13), (4, 4, 2.0))
    b.dome("dome_blue", (0, 6.5, 14), 2.2, 4.0)
    b.dome("gold", (0, -2, 11), 1.6, 3.2)
    b.cyl("plaster_white", (0, -2, 10.4), 1.4, 1.2, 12)
    b.door(0, 9.01, 1.6, 1.6, 3.0, "+y")
    for y in (-6, -2, 2):
        b.window((4.01, y, 4.5), 1.0, 2.4, "+x")
        b.window((-4.01, y, 4.5), 1.0, 2.4, "-x")
    b.export("church")


def bus_stop():
    b = B()
    b.box("concrete", (0, -0.7, 1.3), (4.0, 0.2, 2.6), col=True)
    b.box("concrete", (-1.9, 0, 1.3), (0.2, 1.6, 2.6), col=True)
    b.box("concrete", (1.9, 0, 1.3), (0.2, 1.6, 2.6), col=True)
    b.box("concrete", (0, -0.1, 2.7), (4.4, 2.0, 0.2))
    b.box("wood", (0, -0.4, 0.45), (3.4, 0.4, 0.08))
    b.wall_quad("plaster_blue", 0, -0.59, 1.6, 3.4, 1.4, "+y")
    b.sign("busstop", (0, 0.92, 2.9), 1.8, 0.3)
    b.export("bus_stop")


def well():
    b = B()
    b.cyl("concrete", (0, 0, 0.45), 0.6, 0.9, 14, col=True)
    for x in (-0.6, 0.6):
        b.box("wood", (x, 0, 1.2), (0.12, 0.12, 2.4))
    b.gable("wood_dark", (0, 0, 2.2), 1.6, 1.4, 0.6, 0.15, 'x', "wood_dark")
    b.cyl("wood", (0, 0, 1.5), 0.12, 1.1, 10, axis='X')
    b.export("well")


def pump(b, x, y):
    b.box("metal_red", (x, y, 0.9), (0.7, 0.45, 1.8), col=True)
    b.box("glass", (x, y + 0.23, 1.3), (0.5, 0.02, 0.35))
    b.box("metal_white", (x, y, 1.85), (0.75, 0.5, 0.12))
    b.cyl("rubber", (x + 0.38, y, 1.0), 0.04, 0.25, 8)


def gas_station():
    b = B()
    b.box("asphalt_pad", (0, 0, 0.03), (16, 12, 0.1))
    for x in (-5, 5):
        for y in (-3, 3):
            b.box("metal_white", (x, y, 2.5), (0.35, 0.35, 5.0), col=True)
    b.box("metal_white", (0, 0, 5.2), (13, 9, 0.5))
    b.box("metal_red", (0, 4.52, 5.2), (13, 0.05, 0.5))
    b.sign("gas", (0, 4.56, 6.0), 4.0, 0.75)
    b.roof_sign("gas", (0, 0, 6.3), 4.0, 0.75)
    b.box("concrete", (-2.5, 0, 0.12), (1.5, 6, 0.25))
    b.box("concrete", (2.5, 0, 0.12), (1.5, 6, 0.25))
    pump(b, -2.5, 1.5)
    pump(b, 2.5, 1.5)
    pump(b, -2.5, -1.5)
    pump(b, 2.5, -1.5)
    b.ip("pump_0", (-2.5, 1.5, 1.2))
    b.ip("pump_1", (2.5, 1.5, 1.2))
    b.ip("pump_2", (-2.5, -1.5, 1.2))
    b.ip("pump_3", (2.5, -1.5, 1.2))
    # kiosk
    b.box("plaster_white", (0, -9, 1.6), (7, 4, 3.2), col=True)
    b.box("metal_red", (0, -9, 3.3), (7.4, 4.4, 0.25))
    b.window((-1.8, -6.99, 1.6), 2.6, 1.6, "+y")
    b.door(1.6, -6.99, 1.1, 1.0, 2.2, "+y")
    b.ip("shop_gas", (1.6, -6.4, 1.0))
    b.export("gas_station")


def khrushchevka():
    b = B()
    L, D, H = 48.0, 12.0, 15.2
    fs = b.box("facade_panel", (0, 0, H / 2), (L, D, H), col=True)
    b.box("concrete", (0, 0, H + 0.2), (L + 0.3, D + 0.3, 0.4))
    b.box("concrete", (0, 0, 0.3), (L + 0.2, D + 0.2, 0.6))
    for i in range(4):
        x = -L / 2 + L * (i + 0.5) / 4
        b.box("concrete", (x, D / 2 + 0.8, 2.6), (2.4, 1.6, 0.15))
        for sx in (-1.1, 1.1):
            b.box("concrete", (x + sx, D / 2 + 0.75, 1.3), (0.15, 1.5, 2.6))
        b.box("concrete", (x, D / 2 + 0.75, 0.15), (2.4, 1.5, 0.3))
        b.door(x, D / 2 + 0.01, 1.4, 1.3, 2.2, "+y")
    # balconies
    for i in range(12):
        x = -L / 2 + 2.0 + i * 4.0
        for f in range(1, 5):
            z0 = f * 3.0 + 0.1
            b.box("concrete", (x, -D / 2 - 0.6, z0), (2.6, 1.2, 0.14))
            b.box("metal", (x, -D / 2 - 1.17, z0 + 0.55), (2.6, 0.06, 1.0))
            for sx in (-1.27, 1.27):
                b.box("metal", (x + sx, -D / 2 - 0.6, z0 + 0.55), (0.06, 1.2, 1.0))
    b.export("khrushchevka")


def parts_store():
    b = B()
    b.box("concrete", (0, 0, -0.9), (14.2, 10.2, 2.0))
    b.box("bricks", (0, 0, 2.25), (14, 10, 4.5), col=True)
    b.box("tin", (0, 0, 4.6), (14.6, 10.6, 0.25))
    b.sign("parts", (0, 5.02, 3.8), 6.0, 1.1)
    b.roof_sign("parts", (0, 0, 6.0), 6.0, 1.1)
    b.window((-3.5, 5.01, 1.6), 4.0, 2.0, "+y")
    b.window((3.8, 5.01, 1.6), 3.0, 2.0, "+y")
    b.door(0.8, 5.01, 1.15, 1.4, 2.3, "+y")
    b.box("concrete", (0.8, 5.6, 0.1), (3.0, 1.2, 0.2))
    b.box("tin", (0.8, 5.8, 2.9), (3.4, 1.8, 0.1))
    b.ip("shop_parts", (0.8, 5.8, 1.0))
    b.ip("pickup", (-4.5, 8.0, 0.4))
    # pallet area
    b.box("wood", (-4.5, 8.0, 0.07), (2.2, 2.2, 0.14))
    b.export("parts_store")


def car_market():
    b = B()
    W, D = 44, 32
    b.box("gravel_pad", (0, 0, 0.02), (W, D, 0.1))
    for i in range(11):
        x = -W / 2 + i * W / 10
        b.box("metal", (x, -D / 2, 0.9), (0.08, 0.08, 1.8))
    b.box("metal", (0, -D / 2, 1.6), (W, 0.05, 0.05))
    b.box("metal", (0, -D / 2, 0.8), (W, 0.05, 0.05))
    b.col((0, -D / 2, 0.9), (W, 0.2, 1.8))
    b.box("metal_blue", (-W / 2 + 5, -D / 2 + 3, 1.3), (6, 2.5, 2.6), col=True)
    b.window((-W / 2 + 4, -D / 2 + 4.26, 1.5), 1.6, 1.0, "+y")
    b.door(-W / 2 + 6.5, -D / 2 + 4.26, 1.05, 0.9, 2.0, "+y")
    b.sign("carmarket", (0, D / 2 - 0.5, 4.0), 7.0, 1.3, posts=True)
    b.ip("car_market", (-W / 2 + 6.5, -D / 2 + 5.0, 1.0))
    b.ip("sell", (0, D / 2 - 5, 0.5))
    for i in range(6):
        b.ip("spot_%d" % i, (-W / 2 + 8 + i * 5.6, 0.0, 0.3))
    b.export("car_market")


def town_market():
    b = B()
    b.box("asphalt_pad", (0, 0, 0.03), (26, 18, 0.1))
    for i in range(4):
        x = -9 + i * 6
        for dx in (-2.2, 2.2):
            for dy in (-1.5, 1.5):
                b.box("metal", (x + dx, dy, 1.3), (0.08, 0.08, 2.6))
        b.gable(["tin_green", "tin_red", "tin", "tin_green"][i], (x, 0, 2.6), 4.4, 3.0, 0.6, 0.2, 'x', "metal")
        b.box("wood", (x, 1.2, 0.9), (4.2, 0.6, 0.08), col=True)
        b.box("hay", (x - 1, 1.2, 1.05), (0.8, 0.5, 0.25))
        b.box("apples", (x + 1, 1.2, 1.05), (0.8, 0.5, 0.2))
    b.sign("market", (0, 6.0, 3.8), 5.0, 1.0, posts=True)
    b.ip("deliver", (0, 8.5, 0.5))
    b.export("town_market")


def warehouse():
    b = B()
    b.box("tin", (0, 0, 4.0), (30, 18, 8.0), col=True)
    b.gable("tin", (0, 0, 8.0), 30, 18, 2.5, 0.3, 'x', "tin")
    b.wall_quad("gate_steel", -6, 9.01, 2.5, 6.0, 5.0, "+y")
    b.wall_quad("gate_steel", 6, 9.01, 2.5, 6.0, 5.0, "+y")
    b.sign("warehouse", (0, 9.03, 6.4), 6.0, 1.1)
    b.box("concrete", (0, 11, 0.5), (24, 4, 1.0), col=True)
    b.ip("deliver", (-6, 15, 0.5))
    b.ip("load", (6, 15, 0.5))
    b.export("warehouse")


def monument():
    b = B()
    b.box("concrete", (0, 0, 0.4), (6, 6, 0.8), col=True)
    b.box("concrete", (0, 0, 1.4), (2.0, 2.0, 1.4), col=True)
    b.box("bricks_white", (0, 0, 5.0), (1.2, 1.2, 6.0), col=True)
    b.cyl("gold", (0, 0, 8.3), 0.35, 0.6, 12, r2=0.0)
    for a in range(8):
        ang = a * math.pi / 4
        b.cyl("leaves", (math.cos(ang) * 2.5, math.sin(ang) * 2.5, 1.0), 0.4, 0.5, 8)
    b.export("monument")


def wood_shed(b, c, sx, sy, h, roof="tin"):
    for dx in (-sx / 2, 0, sx / 2):
        for dy in (-sy / 2, sy / 2):
            b.box("wood_dark", (c[0] + dx, c[1] + dy, h / 2), (0.22, 0.22, h), col=True)
    b.gable(roof, (c[0], c[1], h), sx, sy, 1.6, 0.4, 'x', "wood_dark")


def log_pile(b, c, n=12, L=6.0, rot=0.0):
    k = 0
    row = 5
    z = 0.2
    while k < n:
        for i in range(row):
            if k >= n:
                break
            off = (i - (row - 1) / 2) * 0.42
            x = c[0] + math.cos(rot + math.pi / 2) * off
            y = c[1] + math.sin(rot + math.pi / 2) * off
            b.cyl("bark", (x, y, c[2] + z), 0.2, L, 10, axis='X' if abs(math.cos(rot)) > 0.5 else 'Y')
            k += 1
        row -= 1
        z += 0.36
        if row <= 0:
            row = 5
    b.col((c[0], c[1], c[2] + 0.6), (L, 2.2, 1.3), rot)


def plank_stack(b, c):
    for i in range(6):
        b.box("wood", (c[0], c[1], c[2] + 0.05 + i * 0.1), (1.2, 4.0, 0.09))
    b.col((c[0], c[1], c[2] + 0.3), (1.2, 4.0, 0.6))


def office(b, c, sign=None, ip="office", w=6.0, d=4.0):
    b.box("concrete", (c[0], c[1], -0.9), (w + 0.2, d + 0.2, 2.0))
    b.box("plaster_white", (c[0], c[1], 1.4), (w, d, 2.8), col=True)
    b.box("slate", (c[0], c[1], 2.9), (w + 0.5, d + 0.5, 0.2))
    b.window((c[0] - 1.2, c[1] + d / 2 + 0.01, 1.5), 1.4, 1.2, "+y")
    b.door(c[0] + 1.3, c[1] + d / 2 + 0.01, 1.05, 0.9, 2.0, "+y")
    if sign:
        b.sign(sign, (c[0], c[1] + d / 2 + 0.02, 3.4), 3.6, 0.65)
    b.ip(ip, (c[0] + 1.3, c[1] + d / 2 + 0.7, 1.0))


def sawmill():
    b = B()
    b.box("gravel_pad", (0, 0, 0.02), (40, 34, 0.1))
    wood_shed(b, (0, -3, 0), 12, 22, 5.0)
    b.box("metal", (0, -3, 0.5), (1.2, 14, 1.0), col=True)
    b.cyl("metal", (0.2, -3, 1.1), 0.6, 0.06, 20, axis='X')
    office(b, (-13, 9), "sawmill")
    log_pile(b, (13, -6, 0), 13)
    log_pile(b, (13, 2, 0), 10)
    plank_stack(b, (-12, -6, 0))
    plank_stack(b, (-14, -6, 0))
    b.ip("deliver", (12, 10, 0.5))
    b.ip("load", (-6, 12, 0.5))
    b.export("sawmill")


def lumber_camp():
    b = B()
    b.box("gravel_pad", (0, 0, 0.02), (30, 26, 0.1))
    b.box("wood", (-8, 6, 1.4), (6, 4, 2.8), col=True)
    b.gable("tin_green", (-8, 6, 2.8), 6, 4, 1.2, 0.3, 'x', "wood")
    b.sign("lumber", (-8, 8.02, 3.6), 3.4, 0.6)
    b.door(-6.8, 8.01, 1.05, 0.9, 2.0, "+y")
    b.ip("office", (-6.8, 8.7, 1.0))
    log_pile(b, (6, -4, 0), 14)
    log_pile(b, (6, 3, 0), 12)
    log_pile(b, (-6, -6, 0), 9)
    b.cyl("metal_yellow", (0, -10, 1.2), 0.25, 2.4, 8)
    b.ip("load", (0, 9, 0.5))
    b.export("lumber_camp")


def barn():
    b = B()
    b.box("gravel_pad", (0, 4, 0.02), (32, 26, 0.1))
    b.box("wood_dark", (0, 0, 3.5), (24, 12, 7.0), col=True)
    b.gable("tin_red", (0, 0, 7.0), 24, 12, 3.5, 0.4, 'x', "wood_dark")
    b.wall_quad("gate_steel", 0, 6.01, 2.6, 5.0, 5.2, "+y")
    b.sign("farm", (0, 6.03, 6.0), 6.0, 0.9)
    for i in range(4):
        b.cyl("hay", (-9 + i * 2.2, 9, 0.75), 0.75, 1.2, 12, axis='X')
    office(b, (13, 8), None, "office", 5, 3.5)
    b.ip("load", (-6, 11, 0.5))
    b.ip("deliver", (6, 12, 0.5))
    b.export("barn")


def grain_elevator():
    b = B()
    for i in range(4):
        b.cyl("concrete", (-6 + i * 4, 0, 10), 2.0, 20, 16, col=True)
    b.box("concrete", (8, 0, 13), (4, 5, 26), col=True)
    b.box("concrete", (0, 0, 20.5), (20, 4, 1.2))
    b.box("metal", (8, 3, 4), (3, 1, 0.3))
    b.export("grain_elevator")


def cowshed():
    b = B()
    b.box("bricks_white", (0, 0, 2.0), (50, 12, 4.0), col=True)
    b.gable("slate", (0, 0, 4.0), 50, 12, 2.2, 0.4, 'x', "bricks_white")
    for i in range(12):
        b.window((-22 + i * 4, 6.01, 2.6), 1.2, 0.8, "+y")
    b.export("cowshed")


def flour_mill():
    b = B()
    b.box("gravel_pad", (0, 4, 0.02), (30, 26, 0.1))
    b.box("bricks", (0, 0, 5.0), (15, 12, 10.0), col=True)
    b.gable("tin", (0, 0, 10.0), 15, 12, 3.0, 0.3, 'x', "bricks")
    for z in (2.0, 5.5, 8.5):
        for x in (-4.5, 0, 4.5):
            b.window((x, 6.01, z), 1.4, 1.6, "+y")
    b.cyl("metal", (10, -2, 6), 2.2, 12, 14, col=True)
    b.cyl("metal", (10, -2, 12.6), 2.2, 1.2, 14, r2=0.3)
    b.sign("mill", (0, 6.03, 10.8), 4.0, 1.0)
    b.ip("load", (-5, 11, 0.5))
    b.ip("deliver", (6, 11, 0.5))
    b.ip("office", (0, 6.8, 1.0))
    b.export("flour_mill")


def bakery():
    b = B()
    b.box("plaster_pink", (0, 0, 2.2), (14, 10, 4.4), col=True)
    b.box("slate", (0, 0, 4.55), (14.5, 10.5, 0.3))
    b.box("bricks", (4, -2, 6), (1.0, 1.0, 3.5))
    b.sign("bakery", (0, 5.02, 3.7), 3.5, 0.9)
    b.roof_sign("bakery", (0, 0, 5.9), 3.5, 0.9)
    for x in (-4, 4):
        b.window((x, 5.01, 1.7), 2.4, 1.5, "+y")
    b.door(0, 5.01, 1.1, 1.2, 2.2, "+y")
    b.ip("office", (0, 5.7, 1.0))
    b.ip("load", (-5, 9, 0.5))
    b.ip("deliver", (5, 9, 0.5))
    b.export("bakery")


def oil_press():
    b = B()
    b.box("gravel_pad", (0, 3, 0.02), (30, 24, 0.1))
    b.box("tin_green", (0, 0, 3.5), (18, 12, 7.0), col=True)
    b.gable("tin_green", (0, 0, 7.0), 18, 12, 2.0, 0.3, 'x', "tin_green")
    for i in range(3):
        b.cyl("metal_white", (-6 + i * 3.5, -10, 3.0), 1.4, 6.0, 14, col=True)
    b.sign("oil", (0, 6.02, 5.6), 3.5, 0.9)
    b.wall_quad("gate_steel", 0, 6.01, 2.2, 4.0, 4.4, "+y")
    b.ip("office", (6.5, 6.7, 1.0))
    b.ip("load", (-5, 10, 0.5))
    b.ip("deliver", (5, 10, 0.5))
    b.export("oil_press")


def quarry_office():
    b = B()
    b.box("gravel_pad", (0, 0, 0.02), (40, 34, 0.1))
    office(b, (-12, 10), "quarry")
    for (x, y, r, h) in [(8, -6, 6, 5), (-4, -10, 5, 4), (12, 6, 4, 3)]:
        b.cyl("dirt_pile", (x, y, h / 2), r, h, 14, r2=0.6, col=True)
    b.box("metal_yellow", (2, -2, 3.0), (1.2, 12, 0.4), rot=0.5)
    b.ip("load", (0, 10, 0.5))
    b.export("quarry_office")


def furniture_factory():
    b = B()
    b.box("gravel_pad", (0, 5, 0.02), (38, 30, 0.1))
    b.box("bricks", (0, 0, 4.0), (30, 16, 8.0), col=True)
    for i in range(5):
        b.gable("tin", (-12 + i * 6, 0, 8.0), 6, 16, 2.0, 0.1, 'y', "glass")
    b.sign("furniture", (0, 8.02, 6.6), 5.0, 1.1)
    b.wall_quad("gate_steel", -6, 8.01, 2.5, 5.0, 5.0, "+y")
    b.door(6, 8.01, 1.1, 1.2, 2.2, "+y")
    b.ip("office", (6, 8.7, 1.0))
    b.ip("load", (-8, 13, 0.5))
    b.ip("deliver", (8, 14, 0.5))
    b.export("furniture_factory")


def junkyard_office():
    b = B()
    b.box("rust", (0, 0, 1.3), (6, 2.5, 2.6), col=True)
    b.window((-1, 1.26, 1.5), 1.4, 0.9, "+y")
    b.door(1.8, 1.26, 1.05, 0.9, 2.0, "+y")
    b.sign("junk", (0, 1.3, 3.2), 5.5, 0.6)
    for i in range(10):
        a = i * 0.63
        b.box("rust", (math.cos(a) * 26, math.sin(a) * 26, 1.0), (5.0, 0.15, 2.0), rot=a + math.pi / 2, col=True)
    for i in range(6):
        b.tyre((-4 + (i % 3) * 0.85, -3.2, 0.13 + (i // 3) * 0.27))
    b.ip("junk", (1.8, 2.0, 1.0))
    b.ip("sell", (0, 9, 0.5))
    b.export("junkyard_office")


def power_pole():
    b = B()
    b.cyl("wood_dark", (0, 0, 4.5), 0.14, 9.0, 8, col=True)
    b.box("wood_dark", (0, 0, 8.4), (2.0, 0.12, 0.12))
    for x in (-0.85, 0.0, 0.85):
        b.cyl("metal_white", (x, 0, 8.6), 0.05, 0.22, 6)
    b.export("power_pole")


def street_lamp():
    b = B()
    b.cyl("concrete", (0, 0, 3.6), 0.11, 7.2, 8, col=True, r2=0.08)
    b.box("metal", (0, 0.8, 7.1), (0.08, 1.7, 0.08))
    b.box("metal", (0, 1.6, 6.98), (0.28, 0.5, 0.14))
    b.box("lamp", (0, 1.6, 6.9), (0.22, 0.4, 0.03))
    b.ip("streetlight", (0, 1.6, 6.7))
    b.export("street_lamp")


def wreck():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = ROOT + "/tools/src_assets/psx_style_cars_by_ggbot_august2023/Car 06/Car6.obj"
    bpy.ops.wm.obj_import(filepath=src, forward_axis='NEGATIVE_Z', up_axis='Y')
    o = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mn = min(v.co.z for v in o.data.vertices)
    L = max(v.co.y for v in o.data.vertices) - min(v.co.y for v in o.data.vertices)
    s = 4.4 / L
    o.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation((0, 0, -mn)))
    m = bpy.data.materials.new("wreck_tex")
    m.use_nodes = True
    t = m.node_tree.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(os.path.join(os.path.dirname(src), "car6.png"))
    m.node_tree.links.new(t.outputs[0], m.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    o.data.materials.clear()
    o.data.materials.append(m)
    o.name = "wreck"
    bm2 = bmesh.new()
    r = bmesh.ops.create_cube(bm2, size=1.0)
    for v in r["verts"]:
        v.co = Vector((v.co.x * 1.7, v.co.y * 4.2, v.co.z * 1.2 + 0.6))
    m2 = bpy.data.meshes.new("c")
    bm2.to_mesh(m2)
    co = bpy.data.objects.new("col0-colonly", m2)
    bpy.context.scene.collection.objects.link(co)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "wreck.glb"), export_format='GLB', export_yup=True)
    print("BUILT wreck")


# ======================================================================= trees
def blob(b, m, c, r, sub=1, squash=1.0, jitter=0.25):
    res = bmesh.ops.create_icosphere(b.bm, subdivisions=sub, radius=r)
    vs = res["verts"]
    for v in vs:
        n = v.co.normalized()
        v.co = Vector((v.co.x, v.co.y, v.co.z * squash)) * (1.0 + random.uniform(-jitter, jitter)) + Vector(c)
    fs = list({f for v in vs for f in v.link_faces})
    idx = b.mi(m)
    for f in fs:
        f.material_index = idx
    b.bm.normal_update()
    b._uv_box(fs, 0.5)


def trunk(b, m, base, top, r0, r1, seg=7):
    res = bmesh.ops.create_cone(b.bm, cap_ends=False, segments=seg, radius1=r0, radius2=r1, depth=1.0)
    d = Vector(top) - Vector(base)
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    for v in res["verts"]:
        v.co = rot @ Vector((v.co.x, v.co.y, (v.co.z + 0.5) * d.length)) + Vector(base)
    fs = list({f for v in res["verts"] for f in v.link_faces})
    idx = b.mi(m)
    for f in fs:
        f.material_index = idx
        f.smooth = True
    b.bm.normal_update()
    b._uv_box(fs)


def tree(name):
    b = B()
    if name == "pine":
        trunk(b, "bark", (0, 0, -0.3), (0, 0, 13), 0.28, 0.08)
        for i in range(5):
            z = 4.5 + i * 1.9
            r = 2.6 - i * 0.45
            res = bmesh.ops.create_cone(b.bm, cap_ends=True, segments=9, radius1=r, radius2=0.15, depth=2.6)
            for v in res["verts"]:
                v.co += Vector((random.uniform(-0.15, 0.15), random.uniform(-0.15, 0.15), z + 1.3))
            fs = list({f for v in res["verts"] for f in v.link_faces})
            for f in fs:
                f.material_index = b.mi("needles")
            b.bm.normal_update()
            b._uv_box(fs, 0.5)
    elif name == "birch":
        trunk(b, "bark_birch", (0, 0, -0.3), (0.2, 0.1, 11), 0.18, 0.06)
        for i in range(7):
            a = i * 0.9
            blob(b, "leaves_light", (math.cos(a) * 1.4 + 0.2, math.sin(a) * 1.4, 6.5 + (i % 3) * 1.4), 1.6, 1, 1.3)
        blob(b, "leaves_light", (0.2, 0.1, 10.0), 1.4, 1, 1.4)
    elif name == "oak":
        trunk(b, "bark", (0, 0, -0.3), (0, 0, 4.5), 0.45, 0.32)
        for a in (0.3, 2.4, 4.4):
            trunk(b, "bark", (0, 0, 3.5), (math.cos(a) * 2.0, math.sin(a) * 2.0, 6.5), 0.22, 0.1, 6)
        for i in range(8):
            a = i * 0.8
            blob(b, "leaves_dark" if i % 2 else "leaves", (math.cos(a) * 2.4, math.sin(a) * 2.4, 6.5 + (i % 3) * 0.9), 2.4, 1, 0.85)
        blob(b, "leaves", (0, 0, 8.6), 2.6, 1, 0.8)
    elif name == "poplar":
        trunk(b, "bark", (0, 0, -0.3), (0, 0, 16), 0.3, 0.1)
        for i in range(6):
            blob(b, "leaves", (random.uniform(-0.3, 0.3), random.uniform(-0.3, 0.3), 5 + i * 2.2), 1.6 - i * 0.12, 1, 1.6)
    elif name == "willow":
        trunk(b, "bark", (0, 0, -0.3), (0.3, 0, 3.5), 0.45, 0.3)
        for i in range(9):
            a = i * 0.7
            blob(b, "leaves_willow", (math.cos(a) * 2.6, math.sin(a) * 2.6, 4.2 + (i % 2) * 0.8), 2.0, 1, 1.5, 0.15)
        blob(b, "leaves_willow", (0, 0, 6.0), 2.4, 1, 0.9)
    elif name == "acacia":
        trunk(b, "bark", (0, 0, -0.3), (0.4, 0.2, 5.5), 0.3, 0.15)
        for i in range(6):
            a = i * 1.05
            blob(b, "leaves", (math.cos(a) * 2.0 + 0.4, math.sin(a) * 2.0, 6.2 + (i % 2) * 0.7), 1.8, 1, 0.7)
    elif name == "apple":
        trunk(b, "bark", (0, 0, -0.2), (0, 0, 1.8), 0.16, 0.12)
        for i in range(5):
            a = i * 1.25
            blob(b, "leaves_apple", (math.cos(a) * 1.1, math.sin(a) * 1.1, 2.7 + (i % 2) * 0.5), 1.3, 1, 0.8)
        for i in range(10):
            a = i * 0.63
            blob(b, "apples", (math.cos(a) * 1.9, math.sin(a) * 1.9, 2.4 + (i % 3) * 0.4), 0.09, 0, 1.0, 0.0)
    b.export(name, OUTN)




def tree_lod(name):
    # ~20-40 triangle stand-in for distant trees
    b = B()
    def lowblob(m, c, r, sq=1.0):
        res = bmesh.ops.create_icosphere(b.bm, subdivisions=0, radius=r)
        for v in res["verts"]:
            v.co = Vector((v.co.x, v.co.y, v.co.z * sq)) + Vector(c)
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = b.mi(m)
    def lowtrunk(m, h, r):
        res = bmesh.ops.create_cone(b.bm, cap_ends=False, segments=4, radius1=r, radius2=r * 0.5, depth=h)
        for v in res["verts"]:
            v.co += Vector((0, 0, h / 2 - 0.3))
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = b.mi(m)
    if name == "pine":
        lowtrunk("bark", 5, 0.25)
        res = bmesh.ops.create_cone(b.bm, cap_ends=True, segments=6, radius1=2.7, radius2=0.1, depth=9.5)
        for v in res["verts"]:
            v.co += Vector((0, 0, 4.0 + 4.75))
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = b.mi("needles")
    elif name == "birch":
        lowtrunk("bark_birch", 7, 0.18)
        lowblob("leaves_light", (0.2, 0, 7.8), 2.6, 1.4)
    elif name == "oak":
        lowtrunk("bark", 5, 0.45)
        lowblob("leaves", (0, 0, 7.2), 4.0, 0.75)
    elif name == "poplar":
        lowtrunk("bark", 5, 0.3)
        lowblob("leaves", (0, 0, 9.5), 2.0, 3.2)
    elif name == "willow":
        lowtrunk("bark", 4, 0.45)
        lowblob("leaves_willow", (0, 0, 5.2), 3.6, 0.85)
    elif name == "acacia":
        lowtrunk("bark", 5, 0.3)
        lowblob("leaves", (0.4, 0, 6.6), 3.0, 0.6)
    elif name == "apple":
        lowtrunk("bark", 2, 0.15)
        lowblob("leaves_apple", (0, 0, 2.9), 1.9, 0.75)
    b.bm.normal_update()
    b._uv_box(list(b.bm.faces), 0.5)
    b.export(name + "_lod", OUTN)


ALL = {
    "khata": lambda: khata("khata"), "khata_b": lambda: khata("khata_b", "plaster_yellow", "tin_green", 8.0, 6.0, 2.6),
    "khata_tin": lambda: khata("khata_tin", "plaster_blue", "tin", 9.5, 6.5, 2.7),
    "home_house": lambda: khata("home_house", "plaster_white", "tin_red", 10.0, 7.0, 2.8, porch=True, bed=True),
    "garage": garage, "shed": shed, "fence_run": fence_run, "shop_village": shop_village, "church": church, "bus_stop": bus_stop,
    "well": well, "gas_station": gas_station, "khrushchevka": khrushchevka, "parts_store": parts_store, "car_market": car_market,
    "town_market": town_market, "warehouse": warehouse, "monument": monument, "sawmill": sawmill, "lumber_camp": lumber_camp,
    "barn": barn, "grain_elevator": grain_elevator, "cowshed": cowshed, "flour_mill": flour_mill, "bakery": bakery,
    "oil_press": oil_press, "quarry_office": quarry_office, "furniture_factory": furniture_factory, "junkyard_office": junkyard_office,
    "power_pole": power_pole, "wreck": wreck, "street_lamp": street_lamp,
}
for t in ["pine", "birch", "oak", "poplar", "willow", "acacia", "apple"]:
    ALL["tree_" + t] = (lambda t=t: tree(t))
    ALL["treelod_" + t] = (lambda t=t: tree_lod(t))

ids = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for k, f in ALL.items():
    if ids and k not in ids:
        continue
    try:
        f()
    except Exception as e:
        import traceback
        traceback.print_exc()
        print("FAIL", k, e)
