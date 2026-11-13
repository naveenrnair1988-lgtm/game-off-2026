"""Step 2 of the lighting bake: Blender (bpy) builds the room exported by tools/export_scene.gd,
unwraps it for lightmaps, bakes each light group with Cycles and writes:

    assets/baked/room.glb            the static room, second UV set = lightmap UVs
    assets/baked/lm_<atlas>_<group>.webp   lightmaps (sqrt-encoded, see lightmaps.json)
    assets/baked/lightmaps.json      scale per lightmap

Run:  python3 tools/bake_room.py <export_dir> [--size 2048] [--samples 96] [--only lamps]
"""
import bpy, bmesh, json, os, sys, re, math, time
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
SRC = args[0]
def opt(name, default):
    return type(default)(args[args.index(name) + 1]) if name in args else default
SIZE = opt("--size", 2048)
SAMPLES = opt("--samples", 96)
ONLY = opt("--only", "")
POST = "--post" in args      # skip path tracing: re-run the clean-up on the raw bakes saved last time
OUT = os.path.join(ROOT, "assets", "baked")
os.makedirs(OUT, exist_ok=True)
T0 = time.time()
def log(*a):
    print("[bake %6.0fs]" % (time.time() - T0), *a, flush=True)

def g2b(p):          # Godot (x, y, z) -> Blender (x, -z, y)
    return (p[0], -p[2], p[1])

man = json.load(open(os.path.join(SRC, "scene.json")))
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = SAMPLES
scene.cycles.max_bounces = 6
scene.cycles.diffuse_bounces = 4
scene.cycles.use_denoising = True
scene.cycles.use_adaptive_sampling = False
scene.cycles.sample_clamp_indirect = 4.0
scene.cycles.caustics_reflective = False
scene.cycles.caustics_refractive = False
scene.render.threads_mode = "AUTO"
world = bpy.data.worlds.new("w"); scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[1].default_value = 0.0

# ---------------------------------------------------------------- meshes
def read_mesh(e):
    raw = np.fromfile(os.path.join(SRC, e["file"]), dtype=np.uint8)
    n, ni = e["verts"], e["indices"]
    f = raw[: n * 32].view(np.float32)
    pos = f[: n * 3].reshape(n, 3); nrm = f[n * 3: n * 6].reshape(n, 3); uv = f[n * 6: n * 8].reshape(n, 2)
    idx = raw[n * 32: n * 32 + ni * 4].view(np.uint32).reshape(-1, 3)
    pos = np.stack([pos[:, 0], -pos[:, 2], pos[:, 1]], 1)
    nrm = np.stack([nrm[:, 0], -nrm[:, 2], nrm[:, 1]], 1)
    if not e.get("flip"):
        idx = idx[:, ::-1]          # Godot winds clockwise
    return pos, nrm, uv, idx

def make_object(name, pos, nrm, uv, idx):
    me = bpy.data.meshes.new(name)
    me.from_pydata(pos.tolist(), [], idx.tolist())
    me.update()
    uvl = me.uv_layers.new(name="uv0")
    loops = np.zeros(len(me.loops), dtype=np.int32); me.loops.foreach_get("vertex_index", loops)
    uvs = uv[loops].copy(); uvs[:, 1] = 1.0 - uvs[:, 1]
    uvl.data.foreach_set("uv", uvs.ravel())
    me.normals_split_custom_set_from_vertices(nrm.tolist())
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    return ob

room_parts, props, casters, emitters = [], [], [], []
for e in man["meshes"]:
    pos, nrm, uv, idx = read_mesh(e)
    ob = make_object(e["name"].replace("@", "") + "_" + e["file"][:5], pos, nrm, uv, idx)
    ob["key"] = e["key"]
    if e["role"] == "caster":
        casters.append(ob)
    elif e["role"] == "emit":
        ob["color"] = e["color"]; ob["energy"] = e["energy"]; ob["group"] = e["group"]
        emitters.append(ob)
    elif e["key"].startswith("prop:"):
        ob["instance"] = e["instance"]
        props.append(ob)
    else:
        room_parts.append(ob)
log("built", len(room_parts), "room parts,", len(props), "props,", len(casters), "casters,", len(emitters), "emitters")

# ---------------------------------------------------------------- cull what no camera can see
src = open(os.path.join(ROOT, "scripts", "Main.gd")).read()
block = src[src.index("const STATIONS"):src.index("const SCENE_STATION")]
stations = [Vector(g2b([float(a), float(b), float(c)])) for a, b, c in re.findall(r'\[Vector3\(([-\d.]+), ([-\d.]+), ([-\d.]+)\),\s+Vector3', block)]
candidates = []
for s in stations:
    for dx in (-0.5, 0.0, 0.5):
        for dy in (-0.5, 0.0, 0.5):
            for dz in (-0.2, 0.2):
                candidates.append((s, s + Vector((dx, dy, dz))))
