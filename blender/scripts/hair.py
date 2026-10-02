"""Sculpted hair for the round characters (used by accessories.py / make_props.py).

Built for the default R15 head: a rounded box about 1.16 x 1.16 x 1.18 studs, centre at the origin,
face towards -Y, top at z = +0.59. The face decal puts the eyes around z = +0.2 and the eyebrows
around z = +0.33, so nothing comes down over the front below HAIRLINE_FRONT - hair frames the face,
it never covers it (and glasses, at y = -0.62, sit in front of any fringe).

Every style is two things:
  * a CAP: a solid shell that follows the head's real shape (a superellipsoid) down to a hairline
    that runs high at the forehead, lower over the ears and lowest at the nape, thicker on top and
    tapering to nothing at the edge, so the hair reads as volume instead of a box on the head
  * LOCKS: tapered, flattened clumps laid over the cap (or hanging off it) along the style's flow:
    a side swoop, spikes, curtains, a fringe, a ponytail... Their tips are what make it read as hair.
All of it is one mesh named "Hair" so the game recolours it per outfit; ties are "Tie".
"""

import math

import bmesh
from mathutils import Vector

# The head (half sizes) and its squareness (2 = sphere, higher = boxier; the R15 head is ~4)
HX, HY, HZ = 0.58, 0.58, 0.59
POWER = 4.0
HAIRLINE_FRONT = 0.40  # forehead hairline (eyebrows are at ~0.33)


def _s(w, e):
    return math.copysign(abs(w) ** e, w)


def head_point(theta, v, grow=0.0):
    """A point on the head's surface. theta = angle around the head from the front (0 = face, pi =
    back, +pi/2 = the head's left side, which is +X); v = angle down from the top (0 = crown,
    pi = chin). `grow` pushes it out along the surface (studs)."""
    e = 2.0 / POWER
    sx, cx = math.sin(v), math.cos(v)
    # front is -Y: theta 0 -> (0, -1)
    dx, dy = math.sin(theta), -math.cos(theta)
    p = Vector((HX * _s(sx, e) * _s(dx, e), HY * _s(sx, e) * _s(dy, e), HZ * _s(cx, e)))
    n = Vector((p.x / HX ** 2, p.y / HY ** 2, p.z / HZ ** 2)).normalized()
    return p + n * grow, n


def hairline_z(theta, front=HAIRLINE_FRONT, side=-0.02, nape=-0.42):
    """How far down the hair comes at angle theta: high at the forehead, lower over the ears and
    lowest at the nape (smoothly blended)."""
    a = abs(math.atan2(math.sin(theta), math.cos(theta)))  # 0 front .. pi back
    if a < 0.7:
        return front
    if a < 1.6:
        t = (a - 0.7) / 0.9
        t = t * t * (3 - 2 * t)
        return front + (side - front) * t
    t = (a - 1.6) / (math.pi - 1.6)
    t = t * t * (3 - 2 * t)
    return side + (nape - side) * t


def _v_for_z(theta, z):
    lo, hi = 0.0, math.pi
    for _ in range(30):
        mid = (lo + hi) / 2
        if head_point(theta, mid)[0].z > z:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def cap(bm, thickness=0.09, edge=0.012, lon=40, rows=12, line=hairline_z, top_puff=0.03):
    """The solid hair shell: outer surface pushed out by `thickness` (a little more at the crown),
    tapering to `edge` at the hairline, closed against the scalp underneath."""
    outer, inner = [], []
    for i in range(lon):
        theta = i / lon * 2 * math.pi
        vmax = _v_for_z(theta, line(theta))
        o_col, i_col = [], []
        for j in range(rows + 1):
            t = j / rows
            v = vmax * t
            # thick on top, thinning towards the hairline (a soft, rounded edge)
            taper = 1 - t ** 2.2
            grow = edge + (thickness - edge) * taper + top_puff * (1 - t) ** 3
            o_col.append(bm.verts.new(head_point(theta, v, grow)[0]))
            i_col.append(bm.verts.new(head_point(theta, v, -0.01)[0]))
        outer.append(o_col)
        inner.append(i_col)
    for i in range(lon):
        a, b = outer[i], outer[(i + 1) % lon]
        ia, ib = inner[i], inner[(i + 1) % lon]
        for j in range(rows):
            bm.faces.new((a[j], b[j], b[j + 1], a[j + 1]))
            bm.faces.new((ia[j + 1], ib[j + 1], ib[j], ia[j]))
        # close the rim at the hairline
        bm.faces.new((a[rows], b[rows], ib[rows], ia[rows]))
    # the crown: both shells meet at a point (j = 0 rows are all the same point - fine at this size)


