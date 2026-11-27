# Offline world generator: heightmap, surface splat map and object placement.
# Output -> assets/world/{height.bin, splat.png, world.json}
# World is 2048 m x 2048 m, 1 sample per metre (2049 x 2049 heights), centred on origin.
# Coordinates: x east, z south (Godot convention).  Pixel (i=row, j=col) <-> (z = i - 1024, x = j - 1024)
import numpy as np, json, os, math
from scipy import ndimage
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = ROOT + "/assets/world"
os.makedirs(OUT, exist_ok=True)
N = 2049
HALF = 1024
rng = np.random.default_rng(20261126)


def fbm(octaves, base_cells, amp, persistence=0.5):
    h = np.zeros((N, N), np.float32)
    a = amp
    cells = base_cells
    for _ in range(octaves):
        g = rng.random((cells + 3, cells + 3)).astype(np.float32)
        z = ndimage.zoom(g, (N + 2 * N / cells) / (cells + 3), order=3)
        off = int(N / cells)
        h += (z[off:off + N, off:off + N] - 0.5) * a
        a *= persistence
        cells *= 2
    return h


def P(x, z):  # world -> pixel (row, col) float
    return (z + HALF, x + HALF)


# ---------------------------------------------------------------- base terrain
h = 18 + fbm(6, 6, 46.0, 0.48)
# broad tilt: hills in the north-west, flatter steppe south-east
zz, xx = np.mgrid[0:N, 0:N].astype(np.float32)
xw = xx - HALF
zw = zz - HALF
h += (-zw * 0.010) + (-xw * 0.006)
forest_hill = np.exp(-(((xw + 600) / 380) ** 2 + ((zw + 550) / 380) ** 2))
h += forest_hill * 22
# soften the steppe in the south east
steppe = np.clip((xw + zw) / 900.0, 0, 1)
h = h * (1 - 0.55 * steppe) + (np.mean(h)) * 0.55 * steppe

# ---------------------------------------------------------------- river (N->S, east side)
river_pts = []
for t in np.linspace(0, 1, 200):
    z = -1100 + 2200 * t
    x = 560 + 70 * math.sin(t * 7.0) + 40 * math.sin(t * 17.0)
    river_pts.append((x, z))
river_mask = np.zeros((N, N), bool)
for x, z in river_pts:
    r, c = P(x, z)
    river_mask[int(np.clip(r, 0, N - 1)), int(np.clip(c, 0, N - 1))] = True
river_d = ndimage.distance_transform_edt(~river_mask)
WATER = 4.0
valley = np.clip(1 - river_d / 140.0, 0, 1) ** 1.6
h = h * (1 - valley) + (WATER + 2.0) * valley
channel = np.clip(1 - river_d / 16.0, 0, 1)
h -= channel ** 0.7 * 4.5

# ---------------------------------------------------------------- locations (flat pads)
LOC = {
    "home":       dict(x=-330, z=340, r=45, name="Home & Garage"),
    "village":    dict(x=-180, z=300, r=120, name="Sonyachne village"),
    "town":       dict(x=230, z=-120, r=190, name="Stepove town"),
    "gas_west":   dict(x=-20, z=175, r=35, name="Gas station"),
    "farm":       dict(x=180, z=560, r=110, name="Zoria collective farm"),
    "sawmill":    dict(x=-260, z=-300, r=70, name="Sawmill"),
    "lumber":     dict(x=-660, z=-560, r=60, name="Lumber camp"),
    "junkyard":   dict(x=-540, z=120, r=55, name="Junkyard"),
    "mill":       dict(x=430, z=-330, r=60, name="Flour mill & bakery"),
    "oilpress":   dict(x=-40, z=700, r=50, name="Sunflower oil press"),
    "quarry":     dict(x=-760, z=420, r=70, name="Gravel quarry"),
    "east_farm":  dict(x=860, z=620, r=60, name="Khutir farmstead"),
}
for k, L in LOC.items():
    r, c = P(L["x"], L["z"])
    d = np.sqrt((zz - r) ** 2 + (xx - c) ** 2)
    target = float(np.median(h[int(r) - 5:int(r) + 5, int(c) - 5:int(c) + 5]))
    target = max(target, WATER + 3.0)
    L["y"] = target
    w = np.clip(1 - (d - L["r"]) / 60.0, 0, 1)
    w = w * w * (3 - 2 * w)
    h = h * (1 - w) + target * w

# ---------------------------------------------------------------- roads
# kind: asphalt (w 7.5), narrow (w 6), gravel (w 5.5), dirt (w 4.5, muddy)
ROADS = [
    dict(kind="asphalt", w=7.5, pts=[(-1030, 250), (-700, 260), (-450, 280), (-330, 300), (-180, 262), (-20, 205), (120, 80), (230, -60), (330, -140), (560, -190), (760, -210), (1030, -260)]),
    dict(kind="asphalt", w=6.5, pts=[(230, -60), (260, 120), (230, 320), (190, 470)]),
    dict(kind="asphalt", w=6.0, pts=[(330, -140), (400, -250), (430, -300)]),
    dict(kind="gravel", w=5.5, pts=[(-180, 262), (-170, 400), (-60, 470), (80, 520), (150, 540)]),
    dict(kind="gravel", w=5.0, pts=[(-330, 300), (-345, 335)]),
    dict(kind="gravel", w=5.0, pts=[(-450, 280), (-500, 190), (-530, 140)]),
    dict(kind="gravel", w=5.5, pts=[(-180, 262), (-230, 120), (-250, -40), (-240, -180), (-255, -270)]),
    dict(kind="gravel", w=5.0, pts=[(-60, 470), (-50, 600), (-40, 680)]),
    dict(kind="dirt", w=4.5, pts=[(-255, -300), (-330, -360), (-420, -400), (-500, -470), (-580, -500), (-650, -540)]),
    dict(kind="dirt", w=4.0, pts=[(-500, -470), (-470, -620), (-560, -760), (-700, -720), (-760, -620), (-680, -580)]),
    dict(kind="dirt", w=4.0, pts=[(-420, -400), (-360, -560), (-300, -700), (-200, -760)]),
    dict(kind="dirt", w=4.5, pts=[(190, 600), (350, 640), (520, 640), (620, 630), (760, 620), (850, 615)]),
    dict(kind="dirt", w=4.0, pts=[(-700, 260), (-740, 340), (-760, 400)]),
    # town streets
    dict(kind="asphalt", w=6.0, pts=[(120, -120), (330, -120)]),
    dict(kind="asphalt", w=6.0, pts=[(150, -230), (160, -20)]),
    dict(kind="asphalt", w=6.0, pts=[(300, -240), (310, 0)]),
    dict(kind="asphalt", w=6.0, pts=[(150, -230), (300, -240)]),
]


