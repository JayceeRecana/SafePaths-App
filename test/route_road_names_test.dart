import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/utils/route_road_names.dart';
import 'planner_design_test.dart' as fixtures;

void main() {
  test('provider summaries survive a safety refresh', () {
    final names = roadNamesFromDirections({
      'legs': [
        {
          'summary': ' Sample Road ',
          'steps': [
            {'name': 'Other Road'},
          ],
        },
        {'summary': 'Sample Road'},
      ],
    });
    expect(names, ['Sample Road']);
    expect(() => names.add('Invented Road'), throwsUnsupportedError);
    final original = fixtures.route(roadNames: names);
    expect(
      original.copyWith(summary: 'Conditions changed').roadNames,
      original.roadNames,
    );
  });

  test('unnamed summaries fall back only to actual named steps', () {
    expect(
      roadNamesFromDirections({
        'legs': [
          null,
          {
            'summary': ' ',
            'steps': [
              null,
              {'name': ''},
              {'name': 'First Road'},
              {'name': 'First Road'},
              {'name': 'Second Road'},
            ],
          },
        ],
      }),
      ['First Road', 'Second Road'],
    );
    expect(roadNamesFromDirections({}), isEmpty);
    expect(roadNamesFromDirections({'legs': 'bad data'}), isEmpty);
  });
}
