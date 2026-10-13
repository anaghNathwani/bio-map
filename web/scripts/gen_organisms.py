"""
Generates the outlines used by the bird -> microbe loader (web/src/components/BioLoader.jsx and
ios/BioMap/BioMap/Views/Common/BioLoader.swift). Each organism is a closed contour described as a
radius r(theta) around its centre, sampled at N angles, so any two of them can be morphed by simply
interpolating the radii (no self-intersection, no point matching). Both platforms embed the same
numbers, so the animation is identical.

  python3 web/scripts/gen_organisms.py          # rewrites both data files
  python3 web/scripts/gen_organisms.py --preview out.png   # contact sheet to eyeball the shapes
"""
import math, sys, json, pathlib

N = 120
D = math.pi / 180


def lobe(theta, centre_deg, amp, sigma_deg):
    """Angular Gaussian bump, wrapped around the circle."""
    d = (theta - centre_deg * D + math.pi) % (2 * math.pi) - math.pi
    return amp * math.exp(-(d / (sigma_deg * D)) ** 2 / 2)


def ellipse(theta, a, b, rot_deg=0.0, n=2.0):
    t = theta - rot_deg * D
    c, s = abs(math.cos(t) / a), abs(math.sin(t) / b)
    return (c ** n + s ** n) ** (-1 / n)


# The brand bird (same path as ios BirdMark / web bird-mark.svg), flattened to a polygon and
# ray-cast from its bounding-box centre into radii, so the loader starts as the real logo.
_BIRD = [  # start point then (c1, c2, end) cubic segments on a 48x48 canvas
    (6, 27),
    ((11, 14), (21, 7), (34, 7)), ((36.7, 7), (39, 7.4), (41, 8.1)), ((39.2, 9.1), (37.7, 10.4), (36.6, 12.1)),
    ((40, 12.4), (43, 13.4), (45, 15.3)), ((42, 15.6), (39.4, 16.7), (37.3, 18.5)),
    ((38.3, 25.2), (36.1, 31.5), (30.9, 36.1)), ((25.8, 41.4), (18.8, 43.6), (11, 42.4)),
    ((14.6, 41.4), (17.6, 39.5), (19.8, 36.9)), ((14.8, 36.5), (10.4, 33.9), (7.6, 29.8)),
    ((10.2, 30.5), (12.7, 30.4), (15, 29.4)), ((11, 27.8), (7.9, 25), (6, 21.2)),
]


def _bird_polygon():
    pts, p0 = [], _BIRD[0]
    for c1, c2, p3 in _BIRD[1:]:
        for i in range(1, 25):
            u = i / 24
            x = (1-u)**3*p0[0] + 3*(1-u)**2*u*c1[0] + 3*(1-u)*u*u*c2[0] + u**3*p3[0]
            y = (1-u)**3*p0[1] + 3*(1-u)**2*u*c1[1] + 3*(1-u)*u*u*c2[1] + u**3*p3[1]
            pts.append((x, y))
        p0 = p3
    pts.append((6, 27))
    return pts


def bird(t):
    poly = _bird_polygon()
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    dx, dy = math.cos(t), -math.sin(t)       # SVG y points down, our angles run counter-clockwise
    best = 0.0
    for (x1, y1), (x2, y2) in zip(poly, poly[1:]):
        ex, ey = x2 - x1, y2 - y1
        den = dx * ey - dy * ex
        if abs(den) < 1e-9:
            continue
        # solve c + k*d = p1 + m*e
        k = ((x1 - cx) * ey - (y1 - cy) * ex) / den
        m = ((x1 - cx) * dy - (y1 - cy) * dx) / den
        if k > 0 and 0 <= m <= 1:
            best = max(best, k)
    return best or 8.0


def butterfly(t):
    return (.20 + lobe(t, 50, .62, 24) + lobe(t, 130, .62, 24) + lobe(t, 232, .46, 22)
            + lobe(t, 308, .46, 22) + lobe(t, 80, .34, 3.5) + lobe(t, 100, .34, 3.5))


def fish(t):
    return ellipse(t, .66, .32) + lobe(t, 90, .16, 9) + lobe(t, 166, .42, 8) + lobe(t, 194, .42, 8) + lobe(t, 270, .10, 8)


