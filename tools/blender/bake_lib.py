# Shared helpers for baking procedural textures in Blender (run inside
# Blender, e.g. through the MCP bridge with exec(open(path).read())).
#
# A texture set is a function that builds shader nodes on a flat UV plane
# (u, v in 0..1) and returns sockets for its channels. bake_set() bakes each
# channel to a PNG: colour and data channels through an Emission shader
# (bake type EMIT), the normal map from a Bump on the height channel (bake
# type NORMAL, tangent space).

import bpy
import math
import os

TAU = math.tau


class Graph:
    """Thin helper over a material's node tree."""

    def __init__(self, material):
        self.material = material
        self.nodes = material.node_tree.nodes
        self.links = material.node_tree.links

    def node(self, kind, **inputs):
        n = self.nodes.new(kind)
        for key, value in inputs.items():
            if key.startswith('_'):
                setattr(n, key[1:], value)
            else:
                self.set(n.inputs[key], value)
        return n

    def set(self, socket, value):
        if hasattr(value, 'is_linked') or hasattr(value, 'links'):
            self.links.new(value, socket)
        else:
            socket.default_value = value

    def math(self, op, a, b=0.0, clamp=False):
        n = self.nodes.new('ShaderNodeMath')
        n.operation = op
        n.use_clamp = clamp
        self.set(n.inputs[0], a)
        self.set(n.inputs[1], b)
        return n.outputs[0]

    def vmath(self, op, a, b=None):
        n = self.nodes.new('ShaderNodeVectorMath')
        n.operation = op
        self.set(n.inputs[0], a)
        if b is not None:
            self.set(n.inputs[1], b)
        return n.outputs['Vector'] if op not in ('DOT_PRODUCT', 'LENGTH', 'DISTANCE') else n.outputs['Value']

    def combine(self, x, y, z):
        n = self.nodes.new('ShaderNodeCombineXYZ')
        self.set(n.inputs[0], x)
        self.set(n.inputs[1], y)
        self.set(n.inputs[2], z)
        return n.outputs[0]

    def mix(self, factor, a, b):
        """Colour mix: a where factor is 0, b where it is 1."""
        n = self.nodes.new('ShaderNodeMix')
        n.data_type = 'RGBA'
        self.set(n.inputs['Factor'], factor)
        self.set(n.inputs[6], a)
        self.set(n.inputs[7], b)
        return n.outputs[2]

    def mixf(self, factor, a, b):
        return self.math('ADD', self.math('MULTIPLY', a, self.math('SUBTRACT', 1.0, factor)), self.math('MULTIPLY', b, factor))

    def ramp(self, value, stops):
        """stops: [(position, (r, g, b, a)), ...]"""
        n = self.nodes.new('ShaderNodeValToRGB')
        self.set(n.inputs[0], value)
        els = n.color_ramp.elements
        while len(els) > 1:
            els.remove(els[-1])
        els[0].position = stops[0][0]
        els[0].color = stops[0][1]
        for pos, col in stops[1:]:
            e = els.new(pos)
            e.color = col
        return n.outputs['Color']

    def uv(self):
        tc = self.nodes.new('ShaderNodeTexCoord')
        sep = self.nodes.new('ShaderNodeSeparateXYZ')
        self.links.new(tc.outputs['UV'], sep.inputs[0])
        return sep.outputs[0], sep.outputs[1]

    def tile_noise(self, u, v, scale, detail=4.0, roughness=0.5, periods=(1, 1)):
        """Noise that repeats every 1/periods in u and v: the plane is wrapped
        onto a 4D torus, so opposite edges match."""
        pu, pv = periods
        au = self.math('MULTIPLY', u, TAU * pu)
        av = self.math('MULTIPLY', v, TAU * pv)
        k = scale / TAU
        vec = self.combine(self.math('MULTIPLY', self.math('COSINE', au), k), self.math('MULTIPLY', self.math('SINE', au), k), self.math('MULTIPLY', self.math('COSINE', av), k))
        n = self.nodes.new('ShaderNodeTexNoise')
        n.noise_dimensions = '4D'
        self.set(n.inputs['Vector'], vec)
        self.set(n.inputs['W'], self.math('MULTIPLY', self.math('SINE', av), k))
        self.set(n.inputs['Detail'], detail)
        self.set(n.inputs['Roughness'], roughness)
        return n.outputs['Fac']

    def cells(self, u, v, cols, rows, seed=0.0):
        """Grid cells: (edge distance in texture units, per-cell random 0..1,
        position inside the cell fu, fv in 0..1). The edge distance is 0 on a
        cell border."""
        cu = self.math('MULTIPLY', u, cols)
        cv = self.math('MULTIPLY', v, rows)
        fu = self.math('FRACT', cu)
        fv = self.math('FRACT', cv)
        eu = self.math('MINIMUM', fu, self.math('SUBTRACT', 1.0, fu))
        ev = self.math('MINIMUM', fv, self.math('SUBTRACT', 1.0, fv))
        # Scale each edge distance by the cell's own size so seams keep one
        # width in texture space.
        edge = self.math('MINIMUM', self.math('DIVIDE', eu, cols), self.math('DIVIDE', ev, rows))
        cell = self.combine(self.math('FLOOR', cu), self.math('FLOOR', cv), float(cols * 7 + rows) + seed)
        wn = self.nodes.new('ShaderNodeTexWhiteNoise')
        wn.noise_dimensions = '3D'
        self.links.new(cell, wn.inputs['Vector'])
        return edge, wn.outputs['Value'], fu, fv


