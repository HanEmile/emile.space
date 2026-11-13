#!/usr/bin/env python3
"""Build map-cache/world-base.bin: a compact global base layer for the
map renderer (vokobe2/lib/roughmap.ml reads it as an offline fallback
for regions without a richer map-cache/<region>.json).

Sources: Natural Earth 10m GeoJSON (public domain) in map-cache/ne10m/
  ne_10m_coastline.geojson              -> Coast_line
  ne_10m_rivers_lake_centerlines.geojson -> Water_line
  ne_10m_lakes.geojson                   -> Water_fill
  ne_10m_roads.geojson                   -> Road trunk/primary/secondary
(download once with the curl loop in fetch-osm-dataset.sh's header or:
  mkdir -p map-cache/ne10m && cd map-cache/ne10m
  for f in ne_10m_coastline ne_10m_rivers_lake_centerlines \
           ne_10m_lakes ne_10m_roads; do
    curl -sSLO "https://raw.githubusercontent.com/nvkelso/\
natural-earth-vector/master/geojson/$f.geojson"
  done)

Format (little conceptual doc; kept in sync with the OCaml decoder):
  8 bytes  magic "VOKWB001"
  varint   feature_count
  per feature:
    u8     class: 1=coastline, 2=water line, 3=water fill (closed ring),
                  4=road trunk, 5=road primary, 6=road secondary
    varint n_points
    point 0:  zigzag-varint lon, zigzag-varint lat (absolute, quantized)
    point 1+: zigzag-varint dlon, zigzag-varint dlat (delta to previous)
  Coordinates are quantized to Q = 1e-4 degrees (~11 m), stored as
  integers.  varint = unsigned LEB128; zigzag = (n<<1)^(n>>63) style.
"""
import json, math, os, struct, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
NE_DIR = os.path.join(ROOT, "map-cache", "ne10m")
OUT = os.path.join(ROOT, "map-cache", "world-base.bin")

CL_COAST, CL_WATER_LINE, CL_WATER_FILL = 1, 2, 3
CL_TRUNK, CL_PRIMARY, CL_SECONDARY = 4, 5, 6

Q = 1e-4          # degrees per unit (~11 m)
SIMPLIFY = 0.0005 # RDP epsilon in degrees (~50 m)
MIN_POINTS = 3

def rdp(ring, eps):
    """Ramer-Douglas-Peucker on a line (endpoints kept)."""
    if len(ring) < MIN_POINTS:
        return ring
    keep = [False] * len(ring)
    keep[0] = keep[-1] = True
    stack = [(0, len(ring) - 1)]
    while stack:
        i0, i1 = stack.pop()
        x1, y1 = ring[i0][:2]
        x2, y2 = ring[i1][:2]
        dx, dy = x2 - x1, y2 - y1
        ln = math.hypot(dx, dy)
        maxd, maxi = eps, -1
        for i in range(i0 + 1, i1):
            x, y = ring[i][:2]
            d = (math.hypot(x - x1, y - y1) if ln < 1e-12
                 else abs(dx * (y1 - y) - (x1 - x) * dy) / ln)
            if d > maxd:
                maxd, maxi = d, i
        if maxi >= 0:
            keep[maxi] = True
            stack += [(i0, maxi), (maxi, i1)]
    return [pt for pt, k in zip(ring, keep) if k]

def geoms_of(f):
    g = f["geometry"]
    if g is None:
        return []
    if g["type"] == "LineString":
        return [g["coordinates"]]
    if g["type"] == "MultiLineString":
        return g["coordinates"]
    if g["type"] == "Polygon":
        return g["coordinates"]
    if g["type"] == "MultiPolygon":
        return [ring for poly in g["coordinates"] for ring in poly]
    return []

class Writer:
    def __init__(self):
        self.buf = bytearray()
    def u8(self, v):
        self.buf.append(v & 0xFF)
    def varint(self, v):  # unsigned LEB128
        while True:
            b = v & 0x7F
            v >>= 7
            if v:
                self.buf.append(b | 0x80)
            else:
                self.buf.append(b)
                return
    def zz(self, n):  # zigzag-encoded signed -> unsigned varint
        self.varint((n << 1) ^ (n >> 63))
    def feature(self, cls, pts_q):
        self.u8(cls)
        self.varint(len(pts_q))
        x0, y0 = pts_q[0]
        self.zz(x0)
        self.zz(y0)
        for (x1, y1), (x2, y2) in zip(pts_q, pts_q[1:]):
            self.zz(x2 - x1)
            self.zz(y2 - y1)

def quantize(geom):
    pts_q, prev = [], None
    for lon, lat in ((round(p[0] / Q), round(p[1] / Q)) for p in geom):
        if -1800000 <= lon <= 1800000 and -900000 <= lat <= 900000 \
           and (lon, lat) != prev:
            pts_q.append((lon, lat))
            prev = (lon, lat)
    return pts_q

def collect(path, cls_of, closed=False):
    """returns [(cls, quantized_points)], simplified and quantized"""
    out = []
    d = json.load(open(path))
    n_in = n_pts_in = 0
    for f in d["features"]:
        cls = cls_of(f)
        if cls is None:
            continue
        for geom in geoms_of(f):
            n_pts_in += len(geom)
            geom = rdp(geom, SIMPLIFY)
            if closed and geom[0][:2] != geom[-1][:2]:
                geom = geom + [geom[0]]
            q = quantize(geom)
            if len(q) >= MIN_POINTS:
                out.append((cls, q))
                n_in += 1
    print(f"  {os.path.basename(path)}: {n_in} features, "
          f"{n_pts_in} -> {sum(len(p) for _, p in out)} points")
    return out

ROAD_CLASS = {
    "Major Highway": CL_TRUNK, "Beltway": CL_TRUNK, "Bypass": CL_TRUNK,
    "Secondary Highway": CL_PRIMARY,
    "Road": CL_SECONDARY, "Unknown": CL_SECONDARY, "Track": CL_SECONDARY,
}

def main():
    for f in ("ne_10m_coastline", "ne_10m_rivers_lake_centerlines",
              "ne_10m_lakes", "ne_10m_roads"):
        if not os.path.exists(os.path.join(NE_DIR, f + ".geojson")):
            sys.exit(f"missing map-cache/ne10m/{f}.geojson (see docstring)")
    features = []
    features += collect(os.path.join(NE_DIR, "ne_10m_coastline.geojson"),
                        lambda f: CL_COAST)
    features += collect(os.path.join(NE_DIR,
                                     "ne_10m_rivers_lake_centerlines.geojson"),
                        lambda f: CL_WATER_LINE)
    features += collect(os.path.join(NE_DIR, "ne_10m_lakes.geojson"),
                        lambda f: CL_WATER_FILL, closed=True)
    features += collect(os.path.join(NE_DIR, "ne_10m_roads.geojson"),
                        lambda f: ROAD_CLASS.get(
                            f["properties"].get("type")))
    w = Writer()
    w.buf += b"VOKWB001"
    w.varint(len(features))
    for cls, pts in features:
        w.feature(cls, pts)
    with open(OUT, "wb") as fh:
        fh.write(w.buf)
    print(f"{OUT}: {len(features)} features, "
          f"{len(w.buf) / 1e6:.1f} MB")

if __name__ == "__main__":
    main()