def leaf(t):
    return ellipse(t, .86, .30, 38, 1.7) + lobe(t, 38, .10, 5) + lobe(t, 218, .24, 3.5)


def jellyfish(t):
    dome = .56 if math.sin(t) >= 0 else .26
    dome = .26 + .30 * max(0.0, math.sin(t)) ** .5
    tent = sum(lobe(t, a, .56 - .06 * abs(a - 270) / 30, 4.2) for a in (210, 240, 270, 300, 330))
    return dome + tent


def amoeba(t):
    return .46 + lobe(t, 25, .34, 20) + lobe(t, 110, .22, 17) + lobe(t, 195, .30, 21) + lobe(t, 285, .26, 16) + lobe(t, 340, .12, 12)


def bacterium(t):
    return (ellipse(t, .72, .27, 0, 4.2) + lobe(t, 180, .42, 4) + lobe(t, 168, .34, 4) + lobe(t, 192, .34, 4)
            + lobe(t, 0, .20, 4))


def yeast(t):
    return .50 + lobe(t, 38, .36, 16) + lobe(t, 220, .08, 30)


def paramecium(t):
    base = ellipse(t, .74, .30, 20, 2.6)
    return base + .045 * math.cos(30 * t) + lobe(t, 20, .06, 6) + lobe(t, 200, .10, 7)


def diatom(t):
    return .50 + .17 * math.cos(8 * t) ** 2 + .07 * math.cos(16 * t)


ORGANISMS = [
    ("Bird", bird), ("Butterfly", butterfly), ("Fish", fish), ("Leaf", leaf), ("Jellyfish", jellyfish),
    ("Amoeba", amoeba), ("Bacterium", bacterium), ("Yeast", yeast), ("Paramecium", paramecium), ("Diatom", diatom),
]


def smooth(rs, passes=2):
    k = (1, 2, 3, 2, 1)
    for _ in range(passes):
        rs = [sum(w * rs[(i + j - 2) % len(rs)] for j, w in enumerate(k)) / 9 for i in range(len(rs))]
    return rs


def table(fn, soften=0):
    rs = [fn(2 * math.pi * i / N) for i in range(N)]
    if soften:
        rs = smooth(rs, soften)
    m = max(rs)
    return [round(r / m, 3) for r in rs]


def main():
    data = [(n, table(f, 1 if n == 'Bird' else 0)) for n, f in ORGANISMS]
    root = pathlib.Path(__file__).resolve().parents[2]
    if "--preview" in sys.argv:
        import matplotlib; matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, axes = plt.subplots(2, 5, figsize=(15, 6))
        for ax, (n, rs) in zip(axes.flat, data):
            xs = [r * math.cos(2 * math.pi * i / N) for i, r in enumerate(rs)] + [rs[0]]
            ys = [r * math.sin(2 * math.pi * i / N) for i, r in enumerate(rs)] + [0]
            ys[-1] = rs[0] * math.sin(0)
            ax.plot(xs, ys, lw=2); ax.set_title(n); ax.set_aspect("equal"); ax.axis("off")
        fig.savefig(sys.argv[sys.argv.index("--preview") + 1], dpi=80)
        return
    js = ["// GENERATED by web/scripts/gen_organisms.py — edit the script, not this file.",
          f"export const SAMPLES = {N}", "export const ORGANISMS = ["]
    for n, rs in data:
        js.append(f"  {{ name: {json.dumps(n)}, r: {json.dumps(rs)} }},")
    js.append("]\n")
    (root / "web/src/lib/organisms.js").write_text("\n".join(js))
    sw = ["// GENERATED by web/scripts/gen_organisms.py — edit the script, not this file.",
          "enum OrganismData {", f"    static let samples = {N}", "    static let all: [(name: String, r: [Double])] = ["]
    for n, rs in data:
        sw.append(f"        ({json.dumps(n)}, {json.dumps(rs)}),")
    sw += ["    ]", "}\n"]
    (root / "ios/BioMap/BioMap/Views/Common/OrganismData.swift").write_text("\n".join(sw))
    print("wrote", len(data), "organisms")


main()
