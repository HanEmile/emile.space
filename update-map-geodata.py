#!/usr/bin/env python3
"""Precompute map geodata for the (map ...) country/city feature.

Writes:
  map-cache/country-outlines.json  simplified country outlines for ALL countries
  map-cache/places.json            city coordinates + non-country fallbacks (islands
                                   etc.) + country name aliases

Natural Earth 50m outlines are public domain (https://www.naturalearthdata.com).
City coordinates come from Nominatim (osm.org) - run sparingly, it reuses its
previous output and only geocodes locations it hasn't seen before.
"""
import json, os, re, sys, time, urllib.request, urllib.parse, glob

ROOT = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(ROOT, "map-cache")
NE_URL = ("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
          "master/geojson/ne_50m_admin_0_countries.geojson")
NE_LOCAL = os.path.join(CACHE, "ne_50m_admin_0_countries.geojson")
OUTLINES_OUT = os.path.join(CACHE, "country-outlines.json")
PLACES_OUT = os.path.join(CACHE, "places.json")
UA = "vokobe2 geodata updater (https://emile.space)"

ALIASES = {
    "USA": "United States of America",
    "UK": "United Kingdom",
    "Deutschland": "Germany",
}

def fetch(url, out=None):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    if out:
        with open(out, "wb") as f:
            f.write(data)
    return data

def rdp(ring, eps):
    """Ramer-Douglas-Peucker on a closed ring (start point kept fixed)."""
    if len(ring) < 4:
        return ring
    keep = [False] * len(ring)
    keep[0] = keep[-1] = True
    stack = [(0, len(ring) - 1)]
    while stack:
        i0, i1 = stack.pop()
        x1, y1 = ring[i0]
        x2, y2 = ring[i1]
        dx, dy = x2 - x1, y2 - y1
        ln = (dx * dx + dy * dy) ** 0.5
        maxd, maxi = eps, -1
        for i in range(i0 + 1, i1):
            x, y = ring[i]
            if ln < 1e-12:
                d = ((x - x1) ** 2 + (y - y1) ** 2) ** 0.5
            else:
                d = abs(dx * (y1 - y) - (x1 - x) * dy) / ln
            if d > maxd:
                maxd, maxi = d, i
        if maxi >= 0:
            keep[maxi] = True
            stack += [(i0, maxi), (maxi, i1)]
    return [pt for pt, k in zip(ring, keep) if k]

def ring_area(ring):
    """shoelace area in deg^2, lon scaled by cos(mean lat)"""
    if len(ring) < 3:
        return 0.0
    import math
    clat = math.cos(math.radians(sum(p[1] for p in ring) / len(ring)))
    a = 0.0
    for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
        a += (x1 * clat) * y2 - (x2 * clat) * y1
    return abs(a) / 2.0

# ring filtering: keep maps mainland-focused (island cities get a local
# Overpass map instead, see Generator/roughmap).  A ring is dropped when
#   - it is tiny compared to the country's largest ring (specks), or
#   - it is both far away AND small compared to it -- this drops overseas
#     islands (Canaries, Svalbard, Alaska, French Guiana) but keeps both
#     nearby islands (Balearics, Sicily, Hokkaido) and far-away major
#     landmasses (Peninsular Malaysia vs Borneo, Papua for Indonesia)
MIN_RING_FRAC = 0.005
NEAR_RING_DIST_KM = 350.0
FAR_RING_FRAC = 0.30
# pre-simplify 50m rings to ~0.005 deg (~500 m); the renderer simplifies
# further to display pixels, this only keeps the cache compact
SIMPLIFY_EPS = 0.005

def ring_dist_km(a, b):
    """approx min distance between two (already simplified) rings"""
    import math
    best = float("inf")
    for x1, y1 in a:
        clat = math.cos(math.radians(y1))
        for x2, y2 in b:
            d = (((x1 - x2) * clat) ** 2 + (y1 - y2) ** 2) ** 0.5 * 111.32
            if d < best:
                best = d
    return best

def round_ring(ring):
    out, prev = [], None
    for lon, lat in ((round(x, 4), round(y, 4)) for x, y in ring):
        if (lon, lat) != prev:
            out.append([lon, lat])
            prev = (lon, lat)
    # close
    if len(out) > 1 and out[0] != out[-1]:
        out.append(out[0])
    return out

