import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/widgets/report_flood_level_selector.dart';
import 'report_followup_test.dart' as fixtures;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
    'Selected severity remains legible and selection moves between all levels in both themes',
    (tester) async {
      for (final dark in [false, true]) {
        int? selected;
        await tester.pumpWidget(
          fixtures.shell(
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: StatefulBuilder(
                  builder: (context, setState) => ReportFloodLevelSelector(
                    selected: selected,
                    onChanged: (i) => setState(() => selected = i),
                  ),
                ),
              ),
            ),
            dark: dark,
          ),
        );
        for (final label in ['High', 'Low', 'Medium']) {
          final tile = find.byKey(ValueKey('flood-level-$label'));
          await tester.tap(tile);
          await tester.pumpAndSettle();
          expect(tester.widget<Semantics>(tile).properties.selected, isTrue);
          final box = tester.widget<AnimatedContainer>(
            find.descendant(of: tile, matching: find.byType(AnimatedContainer)),
          );
          final bg = (box.decoration as BoxDecoration).color!;
          final glyph = tester.widget<Icon>(
            find
                .descendant(
                  of: tile,
                  matching: find.byWidgetPredicate(
                    (w) => w is Icon && w.icon != Icons.check_circle_rounded,
                  ),
                )
                .first,
          );
          final a = bg.computeLuminance(), b = glyph.color!.computeLuminance();
          expect(
            (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
            greaterThan(3),
            reason: 'Selection must not hide the severity icon in its fill.',
          );
          expect(
            find.descendant(
              of: tile,
              matching: find.byIcon(Icons.check_circle_rounded),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'All levels remain reachable with enlarged English and Filipino text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil'])
        for (final dark in [false, true]) {
          final choices = <int>[];
          await tester.pumpWidget(
            fixtures.shell(
              Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ReportFloodLevelSelector(
                      selected: 2,
                      onChanged: choices.add,
                    ),
                  ),
                ),
              ),
              language: language,
              dark: dark,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final tile
              in find
                  .byType(Semantics)
                  .evaluate()
                  .where(
                    (e) =>
                        e.widget.key is ValueKey &&
                        (e.widget.key as ValueKey).value.toString().startsWith(
                          'flood-level-',
                        ),
                  )
                  .map((e) => find.byKey(e.widget.key!))
                  .toList()) {
            await fixtures.revealFollowupControl(tester, tile);
            await tester.tap(tile);
          }
          expect(choices, [0, 1, 2]);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
    },
  );
}
