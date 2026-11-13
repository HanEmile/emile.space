"""Shared paths/regexes for the map content pipeline (map-cache/*).

Single source for the Geofabrik extract catalog: extract-map-cache.py
maps regions to extracts, fetch-osm-dataset.sh downloads them (via
`python3 -c 'import mapconsts; ...'` or `python3 tools/extract-map-cache.py
--list-extracts`).
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tools/ is one level below the repo root
CACHE = os.path.join(ROOT, "map-cache")

NE_LOCAL = os.path.join(CACHE, "ne_50m_admin_0_countries.geojson")
OUTLINES_OUT = os.path.join(CACHE, "country-outlines.json")
PLACES_OUT = os.path.join(CACHE, "places.json")
GEODATA_STAMP = os.path.join(CACHE, ".geodata.stamp")
MAP_ATTRS_STAMP = os.path.join(CACHE, ".map-attrs.stamp")

# match only (re.match on a filename): rich-region bbox file produced by
# extract-map-cache.py, and the pending .query form
REGION_RE = re.compile(r"-?\d+\.\d+_-?\d+\.\d+_-?\d+\.\d+_-?\d+\.\d+\.json$")
QUERY_RE = re.compile(
    r"(-?\d+\.\d+)_(-?\d+\.\d+)_(-?\d+\.\d+)_(-?\d+\.\d+)\.json\.query$")

# base name (without .filtered.osm.pbf) -> Geofabrik path segment; every
# country polygon name in extract-map-cache.py maps to one of these
EXTRACTS = {
    "germany": "europe/germany",
    "austria": "europe/austria",
    "spain": "europe/spain",
    "netherlands": "europe/netherlands",
    "france": "europe/france",
    "belgium": "europe/belgium",
    "great-britain": "europe/great-britain",
    "poland": "europe/poland",
    "italy": "europe/italy",
    "serbia": "europe/serbia",
    "greece": "europe/greece",
    "switzerland": "europe/switzerland",
    "portugal": "europe/portugal",
    "china": "asia/china",
    "nevada": "north-america/us/nevada",
    "thailand": "asia/thailand",
    "vietnam": "asia/vietnam",
    "cambodia": "asia/cambodia",
    "taiwan": "asia/taiwan",
    "malaysia-singapore-brunei": "asia/malaysia-singapore-brunei",
    "washington": "north-america/us/washington",
    "new-york": "north-america/us/new-york",
}
