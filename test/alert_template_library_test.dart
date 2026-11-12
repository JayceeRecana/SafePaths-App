import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'package:safepaths_app/widgets/alert_template_library.dart';

AlertTemplate sample([String id = 'saved']) => AlertTemplate(
  id: id,
  label: 'Flood reminder',
  title: 'Flood advisory',
  message: 'Check the latest road conditions before travelling.',
  severity: 1,
);

Widget shell(
  Widget library, {
  bool dark = false,
  String language = 'en',
  double scale = 1,
  double keyboard = 0,
}) => MaterialApp(
  theme: AppTheme.theme,
  darkTheme: AppTheme.darkTheme,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('fil')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: child!,
  ),
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => library,
        ),
        child: const Text('Open'),
      ),
    ),
  ),
);

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
}

Future<void> create(WidgetTester tester) async {
  await tapVisible(tester, find.text('Create template').first);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('template-name')),
    'Flood reminder',
  );
  await tester.enterText(
    find.byKey(const ValueKey('template-title')),
    'Flood advisory',
  );
  await tester.enterText(
    find.byKey(const ValueKey('template-message')),
    'Check the latest road conditions before travelling.',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'TEMPLATE_TEST=true');
  });
  tearDownAll(() => SimulatedWeatherService.instance.dispose());

  testWidgets(
    'saved templates open first and choosing one does not save or publish',
    (tester) async {
      AlertTemplate? used;
      var saves = 0;
      await tester.pumpWidget(
        shell(
          AlertTemplateLibrary(
            onUseTemplate: (v) => used = v,
            loadTemplates: () => [sample()],
            saveTemplate: (_) async {
              saves++;
            },
          ),
        ),
      );
      await open(tester);
      expect(find.text('Saved templates (1)'), findsOneWidget);
      expect(find.byKey(const ValueKey('template-name')), findsNothing);
      await tester.tap(find.text('Use template'));
      await tester.pumpAndSettle();
      expect(used!.id, 'saved');
      expect(saves, 0);
      expect(find.byType(AlertTemplateLibrary), findsNothing);
    },
  );

  testWidgets(
    'save and use waits for confirmation, retains failures and reuses the retry ID',
    (tester) async {
      final sent = <AlertTemplate>[];
      final completion = Completer<void>();
      AlertTemplate? used;
      await tester.pumpWidget(
        shell(
          AlertTemplateLibrary(
            onUseTemplate: (v) => used = v,
            loadTemplates: () => [],
            saveTemplate: (v) async {
              sent.add(v);
              if (sent.length == 1) throw StateError('Synthetic save failure');
              return completion.future;
            },
          ),
        ),
      );
      await open(tester);
      await create(tester);
      await tapVisible(tester, find.text('Save and use'));
      await tester.pumpAndSettle();
      expect(used, isNull);
      expect(
        find.textContaining('Could not confirm the save.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('template-message')),
            )
            .controller!
            .text,
        sample().message,
      );
      await tapVisible(tester, find.text('Save and use'));
      await tester.pump();
      expect(sent.length, 2);
      expect(sent[1].id, sent[0].id);
      expect(used, isNull);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
            .onPressed,
        isNull,
      );
      completion.complete();
      await tester.pumpAndSettle();
      expect(used!.id, sent[0].id);
      expect(find.byType(AlertTemplateLibrary), findsNothing);
    },
  );

  testWidgets(
    'save only validates usable content and returns to the library without applying',
    (tester) async {
      final saved = <AlertTemplate>[];
      var uses = 0;
      await tester.pumpWidget(
        shell(
          AlertTemplateLibrary(
            onUseTemplate: (_) => uses++,
            loadTemplates: () => saved,
            saveTemplate: (v) async => saved.add(v),
          ),
        ),
      );
      await open(tester);
      await tapVisible(tester, find.text('Create template').first);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Save template'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.text('Enter a template name.'), findsOneWidget);
      await create(tester);
      await tapVisible(tester, find.text('Save template'));
      await tester.pumpAndSettle();
      expect(saved, hasLength(1));
      expect(uses, 0);
      expect(find.text('Saved templates (1)'), findsOneWidget);
      expect(
        find.text('Template saved. No alert was published.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a timed-out save retains the draft and late success cannot apply it',
    (tester) async {
      final completion = Completer<void>();
      var uses = 0;
      await tester.pumpWidget(
        shell(
          AlertTemplateLibrary(
            onUseTemplate: (_) => uses++,
            loadTemplates: () => [],
            saveTemplate: (_) => completion.future,
          ),
        ),
      );
      await open(tester);
      await create(tester);
      await tapVisible(tester, find.text('Save and use'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not confirm the save.'),
        findsOneWidget,
      );
      completion.complete();
      await tester.pumpAndSettle();
      expect(uses, 0);
      expect(find.byKey(const ValueKey('template-name')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'deletion is confirmed and a failed deletion keeps the saved template',
    (tester) async {
      final saved = [sample()];
      var deletes = 0;
      await tester.pumpWidget(
        shell(
          AlertTemplateLibrary(
            onUseTemplate: (_) {},
            loadTemplates: () => saved,
            deleteTemplate: (id) async {
              if (++deletes == 1) {
                throw StateError('Synthetic deletion failure');
              }
              saved.removeWhere((t) => t.id == id);
            },
          ),
        ),
      );
      await open(tester);
      await tester.tap(find.byTooltip('Delete template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deletes, 0);
      await tester.tap(find.byTooltip('Delete template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(saved, hasLength(1));
      expect(
        find.textContaining('Could not confirm deletion.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Delete template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.text('No saved templates yet'), findsOneWidget);
    },
  );

  test(
    'confirmed mock retries update one saved template instead of duplicating it',
    () async {
      final state = AppStateService.instance,
          before = [...AppStateService.instance.templates];
      addTearDown(() {
        state.templates
          ..clear()
          ..addAll(before);
      });
      await state.addAlertTemplate(sample('retry-id'));
      await state.addAlertTemplate(sample('retry-id'));
      expect(state.templates.where((t) => t.id == 'retry-id'), hasLength(1));
      await state.deleteAlertTemplate('retry-id');
      expect(state.templates.where((t) => t.id == 'retry-id'), isEmpty);
    },
  );

  testWidgets(
    'library and form fit both themes and languages with large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          for (final keyboard in [0.0, 280.0]) {
            await tester.pumpWidget(
              shell(
                AlertTemplateLibrary(
                  onUseTemplate: (_) {},
                  loadTemplates: () => [sample()],
                ),
                language: language,
                dark: dark,
                scale: 2,
                keyboard: keyboard,
              ),
            );
            await open(tester);
            expect(tester.takeException(), isNull);
            final label = language == 'en'
                ? 'Create template'
                : 'Gumawa ng template';
            await tapVisible(tester, find.text(label).first);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('template-name')), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );
}