# the camera also travels between stations: sample those straight lines
for i, a in enumerate(stations):
    for b in stations[i + 1:]:
        for t in (0.2, 0.4, 0.6, 0.8):
            candidates.append((a, a.lerp(b, t)))

def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob

# one material slot per key before joining
mats = {}
def mat_for(key):
    if key not in mats:
        mats[key] = bpy.data.materials.new(key)
    return mats[key]
for ob in room_parts + props:
    ob.data.materials.append(mat_for(ob["key"]))
prop_groups = {}
for ob in props:
    prop_groups.setdefault(ob["instance"], []).append(ob)
props = [join(v, k) if len(v) > 1 else v[0] for k, v in prop_groups.items()]
for ob, k in zip(props, prop_groups.keys()):
    ob.name = k
room = join(room_parts, "Room")

dg = bpy.context.evaluated_depsgraph_get()
occluders = [room] + props
bm_all = bmesh.new()
for ob in occluders:
    bm_all.from_mesh(ob.data)
bvh = BVHTree.FromBMesh(bm_all)
# an eye point only counts if it is in the open: in sight of the station it belongs to
eyes = []
for s, e in candidates:
    d = e - s
    if d.length < 1e-4 or bvh.ray_cast(s, d.normalized(), d.length)[0] is None:
        eyes.append(e)
log(len(stations), "camera stations,", len(eyes), "eye points")
bm = bmesh.new(); bm.from_mesh(room.data); bm.faces.ensure_lookup_table()
kill = []
for f in bm.faces:
    pts = [f.calc_center_median()] + [(f.calc_center_median() + v.co * 3) / 4 for v in f.verts]
    seen = False
    for p in pts:
        o = p + f.normal * 0.004
        for eye in eyes:
            d = eye - o
            if d.dot(f.normal) <= 0.0:
                continue
            dist = d.length
            hit = bvh.ray_cast(o, d / dist, dist - 0.01)
            if hit[0] is None:
                seen = True; break
        if seen:
            break
    if not seen:
        kill.append(f)
log("room faces", len(bm.faces), "-> culling", len(kill), "never seen")
bmesh.ops.delete(bm, geom=kill, context="FACES")
bm.to_mesh(room.data); bm.free(); bm_all.free()
room.data.update()

# ---------------------------------------------------------------- lightmap UVs
bpy.ops.object.select_all(action="DESELECT")
room.select_set(True); bpy.context.view_layer.objects.active = room
lm = room.data.uv_layers.new(name="lm"); room.data.uv_layers.active = lm
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
bpy.ops.uv.average_islands_scale()
bpy.ops.object.mode_set(mode="OBJECT")
# a face thinner than a texel would catch no samples and read its neighbours: give every island a few texels each way
from bpy_extras import mesh_utils
lm = room.data.uv_layers["lm"]
uvd = np.zeros(len(room.data.loops) * 2, dtype=np.float32); lm.data.foreach_get("uv", uvd); uvd = uvd.reshape(-1, 2)
MINW = 4.0 / SIZE
grown = 0
for isl in mesh_utils.mesh_linked_uv_islands(room.data):
    li = np.array([l for pi in isl for l in room.data.polygons[pi].loop_indices])
    u = uvd[li]; lo = u.min(0); hi = u.max(0); c = (lo + hi) * 0.5; w = hi - lo
    k = np.maximum(1.0, MINW / np.maximum(w * 0.5, 1e-9) * 0.5)   # scale in the packed layout is about half the raw one
    if (k > 1.0).any():
        uvd[li] = c + (u - c) * k; grown += 1
lm.data.foreach_set("uv", uvd.ravel())
log("widened", grown, "thin islands")
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.pack_islands(margin=6.0 / SIZE, rotate=False, scale=True)
bpy.ops.object.mode_set(mode="OBJECT")
area = sum(p.area for p in room.data.polygons)
log("room area %.0f m2 -> about %.1f px/cm" % (area, math.sqrt(SIZE * SIZE * 0.7 / max(area, 1)) / 100))

# Texels whose surface point is buried in, or pressed against, other geometry (a wall running on
# inside the wall it meets, the floor under a table leg) bake to garbage and then bleed along the
# seam. Find them now; after the bake they are refilled from their valid neighbours.
D1 = Vector((0.31, 0.57, 0.76)).normalized()
D2 = Vector((-0.64, 0.23, -0.73)).normalized()
def inside(o, d):
    """True if o is inside a solid of the original (unculled) room: odd number of crossings."""
    n = 0
    for _ in range(48):
        hit = bvh.ray_cast(o, d)
        if hit[0] is None:
            break
        n += 1
        o = hit[0] + d * 2e-4
    return n % 2 == 1