def lock(bm, points, width=0.14, thickness=0.06, tip=0.15, sides=6, out=None, root_width=None):
    """A tapered, flattened clump of hair along `points` (a list of Vectors, root first). It's
    widest near the root and narrows to `tip` x width at the end; flattened so it lies along the
    surface (normal = `out`, or away from the head centre)."""
    pts = [Vector(p) for p in points]
    # smooth the path (Catmull-Rom, 4 samples per span)
    path = []
    for k in range(len(pts) - 1):
        p0 = pts[max(k - 1, 0)]
        p1, p2 = pts[k], pts[k + 1]
        p3 = pts[min(k + 2, len(pts) - 1)]
        for s in range(4):
            t = s / 4
            t2, t3 = t * t, t * t * t
            path.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                               + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    path.append(pts[-1])
    n = len(path)
    rings = []
    rw = root_width if root_width is not None else width
    for i, p in enumerate(path):
        f = i / (n - 1)
        ahead = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)])
        if ahead.length < 1e-6:
            ahead = Vector((0, 0, -1))
        ahead.normalize()
        normal = (out(p) if out else p.normalized())
        side = ahead.cross(normal)
        if side.length < 1e-5:
            side = ahead.cross(Vector((1, 0, 0)))
        side.normalize()
        normal = side.cross(ahead).normalized()
        # width: swells a little after the root, then tapers to the tip
        w = (rw + (width - rw) * min(f * 4, 1)) * (1 - (1 - tip) * f ** 1.4)
        th = thickness * (1 - 0.7 * f)
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring.append(bm.verts.new(p + side * math.cos(a) * w * 0.5 + normal * math.sin(a) * th * 0.5))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(sides):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
    end = bm.verts.new(path[-1] + (path[-1] - path[-2]).normalized() * 0.02)
    for k in range(sides):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % sides], end))
    bm.faces.new(list(reversed(rings[0])))


def surface_path(controls, grow=0.1):
    """(theta, z) pairs on the head -> 3D points just over the cap."""
    out = []
    for theta, z in controls:
        out.append(head_point(theta, _v_for_z(theta, z), grow)[0])
    return out


def ball(bm, radius, center, scale=(1, 1, 1), segments=10, rings=6):
    geom = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    for v in geom["verts"]:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + Vector(center)


def ring(bm, radius, tube, center, axis="Z", segments=14, sides=6):
    rings = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        r = []
        for k in range(sides):
            b = 2 * math.pi * k / sides
            local = Vector((math.cos(a) * (radius + math.cos(b) * tube), math.sin(a) * (radius + math.cos(b) * tube),
                            math.sin(b) * tube))
            if axis == "Y":
                local = Vector((local.x, local.z, local.y))
            elif axis == "X":
                local = Vector((local.z, local.y, local.x))
            r.append(bm.verts.new(local + Vector(center)))
        rings.append(r)
    for i in range(segments):
        for k in range(sides):
            bm.faces.new((rings[i][k], rings[(i + 1) % segments][k], rings[(i + 1) % segments][(k + 1) % sides],
                          rings[i][(k + 1) % sides]))


# --- Styles -------------------------------------------------------------------------------------

