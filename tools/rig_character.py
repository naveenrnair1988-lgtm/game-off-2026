"""Build a game-ready rigged character from auto-rigged GLBs.

  python3 tools/rig_character.py main.glb out.glb --grid grid.png            (measure the face)
  python3 tools/rig_character.py main.glb out.glb --clips talk=talk.glb ... --face "neck=..,mouth=..,chin=..,eye=..,eye_dx=..,eye_cx=..,mouth_w=..,cx=.."

main.glb carries the mesh, textures, skeleton and one animation; each --clips file carries the same
rig with another animation (its mesh is ignored). The result faces +Z (glTF), has every clip as a
named animation, 2048 px WEBP textures, and four face shape keys (jaw, blink, brow_up, brow_dn)
built from the measured face heights. Mouth-interior shading data goes in UV2 (x off the centre
line / height, normalised height) and vertex colour red (jaw mask).
"""
import bpy, sys, math, os, argparse
import numpy as np
from mathutils import Vector, Matrix

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("dst")
ap.add_argument("--grid", default="")
ap.add_argument("--span", type=float, default=0.24)
ap.add_argument("--clips", nargs="*", default=[])
ap.add_argument("--main-clip", default="idle")
ap.add_argument("--face", default="")
ap.add_argument("--tex", type=int, default=2048)
a = ap.parse_args(sys.argv[1:])


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-12), 0.0, 1.0)
    return t * t * (3 - 2 * t)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a.src)
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == "ARMATURE")
mesh = next(o for o in sc.objects if o.type == "MESH")
act_main = arm.animation_data.action if arm.animation_data else None
if act_main:
    act_main.name = a.main_clip

# ---- turn the figure to face -Y (Blender) = +Z (glTF), using the rig's shoulders
arm.data.pose_position = "REST"
bpy.context.view_layer.update()
mw = arm.matrix_world
bones = arm.data.bones
side = (mw @ bones["LeftArm"].head_local) - (mw @ bones["RightArm"].head_local)
ang = -math.atan2(side.y, side.x)          # rotation about Z that puts the figure's left on +X, so it faces -Y
root = bpy.data.objects.new("Character", None)
sc.collection.objects.link(root)
for o in [o for o in sc.objects if o.parent is None and o is not root]:
    o.parent = root
root.rotation_euler = (0, 0, ang)
bpy.context.view_layer.update()

dg = bpy.context.evaluated_depsgraph_get()
M = mesh.matrix_world.copy()
co = np.array([(M @ v.co)[:] for v in mesh.data.vertices])
lo, hi = co.min(0), co.max(0)
H = hi[2] - lo[2]
cx0 = (lo[0] + hi[0]) / 2
head_x = (arm.matrix_world @ bones["Head"].head_local).x
print("SIZE", (hi - lo).round(3), "feet z", round(lo[2], 4), "H", round(H, 4), "yaw applied", round(math.degrees(ang), 1), "head x", round(head_x, 4))
hn = (co[:, 2] - lo[2]) / H
for img in bpy.data.images:
    if img.size[0] > a.tex:
        img.scale(a.tex, a.tex)