def fresh_plane(name='BakePlane'):
    for o in list(bpy.data.objects):
        if o.name.startswith(name):
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.mesh.primitive_plane_add(size=2.0)
    plane = bpy.context.active_object
    plane.name = name
    return plane


def new_material(name):
    old = bpy.data.materials.get(name)
    if old:
        bpy.data.materials.remove(old)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.node_tree.nodes.clear()
    return mat


def _image(name, size, data):
    old = bpy.data.images.get(name)
    if old:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, width=size[0], height=size[1], alpha=False, float_buffer=False)
    img.colorspace_settings.name = 'Non-Color' if data else 'sRGB'
    return img


def bake_set(set_name, build, size, out_dir, channels):
    """channels: dict channel -> 'color' | 'data' | 'normal'. build(graph)
    returns {'color': socket, 'roughness': socket, 'height': socket, ...}."""
    scene = bpy.context.scene
    try:
        scene.render.engine = 'CYCLES'
    except TypeError:
        pass
    scene.cycles.samples = 1
    scene.cycles.use_denoising = False
    scene.render.bake.margin = 0
    plane = fresh_plane()
    mat = new_material(set_name)
    plane.data.materials.clear()
    plane.data.materials.append(mat)
    g = Graph(mat)
    sockets = build(g)
    out = g.node('ShaderNodeOutputMaterial')
    target = g.node('ShaderNodeTexImage')
    mat.node_tree.nodes.active = target
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for channel, kind in channels.items():
        img = _image('%s_%s' % (set_name, channel), size, kind != 'color')
        target.image = img
        for link in list(out.inputs['Surface'].links):
            g.links.remove(link)
        if kind == 'normal':
            bsdf = g.node('ShaderNodeBsdfPrincipled')
            bump = g.node('ShaderNodeBump', Strength=1.0, Distance=0.02)
            g.links.new(sockets['height'], bump.inputs['Height'])
            g.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
            g.links.new(bsdf.outputs[0], out.inputs['Surface'])
            scene.cycles.bake_type = 'NORMAL'
            scene.render.bake.normal_space = 'TANGENT'
            bpy.ops.object.bake(type='NORMAL')
        else:
            emit = g.node('ShaderNodeEmission')
            g.links.new(sockets[channel], emit.inputs['Color'])
            g.links.new(emit.outputs[0], out.inputs['Surface'])
            scene.cycles.bake_type = 'EMIT'
            bpy.ops.object.bake(type='EMIT')
        path = os.path.join(out_dir, '%s.png' % channel)
        img.filepath_raw = path
        img.file_format = 'PNG'
        img.save()
        written.append(path)
    return written