def buried_mask():
    bmr = bmesh.new()
    for ob in [room] + props:
        bmr.from_mesh(ob.data)
    tree = BVHTree.FromBMesh(bmr)
    me = room.data
    me.calc_loop_triangles()
    uvl = me.uv_layers["lm"].data
    bad = np.zeros((SIZE, SIZE), dtype=bool)
    for tri in me.loop_triangles:
        uv = np.array([uvl[l].uv[:] for l in tri.loops], dtype=np.float64) * SIZE
        co = [me.vertices[v].co for v in tri.vertices]
        n = tri.normal
        x0, y0 = np.floor(uv.min(0)).astype(int); x1, y1 = np.ceil(uv.max(0)).astype(int)
        d = (uv[1, 1] - uv[2, 1]) * (uv[0, 0] - uv[2, 0]) + (uv[2, 0] - uv[1, 0]) * (uv[0, 1] - uv[2, 1])
        if abs(d) < 1e-12:
            continue
        for py in range(max(y0, 0), min(y1 + 1, SIZE)):
            for px in range(max(x0, 0), min(x1 + 1, SIZE)):
                cx, cy = px + 0.5, py + 0.5
                a = ((uv[1, 1] - uv[2, 1]) * (cx - uv[2, 0]) + (uv[2, 0] - uv[1, 0]) * (cy - uv[2, 1])) / d
                b = ((uv[2, 1] - uv[0, 1]) * (cx - uv[2, 0]) + (uv[0, 0] - uv[2, 0]) * (cy - uv[2, 1])) / d
                c = 1.0 - a - b
                if a < -0.02 or b < -0.02 or c < -0.02:
                    continue
                p = co[0] * a + co[1] * b + co[2] * c
                o = p + n * 0.002
                if tree.ray_cast(o, n, 0.025)[0] is not None or (inside(o, D1) and inside(o, D2)):
                    bad[SIZE - 1 - py, px] = True
    bmr.free()
    return bad
BURIED = buried_mask()
log("buried texels: %.1f%% of the atlas" % (100.0 * BURIED.mean()))

# props: their own UVs, each instance in its own cell of the props atlas
cols = math.ceil(math.sqrt(len(props))); rows = math.ceil(len(props) / cols)
for i, ob in enumerate(sorted(props, key=lambda o: o.name)):
    me = ob.data
    uv0 = np.zeros(len(me.loops) * 2, dtype=np.float32); me.uv_layers["uv0"].data.foreach_get("uv", uv0)
    uv0 = uv0.reshape(-1, 2)
    uv0 = uv0 - np.floor(uv0.min(0))
    pad = 12.0 / SIZE
    cx, cy = i % cols, i // cols
    out = np.empty_like(uv0)
    out[:, 0] = (cx + pad * cols + uv0[:, 0] * (1 - 2 * pad * cols)) / cols
    out[:, 1] = (cy + pad * rows + uv0[:, 1] * (1 - 2 * pad * rows)) / rows
    l = me.uv_layers.new(name="lm"); l.data.foreach_set("uv", out.ravel()); me.uv_layers.active = l

# ---------------------------------------------------------------- bake materials
images = {}
def image(atlas):
    if atlas not in images:
        n = SIZE if atlas == "room" else SIZE // 2
        images[atlas] = bpy.data.images.new("lm_" + atlas, n, n, float_buffer=True, alpha=True)
        images[atlas].generated_color = (0, 0, 0, 0)
    return images[atlas]

