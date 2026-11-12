import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/widgets/communication_admin_dialog.dart';

void main() {
  testWidgets(
    'feedback review fits a small display with large text and does not preclaim a fix',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => CommunicationAdminDialog(
                    kind: 'feedback',
                    id: 'test',
                    loadContext: (kind, id) async => {
                      'token': 'b' * 64,
                      'revision': 1,
                      'status': 'reviewed',
                      'owned': true,
                      'allowFollowUp': false,
                    },
                    saveAction: (op, data) async => {'queuedCount': 0},
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Factual update / closure note'), findsOneWidget);
      expect(find.textContaining('dispatched'), findsNothing);
      expect(find.textContaining('investigated and fixed'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a failed feedback save preserves the draft and sends a reply without silently closing it',
    (tester) async {
      Map<String, dynamic>? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => CommunicationAdminDialog(
                    kind: 'feedback',
                    id: 'test',
                    loadContext: (kind, id) async => {
                      'token': 'b' * 64,
                      'revision': 1,
                      'status': 'reviewed',
                      'owned': true,
                      'allowFollowUp': false,
                    },
                    saveAction: (op, data) async {
                      captured = data;
                      throw StateError('Synthetic service interruption');
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Factual acknowledgement for review',
      );
      await tester.tap(find.text('Save update'));
      await tester.pumpAndSettle();
      expect(captured?['action'], 'reply');
      expect(captured?['notify'], false);
      expect(captured?.containsKey('outcome'), false);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Factual acknowledgement for review',
      );
      expect(
        find.textContaining('Synthetic service interruption'),
        findsOneWidget,
      );
    },
  );
}
