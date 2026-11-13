"""Shared geometry/packing helpers for the map-cache builders
(build-world-base.py, build-world-rich.py, update-map-geodata.py)."""
import math

# feature classes shared by world-base.bin and world-rich.bin (decoded
# by vokobe2/lib/roughmap.ml)
CL_COAST, CL_WATER_LINE, CL_WATER_FILL = 1, 2, 3
CL_TRUNK, CL_PRIMARY, CL_SECONDARY = 4, 5, 6

Q = 1e-4  # degrees per quantized unit (~11 m)

# classify an OSM way's tags into a feature class (or None to skip);
# split maps keep the renderer's draws-all-five switch cheap
ROADS_MAJOR = {"motorway", "motorway_link", "trunk", "trunk_link"}
ROADS_PRIMARY = {"primary", "primary_link"}
ROADS_SECONDARY = {"secondary"}
WATERWAYS = {"river", "canal", "stream"}

def osm_way_class(tags):
    if tags.get("highway") in ROADS_MAJOR: return CL_TRUNK
    if tags.get("highway") in ROADS_PRIMARY: return CL_PRIMARY
    if tags.get("highway") in ROADS_SECONDARY: return CL_SECONDARY
    if tags.get("waterway") in WATERWAYS: return CL_WATER_LINE
    if tags.get("natural") == "coastline": return CL_COAST
    if tags.get("natural") == "water" or tags.get("landuse") == "reservoir":
        return CL_WATER_FILL
    return None

# classify a Natural Earth ne_10m_roads feature ("type" property)
NE_ROAD_CLASS = {
    "Major Highway": CL_TRUNK, "Beltway": CL_TRUNK, "Bypass": CL_TRUNK,
    "Secondary Highway": CL_PRIMARY,
    "Road": CL_SECONDARY, "Unknown": CL_SECONDARY, "Track": CL_SECONDARY,
}

def rdp(ring, eps, min_len=4):
    """Ramer-Douglas-Peucker on a line/ring (endpoints kept).  Points may
    carry extra coordinates (only the first two take part).  Lines
    shorter than min_len pass through untouched (build-world-base.py
    needs min_len=3 so dropped points can still reject a feature via
    its MIN_POINTS check)."""
    if len(ring) < min_len:
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

class Writer:
    """varint/zigzag writer for the world-*.bin feature format (magic
    header is the caller's job; see the build-world-*.py docstrings)"""
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
    def feature(self, cls, pts):
        """one feature: class, then quantized points (absolute first,
        deltas after)"""
        self.u8(cls)
        self.varint(len(pts))
        x0, y0 = pts[0]
        self.zz(x0)
        self.zz(y0)
        for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
            self.zz(x2 - x1)
            self.zz(y2 - y1)
