"""Cut stray geometry off a prepared character (e.g. hair wisps the generator turned into loops).
python3 tools/trim_character.py in.glb out.glb --x 0.088 --h 0.80 0.905
Deletes vertices further than --x (fraction of height) from the centre line between the two --h heights."""
import bpy, sys, os, argparse, bmesh
ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("dst")
ap.add_argument("--x", type=float, required=True)
ap.add_argument("--h", type=float, nargs=2, required=True)
ap.add_argument("--cx", type=float, default=0.0)
ap.add_argument("--lum", type=float, default=0.0, help="only delete vertices whose texture colour is brighter than this (keeps dark hair)")
a = ap.parse_args()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a.src)
ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
zs = [v.co.z for v in ob.data.vertices]; xs = [v.co.x for v in ob.data.vertices]
z0, H = min(zs), max(zs) - min(zs); cx = (min(xs) + max(xs)) / 2 + a.cx * H
bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
kill = [v for v in bm.verts if abs(v.co.x - cx) / H > a.x and a.h[0] < (v.co.z - z0) / H < a.h[1]]
if a.lum > 0.0:
    import numpy as np
    img = next(n.image for n in ob.data.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.outputs[0].links and n.outputs[0].links[0].to_socket.name == "Base Color")
    w, hh = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(hh, w, 4)
    uvl = bm.loops.layers.uv.active
    def lum(v):
        u = v.link_loops[0][uvl].uv
        c = px[min(hh - 1, max(0, int(u.y % 1.0 * hh))), min(w - 1, max(0, int(u.x % 1.0 * w)))]
        return 0.3 * c[0] + 0.6 * c[1] + 0.1 * c[2]
    kill = [v for v in kill if v.link_loops and lum(v) > a.lum]
print("deleting", len(kill), "verts")
ks = set(kill)
near = {e.other_vert(v) for v in kill for e in v.link_edges} - ks
bmesh.ops.delete(bm, geom=kill, context="VERTS")
# close the holes that leaves, and give the new faces the texture coordinates their corners already had
uv = bm.loops.layers.uv.active
known = {}
for f in bm.faces:
    for l in f.loops:
        known.setdefault(l.vert.index, l[uv].uv.copy())
old = set(bm.faces)
bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary and e.verts[0] in near and e.verts[1] in near], sides=0)
new = [f for f in bm.faces if f not in old]
for f in new:
    for l in f.loops:
        if l.vert.index in known:
            l[uv].uv = known[l.vert.index]
bmesh.ops.triangulate(bm, faces=new)
bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f not in old])
print("filled", len(new), "holes")
bm.to_mesh(ob.data); bm.free()
bpy.ops.export_scene.gltf(filepath=a.dst, export_format="GLB", export_yup=True, use_selection=True, export_image_format="WEBP", export_image_quality=92)
print("WROTE", a.dst, os.path.getsize(a.dst) // 1024, "KB")