def swoop(bm):
    """Side-swept: short at the back and sides, a big swoop from the crown across the forehead to
    one side, ending in pointed tips just above the eyebrow, plus a lifted quiff at the front."""
    cap(bm, thickness=0.1)
    # the swoop: locks from the back of the crown, over the top, sweeping to the head's right (-X)
    for k in range(9):
        start = 0.5 + k * 0.18
        lock(bm, surface_path([
            (math.pi - 0.3 + k * 0.08, 0.55),
            (math.pi * 0.55 - k * 0.05, 0.62),
            (0.35 - k * 0.12, 0.58),
            (-0.35 - k * 0.12, HAIRLINE_FRONT + 0.03 + k * 0.012),
            (-0.75 - k * 0.1, HAIRLINE_FRONT + 0.0),
        ], grow=0.1 + start * 0.01), width=0.2, thickness=0.09, tip=0.1)
    # quiff tips lifting off the front
    for k in range(4):
        base = head_point(0.2 - k * 0.22, _v_for_z(0.2 - k * 0.22, 0.5), 0.12)[0]
        lock(bm, [base, base + Vector((-0.08, -0.12, 0.12)), base + Vector((-0.16, -0.2, 0.1))],
             width=0.14, thickness=0.07, tip=0.05)
    # tidy sides: short combed locks going back over the ears
    for side in (-1, 1):
        for k in range(4):
            th = side * (1.2 + k * 0.25)
            lock(bm, surface_path([(th, 0.35), (th + side * 0.35, 0.12), (th + side * 0.55, 0.0)], grow=0.08),
                 width=0.16, thickness=0.06, tip=0.3)


def spiky(bm):
    """Anime spikes: a close cap with spikes fanning up and back from the crown, a few falling
    forward over the forehead (stopping above the brows)."""
    cap(bm, thickness=0.07)
    spikes = [
        # theta, z of the root, direction (x, y, z), length
        (0.0, 0.5, (0.0, -0.55, 0.65), 0.42), (0.45, 0.5, (0.25, -0.5, 0.65), 0.4),
        (-0.45, 0.5, (-0.25, -0.5, 0.65), 0.4), (0.0, 0.58, (0.0, 0.1, 1.0), 0.48),
        (0.9, 0.48, (0.55, -0.1, 0.75), 0.42), (-0.9, 0.48, (-0.55, -0.1, 0.75), 0.42),
        (1.5, 0.35, (0.8, 0.15, 0.45), 0.38), (-1.5, 0.35, (-0.8, 0.15, 0.45), 0.38),
        (2.2, 0.4, (0.55, 0.6, 0.45), 0.42), (-2.2, 0.4, (-0.55, 0.6, 0.45), 0.42),
        (math.pi, 0.45, (0.0, 0.8, 0.35), 0.45), (2.7, 0.1, (0.3, 0.9, -0.1), 0.35),
        (-2.7, 0.1, (-0.3, 0.9, -0.1), 0.35), (1.2, 0.56, (0.35, 0.2, 0.9), 0.4),
        (-1.2, 0.56, (-0.35, 0.2, 0.9), 0.4), (2.0, 0.55, (0.3, 0.5, 0.8), 0.4),
        (-2.0, 0.55, (-0.3, 0.5, 0.8), 0.4),
    ]
    for theta, z, d, length in spikes:
        base = head_point(theta, _v_for_z(theta, z), 0.05)[0]
        d = Vector(d).normalized()
        bend = Vector((0, 0, -0.08)) if d.z < 0.3 else Vector((0, 0, 0.03))
        lock(bm, [base, base + d * length * 0.5 + bend, base + d * length],
             width=0.24, thickness=0.14, tip=0.02, sides=6)
    # forelocks over the forehead
    for k, x in enumerate((-0.28, 0.0, 0.28)):
        base = head_point(x, _v_for_z(x, 0.52), 0.1)[0]
        lock(bm, [base, base + Vector((x * 0.3, -0.16, -0.05)), base + Vector((x * 0.4 + 0.04 * (k - 1), -0.2, -0.13))],
             width=0.16, thickness=0.07, tip=0.05)