def setup_material(m, key, atlas):
    m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfDiffuse")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    info = man["materials"].get(key, {})
    col = info.get("color", [0.6, 0.6, 0.6])
    tex = None
    if key.startswith("prop:"):
        p = os.path.join(ROOT, "assets", "models", key[5:] + "_Image_0.webp")
        if os.path.exists(p):
            tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = bpy.data.images.load(p)
            uvn = nt.nodes.new("ShaderNodeUVMap"); uvn.uv_map = "uv0"
            nt.links.new(uvn.outputs[0], tex.inputs[0])
        col = [1, 1, 1]
    elif info.get("tex"):
        p = os.path.join(ROOT, info["tex"].replace("res://", ""))
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = bpy.data.images.load(p)
        tex.projection = "BOX"; tex.projection_blend = 0.2
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        mp = nt.nodes.new("ShaderNodeMapping")
        s = info.get("scale", 1.0)
        mp.inputs["Scale"].default_value = (s, s, s)
        nt.links.new(geo.outputs["Position"], mp.inputs[0]); nt.links.new(mp.outputs[0], tex.inputs[0])
    if tex is not None:
        mul = nt.nodes.new("ShaderNodeMixRGB"); mul.blend_type = "MULTIPLY"; mul.inputs[0].default_value = 1.0
        mul.inputs[2].default_value = (col[0], col[1], col[2], 1)
        nt.links.new(tex.outputs[0], mul.inputs[1]); nt.links.new(mul.outputs[0], bsdf.inputs[0])
    else:
        # metals bounce more than their dark base colour suggests
        k = 1.0
        bsdf.inputs[0].default_value = (col[0] * k, col[1] * k, col[2] * k, 1)
    tgt = nt.nodes.new("ShaderNodeTexImage"); tgt.image = image(atlas); tgt.name = "bake_target"
    uvn = nt.nodes.new("ShaderNodeUVMap"); uvn.uv_map = "lm"
    nt.links.new(uvn.outputs[0], tgt.inputs[0])
    nt.nodes.active = tgt; tgt.select = True

for slot in room.material_slots:
    setup_material(slot.material, slot.material.name, "room")
for ob in props:
    for slot in ob.material_slots:
        setup_material(slot.material, slot.material.name, "props")

# casters: block light, never baked
cm = bpy.data.materials.new("caster"); cm.use_nodes = True
for ob in casters:
    ob.data.materials.append(cm)

# ---------------------------------------------------------------- lights, by group
def emission_mat(name, color, strength):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (color[0], color[1], color[2], 1); em.inputs[1].default_value = strength
    nt.links.new(em.outputs[0], out.inputs[0])
    return m

def point(name, pos, color, watts, radius=0.05):
    ld = bpy.data.lights.new(name, "POINT"); ld.energy = watts; ld.color = color; ld.shadow_soft_size = radius
    ob = bpy.data.objects.new(name, ld); ob.location = g2b(pos); scene.collection.objects.link(ob)
    return ob

groups = {"lamps": [], "accent": [], "head": []}
window = None
for i, l in enumerate(man["lights"]):
    if l["kind"] == "lamp":
        # white: the game tints this group with the palette (warm sober, cold in the Voice)
        p = list(l["pos"]); desk = p[1] < 2.0
        if desk:
            groups["lamps"].append(point("lamp%d" % i, p, (1, 1, 1), 11, 0.04))
        else:
            # a pendant throws a pool of light downwards; only a little escapes past the shade
            sd = bpy.data.lights.new("lamp%d" % i, "SPOT"); sd.energy = 150; sd.color = (1, 1, 1); sd.shadow_soft_size = 0.05
            sd.spot_size = math.radians(128); sd.spot_blend = 0.75
            so = bpy.data.objects.new("lamp%d" % i, sd); so.location = g2b([p[0], p[1] - 0.10, p[2]])   # a new spot points straight down
            scene.collection.objects.link(so)
            groups["lamps"].append(so)
            groups["lamps"].append(point("lampfill%d" % i, [p[0], p[1] - 0.10, p[2]], (1, 1, 1), 14, 0.04))
    elif l["kind"] == "neon":
        groups["accent"].append(point("neon", l["pos"], (1.0, 0.16, 0.34), 60, 0.25))
    elif l["kind"] == "headlight":
        groups["head"].append(point("head", [-1.6, 1.5, 5.4], (0.80, 0.90, 1.0), 2600, 0.35))
for ob in emitters:
    if ob.name.startswith("Window"):
        window = ob
        continue
    col = ob["color"]; lum = max(0.2126 * col[0] + 0.7152 * col[1] + 0.0722 * col[2], 1e-3)
    warm = col[0] > col[2]
    if warm:
        ob.data.materials.append(emission_mat("em_" + ob.name, (1, 1, 1), 2.2 * ob["energy"] * lum))
        groups["lamps"].append(ob)
    else:
        ob.data.materials.append(emission_mat("em_" + ob.name, col, 1.5 * ob["energy"]))
        groups["accent"].append(ob)
# the street outside: a cold area light pushed through the blinds; the window pane itself only glows
if window is not None:
    window.hide_render = True
    for grp, col, watts in (("accent", (0.30, 0.48, 1.0), 260), ("head", (0.85, 0.93, 1.0), 1500)):
        ad = bpy.data.lights.new("street_" + grp, "AREA"); ad.shape = "RECTANGLE"; ad.size = 3.9; ad.size_y = 1.35
        ad.energy = watts; ad.color = col; ad.spread = math.radians(120)
        ao = bpy.data.objects.new("street_" + grp, ad)
        ao.location = g2b([-1.6, 1.9, 4.145])   # between the pane and the slats; ao.rotation_euler = (math.radians(78), 0, 0)   # facing into the room, tilted down
        scene.collection.objects.link(ao)
        groups[grp].append(ao)
    groups["head"] = [o for o in groups["head"] if o.name != "head"]

