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
import json, os, sys

from mapconsts import CACHE
from maptools import (CL_COAST, CL_WATER_LINE, CL_WATER_FILL, NE_ROAD_CLASS,
                      Q, Writer, rdp)

NE_DIR = os.path.join(CACHE, "ne10m")
OUT = os.path.join(CACHE, "world-base.bin")

SIMPLIFY = 0.0005 # RDP epsilon in degrees (~50 m)
MIN_POINTS = 3

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
            geom = rdp(geom, SIMPLIFY, MIN_POINTS)
            if closed and geom[0][:2] != geom[-1][:2]:
                geom = geom + [geom[0]]
            q = quantize(geom)
            if len(q) >= MIN_POINTS:
                out.append((cls, q))
                n_in += 1
    print(f"  {os.path.basename(path)}: {n_in} features, "
          f"{n_pts_in} -> {sum(len(p) for _, p in out)} points")
    return out

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
                        lambda f: NE_ROAD_CLASS.get(
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