def long_hair(bm):
    """Long and straight with a centre part: curtains framing the face down past the shoulders,
    a full back panel of locks, tips separating at the bottom."""
    cap(bm, thickness=0.1, line=lambda t: hairline_z(t, front=0.42, side=-0.1, nape=-0.3))
    # centre part: locks from the part line sweeping down each side
    for side in (-1, 1):
        for k in range(9):
            th = side * (0.68 + k * 0.2)  # frames the face: starts beside it, never in front
            path = surface_path([(side * 0.02, 0.6), (th * 0.6, 0.48), (th, 0.15)], grow=0.11)
            last = path[-1]
            outdir = Vector((last.x, last.y, 0)).normalized()
            # hang down past the shoulders, flaring out slightly over the body
            path += [last + Vector((0, 0, -0.45)) + outdir * 0.06,
                     last + Vector((0, 0, -0.95)) + outdir * 0.14 + Vector((0, 0.05, 0)),
                     last + Vector((0, 0, -1.25)) + outdir * 0.16 + Vector((0, 0.06 * (k % 2), 0))]
            lock(bm, path, width=0.36, thickness=0.11, tip=0.3)
    # the back: a solid panel, then a wide fall of locks over it
    nape = head_point(math.pi, _v_for_z(math.pi, -0.2), 0.08)[0]
    lock(bm, [nape + Vector((0, 0, 0.5)), nape, nape + Vector((0, 0.06, -0.5)), nape + Vector((0, 0.1, -0.9))],
         width=1.05, thickness=0.14, tip=0.85, out=lambda p: Vector((0, 1, 0)))
    for k in range(10):
        th = math.pi + (k - 4.5) * 0.2
        path = surface_path([(th, 0.55), (th, 0.2), (th, -0.2)], grow=0.11)
        last = path[-1]
        path += [last + Vector((0, 0.05, -0.5)), last + Vector((0, 0.1, -0.95 - 0.06 * (k % 2)))]
        lock(bm, path, width=0.36, thickness=0.12, tip=0.3)


def bob(bm):
    """A chin-length bob: a straight blunt fringe above the brows, sides that curve in under the
    jaw, the back rounded and full."""
    cap(bm, thickness=0.12, line=lambda t: hairline_z(t, front=0.38, side=-0.3, nape=-0.38))
    # blunt fringe: a row of short locks ending in a straight line above the eyebrows
    for k in range(9):
        th = -0.75 + k * 0.1875
        top = head_point(th, _v_for_z(th, 0.58), 0.12)[0]
        mid = head_point(th, _v_for_z(th, 0.46), 0.14)[0]
        end = head_point(th, _v_for_z(th, 0.37), 0.15)[0]
        lock(bm, [top, mid, end], width=0.17, thickness=0.08, tip=0.7)
    # side curtains that tuck in under the chin
    for side in (-1, 1):
        for k in range(4):
            th = side * (0.95 + k * 0.32)
            path = surface_path([(th, 0.5), (th, 0.1), (th, -0.25)], grow=0.13)
            last = path[-1]
            inward = -Vector((last.x, last.y, 0)).normalized()
            path += [last + Vector((0, 0, -0.12)) + inward * 0.04, last + Vector((0, 0, -0.18)) + inward * 0.12]
            lock(bm, path, width=0.25, thickness=0.1, tip=0.5)
    for k in range(6):
        th = math.pi + (k - 2.5) * 0.3
        path = surface_path([(th, 0.5), (th, 0.0), (th, -0.32)], grow=0.13)
        last = path[-1]
        path.append(last + Vector((0, -0.08, -0.1)))
        lock(bm, path, width=0.28, thickness=0.1, tip=0.5)


def ponytail(bm, tie_material_bm=None):
    """Pulled back: a sleek cap with comb lines running back to a high tie, then a thick ponytail
    that swings down in an S-curve and splits into a tuft at the end."""
    cap(bm, thickness=0.07, line=lambda t: hairline_z(t, front=0.42, side=0.0, nape=-0.35))
    tie_at = head_point(math.pi, _v_for_z(math.pi, 0.32), 0.1)[0]
    # comb lines sweeping back to the tie
    for k in range(10):
        th = -2.6 + k * 0.58
        if abs(th) < 0.05:
            th = 0.05
        start = head_point(th, _v_for_z(th, hairline_z(th) + 0.06), 0.07)[0]
        crown = head_point(th * 0.5, 0.35, 0.1)[0]
        lock(bm, [start, crown, tie_at + Vector((0, -0.05, 0.02))], width=0.16, thickness=0.05, tip=0.5)
    # the tail itself: a few thick locks twisting together
    for k in range(5):
        a = k / 5 * 2 * math.pi
        o = Vector((math.cos(a) * 0.05, 0, math.sin(a) * 0.05))
        lock(bm, [tie_at + o, tie_at + Vector((0, 0.3, 0.05)) + o, tie_at + Vector((0, 0.42, -0.35)) + o * 1.3,
                  tie_at + Vector((0, 0.32, -0.8)) + o * 1.8, tie_at + Vector((0, 0.4, -1.05)) + o * 2.4],
             width=0.2, thickness=0.12, tip=0.15, out=lambda p: Vector((p.x, 0.0, 0.3)).normalized()
             if abs(p.x) > 0.01 else Vector((1, 0, 0)))
    if tie_material_bm is not None:
        ring(tie_material_bm, 0.11, 0.045, tie_at + Vector((0, 0.08, 0.0)), axis="Y")