def densify(pts, step=1.0):
    pts = np.array(pts, float)
    out = []
    # catmull-rom through points
    P0 = np.vstack([pts[0], pts, pts[-1]])
    for i in range(1, len(P0) - 2):
        p0, p1, p2, p3 = P0[i - 1], P0[i], P0[i + 1], P0[i + 2]
        seg = np.linalg.norm(p2 - p1)
        n = max(2, int(seg / step))
        for t in np.linspace(0, 1, n, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return np.array(out)


# real roads don't climb straight up hills: cut/fill the profile to a maximum grade
MAX_GRADE = {"asphalt": 0.075, "gravel": 0.10, "dirt": 0.14}


def limit_grade(ys, ds, g):
    # average of forward- and backward-clamped profiles: both are g-Lipschitz, so is the mean
    f = ys.copy()
    b = ys.copy()
    for i in range(1, len(f)):
        f[i] = min(max(f[i], f[i - 1] - g * ds), f[i - 1] + g * ds)
    for i in range(len(b) - 2, -1, -1):
        b[i] = min(max(b[i], b[i + 1] - g * ds), b[i + 1] + g * ds)
    # round the vertical curves (smoothing keeps the grade limit)
    return ndimage.gaussian_filter1d((f + b) / 2, 12, mode='nearest')


road_center = np.zeros((N, N), bool)
road_height = np.zeros((N, N), np.float32)
road_halfw = np.zeros((N, N), np.float32)
road_kind = np.zeros((N, N), np.uint8)
KIND_ID = {"asphalt": 1, "gravel": 2, "dirt": 3}
hs = ndimage.gaussian_filter(h, 6)
done_pts, done_ys = [], []
for rd in ROADS:
    d = densify(rd["pts"], 0.5)
    rd["dense"] = d
    rr = np.clip(d[:, 1] + HALF, 0, N - 1)
    cc = np.clip(d[:, 0] + HALF, 0, N - 1)
    ys = ndimage.map_coordinates(hs, [rr, cc], order=1)
    ys = np.maximum(ys, WATER + 2.2)  # embankment over the river
    ys = ndimage.gaussian_filter1d(ys, 40 if rd["kind"] == "asphalt" else 18, mode='nearest')
    ys = limit_grade(ys, 0.5, MAX_GRADE[rd["kind"]])
    # junctions: pin to the height of roads already laid so there is no step where they meet
    if done_pts:
        from scipy.spatial import cKDTree
        tree = cKDTree(np.concatenate(done_pts))
        allys = np.concatenate(done_ys)
        dd, ii = tree.query(d, distance_upper_bound=rd["w"] / 2 + 5.0)
        pin = np.isfinite(dd)
        if pin.any():
            for _ in range(6):
                ys[pin] = allys[ii[pin]]
                ys = limit_grade(ys, 0.5, MAX_GRADE[rd["kind"]])
            ys[pin] = allys[ii[pin]]
            ys = ndimage.gaussian_filter1d(ys, 3, mode='nearest')
    done_pts.append(d)
    done_ys.append(ys)
    rd["ys"] = ys
    for (x, z), y in zip(d, ys):
        r, c = int(round(z + HALF)), int(round(x + HALF))
        if 0 <= r < N and 0 <= c < N:
            if not road_center[r, c] or KIND_ID[rd["kind"]] < road_kind[r, c]:
                road_center[r, c] = True
                road_height[r, c] = y
                road_halfw[r, c] = rd["w"] / 2
                road_kind[r, c] = KIND_ID[rd["kind"]]
dist, (ir, ic) = ndimage.distance_transform_edt(~road_center, return_indices=True)
rh = road_height[ir, ic]
hw = road_halfw[ir, ic]
rk = road_kind[ir, ic]
h_nat = h.copy()   # natural terrain (with location pads); roads and building lots are graded into it below
blend = np.clip(1 - (dist - hw) / 9.0, 0, 1)
blend = blend * blend * (3 - 2 * blend)
h_road = h * (1 - blend) + rh * blend
# nearest-centre-pixel heights terrace the road on climbs (~grade x 1 m steps): smooth the corridor
corr = np.clip(1 - (dist - hw - 2.0) / 4.0, 0, 1)
for _ in range(2):
    h_road = h_road * (1 - corr) + ndimage.gaussian_filter(h_road, 1.6) * corr
road_mask = dist <= hw + 1.0   # carriageway + shoulder: these heights are fixed

# Cut/fill banks: the road profile is grade-limited, so it can sit metres above or below the natural
# ground. A fixed 9 m blend made 50-60 degree walls (a trench with buildings stranded on top), so
# instead the terrain may rise or fall at most BANK_SLOPE per metre away from any fixed surface
# (road, building lot, driveway). Steeper only where a gentle bank would fill the river or a pond.
BANK_SLOPE = 0.28   # ~1:3.5, about 16 degrees: a car can drive up or down it


def grade(base, mask, fixed, iters=220):
    # Upper / lower envelopes U = min(F + s*d), L = max(F - s*d) over ALL fixed pixels (chamfer
    # propagation), so the terrain between two fixed surfaces never gets steeper than the bank slope.
    c1, c2 = BANK_SLOPE, BANK_SLOPE * math.sqrt(2)
    cost = np.array([[c2, c1, c2], [c1, 0.0, c1], [c2, c1, c2]], np.float32)
    U = np.where(mask, fixed, 1e4).astype(np.float32)
    L = np.where(mask, fixed, -1e4).astype(np.float32)
    for _ in range(iters):
        U = ndimage.grey_erosion(U, structure=-cost)
        L = ndimage.grey_dilation(L, structure=-cost)
    out = np.clip(base, L, U)
    # by the river and ponds a gentle bank would fill the water: use the steep nearest-surface cone there
    dm, (jr, jc) = ndimage.distance_transform_edt(~mask, return_indices=True)
    fn = fixed[jr, jc]
    steep = (river_d < 40) | (h_nat < WATER + 1.0)
    out[steep] = np.clip(base, fn - 0.9 * dm, fn + 0.9 * dm)[steep]
    # round off the creases at the top and bottom of each bank
    k = np.clip((dm - 1.0) / 3.0, 0, 1)
    out = out * (1 - k) + ndimage.gaussian_filter(out, 2.5) * k
    out[mask] = fixed[mask]
    return out


def road_details(hh):
    # slight crown / ditch for dirt & gravel
    ditch = np.clip(1 - np.abs(dist - hw - 1.6) / 1.2, 0, 1) * (rk >= 2)
    hh = hh - ditch * 0.35
    # ruts in dirt roads
    rut = (rk == 3) * np.clip(1 - np.abs(np.abs(dist) - 0.9) / 0.35, 0, 1) * (dist < hw)
    return hh - rut * 0.12


# provisional surface for the preview and object placement; graded for real once the lots are known
h = road_details(h_road)

# ---------------------------------------------------------------- splat
splat = np.zeros((N, N, 4), np.float32)
asph = (rk == 1) & (dist <= hw + 0.3)
splat[..., 0] = np.clip((hw + 0.6 - dist) / 0.8, 0, 1) * (rk == 1)
splat[..., 1] = np.clip((hw + 1.2 - dist) / 1.5, 0, 1) * (rk >= 2)
# shoulders of asphalt are gravel
splat[..., 1] = np.maximum(splat[..., 1], np.clip((hw + 1.8 - dist) / 1.0, 0, 1) * (rk == 1) * (1 - splat[..., 0]))
# mud: dirt roads in the forest are muddy; low wet patches; river banks
mudnoise = fbm(4, 24, 1.0, 0.55)
forest_zone = np.clip(1 - (np.sqrt((xw + 560) ** 2 + (zw + 560) ** 2) - 380) / 120, 0, 1)
mud = ((rk == 3) & (dist < hw + 1.5)) * np.clip(0.55 + mudnoise * 2.2 + forest_zone * 0.6, 0, 1)
mud = np.maximum(mud, np.clip(1 - (river_d - 16) / 10, 0, 1) * 0.9 * (river_d > 6))
mud = np.maximum(mud, np.clip((mudnoise - 0.24) * 4, 0, 1) * forest_zone * 0.75)
# farm yard is muddy
for k in ("farm", "lumber", "east_farm"):
    L = LOC[k]
    r, c = P(L["x"], L["z"])
    d = np.sqrt((zz - r) ** 2 + (xx - c) ** 2)
    mud = np.maximum(mud, np.clip(1 - d / (L["r"] * 0.8), 0, 1) * np.clip(0.5 + mudnoise * 3, 0, 1))
splat[..., 2] = np.clip(mud, 0, 1) * (1 - splat[..., 0])

# fields (rotated rectangles) : crop 1 wheat 2 sunflower 3 plowed
FIELDS = [
    dict(c=(330, 760), size=(300, 220), rot=0.15, crop="wheat"),
    dict(c=(-10, 830), size=(260, 200), rot=-0.1, crop="sunflower"),
    dict(c=(-300, 600), size=(220, 180), rot=0.3, crop="wheat"),
    dict(c=(420, 420), size=(200, 160), rot=-0.2, crop="sunflower"),
    dict(c=(-560, 700), size=(240, 200), rot=0.0, crop="plowed"),
    dict(c=(650, 380), size=(140, 260), rot=0.1, crop="wheat"),
    dict(c=(-30, 420), size=(120, 70), rot=0.25, crop="sunflower"),
]
field_map = np.zeros((N, N), np.uint8)
for i, f in enumerate(FIELDS):
    cx, cz = f["c"]
    co, si = math.cos(f["rot"]), math.sin(f["rot"])
    lx = (xw - cx) * co + (zw - cz) * si
    lz = -(xw - cx) * si + (zw - cz) * co
    inside = (np.abs(lx) < f["size"][0] / 2) & (np.abs(lz) < f["size"][1] / 2) & (dist > hw + 4) & (river_d > 30)
    field_map[inside] = {"wheat": 1, "sunflower": 2, "plowed": 3}[f["crop"]]
splat[..., 3] = (field_map > 0).astype(np.float32) * (1 - np.maximum(splat[..., 0], splat[..., 1]))

# ---------------------------------------------------------------- save height / splat
h = np.maximum(h, WATER - 3.5).astype(np.float32)
h.astype("<f4").tofile(os.path.join(OUT, "height.bin"))
img = (np.clip(splat[:2048, :2048], 0, 1) * 255).astype(np.uint8)
img.tofile(os.path.join(OUT, "splat.bin"))
(field_map[:2048, :2048]).astype(np.uint8).tofile(os.path.join(OUT, "fields.bin"))
# preview
prev = np.clip((h - h.min()) / (h.max() - h.min()), 0, 1)
pv = np.stack([prev * 0.5 + 0.3] * 3, -1)
pv[..., 1] += 0.15 * (field_map > 0)
pv[river_d < 12] = [0.2, 0.4, 0.8]
pv[splat[..., 0] > 0.5] = [0.15, 0.15, 0.15]
pv[splat[..., 1] > 0.5] = [0.7, 0.65, 0.55]
pv[splat[..., 2] > 0.5] = [0.35, 0.25, 0.15]


def H(x, z):
    r, c = z + HALF, x + HALF
    return float(ndimage.map_coordinates(h, [[r], [c]], order=1)[0])


# ---------------------------------------------------------------- objects
objs = []


def place(kind, x, z, rot=0.0, **kw):
    o = dict(kind=kind, x=round(x, 2), y=round(H(x, z), 2), z=round(z, 2), rot=round(rot, 3))
    o.update(kw)
    objs.append(o)
    return o


def road_dir_near(x, z):
    best = None
    for rd in ROADS:
        d = rd["dense"]
        i = np.argmin((d[:, 0] - x) ** 2 + (d[:, 1] - z) ** 2)
        dd = (d[i, 0] - x) ** 2 + (d[i, 1] - z) ** 2
        if best is None or dd < best[0]:
            j = min(i + 1, len(d) - 1)
            k = max(i - 1, 0)
            best = (dd, d[j] - d[k], d[i])
    return best


def face_road(x, z):
    _, dv, p = road_dir_near(x, z)
    # yaw so that building front (-Z local) faces the road point
    return math.atan2(-(p[0] - x), -(p[1] - z))


# home
L = LOC["home"]
place("home_house", L["x"] - 12, L["z"] + 14, 0.0)
place("garage", L["x"] + 10, L["z"] + 8, 0.0)
place("shed", L["x"] - 22, L["z"] - 6, 0.0)
place("spawn_player", L["x"] + 10, L["z"] - 4, 0.0)
# village khatas along the street (both sides of highway & gravel road), with fenced yards
BUILT = []   # (x, z, radius) of placed buildings for overlap checks


def free_spot(px, pz, r, road_margin=3.0):
    ri, ci = int(round(pz + HALF)), int(round(px + HALF))
    if not (0 <= ri < N and 0 <= ci < N):
        return False
    # distance from the footprint edge to the nearest road edge
    if dist[ri, ci] - hw[ri, ci] < r + road_margin:
        return False
    for bx, bz, br in BUILT:
        if np.hypot(px - bx, pz - bz) < r + br + 2.0:
            return False
    if river_d[ri, ci] < r + 12:
        return False
    return True


def local_to_world(cx, cz, yaw, lx, lz):
    c, s_ = math.cos(yaw), math.sin(yaw)
    return cx + lx * c + lz * s_, cz - lx * s_ + lz * c


village_types = ["khata", "khata_b", "khata", "khata_tin"]
vi = 0
BUILT.append((LOC["home"]["x"], LOC["home"]["z"], 40))
BUILT.append((LOC["gas_west"]["x"], LOC["gas_west"]["z"], 25))
# village shop (placed below): keep khata yards off its plot
BUILT.append((LOC["village"]["x"] + 30, LOC["village"]["z"] - 60, 3))
for rd_idx, spans in [(0, (-430, -60)), (3, (-180, 0))]:
    d = ROADS[rd_idx]["dense"]
    last = None
    for i in range(0, len(d), 4):
        x, z = d[i]
        if rd_idx == 0 and not (spans[0] < x < spans[1]):
            continue
        if rd_idx == 3 and not (300 < z < 470 and x < 0):
            continue
        if last is not None and np.hypot(x - last[0], z - last[1]) < 30:
            continue
        j = min(i + 2, len(d) - 1)
        t = d[j] - d[max(i - 2, 0)]
        t = t / (np.linalg.norm(t) + 1e-6)
        n = np.array([-t[1], t[0]])
        for side in (-1, 1):
            px, pz = np.array([x, z]) + n * side * 21
            if not free_spot(px, pz, 13.0, 1.0):
                continue
            yaw = math.atan2(n[0] * side, n[1] * side)
            house = place(village_types[vi % 4], px, pz, yaw)
            house["_yard"] = []
            BUILT.append((px, pz, 13.0))
            # yard fence: front (with gate), both sides and back
            for (lx, lz, L, rot) in [(0, -8.5, 20, 0.0), (-10, 1.5, 20, math.pi / 2), (10, 1.5, 20, math.pi / 2), (0, 11.5, 20, 0.0)]:
                fx, fz = local_to_world(px, pz, yaw, lx, lz)
                house["_yard"].append(place("fence_run", fx, fz, yaw + rot, length=L, yard=True))
            vi += 1
        last = (x, z)
L = LOC["village"]
place("shop_village", L["x"] + 30, L["z"] - 60, 0.4)
place("church", L["x"] - 40, L["z"] + 85, 0.2)
place("bus_stop", L["x"] + 5, L["z"] - 30, 0.4)
place("well", L["x"] - 10, L["z"] + 20, 0.0)
# gas station
L = LOC["gas_west"]
place("gas_station", L["x"] + 8, L["z"] - 6, 0.65)
# town
L = LOC["town"]
for i, (dx, dz) in enumerate([(-80, -60), (-80, 30), (60, -60), (60, 30), (-20, -90), (110, -40)]):
    place("khrushchevka", L["x"] + dx, L["z"] + dz, 0.0 if i % 2 == 0 else math.pi / 2)
place("parts_store", L["x"] - 30, L["z"] + 85, 0.0)
place("car_market", L["x"] + 120, L["z"] + 95, 0.0)
place("town_market", L["x"] + 10, L["z"] - 20, 0.0)
place("warehouse", L["x"] + 150, L["z"] - 120, 0.3)
place("gas_station", L["x"] - 120, L["z"] + 150, 0.9)
place("monument", L["x"] - 5, L["z"] + 40, 0.0)
# industry sites
L = LOC["sawmill"]; place("sawmill", L["x"], L["z"], 0.3, industry="sawmill")
L = LOC["lumber"]; place("lumber_camp", L["x"], L["z"], 0.6, industry="lumber_camp")
L = LOC["farm"]; place("barn", L["x"] - 30, L["z"] + 10, 0.1, industry="grain_farm"); place("grain_elevator", L["x"] + 40, L["z"] - 20, 0.1)
place("cowshed", L["x"] - 20, L["z"] + 60, 0.1)
L = LOC["mill"]; place("flour_mill", L["x"], L["z"], -0.2, industry="flour_mill"); place("bakery", L["x"] + 35, L["z"] + 25, -0.2, industry="bakery")
L = LOC["oilpress"]; place("oil_press", L["x"], L["z"], 0.0, industry="oil_press")
L = LOC["east_farm"]; place("barn", L["x"], L["z"], 0.5, industry="sunflower_farm"); place("khata", L["x"] + 25, L["z"] - 20, 0.5)
L = LOC["quarry"]; place("quarry_office", L["x"], L["z"], 0.0, industry="quarry")
L = LOC["town"]; place("furniture_factory", L["x"] + 160, L["z"] - 30, 0.0, industry="furniture_factory")
L = LOC["junkyard"]; place("junkyard_office", L["x"], L["z"], 0.2)
for i in range(14):
    a = i * 0.9
    place("wreck", L["x"] + math.cos(a) * (18 + i * 1.5), L["z"] + math.sin(a) * (18 + i * 1.5), a * 1.7)

# turn service / industry buildings towards the nearest road
for o in objs:
    if o["kind"] in ("shop_village", "bus_stop", "gas_station", "parts_store", "car_market", "town_market", "warehouse", "sawmill",
                     "lumber_camp", "barn", "flour_mill", "bakery", "oil_press", "quarry_office", "furniture_factory", "junkyard_office", "church", "garage", "home_house"):
        o["rot"] = round(face_road(o["x"], o["z"]), 3)

# power line poles along the highway
d = ROADS[0]["dense"]
for i in range(0, len(d), 120):
    x, z = d[i]
    j = min(i + 2, len(d) - 1)
    t = d[j] - d[max(i - 2, 0)]
    t = t / (np.linalg.norm(t) + 1e-6)
    n = np.array([-t[1], t[0]])
    px, pz = np.array([x, z]) + n * 9
    place("power_pole", px, pz, math.atan2(t[0], t[1]))

# street lamps along village and town streets
for rd_idx, keep in [(0, lambda x, z: -430 < x < 330), (3, lambda x, z: z < 470), (1, lambda x, z: True), (13, lambda x, z: True), (14, lambda x, z: True), (15, lambda x, z: True), (16, lambda x, z: True)]:
    d = ROADS[rd_idx]["dense"]
    w2 = ROADS[rd_idx]["w"] / 2
    k = 0
    for i in range(0, len(d), 90):
        x, z = d[i]
        if not keep(x, z):
            continue
        if rd_idx == 0 and not (-430 < x < -60 or 120 < x < 330):
            continue
        j = min(i + 2, len(d) - 1)
        t = d[j] - d[max(i - 2, 0)]
        t = t / (np.linalg.norm(t) + 1e-6)
        n = np.array([-t[1], t[0]])
        side = 1 if k % 2 == 0 else -1
        px, pz = np.array([x, z]) + n * side * (w2 + 1.6)
        ok = all(np.hypot(px - bx, pz - bz) > br for bx, bz, br in BUILT)
        if ok:
            place("street_lamp", px, pz, math.atan2(n[0] * side, n[1] * side))
        k += 1

# ---------------------------------------------------------------- setback from roads
# Local footprints (x0, x1, z0, z1) = axis-aligned bounds of assets/buildings/<kind>.glb in model space
# (front faces -Z). Checking the real rotated rectangle instead of a radius keeps long or rotated
# buildings (shops, khrushchevkas, factories) from sitting on the shoulder.
FOOTPRINT = {
    "khata": (-4.95, 4.95, -4.45, 3.71), "khata_b": (-4.45, 4.45, -4.45, 3.71), "khata_tin": (-5.2, 5.2, -4.7, 3.96),
    "home_house": (-5.45, 5.45, -6.4, 4.21), "garage": (-4.6, 4.6, -5.8, 4.7), "shed": (-2.3, 2.3, -2.21, 1.8),
    "shop_village": (-5.3, 5.3, -4.6, 3.8), "church": (-4.4, 4.4, -10.0, 10.0), "bus_stop": (-2.2, 2.2, -0.92, 1.1),
    "well": (-0.95, 0.95, -0.85, 0.85), "gas_station": (-8.0, 8.0, -6.0, 11.2), "khrushchevka": (-24.15, 24.15, -7.6, 7.2),
    "parts_store": (-7.3, 7.3, -9.1, 5.3), "car_market": (-22.04, 22.04, -16.0, 16.1), "town_market": (-13.0, 13.0, -9.0, 9.0),
    "warehouse": (-15.3, 15.3, -13.0, 9.3), "monument": (-3.0, 3.0, -3.0, 3.0), "sawmill": (-20.0, 20.0, -17.0, 17.0),
    "lumber_camp": (-15.0, 15.0, -13.0, 13.0), "barn": (-16.0, 16.0, -17.0, 9.0), "grain_elevator": (-10.0, 10.0, -3.5, 2.5),
    "cowshed": (-25.4, 25.4, -6.4, 6.4), "flour_mill": (-15.0, 15.0, -17.0, 9.0), "bakery": (-7.25, 7.25, -5.71, 5.25),
    "oil_press": (-15.0, 15.0, -15.0, 11.4), "quarry_office": (-20.0, 20.0, -17.0, 17.0),
    "furniture_factory": (-19.0, 19.0, -20.0, 10.0), "junkyard_office": (-26.1, 26.08, -25.59, 25.64),
}
# minimum clear distance (m) from any part of the building to the road edge
SETBACK_DEFAULT = 8.0
SETBACK = {"bus_stop": 3.0, "well": 3.0, "monument": 4.0, "gas_station": 4.0, "shed": 5.0, "garage": 5.0}
road_gap = dist - hw


def footprint_gap(o):
    """(clear distance from the footprint to the nearest road edge, world point where it is smallest)"""
    x0, x1, z0, z1 = FOOTPRINT[o["kind"]]
    c, s_ = math.cos(o["rot"]), math.sin(o["rot"])
    best = (1e9, None)
    nx, nz = max(2, int((x1 - x0) / 0.5) + 1), max(2, int((z1 - z0) / 0.5) + 1)
    pts = [(lx, z) for lx in np.linspace(x0, x1, nx) for z in (z0, z1)] + [(x, lz) for lz in np.linspace(z0, z1, nz) for x in (x0, x1)]
    for lx, lz in pts:
        wx, wz = o["x"] + lx * c + lz * s_, o["z"] - lx * s_ + lz * c
        ri, ci = int(round(wz + HALF)), int(round(wx + HALF))
        if 0 <= ri < N and 0 <= ci < N and road_gap[ri, ci] < best[0]:
            best = (float(road_gap[ri, ci]), (ri, ci))
    return best


def move_obj(o, dx, dz):
    o["x"] = round(o["x"] + dx, 2)
    o["z"] = round(o["z"] + dz, 2)
    for f in o.get("_yard", []):
        f["x"] = round(f["x"] + dx, 2)
        f["z"] = round(f["z"] + dz, 2)


setback_log = []
for o in objs:
    if o["kind"] not in FOOTPRINT:
        continue
    need = SETBACK.get(o["kind"], SETBACK_DEFAULT)
    g0, _ = footprint_gap(o)
    x0_, z0_ = o["x"], o["z"]
    for it in range(120):
        g, p = footprint_gap(o)
        if g >= need or p is None:
            break
        # push away from the road centre nearest to the closest footprint point
        ri, ci = p
        d = np.array([ci - ic[ri, ci], ri - ir[ri, ci]], float)
        n_ = np.linalg.norm(d)
        d = d / n_ if n_ > 1e-3 else np.array([o["x"] - (ic[ri, ci] - HALF), o["z"] - (ir[ri, ci] - HALF)]) / max(1e-3, math.hypot(o["x"] - (ic[ri, ci] - HALF), o["z"] - (ir[ri, ci] - HALF)))
        move_obj(o, d[0] * 0.5, d[1] * 0.5)
    g1, _ = footprint_gap(o)
    if (o["x"], o["z"]) != (x0_, z0_) or g1 < need:
        setback_log.append((o["kind"], x0_, z0_, g0, o["x"], o["z"], g1, need))
print("setback: moved %d buildings" % len(setback_log))
for k, ax, az, ga, bx, bz, gb, need in setback_log:
    print("  %-18s (%7.1f,%7.1f) gap %5.1f m -> (%7.1f,%7.1f) gap %5.1f m  [min %.1f]%s" % (k, ax, az, ga, bx, bz, gb, need, "" if gb >= need else "  NOT MET"))

# keep every object off the roads: nudge buildings / poles / lamps away, drop fence runs that end up on a road
FOOT0 = {"khata": 9, "khata_b": 8, "khata_tin": 9, "home_house": 9, "garage": 6, "shed": 3, "shop_village": 8, "church": 11, "bus_stop": 2.5,
         "well": 1.5, "gas_station": 9, "khrushchevka": 26, "parts_store": 9, "car_market": 22, "town_market": 13, "warehouse": 17,
         "monument": 4, "sawmill": 18, "lumber_camp": 14, "barn": 16, "grain_elevator": 12, "cowshed": 26, "flour_mill": 14, "bakery": 9,
         "oil_press": 14, "quarry_office": 18, "furniture_factory": 18, "junkyard_office": 26, "power_pole": 0.6, "street_lamp": 0.5, "wreck": 2.5}
keep = []
for o in objs:
    k = o["kind"]
    if k == "fence_run":
        ri, ci = int(round(o["z"] + HALF)), int(round(o["x"] + HALF))
        half = float(o.get("length", 18)) / 2
        ok = True
        yaw = o["rot"]
        for t in np.linspace(-half, half, 9):
            fx, fz = o["x"] + math.cos(yaw) * t, o["z"] - math.sin(yaw) * t
            r2, c2 = int(round(fz + HALF)), int(round(fx + HALF))
            if 0 <= r2 < N and 0 <= c2 < N and dist[r2, c2] - hw[r2, c2] < 1.2:
                ok = False
        if ok:
            keep.append(o)
        continue
    rr = None if k in FOOTPRINT else FOOT0.get(k)
    if rr is not None:
        for it in range(60):
            ri, ci = int(round(o["z"] + HALF)), int(round(o["x"] + HALF))
            if not (0 <= ri < N and 0 <= ci < N):
                break
            gap = dist[ri, ci] - hw[ri, ci]
            if gap >= rr + 1.0:
                break
            cz, cx = ir[ri, ci] - HALF, ic[ri, ci] - HALF
            d = np.array([o["x"] - cx, o["z"] - cz])
            n_ = np.linalg.norm(d)
            d = d / n_ if n_ > 1e-3 else np.array([1.0, 0.0])
            o["x"] = round(o["x"] + d[0] * 1.0, 2)
            o["z"] = round(o["z"] + d[1] * 1.0, 2)
        o["y"] = round(H(o["x"], o["z"]), 2)
    keep.append(o)
objs[:] = keep

FOOT = {"khata": 9, "khata_b": 8, "khata_tin": 9, "home_house": 10, "garage": 7, "shed": 4, "shop_village": 9, "church": 12, "bus_stop": 3,
        "well": 2, "gas_station": 13, "khrushchevka": 28, "parts_store": 12, "car_market": 26, "town_market": 16, "warehouse": 20,
        "monument": 5, "sawmill": 22, "lumber_camp": 18, "barn": 20, "grain_elevator": 13, "cowshed": 26, "flour_mill": 18, "bakery": 12,
        "oil_press": 18, "quarry_office": 22, "furniture_factory": 22, "junkyard_office": 28}
for o in objs:
    rr = FOOT.get(o["kind"], 0)
    if rr == 0:
        continue
    r0, c0 = int(o["z"] + HALF), int(o["x"] + HALF)
    yy, xx2 = np.ogrid[-rr:rr + 1, -rr:rr + 1]
    disk = (yy * yy + xx2 * xx2) <= rr * rr
    sl = (slice(max(0, r0 - rr), min(N, r0 + rr + 1)), slice(max(0, c0 - rr), min(N, c0 + rr + 1)))
    sub = disk[(sl[0].start - (r0 - rr)):(sl[0].stop - (r0 - rr)), (sl[1].start - (c0 - rr)):(sl[1].stop - (c0 - rr))]
    fm = field_map[sl]
    fm[sub & (fm == 0)] = 4
(field_map[:2048, :2048]).astype(np.uint8).tofile(os.path.join(OUT, "fields.bin"))

# ---------------------------------------------------------------- building lots and driveways
# Every building gets a flat lot at (or within a ramp of) the height of the road next to it, plus a
# graded driveway from the lot to the road edge; then the terrain is re-graded around roads + lots.
# Khata lots cover the whole fenced yard (local x -10..10, z -8.5..11.5, front facing the road).
LOT = {"khata": (-10.5, 10.5, -9.0, 12.0), "khata_b": (-10.5, 10.5, -9.0, 12.0), "khata_tin": (-10.5, 10.5, -9.0, 12.0)}
LOT_MARGIN = 3.0
DRIVE_HALF = 2.6
lot_mask = np.zeros((N, N), bool)
lot_h = np.zeros((N, N), np.float32)
drive_mask = np.zeros((N, N), bool)
lot_log = []


def rect_pixels(cx, cz, yaw, x0, x1, z0, z1):
    R = int(math.ceil(math.hypot(max(-x0, x1), max(-z0, z1)))) + 1
    r0, c0 = int(round(cz + HALF)), int(round(cx + HALF))
    r1, r2, c1, c2 = max(0, r0 - R), min(N, r0 + R + 1), max(0, c0 - R), min(N, c0 + R + 1)
    yy, xx_ = np.mgrid[r1:r2, c1:c2]
    dx, dz = xx_ - HALF - cx, yy - HALF - cz
    c, s_ = math.cos(yaw), math.sin(yaw)
    lx, lz = dx * c - dz * s_, dx * s_ + dz * c
    return (slice(r1, r2), slice(c1, c2)), (lx >= x0) & (lx <= x1) & (lz >= z0) & (lz <= z1)


def local_from_world(o, wx, wz):
    c, s_ = math.cos(o["rot"]), math.sin(o["rot"])
    dx, dz = wx - o["x"], wz - o["z"]
    return dx * c - dz * s_, dx * s_ + dz * c


for o in objs:
    if o["kind"] not in FOOTPRINT:
        continue
    fx0, fx1, fz0, fz1 = FOOTPRINT[o["kind"]]
    x0, x1, z0, z1 = LOT.get(o["kind"], (fx0 - LOT_MARGIN, fx1 + LOT_MARGIN, fz0 - LOT_MARGIN, fz1 + LOT_MARGIN))
    sl, m = rect_pixels(o["x"], o["z"], o["rot"], x0, x1, z0, z1)
    med = float(np.median(h_nat[sl][m]))
    gap, p = footprint_gap(o)
    target = med
    if p is not None and gap < 40.0:
        # road height at the road centre nearest to the footprint; the lot may sit a gentle ramp above/below it
        rr_, rc_ = ir[p], ic[p]
        ry = float(h_road[rr_, rc_])
        lim = min(1.5, 0.1 * max(gap, 0.0))
        target = ry + float(np.clip(med - ry, -lim, lim))
        # driveway: straight strip from the footprint edge to the road edge, graded linearly
        px_, pz_ = p[1] - HALF, p[0] - HALF
        ex, ez = rc_ - HALF, rr_ - HALF
        L = math.hypot(ex - px_, ez - pz_)
        if L > 0.5:
            ux, uz = (ex - px_) / L, (ez - pz_) / L
            dsl, dm_ = rect_pixels(px_, pz_, math.atan2(ux, uz), -DRIVE_HALF, DRIVE_HALF, -3.0, L)
            # rect_pixels' local +z runs along (ux, uz) when yaw = atan2(ux, uz)
            yy, xx_ = np.mgrid[dsl[0], dsl[1]]
            # the ramp starts where the driveway leaves the lot (khata yards reach past the house front)
            s0 = 0.0
            while s0 < L:
                lx_, lz_ = local_from_world(o, px_ + ux * s0, pz_ + uz * s0)
                if not (x0 <= lx_ <= x1 and z0 <= lz_ <= z1):
                    break
                s0 += 0.25
            run = max(L - hw[rr_, rc_] - 1.0 - s0, 0.5)
            t = np.clip(((xx_ - HALF - px_) * ux + (yy - HALF - pz_) * uz - s0) / run, 0, 1)
            dm_ &= ~road_mask[dsl]
            lot_mask[dsl] |= dm_
            drive_mask[dsl] |= dm_
            lot_h[dsl][dm_] = (target * (1 - t) + ry * t)[dm_]
        lot_log.append((o["kind"], o["x"], o["z"], med - ry, target - ry))
    m &= ~road_mask[sl]
    lot_mask[sl] |= m
    lot_h[sl][m] = target
    o["y"] = round(target, 2)
print("lots: %d buildings graded to the road next to them" % len(lot_log))
for k, x, z, nat_d, lot_d in lot_log:
    if abs(nat_d) > 1.5:
        print("  %-18s (%7.1f,%7.1f) ground was %+5.1f m from the road -> lot %+4.1f m" % (k, x, z, nat_d, lot_d))
fixed = np.where(road_mask, h_road, lot_h).astype(np.float32)
h = road_details(grade(h_nat, road_mask | lot_mask, fixed))
# driveways are gravel (no grass on them, so you can see where to turn in)
dg = np.clip(ndimage.gaussian_filter(drive_mask.astype(np.float32), 0.8) * 1.6, 0, 1)
splat[..., 1] = np.maximum(splat[..., 1], dg * (1 - splat[..., 0]))
splat[..., 2] *= 1 - dg
splat[..., 3] *= 1 - dg
(np.clip(splat[:2048, :2048], 0, 1) * 255).astype(np.uint8).tofile(os.path.join(OUT, "splat.bin"))
h = np.maximum(h, WATER - 3.5).astype(np.float32)
for o in objs:
    if o["kind"] in ("fence_run", "power_pole", "street_lamp", "spawn_player", "wreck"):
        o["y"] = round(H(o["x"], o["z"]), 2)
h.astype("<f4").tofile(os.path.join(OUT, "height.bin"))

# ---------------------------------------------------------------- vegetation
# occupied mask
occ = np.zeros((N, N), bool)
for o in objs:
    r, c = int(o["z"] + HALF), int(o["x"] + HALF)
    rad = 3 if o["kind"] in ("power_pole", "fence_run", "street_lamp") else 22
    occ[max(0, r - rad):r + rad, max(0, c - rad):c + rad] = True
for k, Lc in LOC.items():
    r, c = P(Lc["x"], Lc["z"])
    dd = np.sqrt((zz - r) ** 2 + (xx - c) ** 2)
    occ |= dd < Lc["r"] * 0.85
occ |= dist < hw + 5
occ |= river_d < 22
occu_water = h < WATER + 0.9
occ |= occu_water
occ |= (field_map > 0) & (field_map != 4)
forest_den = np.clip(forest_zone * 1.3 + fbm(3, 10, 1.0) * 1.2 - 0.05, 0, 1)
# tree belts (lesosmuga) along fields & highway
belt_noise = fbm(3, 40, 1.0)
trees = []
cand = rng.random((N // 4, N // 4))
for r4 in range(N // 4):
    for c4 in range(N // 4):
        r = r4 * 4 + int(rng.integers(0, 4))
        c = c4 * 4 + int(rng.integers(0, 4))
        if r >= N or c >= N or occ[r, c]:
            continue
        den = forest_den[r, c] * 0.75
        # sparse trees elsewhere, belts near fields edges
        den = max(den, 0.02)
        if field_map[min(r + 14, N - 1), c] or field_map[max(r - 14, 0), c] or field_map[r, min(c + 14, N - 1)] or field_map[r, max(c - 14, 0)]:
            den = max(den, 0.45)
        if river_d[r, c] < 60:
            den = max(den, 0.25)
        if cand[r4, c4] < den:
            x, z = c - HALF + rng.random(), r - HALF + rng.random()
            if forest_zone[r, c] > 0.4:
                t = "pine" if rng.random() < 0.55 else ("birch" if rng.random() < 0.5 else "oak")
            elif river_d[r, c] < 60:
                t = "willow"
            else:
                t = ["poplar", "birch", "oak", "acacia"][int(rng.integers(0, 4))]
            trees.append([round(x, 1), round(float(h[r, c]), 2), round(z, 1), t, round(0.8 + rng.random() * 0.5, 2), round(rng.random() * 6.28, 2)])
# orchards in the village
for k in range(260):
    L = LOC["village"]
    x = L["x"] + rng.normal(0, 110)
    z = L["z"] + rng.normal(0, 110)
    r, c = int(z + HALF), int(x + HALF)
    if 0 <= r < N and 0 <= c < N and not occ[r, c]:
        trees.append([round(x, 1), round(float(h[r, c]), 2), round(z, 1), "apple", round(0.8 + rng.random() * 0.4, 2), round(rng.random() * 6.28, 2)])
print("trees", len(trees), "objects", len(objs))

roads_out = []
for rd in ROADS:
    d = rd["dense"][::4]
    ys = rd["ys"][::4]
    roads_out.append(dict(kind=rd["kind"], w=rd["w"], pts=[[round(float(x), 2), round(float(y), 2), round(float(z), 2)] for (x, z), y in zip(d, ys)]))
for k, Lc in LOC.items():
    Lc["y"] = round(H(Lc["x"], Lc["z"]), 2)
for o in objs:
    o.pop("_yard", None)
world = dict(size=2048, water=WATER, river=[[round(x, 1), round(z, 1)] for x, z in river_pts], locations=LOC, roads=roads_out, objects=objs, fields=FIELDS)
json.dump(world, open(os.path.join(OUT, "world.json"), "w"))
json.dump(trees, open(os.path.join(OUT, "trees.json"), "w"))
for o in objs:
    r, c = int(o["z"] + HALF), int(o["x"] + HALF)
    pv[max(0, r - 6):r + 6, max(0, c - 6):c + 6] = [1, 0.2, 0.2]
for t in trees[::3]:
    r, c = int(t[2] + HALF), int(t[0] + HALF)
    if 0 <= r < N and 0 <= c < N:
        pv[r, c] = [0.1, 0.35, 0.1]
Image.fromarray((np.clip(pv, 0, 1) * 255).astype(np.uint8)).resize((1024, 1024)).save(os.path.join(ROOT, "tools", "map_preview.png"))
print("height range", h.min(), h.max())


# ---------------------------------------------------------------- map texture for the tablet
mp = np.zeros((N, N, 3), np.float32)
hn = np.clip((h - WATER) / 60.0, 0, 1)
mp[:] = np.stack([0.42 + hn * 0.25, 0.55 + hn * 0.18, 0.32 + hn * 0.1], -1)
shade = np.clip(0.85 + (np.roll(h, 1, 1) - h) * 0.12, 0.6, 1.2)
mp *= shade[..., None]
fm = field_map
mp[fm == 1] = [0.85, 0.75, 0.42]
mp[fm == 2] = [0.92, 0.8, 0.2]
mp[fm == 3] = [0.5, 0.38, 0.26]
fd = np.zeros((N, N), np.float32)
for t in trees:
    r, c = int(t[2] + HALF), int(t[0] + HALF)
    if 0 <= r < N and 0 <= c < N:
        fd[r, c] = 1
fd = ndimage.gaussian_filter(fd, 3) > 0.02
mp[fd] = mp[fd] * 0.55 + np.array([0.1, 0.3, 0.12]) * 0.45
mp[h < WATER] = [0.25, 0.45, 0.7]
mp[splat[..., 2] > 0.55] = [0.42, 0.32, 0.22]
mp[splat[..., 1] > 0.5] = [0.82, 0.76, 0.62]
mp[splat[..., 0] > 0.5] = [0.22, 0.22, 0.24]
for o in objs:
    if o["kind"] in ("power_pole", "fence_run", "street_lamp"):
        continue
    r, c = int(o["z"] + HALF), int(o["x"] + HALF)
    mp[max(0, r - 5):r + 5, max(0, c - 5):c + 5] = [0.75, 0.3, 0.25]
Image.fromarray((np.clip(mp, 0, 1) * 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "map.png"))
print("map ok")
