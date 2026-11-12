import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'inventory.dart';

/// One-time AST migration, also usable to inventory remaining static copy.
/// Only literal interface messages are translated; authored content is preserved.
void main(List<String> args) {
  if (args.isNotEmpty &&
      (args.length != 1 || args.single != '--catalog-only')) {
    throw ArgumentError(
      'Use --catalog-only to regenerate messages without migrating widget source.',
    );
  }
  final messages = <String, dynamic>{};
  for (final file in Directory(
    'lib/l10n',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
    messages.addAll(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
  }
  final encoded = const JsonEncoder.withIndent(
    '  ',
  ).convert(messages).replaceAll(r'$', r'\$');
  File('lib/l10n/app_strings.dart').writeAsStringSync(
    '''// Generated from the JSON catalogs by scripts/localization/apply.dart.
import 'package:flutter/widgets.dart';

const filipinoMessages = <String, String>$encoded;

/// Call only for interface copy, never for user reports or broadcast contents.
String tr(BuildContext context, String message) =>
    Localizations.localeOf(context).languageCode == 'fil'
        ? filipinoMessages[message] ?? message
        : message;
''',
  );
  if (args.contains('--catalog-only')) {
    stdout.writeln(
      'Generated the translation catalog only. Widget source unchanged.',
    );
    return;
  }
  var total = 0;
  final remaining = <String>{};
  for (final directory in ['lib/screens', 'lib/widgets']) {
    for (final file
        in Directory(directory)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      var source = file.readAsStringSync();
      final unit = parseString(content: source).unit;
      final visitor = Inventory();
      unit.accept(visitor);
      final edits = <int, ({int length, String value})>{};
      for (final node in visitor.strings) {
        // Seed data and const model declarations are not widget copy.
        var inFunction = false;
        for (
          AstNode? ancestor = node.parent;
          ancestor != null;
          ancestor = ancestor.parent
        ) {
          if (ancestor is FunctionBody) {
            inFunction = true;
            break;
          }
        }
        if (!inFunction) continue;
        if (!messages.containsKey(node.value)) {
          remaining.add(node.value);
          continue;
        }
        edits[node.offset] = (
          length: node.length,
          value: 'tr(context, ${node.toSource()})',
        );
        for (
          AstNode? ancestor = node.parent;
          ancestor != null;
          ancestor = ancestor.parent
        ) {
          if (ancestor is InstanceCreationExpression &&
              ancestor.keyword?.lexeme == 'const') {
            edits[ancestor.keyword!.offset] = (length: 6, value: '');
          }
          if (ancestor is TypedLiteral && ancestor.constKeyword != null) {
            edits[ancestor.constKeyword!.offset] = (length: 6, value: '');
          }
        }
        total++;
      }
      if (edits.isEmpty) continue;
      for (final offset
          in edits.keys.toList()..sort((a, b) => b.compareTo(a))) {
        final edit = edits[offset]!;
        source = source.replaceRange(offset, offset + edit.length, edit.value);
      }
      final relative = directory == 'lib/screens' ? '../../' : '../';
      final import = "import '${relative}l10n/app_strings.dart';";
      if (!source.contains(import)) source = '$import\n$source';
      file.writeAsStringSync(source);
    }
  }
  File('scripts/localization/remaining.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(remaining.toList()..sort()),
  );
  stdout.writeln(
    'Translated $total interface occurrences; ${remaining.length} distinct static messages remain.',
  );
}
