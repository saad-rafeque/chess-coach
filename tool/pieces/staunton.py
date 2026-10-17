"""Models a Staunton chess set in Blender and renders every piece in several materials.

Run with Blender 4.5 (free, blender.org):
  blender -b -P tool/pieces/staunton.py -- <out dir> <style>[,<style>...] [size]

Each style becomes <out dir>/<style>/{w,b}{K,Q,R,B,N,P}.png on a transparent background, lit like a
studio photo, with a soft contact shadow. The models are original work of this project (GPL-3.0).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/pieces"
STYLES = argv[1].split(",") if len(argv) > 1 else ["classic"]
SIZE = int(argv[2]) if len(argv) > 2 else 384
ONLY = argv[3] if len(argv) > 3 else "KQRBNP"
SAMPLES = int(argv[4]) if len(argv) > 4 else 128


# ----------------------------------------------------------------------------- geometry helpers --

def catmull(points, per=6):
    """Smooths a polyline of (r, z) points with Catmull-Rom splines, keeping the end points."""
    out = []
    pts = [points[0]] + points + [points[-1]]
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    out.append(points[-1])
    return out


def lathe(name, profile, steps=96, smooth=True):
    """Revolves a profile of (radius, height) points around Z. The profile starts and ends on the axis."""
    pts = catmull(profile) if smooth else profile
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    verts = [bm.verts.new((max(r, 0.0), 0.0, z)) for r, z in pts]
    for a, b in zip(verts, verts[1:]):
        bm.edges.new((a, b))
    bmesh.ops.spin(bm, geom=bm.verts[:] + bm.edges[:], cent=(0, 0, 0), axis=(0, 0, 1), angle=math.tau, steps=steps,
                   use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for p in mesh.polygons:
        p.use_smooth = True
    return obj


def base(R, top):
    """The common turned foot: a wide disc with a bevel, a cove and a bead, ending at height `top`."""
    return [(0, 0), (R, 0), (R, 0.022), (R * 0.985, 0.034), (R * 0.95, 0.046), (R * 0.9, 0.052), (R * 0.86, 0.06),
            (R * 0.84, 0.072), (R * 0.86, 0.086), (R * 0.87, 0.098), (R * 0.85, 0.11), (R * 0.79, 0.118),
            (R * 0.74, top)]


def ring(r, z, h=0.03):
    """A collar: out, round over, back in."""
    return [(r * 0.8, z), (r, z + h * 0.25), (r * 1.04, z + h * 0.5), (r, z + h * 0.75), (r * 0.8, z + h)]


def boolean(obj, cutter, op="DIFFERENCE"):
    mod = obj.modifiers.new("cut", "BOOLEAN")
    mod.operation = op
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def box(size, loc, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        m = o.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = 4
        bpy.ops.object.modifier_apply(modifier=m.name)
        for p in o.data.polygons:
            p.use_smooth = True
    return o


def sphere(r, loc):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=32, ring_count=16)
    o = bpy.context.active_object
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def finish(obj):
    """Smooth shading that keeps the turned edges crisp."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    return obj


# --------------------------------------------------------------------------------------- pieces --

def pawn():
    p = base(0.27, 0.13) + [(0.17, 0.16), (0.135, 0.2), (0.11, 0.25), (0.1, 0.27)]
    p += ring(0.15, 0.275, 0.035) + [(0.085, 0.32), (0.08, 0.335)]
    # The head: a ball.
    c, r = 0.43, 0.105
    for k in range(-62, 91, 8):
        a = math.radians(k)
        p.append((r * math.cos(a), c + r * math.sin(a)))
    p.append((0, c + r))
    return finish(lathe("P", p))


def rook():
    p = base(0.3, 0.13) + [(0.215, 0.16), (0.195, 0.22), (0.185, 0.32), (0.19, 0.42), (0.205, 0.47)]
    p += [(0.235, 0.48), (0.245, 0.495), (0.232, 0.51), (0.222, 0.52), (0.222, 0.615), (0.215, 0.625),
          (0.165, 0.625), (0.16, 0.6), (0.0, 0.6)]
    obj = lathe("R", p)
    for a in (0, 60, 120):
        boolean(obj, box((0.6, 0.06, 0.08), (0, 0, 0.64), (0, 0, math.radians(a))))
    return finish(obj)


