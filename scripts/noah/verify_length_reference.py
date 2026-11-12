"""Generate independent GIS test shares; never used by production code."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--deps', help='Optional isolated Shapely dependency directory')
args = parser.parse_args()
if args.deps:
    sys.path.insert(0, str(Path(args.deps).resolve()))
from shapely.geometry import shape, box, mapping, LineString
from shapely.ops import unary_union

raw = Path('assets/noah/marulas-5year.geojson').read_bytes()
data = json.loads(raw)
classes = {int(f['properties']['Var']): shape(f['geometry']) for f in data['features']}
extent = box(*data['metadata']['preparedBounds'])
cases = []
for latitude in [14.667, 14.676, 14.685]:
    line = LineString([(120.95, latitude), (121.02, latitude)])
    assigned = {'high': classes[3], 'medium': classes[2].difference(classes[3]),
                'low': classes[1].difference(unary_union([classes[2], classes[3]]))}
    fractions = {key: line.intersection(geometry).length / line.length for key, geometry in assigned.items()}
    fractions['noMappedHazard'] = line.intersection(extent).difference(unary_union(list(classes.values()))).length / line.length
    fractions['outsidePrepared'] = line.difference(extent).length / line.length
    assert abs(sum(fractions.values()) - 1) < 1e-8
    cases.append(dict(name='Marulas east-west ' + str(latitude), geometry=mapping(line), fractions=fractions))
output = dict(source_sha256=hashlib.sha256(raw).hexdigest(),
              method='Independent Shapely polygon difference/intersection; straight east-west lines, fractions of unique mapped length; highest-class overlap assignment.', cases=cases)
Path('test/fixtures/noah_length_reference.json').write_text(json.dumps(output, indent=2), encoding='utf-8')