if a.grid:
    sc.render.engine = "CYCLES"; sc.cycles.samples = 16; sc.cycles.use_denoising = True
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.6, 0.6, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 1.6
    cam = bpy.data.objects.new("c", bpy.data.cameras.new("c")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"
    span = a.span
    cam.data.ortho_scale = span * H
    cam.location = (head_x, -5, lo[2] + (1.0 - span / 2) * H); cam.rotation_euler = (math.radians(90), 0, 0)
    sc.render.resolution_x = 900; sc.render.resolution_y = 900
    sc.render.filepath = a.grid
    bpy.ops.render.render(write_still=True)
    from PIL import Image, ImageDraw
    im = Image.open(a.grid).convert("RGB"); d = ImageDraw.Draw(im)
    npp = span / 900.0
    t = math.floor(1.0 / 0.005) * 0.005
    while t > 1.0 - span:
        y = (1.0 - t) / npp
        major = round(t * 1000) % 10 == 0
        d.line([(0, y), (900, y)], fill=(0, 255, 0) if major else (0, 110, 0), width=1)
        if major:
            d.text((4, y - 11), "%.2f" % t, fill=(0, 255, 0))
        t -= 0.005
    for k in range(-11, 12):
        dx = k * 0.01
        x = 450 + dx / npp
        d.line([(x, 0), (x, 900)], fill=(255, 70, 70) if k % 5 == 0 else (120, 40, 40), width=1)
        if k % 5 == 0:
            d.text((x + 2, 884), "%+.2f" % dx, fill=(255, 90, 90))
    im.save(a.grid)
    # side view of the whole figure, to check the rest pose and facing
    cam.data.ortho_scale = 1.15 * H
    cam.location = (head_x, -5, lo[2] + 0.5 * H)
    sc.render.resolution_x = 500; sc.render.resolution_y = 700
    sc.render.filepath = a.grid.replace(".png", "_body.png")
    bpy.ops.render.render(write_still=True)
    print("PROFILE h : front/H back/H (relative to the head bone)")
    hy = (arm.matrix_world @ bones["Head"].head_local).y
    for hq in np.arange(0.80, 1.0, 0.01):
        s = co[(hn >= hq) & (hn < hq + 0.01) & (np.abs(co[:, 0] - head_x) < 0.02 * H)]
        if len(s):
            print("  %.2f front %.3f back %.3f" % (hq, -(s[:, 1].min() - hy) / H, -(s[:, 1].max() - hy) / H))
    print("HEAD BONE h %.3f  neck bone h %.3f" % (((arm.matrix_world @ bones["Head"].head_local).z - lo[2]) / H, ((arm.matrix_world @ bones["neck"].head_local).z - lo[2]) / H))
    sys.exit(0)

# ---- face shape keys, from the measured heights (fractions of the figure's height)
F = dict(kv.split("=") for kv in a.face.split(","))
F = {k: float(v) for k, v in F.items()}
neck, mouth, chin, eye = F["neck"], F["mouth"], F["chin"], F["eye"]
eye_dx, eye_cx, mouth_w = F["eye_dx"], F.get("eye_cx", 0.0), F.get("mouth_w", 0.022)
hx = head_x + F.get("cx", 0.0) * H               # centre line of the face
hy = (arm.matrix_world @ bones["Head"].head_local).y
front = -(co[:, 1] - hy)                         # how far in front of the head bone, world units
depth = F.get("face", 0.07) * H                  # head bone to the face surface
mx = np.abs(co[:, 0] - hx) / H
ws = 1.0 - smooth(mouth - 0.003, mouth + 0.0005, hn)
mask0 = smooth(depth * 0.25, depth * 0.7, front) * smooth(neck, neck + 0.02, hn)
mask = smooth(depth * 0.25, depth * 0.7, front)
td = np.clip((mouth - hn) / max(mouth - chin, 0.001), 0.0, 1.0)
mask = mask * (1.0 - smooth(mouth_w * 0.30 + (mouth_w * 1.0) * td, mouth_w * 1.08 + (mouth_w * 1.52) * td, mx))
mask = mask * smooth(chin - 0.02, chin - 0.004, hn)
wj = ws * mask
head_u = (1.0 - neck) * H
amp = head_u * 0.034
d_jaw = np.zeros_like(co); d_jaw[:, 2] = -wj * amp; d_jaw[:, 1] = wj * amp * 0.3
openh = head_u * 0.050
lash = eye + 0.5 * openh / H
ex = np.abs(np.abs(co[:, 0] - hx - eye_cx * H) - eye_dx * H)
we = (1.0 - smooth(head_u * 0.085, head_u * 0.15, ex)) * mask0
lid = smooth(eye - 0.6 * openh / H, lash, hn) * (1.0 - smooth(lash + 0.3 * openh / H, lash + 2.4 * openh / H, hn))
d_blink = np.zeros_like(co); d_blink[:, 2] = -we * lid * openh * 1.05
bw = smooth(lash, lash + 0.8 * openh / H, hn) * (1.0 - smooth(lash + 2.2 * openh / H, lash + 4.5 * openh / H, hn))
bx = 1.0 - smooth(head_u * 0.30, head_u * 0.50, np.abs(co[:, 0] - hx - eye_cx * H))
d_brow = np.zeros_like(co); d_brow[:, 2] = bw * bx * mask0 * openh * 0.55
R = M.to_3x3().inverted()
Rn = np.array(R)
if not mesh.data.shape_keys:
    mesh.shape_key_add(name="Basis")
base = np.array([v.co[:] for v in mesh.data.vertices])
for name, dw in [("jaw", d_jaw), ("blink", d_blink), ("brow_up", d_brow), ("brow_dn", -d_brow)]:
    k = mesh.shape_key_add(name=name)
    loc = base + dw @ Rn.T
    k.data.foreach_set("co", loc.ravel())
    print("shape", name, "moves", int((np.abs(dw).sum(1) > 1e-6).sum()), "verts, max", round(float(np.abs(dw).max()) / H, 5), "H")
# data for the mouth interior: UV2 = (|x| off the centre line / H, height), colour red = jaw mask
uv2 = mesh.data.uv_layers.new(name="face")
col = mesh.data.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
li = np.array([l.vertex_index for l in mesh.data.loops])
uvd = np.stack([mx[li], hn[li]], 1)
uv2.data.foreach_set("uv", uvd.ravel())
cd = np.zeros((len(li), 4)); cd[:, 0] = mask[li]; cd[:, 3] = 1.0
col.data.foreach_set("color", cd.ravel())

# ---- the other clips: same rig, different action
arm.data.pose_position = "POSE"
actions = [act_main] if act_main else []
for spec in a.clips:
    name, path = spec.split("=")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    arm2 = next(o for o in new if o.type == "ARMATURE")
    act = arm2.animation_data.action
    act.name = name
    act.use_fake_user = True
    actions.append(act)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
# every action becomes an NLA strip on the one armature, which is how the exporter finds them
arm.animation_data.action = None
for tr in list(arm.animation_data.nla_tracks):
    arm.animation_data.nla_tracks.remove(tr)
for act in actions:
    tr = arm.animation_data.nla_tracks.new()
    tr.name = act.name
    st = tr.strips.new(act.name, int(act.frame_range[0]), act)
    st.name = act.name
    print("clip", act.name, "frames", tuple(int(x) for x in act.frame_range))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=a.dst, export_format="GLB", export_yup=True, use_selection=True,
    export_image_format="WEBP", export_image_quality=88, export_animations=True, export_animation_mode="NLA_TRACKS",
    export_morph=True, export_morph_normal=False, export_skins=True, export_optimize_animation_size=True,
    export_attributes=True, export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True, export_all_vertex_colors=True)
print("WROTE", a.dst, os.path.getsize(a.dst) // 1024, "KB")