def bishop():
    p = base(0.28, 0.13) + [(0.185, 0.16), (0.14, 0.22), (0.11, 0.31), (0.095, 0.4), (0.093, 0.42)]
    p += ring(0.14, 0.425, 0.035) + [(0.1, 0.465)] + ring(0.115, 0.47, 0.02)
    p += [(0.1, 0.5), (0.125, 0.53), (0.142, 0.57), (0.145, 0.61), (0.135, 0.65), (0.11, 0.69), (0.075, 0.72),
          (0.045, 0.735), (0.03, 0.74)]
    c, r = 0.77, 0.032
    for k in range(-60, 91, 15):
        a = math.radians(k)
        p.append((r * math.cos(a), c + r * math.sin(a)))
    p.append((0, c + r))
    obj = lathe("B", p)
    # The mitre's slit, cut on the front at a slant.
    boolean(obj, box((0.5, 0.17, 0.028), (0.0, -0.08, 0.62), (0, math.radians(-38), 0)))
    return finish(obj)


def queen():
    p = base(0.31, 0.13) + [(0.205, 0.16), (0.16, 0.22), (0.125, 0.33), (0.105, 0.45), (0.1, 0.52)]
    p += ring(0.15, 0.53, 0.04) + [(0.105, 0.575), (0.1, 0.59)]
    p += [(0.115, 0.62), (0.14, 0.67), (0.165, 0.72), (0.185, 0.765), (0.192, 0.79), (0.18, 0.8), (0.14, 0.805),
          (0.11, 0.82), (0.075, 0.845), (0.045, 0.855)]
    c, r = 0.885, 0.036
    for k in range(-60, 91, 15):
        a = math.radians(k)
        p.append((r * math.cos(a), c + r * math.sin(a)))
    p.append((0, c + r))
    obj = lathe("Q", p)
    # The coronet: scallops around the rim leave eight points.
    for k in range(8):
        a = math.tau * k / 8
        boolean(obj, sphere(0.04, (0.2 * math.cos(a), 0.2 * math.sin(a), 0.815)))
    for k in range(8):
        a = math.tau * (k + 0.5) / 8
        sphere_obj = sphere(0.016, (0.19 * math.cos(a), 0.19 * math.sin(a), 0.805))
        boolean(obj, sphere_obj, "UNION")
    return finish(obj)


def king():
    p = base(0.32, 0.13) + [(0.215, 0.16), (0.17, 0.22), (0.13, 0.34), (0.11, 0.47), (0.105, 0.55)]
    p += ring(0.155, 0.56, 0.04) + [(0.11, 0.605), (0.105, 0.62)]
    p += [(0.12, 0.65), (0.148, 0.7), (0.17, 0.75), (0.18, 0.79), (0.172, 0.805), (0.13, 0.82), (0.08, 0.835),
          (0.05, 0.842), (0.04, 0.85), (0.042, 0.865), (0.0, 0.865)]
    body = lathe("K", p)
    cross = join([box((0.05, 0.04, 0.16), (0, 0, 0.935), bevel=0.012),
                  box((0.13, 0.04, 0.045), (0, 0, 0.955), bevel=0.012)], "cross")
    return finish(join([body, cross], "K"))


# Side view of the horse, facing -X: (x, z).
KNIGHT_OUTLINE = [
    (-0.15, 0.15), (-0.165, 0.2), (-0.16, 0.26), (-0.135, 0.32), (-0.115, 0.36), (-0.15, 0.385), (-0.205, 0.398),
    (-0.255, 0.41), (-0.283, 0.43), (-0.296, 0.46), (-0.292, 0.495), (-0.272, 0.52), (-0.235, 0.552),
    (-0.19, 0.592), (-0.145, 0.632), (-0.105, 0.668), (-0.085, 0.69), (-0.078, 0.725), (-0.068, 0.77),
    (-0.048, 0.738), (-0.03, 0.722), (0.0, 0.722), (0.045, 0.705), (0.09, 0.672), (0.13, 0.625), (0.165, 0.56),
    (0.19, 0.48), (0.205, 0.4), (0.208, 0.32), (0.2, 0.24), (0.19, 0.15),
]


