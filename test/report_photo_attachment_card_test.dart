import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/widgets/report_photo_attachment_card.dart';
import 'report_followup_test.dart' as fixtures;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  final preview = MemoryImage(
    Uint8List.fromList(img.encodePng(img.Image(width: 20, height: 30))),
  );
  testWidgets(
    'The empty photo area is full width and opens the existing picker callback',
    (tester) async {
      tester.view.physicalSize = const Size(390, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var picked = 0;
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ReportPhotoAttachmentCard(onPick: () => picked++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = find
          .ancestor(of: find.text('Add Photo'), matching: find.byType(InkWell))
          .first;
      expect(tester.getSize(target).width, greaterThan(280));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(140));
      await tester.tap(find.text('Add Photo'));
      expect(picked, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Selected evidence stays uncropped and change/remove reach the form callbacks',
    (tester) async {
      var changed = 0, removed = 0;
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: SingleChildScrollView(
              child: ReportPhotoAttachmentCard(
                preview: preview,
                onPick: () => changed++,
                onRemove: () => removed++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      expect(find.byIcon(Icons.verified), findsNothing);
      await tester.tap(find.text('Change photo'));
      await tester.tap(find.text('Remove photo'));
      expect(changed, 1);
      expect(removed, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Processing state prevents replacement and removal actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixtures.shell(
        Scaffold(
          body: ReportPhotoAttachmentCard(
            preview: preview,
            processing: true,
            onPick: () => fail('Picker opened during preparation'),
            onRemove: () => fail('Photo removed during preparation'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Validating and processing photo...'), findsOneWidget);
    expect(find.text('Change photo'), findsNothing);
    expect(find.text('Remove photo'), findsNothing);
    expect(find.text('Add Photo'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Both attachment states fit enlarged English and Filipino text in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil'])
        for (final dark in [false, true])
          for (final attached in [false, true]) {
            await tester.pumpWidget(
              fixtures.shell(
                Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ReportPhotoAttachmentCard(
                        preview: attached ? preview : null,
                        onPick: () {},
                        onRemove: () {},
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
            await tester.pumpWidget(const SizedBox.shrink());
          }
    },
  );
}
