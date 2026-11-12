# Static NOAH awareness asset

The Flutter app consumes `assets/noah/marulas-5year.geojson`; it never opens the
regional shapefile on a phone. The asset is shared by both build flavours and
does not enter report verification, road-status persistence, risk computation,
planning or navigation decisions.

To reproduce, install Python `pyshp` (3.x) and `shapely` (2.x) in a development
environment, then run from the project root:

```powershell
python scripts/noah/prepare_marulas.py --source 'C:\path\MetroManila_Flood_5year'
```

The source argument is a base path, without extension. All four component
hashes must match the pinned BetterGov mirror release recorded in NOTICE.md.
`--deps` optionally points to an isolated Python package directory; `--out`
selects a review-output directory. The original files are read-only inputs.

The script filters rings against Marulas plus an approximately 500 m buffer,
preserves shell/hole grouping, explicitly repairs invalid candidate polygons,
and clips/unions per hazard class. Review repair statistics, polygon validity,
alignment and display size before adopting regenerated assets. It does not
simplify, invent a study-coverage mask, or reassign hazard levels. Any future
source update requires an explicit provenance/hash/legend review.

Source attribution, open database terms, scenario and date limitations are in
`assets/noah/NOTICE.md`. Keep the adapted database and notice available under
those terms. No private resident data is included.

Road-length calculation reference cases can be regenerated with:

```powershell
python scripts/noah/verify_length_reference.py
```

This uses Shapely and writes only the independent test fixture under
`test/fixtures/`. Its synthetic east-west lines intersect the real bundled
NOAH polygons; they are not production road records or barangay percentages.
The app calculates the selected road's unique mapped length separately in Dart.