def rings_of_geometry(geom):
    polys = []
    if geom["type"] == "Polygon":
        polys = [geom["coordinates"]]
    elif geom["type"] == "MultiPolygon":
        polys = geom["coordinates"]
    rings = []
    for poly in polys:
        for ring in poly:  # outer + holes; both get stroked anyway
            if len(ring) < 4:
                continue
            r = round_ring(rdp(ring, SIMPLIFY_EPS))
            if len(r) >= 4:
                rings.append(r)
    if not rings:
        return rings
    main = max(rings, key=ring_area)
    main_area = ring_area(main)
    def keep(r):
        a = ring_area(r)
        if a < MIN_RING_FRAC * main_area:
            return False
        if ring_dist_km(r, main) <= NEAR_RING_DIST_KM:
            return True
        return a >= FAR_RING_FRAC * main_area
    return [r for r in rings if keep(r)]

# ---------------- country outlines -------------------------------------------------

if not os.path.exists(NE_LOCAL):
    print("downloading Natural Earth 50m countries ...")
    fetch(NE_URL, NE_LOCAL)

ne = json.load(open(NE_LOCAL))
outlines = {}
for f in ne["features"]:
    p, rings = f["properties"], rings_of_geometry(f["geometry"])
    if not rings:
        continue
    xs = [pt[0] for r in rings for pt in r]
    ys = [pt[1] for r in rings for pt in r]
    entry = {"bbox": [min(ys), min(xs), max(ys), max(xs)], "rings": rings}
    for key in ("NAME", "NAME_EN", "ADMIN"):
        n = p.get(key)
        if n and n not in outlines:
            outlines[n] = entry

json.dump(outlines, open(OUTLINES_OUT, "w"), separators=(",", ":"), sort_keys=True)
print(f"{OUTLINES_OUT}: {len(outlines)} names, "
      f"{os.path.getsize(OUTLINES_OUT) // 1024} KB")

# ---------------- places ------------------------------------------------------------

loc_re = re.compile(r'\(location\s+((?:"[^"]*"\s*)+)\)')
q_re = re.compile(r'"([^"]*)"')

locations = set()
for path in glob.glob(os.path.join(ROOT, "input", "*.md")):
    for m in loc_re.finditer(open(path).read()):
        vals = q_re.findall(m.group(1))
        if len(vals) == 2:
            locations.add((vals[0], vals[1]))
        else:
            for v in vals:
                locations.add((v, None))

def canon(country):
    return ALIASES.get(country, country) if country else country

places = {"aliases": ALIASES, "countries": {}, "cities": {}, "unresolved": []}
if os.path.exists(PLACES_OUT):
    places = json.load(open(PLACES_OUT))
places["aliases"] = ALIASES

def nominatim(q):
    url = ("https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&q="
           + urllib.parse.quote(q))
    try:
        return json.loads(fetch(url))
    except Exception as e:
        print(f"  request failed for {q!r}: {e}")
        return []

def geocode(city, country):
    """returns dict with lat/lon (/width_km) or None"""
    res = nominatim(f"{city}, {canon(country)}" if country else city)
    if not res:
        return None
    r = res[0]
    out = {"lat": round(float(r["lat"]), 5), "lon": round(float(r["lon"]), 5)}
    if "boundingbox" in r:
        s, n, w, e = map(float, r["boundingbox"])
        import math
        # clamp: Nominatim bboxes of island city-states (Hong Kong,
        # Singapore) span far more sea than land; cap keeps the map urban
        out["width_km"] = max(1, min(40, round((e - w) * 111.320 * math.cos(math.radians(out["lat"])))))
    return out

n_geo = 0
for city, country in sorted(locations):
    if city.lower() == "online":
        continue
    # a country-attr value that has no outline gets a center/width fallback;
    # islands and regions used as "cities" get handled by their country map
    if country and canon(country) not in outlines and canon(country) not in places["countries"]:
        d = geocode(canon(country), None)
        time.sleep(1.1)
        n_geo += 1
        if d:
            places["countries"][canon(country)] = d
            print(f"  country fallback: {country} -> {d}")
    if city not in places["cities"] and city not in places["unresolved"]:
        d = geocode(city, country)
        time.sleep(1.1)
        n_geo += 1
        if d:
            places["cities"][city] = {"lat": d["lat"], "lon": d["lon"]}
            print(f"  city: {city} -> {d['lat']}, {d['lon']}")
        else:
            places["unresolved"].append(city)
            print(f"  UNRESOLVED: {city}")

json.dump(places, open(PLACES_OUT, "w"), indent=1, sort_keys=True, ensure_ascii=False)
print(f"{PLACES_OUT}: {len(places['cities'])} cities, "
      f"{len(places['countries'])} country fallbacks, "
      f"{len(places['unresolved'])} unresolved, {n_geo} new lookups")
