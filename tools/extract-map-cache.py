#!/usr/bin/env python3
"""Rebuild map-cache/<region>.json files fully offline from the filtered
Geofabrik extracts (map-cache/osm/*.filtered.osm.pbf, see
fetch-osm-dataset.sh).

Reads the region list from map-cache/*.query files (dumped by a build
with --dump-missing-queries), clips each bbox out of its country's
filtered extract with `osmium extract`, and converts the result to the
Overpass-JSON shape vokobe2/lib/roughmap.ml renders, dropping the .query
file on success.

Regions whose country extract is missing are kept as .query files.
Run inside nix:  nix-shell shell.nix --run 'python3 tools/extract-map-cache.py'
"""
import json, os, subprocess, sys, tempfile

from mapconsts import CACHE, EXTRACTS, NE_LOCAL, QUERY_RE

OSM_DIR = os.path.join(CACHE, "osm")

if "--list-extracts" in sys.argv:
    # Geofabrik paths for fetch-osm-dataset.sh (one per line)
    for path in EXTRACTS.values():
        print(path)
    sys.exit(0)

# Natural Earth country name -> extract base name
COUNTRY_TO_EXTRACT = {
    "People's Republic of China": "china",
    "Germany": "germany",
    "Austria": "austria",
    "Spain": "spain",
    "Netherlands": "netherlands",
    "France": "france",
    "Belgium": "belgium",
    "Luxembourg": "belgium",
    "United Kingdom": "great-britain",
    "Poland": "poland",
    "Italy": "italy",
    "Serbia": "serbia",
    "Greece": "greece",
    "Switzerland": "switzerland",
    "Portugal": "portugal",
    "China": "china",
    "Macao": "china",
    "Hong Kong": "china",
    "Thailand": "thailand",
    "Vietnam": "vietnam",
    "Cambodia": "cambodia",
    "Taiwan": "taiwan",
    "Malaysia": "malaysia-singapore-brunei",
    "Singapore": "malaysia-singapore-brunei",
}

# region centers that fall outside all country polygons (sea, tiny NE
# islands): explicit extract overrides, keyed by rounded center
OVERRIDES = {
    (7.74, 98.78): "thailand",           # Phuket bay
    (12.21, 109.29): "vietnam",          # Nha Trang bay
    (40.71, -74.01): "new-york",         # New York City
    (48.65, -122.82): "washington",      # Orcas / San Juan Islands
    (36.17, -115.15): "nevada",          # Las Vegas
}

# feature classes the renderer draws (mirror of the Overpass query /
# the tags-filter used for the extracts)
HIGHWAYS = {"motorway", "motorway_link", "trunk", "trunk_link",
            "primary", "primary_link", "secondary"}
WATERWAYS = {"river", "canal", "stream"}

def point_in_ring(ring, x, y):
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside

def country_of(ne, lat, lon):
    for f in ne["features"]:
        geom = f["geometry"]
        polys = ([geom["coordinates"]] if geom["type"] == "Polygon"
                 else geom["coordinates"])
        for poly in polys:
            if point_in_ring(poly[0], lon, lat):
                return f["properties"].get("NAME_EN") or \
                       f["properties"].get("NAME")
    return None

def extract_for(ne, lat, lon):
    """rounded center first (overrides), then unrounded point-in-polygon"""
    ov = OVERRIDES.get((round(lat, 2), round(lon, 2)))
    if ov:
        return ov
    name = country_of(ne, lat, lon)
    return COUNTRY_TO_EXTRACT.get(name)

def wanted_way(tags):
    if tags.get("highway") in HIGHWAYS: return True
    if tags.get("waterway") in WATERWAYS: return True
    if tags.get("natural") in ("water", "coastline"): return True
    if tags.get("landuse") == "reservoir": return True
    return False

def wanted_rel(tags):
    return tags.get("natural") == "water" or tags.get("landuse") == "reservoir"

def convert(pbf_path, out_path):
    """region .osm.pbf -> Overpass-shaped {"elements": [...]} JSON"""
    import osmium
    ways = {}
    class WayPass(osmium.SimpleHandler):
        def way(self, w):
            if not wanted_way(w.tags): return
            geom = [
                {"lat": round(n.location.lat, 7),
                 "lon": round(n.location.lon, 7)}
                for n in w.nodes if n.location.valid()
            ]
            if len(geom) >= 2:
                ways[w.id] = {
                    "type": "way", "id": w.id,
                    "tags": dict(w.tags), "geometry": geom}
    # relation objects are only valid inside the callback: copy out the
    # member refs/roles there, resolve geometries afterwards
    rels = []
    class RelPass(osmium.SimpleHandler):
        def relation(self, r):
            if not wanted_rel(r.tags): return
            rels.append((r.id, dict(r.tags),
                         [(m.ref, m.role) for m in r.members
                          if m.type == "w" and m.role.startswith("outer")]))
    WayPass().apply_file(pbf_path, locations=True)
    RelPass().apply_file(pbf_path)

    elements = list(ways.values())
    for rid, rtags, ref_roles in rels:
        members = [{"type": "way", "ref": ref, "role": role,
                    "geometry": ways[ref]["geometry"]}
                   for ref, role in ref_roles if ref in ways]
        if members:
            elements.append({"type": "relation", "id": rid,
                             "tags": rtags, "members": members})
    # a stale parsed-feature .bin cache must never shadow the fresh json
    try:
        os.unlink(out_path + ".bin")
    except FileNotFoundError:
        pass
    with open(out_path, "w") as f:
        json.dump({"version": 0.6, "elements": elements}, f,
                  separators=(",", ":"))

def main():
    queries = sorted(f for f in os.listdir(CACHE) if QUERY_RE.match(f))
    if not queries:
        print("no map-cache/*.query files (run a build with"
              " --dump-missing-queries first)")
        return
    ne = json.load(open(NE_LOCAL))
    missing_extracts = set()
    done = failed = 0
    for q in queries:
        s, w, n, e = map(float, QUERY_RE.match(q).groups()[:4])
        extract = extract_for(ne, (s + n) / 2, (w + e) / 2)
        if not extract:
            print(f"  SKIP {q}: no country found for center")
            failed += 1
            continue
        filtered = os.path.join(OSM_DIR, f"{extract}.filtered.osm.pbf")
        if not os.path.exists(filtered):
            if extract not in missing_extracts:
                print(f"  SKIP {q}: extract {extract} not downloaded yet")
            missing_extracts.add(extract)
            failed += 1
            continue
        with tempfile.NamedTemporaryFile(
                suffix=".osm.pbf", dir=OSM_DIR, delete=False) as tf:
            tmp = tf.name
        try:
            subprocess.run(
                ["osmium", "extract", "-b", f"{w},{s},{e},{n}",
                 "--strategy", "smart", "--no-progress",
                 "-o", tmp, filtered, "--overwrite"],
                check=True, capture_output=True)
            convert(tmp, os.path.join(CACHE, q[:-len(".query")]))
        except subprocess.CalledProcessError as err:
            print(f"  FAIL {q}: {err.stderr.decode()[:200]}")
            failed += 1
            continue
        finally:
            os.unlink(tmp)
        os.unlink(os.path.join(CACHE, q))
        done += 1
    print(f"{done} region(s) extracted, {failed} skipped/failed")
    if missing_extracts:
        print("missing extracts:", ", ".join(sorted(missing_extracts)))

if __name__ == "__main__":
    main()