def knight():
    foot = lathe("Nbase", base(0.3, 0.13) + [(0.215, 0.15), (0.21, 0.165), (0.0, 0.165)])
    # Extrude the outline into a head, then taper the muzzle and round everything.
    mesh = bpy.data.meshes.new("Nhead")
    bm = bmesh.new()
    outline = catmull(KNIGHT_OUTLINE + [KNIGHT_OUTLINE[0]], per=4)[:-1]
    verts = [bm.verts.new((x, -0.12, z)) for x, z in outline]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.y += 0.24
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for v in bm.verts:
        x, z = v.co.x, v.co.z
        t = min(max((-x - 0.05) / 0.25, 0.0), 1.0)          # 0 at the neck, 1 at the nose
        k = 1.0 - 0.38 * t - 0.25 * min(max((z - 0.62) / 0.12, 0), 1)  # narrower muzzle and ears
        v.co.y *= k
    bm.to_mesh(mesh)
    bm.free()
    head = bpy.data.objects.new("Nhead", mesh)
    bpy.context.collection.objects.link(head)
    bpy.context.view_layer.objects.active = head
    m = head.modifiers.new("bevel", "BEVEL")
    m.width = 0.075
    m.segments = 8
    m.limit_method = "NONE"
    bpy.ops.object.modifier_apply(modifier=m.name)
    s = head.modifiers.new("sub", "SUBSURF")
    s.levels = 2
    bpy.ops.object.modifier_apply(modifier=s.name)
    for p in head.data.polygons:
        p.use_smooth = True
    # Eyes and nostrils.
    for y in (-0.105, 0.105):
        boolean(head, sphere(0.03, (-0.155, y * 0.72, 0.588)))
    for y in (-0.05, 0.05):
        boolean(head, sphere(0.014, (-0.288, y, 0.47)))
    # Mane: a few grooves along the back of the neck.
    for k in range(5):
        z = 0.64 - k * 0.07
        x = 0.06 + k * 0.03
        boolean(head, box((0.12, 0.5, 0.012), (x + 0.07, 0, z), (0, math.radians(-50 + k * 6), 0)))
    obj = join([foot, head], "N")
    return finish(obj)


BUILDERS = {"P": pawn, "R": rook, "B": bishop, "N": knight, "Q": queen, "K": king}


# ------------------------------------------------------------------------------------ materials --

def principled(name, color, rough=0.35, metal=0.0, coat=0.0, trans=0.0, sss=0.0, ior=1.45):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.08
    b.inputs["Transmission Weight"].default_value = trans
    b.inputs["IOR"].default_value = ior
    if sss:
        b.inputs["Subsurface Weight"].default_value = sss
        b.inputs["Subsurface Radius"].default_value = (0.05, 0.035, 0.025)
        b.inputs["Subsurface Scale"].default_value = 0.05
    return m, b


