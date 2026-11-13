#!/usr/bin/env python3
"""Pack all map-cache/<region>.json files (rich OSM extracts, see
extract-map-cache.py) into map-cache/world-rich.bin: one compact
varint-delta-binary file that is COMMITTED TO THE REPO, so a fresh clone
renders every visited region at full detail while the coarse
world-base.bin covers the rest of the planet.

Same record format as build-world-base.py (see its docstring), with
magic "VOKWR001" and coordinates quantized to Q = 1e-4 degrees (~11 m).
Classes: 1=coastline, 2=water line, 3=water fill (closed ring),
4=major road (motorway/trunk), 5=primary road, 6=secondary road.

Only what the maps actually show: geometries are RDP-simplified to
~25 m and quantized to 11 m (maps render at ~42 m/px), water fills
below ~60 m across (sub-pixel) and way segments far outside their
region are dropped.
"""
import json, os, re, sys

from mapconsts import CACHE, REGION_RE
from maptools import (CL_WATER_FILL, Q, Writer, osm_way_class, rdp)

OUT = os.path.join(CACHE, "world-rich.bin")

SIMPLIFY = 0.00025  # ~25 m RDP epsilon (well below a display pixel)
FILL_MIN_DEG = 0.0006  # drop water fills < ~60 m bbox (sub-pixel dots)
CLIP_PAD = 0.02   # keep way points within region bbox + this pad (~2 km)

def clip_runs(geom, s, w, n, e):
    """runs of consecutive points inside the padded region bbox (open
    lines only; the smart extractor keeps whole ways past the edge)"""
    runs, cur = [], []
    ps, pw, pn, pe = s - CLIP_PAD, w - CLIP_PAD, n + CLIP_PAD, e + CLIP_PAD
    for pt in geom:
        if pw <= pt[0] <= pe and ps <= pt[1] <= pn:
            cur.append(pt)
        elif cur:
            runs.append(cur)
            cur = []
    if cur:
        runs.append(cur)
    return runs

def tiny_fill(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return max(max(xs) - min(xs), max(ys) - min(ys)) < FILL_MIN_DEG

def quantize(geom, closed):
    pts, prev = [], None
    for lon, lat in geom:
        pt = (round(lon / Q), round(lat / Q))
        if pt != prev:
            pts.append(pt)
            prev = pt
    if closed and pts and pts[0] != pts[-1]:
        pts.append(pts[0])
    return pts

def main():
    w = Writer()
    w.buf += b"VOKWR001"
    pos = bytearray()  # placeholder-free two-pass via list
    features = []
    seen = set()
    n_dup = 0
    files = sorted(f for f in os.listdir(CACHE) if REGION_RE.match(f))
    if not files:
        sys.exit("no map-cache/<region>.json files found")
    for fn in files:
        rs, rw, rn, re_ = map(float, re.findall(r"-?\d+\.\d+", fn)[:4])
        d = json.load(open(os.path.join(CACHE, fn)))
        for el in d.get("elements", []):
            if el.get("type") == "way" and el.get("geometry"):
                cls = osm_way_class(el.get("tags", {}))
                if cls is None:
                    continue
                geom = [(p["lon"], p["lat"]) for p in el["geometry"]]
                geom = rdp(geom, SIMPLIFY)
                if cls == CL_WATER_FILL:
                    runs = [geom]  # fills stay whole (clipping breaks rings)
                else:
                    runs = clip_runs(geom, rs, rw, rn, re_)
                for run in runs:
                    pts = quantize(run, cls == CL_WATER_FILL)
                    if len(pts) < 3 or (cls == CL_WATER_FILL
                                        and tiny_fill(pts)):
                        continue
                    # overlapping regions share boundary-crossing ways;
                    # sketch dedupes retry runs
                    key = (cls, pts[0], pts[-1], len(pts))
                    if key in seen:
                        n_dup += 1
                        continue
                    seen.add(key)
                    features.append((cls, pts))
            elif el.get("type") == "relation":
                for m in el.get("members", []):
                    if m.get("role", "").startswith("outer") and m.get(
                            "geometry"):
                        geom = [(p["lon"], p["lat"]) for p in m["geometry"]]
                        geom = rdp(geom, SIMPLIFY)
                        pts = quantize(geom, closed=True)
                        if len(pts) >= 3 and not tiny_fill(pts):
                            features.append((CL_WATER_FILL, pts))
    w.varint(len(features))
    for cls, pts in features:
        w.feature(cls, pts)
    with open(OUT, "wb") as fh:
        fh.write(w.buf)
    print(f"{OUT}: {len(features)} features "
          f"({n_dup} skipped), {len(w.buf) / 1e6:.1f} MB "
          f"from {len(files)} regions")

if __name__ == "__main__":
    main()
