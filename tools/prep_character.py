"""Prepare a generated character GLB for the game: turn it to face +Z (glTF), stand it on the
origin, shrink textures, and write a clean GLB. Also renders an orthographic front view of the
head with a measuring grid, used to set the rig heights in scripts/Main.gd (RIG).

usage: python3 tools/prep_character.py in.glb out.glb grid.png [--yaw degrees] [--tex 2048]
"""
import bpy, sys, math, os
import numpy as np
from mathutils import Vector, Matrix
a = sys.argv[1:]
src, dst, grid = a[0], a[1], a[2]
yaw = float(a[a.index("--yaw") + 1]) if "--yaw" in a else 0.0
tex = int(a[a.index("--tex") + 1]) if "--tex" in a else 2048
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
meshes = [o for o in sc.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
ob.parent = None
ob.matrix_world = Matrix.Rotation(math.radians(yaw), 4, "Z") @ ob.matrix_world
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = np.array([v.co[:] for v in ob.data.vertices])
lo, hi = co.min(0), co.max(0)
off = Vector((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
ob.data.transform(Matrix.Translation(off))
co = co + np.array(off)
lo, hi = co.min(0), co.max(0); H = hi[2]
print("SIZE", (hi - lo).round(3), "verts", len(co), "tris", sum(len(p.vertices) - 2 for p in ob.data.polygons))
for img in bpy.data.images:
    if img.size[0] > tex:
        img.scale(tex, tex)
# ---- measuring render: orthographic, front (the model faces -Y in Blender = +Z in glTF)
sc.render.engine = "CYCLES"; sc.cycles.samples = 16; sc.cycles.use_denoising = True
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.6, 0.6, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 1.6
cam = bpy.data.objects.new("c", bpy.data.cameras.new("c")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"
span = float(a[a.index("--span") + 1]) if "--span" in a else 0.24    # fraction of height shown
top = float(a[a.index("--top") + 1]) if "--top" in a else 1.0
cam.data.ortho_scale = span * H
cz = (top - span / 2) * H
cam.location = (0, -5, cz); cam.rotation_euler = (math.radians(90), 0, 0)
sc.render.resolution_x = 900; sc.render.resolution_y = 900
sc.render.filepath = grid
bpy.ops.render.render(write_still=True)
from PIL import Image, ImageDraw
im = Image.open(grid).convert("RGB"); d = ImageDraw.Draw(im)
npp = span / 900.0
t = math.floor(top / 0.005) * 0.005
while t > top - span:
    y = (top - t) / npp
    major = round(t * 1000) % 10 == 0
    d.line([(0, y), (900, y)], fill=(0, 255, 0) if major else (0, 110, 0), width=1)
    if major:
        d.text((4, y - 11), "%.2f" % t, fill=(0, 255, 0))
    t -= 0.005
for k in range(-11, 12):
    dx = k * 0.01
    x = 450 + dx / npp          # image right = model +X
    d.line([(x, 0), (x, 900)], fill=(255, 70, 70) if k % 5 == 0 else (120, 40, 40), width=1)
    if k % 5 == 0:
        d.text((x + 2, 884), "%+.2f" % dx, fill=(255, 90, 90))
im.save(grid)
# profile: how far forward the surface is at each height, on the centre line
hn = co[:, 2] / H
print("PROFILE h : front(-y)/H , halfwidth/H")
for hq in np.arange(0.70, 1.0, 0.02):
    s = co[(hn >= hq) & (hn < hq + 0.02)]
    c = s[np.abs(s[:, 0]) < 0.02 * H]
    if len(s) and len(c):
        print("  %.2f front %.3f back %.3f width %.3f" % (hq, -c[:, 1].min() / H, -c[:, 1].max() / H, (s[:, 0].max() - s[:, 0].min()) / H))
bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_yup=True, use_selection=True, export_image_format="WEBP", export_image_quality=88)
print("WROTE", dst, os.path.getsize(dst) // 1024, "KB")
