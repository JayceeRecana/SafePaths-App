# NOAH 5-year flood awareness layer

Source: Project NOAH and its contributors, distributed through BetterGov.PH.
Scenario: Metro Manila, 5-year rainfall return period. Static modeled hazard;
not live flooding, a forecast, or verified road passability.

Mirror: https://huggingface.co/datasets/bettergovph/project-noah-hazard-maps
Pinned revision: 3820095a7e40b6bc852390d43a8c6d368d6fe081
Original package: Flood/5yr/MetroManila.zip
ZIP SHA256: 99bb769db123c574d8190b4316150f72c818a6bb3dacdb1d0b609f28e960e7f9

Adaptation by SafePaths: geometry repair and crop to Marulas plus an approximately
500 m surrounding buffer (120.963,14.661,121.0045,14.6905). No class reassignment.
Original model date is not established. Preparation time is not model freshness.
This file has no independent study/no-data coverage mask. An unshaded location
does not establish no hazard or safety. Var=1/2/3 means low/medium/high hazard;
classification can consider both depth and velocity.

Database and this adapted GeoJSON: Open Database License (ODbL) 1.0.
https://opendatacommons.org/licenses/odbl/1.0/
The adapted database is included as marulas-5year.geojson, openly redistributable
under the same licence. Preserve this notice and attribution when distributing.

Dataset documentation: https://huggingface.co/datasets/bettergovph/project-noah-hazard-maps/blob/main/README.md
Original project: https://noah.up.edu.ph/