def textured(name, c1, c2, kind, scale, rough=0.35, coat=0.4, metal=0.0):
    """Wood grain (bands along the piece) or marble veins mixed between two colours."""
    m, b = principled(name, c1, rough, metal, coat)
    nt = m.node_tree
    coord = nt.nodes.new("ShaderNodeTexCoord")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*c1, 1)
    ramp.color_ramp.elements[1].color = (*c2, 1)
    if kind == "wood":
        tex = nt.nodes.new("ShaderNodeTexWave")
        tex.wave_type = "RINGS"
        tex.rings_direction = "Z"
        tex.inputs["Scale"].default_value = scale
        tex.inputs["Distortion"].default_value = 6
        tex.inputs["Detail"].default_value = 3
        ramp.color_ramp.elements[0].position = 0.25
        ramp.color_ramp.elements[1].position = 0.95
    else:
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = scale
        tex.inputs["Detail"].default_value = 12
        tex.inputs["Distortion"].default_value = 3.5
        ramp.color_ramp.elements[0].position = 0.48
        ramp.color_ramp.elements[1].position = 0.52
        ramp.color_ramp.interpolation = "EASE"
    nt.links.new(coord.outputs["Object"], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return m


def marble(name, base_color, vein_color, scale=2.2, rough=0.1, width=0.035):
    """Marble: thin, wavy veins where a noise field crosses its middle value."""
    m, b = principled(name, base_color, rough, coat=0.7)
    nt = m.node_tree
    coord = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 9
    noise.inputs["Roughness"].default_value = 0.6
    noise.inputs["Distortion"].default_value = 1.6
    sub = nt.nodes.new("ShaderNodeMath")
    sub.operation = "SUBTRACT"
    sub.inputs[1].default_value = 0.5
    absn = nt.nodes.new("ShaderNodeMath")
    absn.operation = "ABSOLUTE"
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*vein_color, 1)
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[1].color = (*base_color, 1)
    ramp.color_ramp.elements[1].position = width
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], sub.inputs[0])
    nt.links.new(sub.outputs[0], absn.inputs[0])
    nt.links.new(absn.outputs[0], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return m


def styles():
    """Each style: (white material, black material). Colours are linear RGB."""
    return {
        # Polished tournament plastic, like most online sets.
        "classic": (principled("wc", (0.8, 0.74, 0.62), 0.34, coat=0.35, sss=0.1)[0],
                    principled("bc", (0.012, 0.012, 0.014), 0.32, coat=0.5)[0]),
        # Boxwood and ebony, the traditional wooden set.
        "wood": (textured("ww", (0.62, 0.42, 0.2), (0.48, 0.28, 0.11), "wood", 9, 0.38, 0.45),
                 textured("bw", (0.05, 0.022, 0.012), (0.11, 0.05, 0.025), "wood", 9, 0.35, 0.5)),
        # Rosewood against light maple.
        "rosewood": (textured("wr", (0.8, 0.62, 0.38), (0.66, 0.46, 0.24), "wood", 7, 0.4, 0.4),
                     textured("br", (0.2, 0.045, 0.025), (0.09, 0.02, 0.012), "wood", 8, 0.35, 0.5)),
        # Carrara and Nero Marquina marble.
        "marble": (marble("wm", (0.8, 0.8, 0.78), (0.3, 0.31, 0.33)),
                   marble("bm", (0.02, 0.02, 0.022), (0.38, 0.38, 0.4), scale=1.6, width=0.014)),
        # Gold and silver.
        "metal": (principled("wg", (0.95, 0.68, 0.28), 0.22, metal=1)[0],
                  principled("bg", (0.32, 0.33, 0.36), 0.25, metal=1)[0]),
        # Frosted clear glass and smoked glass.
        "glass": (principled("wgl", (0.9, 0.95, 1.0), 0.18, trans=1, ior=1.5)[0],
                  principled("bgl", (0.12, 0.13, 0.16), 0.15, trans=1, ior=1.5)[0]),
        # Glazed porcelain: white and royal blue.
        "porcelain": (principled("wp", (0.88, 0.88, 0.86), 0.18, coat=0.8, sss=0.2)[0],
                      principled("bp", (0.025, 0.06, 0.22), 0.18, coat=0.8)[0]),
        # Soft matte, a calm modern look.
        "matte": (principled("wma", (0.8, 0.79, 0.76), 0.75)[0],
                  principled("bma", (0.07, 0.075, 0.085), 0.72)[0]),
        # Ivory and deep red lacquer.
        "ivory": (principled("wi", (0.85, 0.76, 0.58), 0.3, coat=0.5, sss=0.25)[0],
                  principled("bi", (0.28, 0.02, 0.025), 0.25, coat=0.7)[0]),
        # Brass and gunmetal.
        "brass": (principled("wb", (0.78, 0.6, 0.3), 0.32, metal=1)[0],
                  principled("bb", (0.08, 0.085, 0.095), 0.3, metal=1)[0]),
    }


# ---------------------------------------------------------------------------------------- scene --

def scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = SIZE
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Punchy"
    world = bpy.data.worlds.new("world")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.33, 0.36, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.3

    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.12
    elev = math.radians(17)
    dist = 6
    cam.location = (0, -dist * math.cos(elev), 0.47 + dist * math.sin(elev))
    cam.rotation_euler = (math.pi / 2 - elev, 0, 0)
    sc.collection.objects.link(cam)
    sc.camera = cam

    def area(name, loc, power, size, color=(1, 1, 1)):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        light.data.energy = power
        light.data.size = size
        light.data.color = color
        light.location = loc
        direction = Vector((0, 0, 0.45)) - Vector(loc)
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(light)

    area("key", (-2.2, -2.6, 3.0), 330, 1.6, (1.0, 0.96, 0.9))
    area("fill", (2.6, -2.2, 1.4), 70, 3.0, (0.85, 0.92, 1.0))
    area("rim", (0.8, 2.6, 2.6), 420, 1.2)

    bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.is_shadow_catcher = True
    return sc


def render_style(sc, style, mats):
    folder = os.path.join(OUT, style)
    os.makedirs(folder, exist_ok=True)
    for code, build in BUILDERS.items():
        if code not in ONLY:
            continue
        obj = build()
        for color, mat in (("w", mats[0]), ("b", mats[1])):
            obj.data.materials.clear()
            obj.data.materials.append(mat)
            # Knights face left on both sides, as in printed diagrams.
            sc.render.filepath = os.path.join(folder, f"{color}{code}.png")
            bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(obj, do_unlink=True)


sc = scene()
all_styles = styles()
for name in STYLES:
    render_style(sc, name, all_styles[name])
print("done", STYLES)
