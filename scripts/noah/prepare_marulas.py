"""Reproduce the bounded display asset from the pinned NOAH mirror shapefile."""
import sys,json,gzip,argparse,hashlib
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('--source',required=True,help='Shapefile base path without extension')
parser.add_argument('--out',default='assets/noah')
parser.add_argument('--deps',help='Optional isolated Python dependency directory')
args=parser.parse_args()
OUT=Path(args.out)
OUT.mkdir(parents=True,exist_ok=True)
if args.deps:sys.path.insert(0,str(Path(args.deps).resolve()))
expected={'shp':'0bef21e14bfa51259f9948b0b7daf4806b8e0ca2fae06a5a439ace2ff2e15aa4','shx':'2a88d8ad910413f8b23be155b65e5527dc9c7aa6e4c9bc727bf7314798716d05','dbf':'4fb5c7022caf0bbe99d0ed0bfb78d357c502ff86b8b7aec74f29c5c160d74df1','prj':'a02a27b1d1982c8516d83398e85a3c8b1aef1713c13ef4d84d7bde17430c07c4'}
for extension,digest in expected.items():
    if hashlib.sha256(Path(args.source+'.'+extension).read_bytes()).hexdigest()!=digest:
        raise ValueError('Source does not match pinned release: '+extension)
import shapefile
from shapely.geometry import Polygon,box,mapping
from shapely import make_valid
from shapely.ops import unary_union

reader=shapefile.Reader(args.source)
clip=box(120.963,14.661,121.0045,14.6905)
report=dict(fields=reader.fields,bounds=list(reader.bbox),shape_count=len(reader),records=[])
features=[]
for sr in reader.iterShapeRecords():
    s=sr.shape
    rings=[]
    starts=list(s.parts)+[len(s.points)]
    for a,b in zip(starts,starts[1:]):
        pts=s.points[a:b]
        xs=[p[0] for p in pts];ys=[p[1] for p in pts]
        if max(xs)<clip.bounds[0] or min(xs)>clip.bounds[2] or max(ys)<clip.bounds[1] or min(ys)>clip.bounds[3]:
            continue
        rings.append(pts)
    grouping_errors={}
    polygons=shapefile.organize_polygon_rings(rings,grouping_errors)
    if grouping_errors:
        raise ValueError('Unresolved polygon grouping: '+str(grouping_errors))
    parts=[];invalid=0
    for polygon in polygons:
        g=Polygon(polygon[0],polygon[1:])
        if not g.is_valid:
            invalid+=1
            g=make_valid(g)
        c=g.intersection(clip)
        if not c.is_empty:parts.append(c)
    g=unary_union(parts)
    assert g.is_valid
    attrs=sr.record.as_dict()
    report['records'].append(dict(attributes=attrs,source_parts=len(s.parts),source_points=len(s.points),candidate_rings=len(rings),grouping_errors=grouping_errors,invalid_candidate_polygons_repaired=invalid,marulas_intersects=not g.is_empty,clipped_valid=g.is_valid))
    if not g.is_empty:
        features.append(dict(type='Feature',properties=attrs,geometry=mapping(g)))
payload=json.dumps(dict(type='FeatureCollection',metadata=dict(id='noah-metro-manila-5yr-3820095-marulas',scenarioYears=5,preparedBounds=list(clip.bounds),hasCoverageMask=False,modelDate=None,source='Project NOAH; BetterGov.PH mirror',revision='3820095a7e40b6bc852390d43a8c6d368d6fe081'),features=features),separators=(',',':')).encode()
(OUT/'marulas-5year.geojson').write_bytes(payload)
report.update(geojson_bytes=len(payload),gzip_bytes=len(gzip.compress(payload)),method='Filter source rings by Marulas bounding box, group shells and holes, repair invalid candidate polygons, clip and union. Full-region geometry validity not evaluated.')
(OUT/'local-check.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