def afro(bm):
    """A big round afro: a full ball of tight curls (bumps) sitting over and around the head."""
    cap(bm, thickness=0.12, line=lambda t: hairline_z(t, front=0.42, side=-0.05, nape=-0.3))
    centre = Vector((0, 0.06, 0.42))
    rng = 0
    for i in range(140):
        # Fibonacci sphere, squashed, skipping the face
        y = 1 - (i / 139) * 2
        r = math.sqrt(1 - y * y)
        a = i * 2.39996
        d = Vector((math.cos(a) * r, math.sin(a) * r, y))
        if d.z < -0.45 or (d.y < -0.35 and d.z < 0.25):
            continue
        p = centre + Vector((d.x * 0.95, d.y * 0.92, d.z * 0.72))
        rng = (rng * 1103515245 + 12345) % 2147483648
        size = 0.16 + (rng % 100) / 100 * 0.07
        ball(bm, size, p, segments=7, rings=5)


def buns(bm, tie_material_bm=None):
    """Space buns: a centre-parted cap pulled up into two round buns on top, wrapped and tied."""
    cap(bm, thickness=0.08, line=lambda t: hairline_z(t, front=0.42, side=-0.05, nape=-0.38))
    for side in (-1, 1):
        c = Vector((side * 0.36, 0.08, 0.7))
        ball(bm, 0.26, c, segments=12, rings=8)
        # wrapped strands around each bun
        for k in range(5):
            a = k / 5 * 2 * math.pi
            lock(bm, [c + Vector((math.cos(a) * 0.27, math.sin(a) * 0.27, -0.12)),
                      c + Vector((math.cos(a + 1) * 0.28, math.sin(a + 1) * 0.28, 0.05)),
                      c + Vector((math.cos(a + 2) * 0.2, math.sin(a + 2) * 0.2, 0.2))],
                 width=0.12, thickness=0.06, tip=0.3, out=lambda p, c=c: (p - c).normalized())
        if tie_material_bm is not None:
            ring(tie_material_bm, 0.2, 0.04, c + Vector((0, 0, -0.2)), axis="Z")
    # a few loose strands framing the face
    for side in (-1, 1):
        base = head_point(side * 0.75, _v_for_z(side * 0.75, 0.42), 0.09)[0]
        lock(bm, [base, base + Vector((side * 0.03, -0.04, -0.25)), base + Vector((side * 0.02, -0.03, -0.45))],
             width=0.08, thickness=0.04, tip=0.3)


def messy(bm):
    """Bed head: a full cap covered in short locks pointing every which way."""
    cap(bm, thickness=0.11)
    seed = 7
    for i in range(34):
        seed = (seed * 1103515245 + 12345) % 2147483648
        th = (seed % 1000) / 1000 * 2 * math.pi
        seed = (seed * 1103515245 + 12345) % 2147483648
        z = 0.15 + (seed % 1000) / 1000 * 0.42
        if abs(math.atan2(math.sin(th), math.cos(th))) < 0.8 and z < 0.48:
            z = 0.5
        base, normal = head_point(th, _v_for_z(th, z), 0.1)
        seed = (seed * 1103515245 + 12345) % 2147483648
        twist = ((seed % 1000) / 1000 - 0.5) * 1.6
        tangent = Vector((-normal.y, normal.x, 0)).normalized() if abs(normal.z) < 0.95 else Vector((1, 0, 0))
        d = (normal * 0.8 + tangent * twist + Vector((0, 0, 0.25))).normalized()
        lock(bm, [base, base + d * 0.12, base + d * 0.22 + tangent * twist * 0.05], width=0.17, thickness=0.08,
             tip=0.05)


STYLES = {
    "HairSwoop": swoop,
    "HairSpiky": spiky,
    "HairLong": long_hair,
    "HairBob": bob,
    "HairPonytail": ponytail,
    "HairAfro": afro,
    "HairBuns": buns,
    "HairMessy": messy,
}
TIED = {"HairPonytail", "HairBuns"}  # these also get a "Tie" mesh
