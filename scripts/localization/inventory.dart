import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class Inventory extends RecursiveAstVisitor<void> {
  final List<SimpleStringLiteral> strings = [];
  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    AstNode expression = node;
    while (true) {
      final parent = expression.parent;
      if (parent is ConditionalExpression &&
              (parent.thenExpression == expression ||
                  parent.elseExpression == expression) ||
          parent is BinaryExpression && parent.operator.lexeme == '??' ||
          parent is SwitchExpressionCase && parent.expression == expression ||
          parent is SwitchExpression) {
        expression = parent!;
      } else {
        break;
      }
    }
    final parent = expression.parent;
    bool ui = false;
    if (parent is ArgumentList && parent.arguments.first == expression) {
      final call = parent.parent;
      ui =
          call is InstanceCreationExpression &&
          ['Text', 'TextSpan'].contains(call.constructorName.type.toSource());
      ui =
          ui ||
          call is MethodInvocation &&
              ['Text', 'TextSpan'].contains(call.methodName.name);
      ui =
          ui ||
          call is MethodInvocation &&
              call.methodName.name.startsWith('_build') &&
              RegExp(r'^[A-Z]').hasMatch(node.value);
    }
    if (parent is NamedExpression) {
      ui = [
        'labelText',
        'hintText',
        'helperText',
        'errorText',
        'tooltip',
        'semanticLabel',
        'title',
        'subtitle',
        'label',
        'emptyMessage',
      ].contains(parent.name.label.name);
      if (parent.name.label.name == 'text') {
        final call = parent.parent?.parent;
        ui =
            call is MethodInvocation && call.methodName.name == 'TextSpan' ||
            call is InstanceCreationExpression &&
                call.constructorName.type.toSource() == 'TextSpan';
      }
    }
    if (ui &&
        node.value.contains(RegExp('[a-zA-Z]')) &&
        node.value != 'SafePaths')
      strings.add(node);
    super.visitSimpleStringLiteral(node);
  }
}

void main(List<String> args) {
  final entries = <String, List<String>>{};
  final files = <File>[
    for (final directory in ['lib/screens', 'lib/widgets'])
      ...Directory(directory)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
  ];
  for (final file in files) {
    final unit = parseString(content: file.readAsStringSync()).unit;
    final visitor = Inventory();
    unit.accept(visitor);
    for (final string in visitor.strings) {
      (entries[string.value] ??= []).add(file.path.replaceAll('\\', '/'));
    }
  }
  File(
    'scripts/localization/inventory.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(entries));
  stdout.writeln('${entries.length} distinct UI messages');
}