all_sources = [o for g in groups.values() for o in g]

def enable(group):
    for o in all_sources:
        on = o in groups[group]
        o.hide_render = not on
        o.hide_viewport = not on

# ---------------------------------------------------------------- bake
scene.render.bake.use_pass_direct = True
scene.render.bake.use_pass_indirect = True
scene.render.bake.use_pass_color = False
scene.render.bake.margin = 6
scene.render.bake.margin_type = "EXTEND"
scene.render.bake.use_clear = True
scene.render.bake.target = "IMAGE_TEXTURES"
meta = {}
from PIL import Image
from scipy import ndimage

def clean(rgb, cover):
    """Knock out fireflies and smooth Monte Carlo grain without bleeding across islands."""
    out = np.empty_like(rgb)
    w = ndimage.gaussian_filter(cover, 1.1) + 1e-6
    for c in range(3):
        ch = rgb[:, :, c]
        med = ndimage.median_filter(ch, size=3)
        ch = np.where(ch > med * 2.5 + 0.02, med, ch)          # fireflies
        out[:, :, c] = ndimage.gaussian_filter(ch * cover, 1.1) / w
    # fill what was never baked from its neighbours so bilinear sampling has something to read
    idx = ndimage.distance_transform_edt(cover < 0.5, return_distances=False, return_indices=True)
    return np.where(cover[:, :, None] > 0.5, out, out[idx[0], idx[1]])

for group in groups:
    if ONLY and group not in ONLY.split(","):
        continue
    enable(group)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [room] + props:
        o.select_set(True)
    bpy.context.view_layer.objects.active = room
    scene.cycles.samples = SAMPLES if group == "lamps" else max(8, SAMPLES // 2)
    if not POST:
        log("baking", group, "at", SIZE, "px,", scene.cycles.samples, "samples")
        bpy.ops.object.bake(type="DIFFUSE")
    for atlas, img in images.items():
        n = img.size[0]
        raw = os.path.join(SRC, "raw_%s_%s.npy" % (atlas, group))
        if POST:
            full = np.load(raw).astype(np.float32)
        else:
            px = np.empty(n * n * 4, dtype=np.float32); img.pixels.foreach_get(px)
            full = np.nan_to_num(px.reshape(n, n, 4)[::-1], nan=0.0, posinf=0.0, neginf=0.0)
            np.save(raw, full.astype(np.float16))
        cover = full[:, :, 3] > 0.5
        if atlas == "room":
            cover &= ~BURIED
        rgb = clean(full[:, :, :3], cover.astype(np.float32))
        lit = rgb[rgb.max(2) > 1e-5]
        scale = float(max(np.percentile(lit, 99.0) if lit.size else 0.0, 1e-4))
        enc = np.sqrt(np.clip(rgb / scale, 0.0, 1.0))
        name = "lm_%s_%s.webp" % (atlas, group)
        Image.fromarray((enc * 255.0 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name), quality=92, method=6)
        meta["%s_%s" % (atlas, group)] = {"file": name, "scale": scale, "mean": float(rgb.mean())}
        log("  wrote", name, "scale %.3f mean %.4f" % (scale, rgb.mean()))
mp = os.path.join(OUT, "lightmaps.json")
old = json.load(open(mp)) if os.path.exists(mp) else {}
old.update(meta)
old["materials"] = man["materials"]
json.dump(old, open(mp, "w"), indent=1)

# ---------------------------------------------------------------- export the room
if not ONLY and not POST:
    for o in list(scene.collection.objects):
        if o not in [room] + props:
            bpy.data.objects.remove(o, do_unlink=True)
    for m in bpy.data.materials:
        if m.use_nodes:
            m.node_tree.nodes.clear()
            out = m.node_tree.nodes.new("ShaderNodeOutputMaterial"); b = m.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
            m.node_tree.links.new(b.outputs[0], out.inputs[0])
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "room.glb"), export_format="GLB", export_yup=True, export_texcoords=True,
                              export_normals=True, export_materials="EXPORT", export_image_format="NONE", export_apply=False, use_selection=True)
    log("wrote room.glb", os.path.getsize(os.path.join(OUT, "room.glb")) // 1024, "KB")
log("done")
