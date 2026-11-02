// What scripts/extract_strings.dart and unit_test/l10n/translations_test.dart
// share: reading the app's messages into the English ARB file, and checking
// the translations against it. See docs/localization.md.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:collection/collection.dart';
import 'package:intl_translation/extract_messages.dart';
// ignore: implementation_imports
import 'package:intl_translation/src/arb_generation.dart';
// ignore: implementation_imports
import 'package:intl_utils/src/parser/icu_parser.dart';
// ignore: implementation_imports
import 'package:intl_utils/src/parser/message_format.dart';
import 'package:path/path.dart' as p;

/// The language every string is written in, and whose ARB file the others
/// translate.
const sourceLocale = 'en';

/// Where the translations that ship are, from rooster/.
const arbDirectory = 'assets/l10n';

/// The Dart files whose `Intl.message`s are translated, from rooster/: the
/// app's, and the calendar widget's that the app embeds. Sorted, so the
/// English ARB file comes out in the same order everywhere.
List<File> messageSources() {
  final files = <File>[];
  for (final directory in ['lib', '../widgets/calendar/lib']) {
    for (final entity in Directory(directory).listSync(recursive: true)) {
      final path = p.normalize(entity.path);
      if (entity is! File ||
          !path.endsWith('.dart') ||
          path.endsWith('.g.dart') ||
          p.split(path).contains('generated') ||
          path.contains('widgetbook')) {
        continue;
      }
      files.add(File(path));
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// The English ARB file the code's messages make: each message and its
/// metadata (description, placeholders in the order of the method's
/// parameters), in the order of [sources]. [warnings] gets what intl could
/// not read, such as a message whose name is not its method's.
Map<String, Object?> extractEnglish(List<File> sources,
    {List<String>? warnings}) {
  final extraction = MessageExtraction(
      onMessage: (message) => warnings?.add(message), warningsAreErrors: false);
  final arb = <String, Object?>{'@@locale': sourceLocale};
  final seenIn = <String, String>{};
  for (final file in sources) {
    for (final message in extraction.parseFile(file).values) {
      final entry = toARB(message: message);
      final name = message.name;
      // One name is one string: a second message under it would take the
      // first one's translation.
      if (seenIn.containsKey(name) &&
          jsonEncode(entry) !=
              jsonEncode({name: arb[name], '@$name': arb['@$name']})) {
        warnings?.add('$name is in ${seenIn[name]} and in ${file.path}, '
            'with a different text or description');
      }
      seenIn[name] ??= file.path;
      arb.addAll(entry);
    }
  }
  return arb;
}

/// Every `intl_<locale>.arb` in [arbDirectory], by locale, English included.
Map<String, Map<String, Object?>> readArbFiles() {
  final files = Directory(arbDirectory)
      .listSync()
      .whereType<File>()
      .where((file) =>
          p.basename(file.path).startsWith('intl_') &&
          file.path.endsWith('.arb'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final file in files)
      p.basenameWithoutExtension(file.path).substring('intl_'.length):
          (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>(),
  };
}

File arbFile(String locale) => File(p.join(arbDirectory, 'intl_$locale.arb'));

/// Writes [arb] the way the extraction tools do: two spaces, a newline at
/// the end.
void writeArb(String locale, Map<String, Object?> arb) => arbFile(locale)
    .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(arb)}\n');

/// The message keys of [arb], without its metadata.
Iterable<String> messageKeys(Map<String, Object?> arb) =>
    arb.keys.where((key) => !key.startsWith('@'));

/// [translation] in [english]'s order, without the strings the code no
/// longer has. Translations keep no metadata: the descriptions and
/// placeholders are the English file's.
Map<String, Object?> syncTranslation(String locale,
    Map<String, Object?> english, Map<String, Object?> translation) {
  return {
    '@@locale': locale,
    for (final key in messageKeys(english))
      if (translation[key] is String) key: translation[key],
  };
}

/// The names a message takes, each with how it takes it: `argument` for a
/// `{placeholder}`, `plural`, `select` or `gender` for the variable of one.
/// Null when the text is not valid ICU, or a plural or select has no
/// `other` case. A plural that lost a brace reads as plain text with an
/// argument in it, so comparing how, not only which, catches it.
Map<String, String>? messageArguments(String text) {
  final elements = IcuParser().parse(text);
  if (elements == null) return null;

  final names = <String, String>{};
  var valid = true;
  void visit(BaseElement element) {
    switch (element) {
      case ArgumentElement():
        names.putIfAbsent(element.value, () => 'argument');
      case PluralElement(:final options) ||
            SelectElement(:final options) ||
            GenderElement(:final options):
        names[element.value] = element.type.name;
        if (!options.any((option) => option.name == 'other')) valid = false;
        for (final option in options) {
          option.value.forEach(visit);
        }
    }
  }

  elements.forEach(visit);
  return valid ? names : null;
}

/// What is wrong with [translation] against [english]: strings missing or
/// no longer in the code, and strings whose placeholders differ from the
/// English (or that are not valid ICU). Empty when it is complete.
List<String> translationProblems(
    Map<String, Object?> english, Map<String, Object?> translation) {
  final problems = <String>[];
  for (final key in messageKeys(english)) {
    final text = translation[key];
    if (text is! String || text.trim().isEmpty) {
      problems.add('$key: not translated');
      continue;
    }

    final expected = messageArguments(english[key] as String);
    final actual = messageArguments(text);
    if (actual == null) {
      problems.add('$key: not valid ICU: $text');
    } else if (expected != null &&
        !const MapEquality<String, String>().equals(expected, actual)) {
      problems.add('$key: takes $actual instead of $expected: $text');
    }
  }
  for (final key in messageKeys(translation)) {
    if (!english.containsKey(key)) {
      problems.add('$key: the code no longer has this string');
    }
  }
  return problems;
}

/// Where a string literal that people read sits in the code: `path:line`
/// and the text.
class HardcodedString {
  HardcodedString(this.path, this.line, this.text);

  final String path;
  final int line;
  final String text;

  @override
  String toString() => '$path:$line: $text';
}

/// The comment that keeps a literal in the interface untranslated, on its
/// line or in the comment right above it, with the reason after the colon.
const notTranslatedMarker = 'Not translated:';

const _textWidgets = {'Text', 'SelectableText'};

/// Named arguments that hold text shown to people.
const _textArguments = {
  'tooltip',
  'hintText',
  'labelText',
  'helperText',
  'errorText',
  'semanticLabel',
  'semanticsLabel',
  'title',
  'subtitle',
  'label',
  'header',
  'description',
  'placeholder',
  'message',
};

/// String literals written straight into the interface in [sources]: the
/// text of a `Text`, or a named argument such as `tooltip:` or `label:`.
/// Literals with no word in them (`"•"`, `"$count"`) are not text, and a
/// [notTranslatedMarker] comment keeps one deliberately.
List<HardcodedString> hardcodedStrings(List<File> sources) {
  final found = <HardcodedString>[];
  for (final file in sources) {
    final content = file.readAsStringSync();
    final unit = parseString(
            content: content,
            featureSet: FeatureSet.latestLanguageVersion(),
            throwIfDiagnostics: false)
        .unit;
    final lines = content.split('\n');
    unit.accept(_HardcodedStringFinder((literal) {
      final line = unit.lineInfo.getLocation(literal.offset).lineNumber;
      // Its own line, and the comment right above it, however many lines
      // that comment takes.
      var marked = lines[line - 1].contains(notTranslatedMarker);
      for (var above = line - 2;
          !marked && above >= 0 && lines[above].trimLeft().startsWith('//');
          above--) {
        marked = lines[above].contains(notTranslatedMarker);
      }
      if (marked) return;
      found.add(HardcodedString(file.path, line, literal.toSource()));
    }));
  }
  return found;
}

class _HardcodedStringFinder extends RecursiveAstVisitor<void> {
  _HardcodedStringFinder(this.onFound);

  final void Function(StringLiteral literal) onFound;

  static final _word = RegExp(r'[A-Za-z]{2,}');

  bool _isText(Expression expression) {
    if (expression is! StringLiteral) return false;
    final parts = switch (expression) {
      SimpleStringLiteral(:final value) => [value],
      StringInterpolation(:final elements) => [
          for (final element in elements)
            if (element is InterpolationString) element.value
        ],
      AdjacentStrings(:final strings) => [
          for (final string in strings) string.toSource()
        ],
    };
    return parts.any(_word.hasMatch);
  }

  void _checkFirstArgument(String callee, ArgumentList arguments) {
    final name = callee.split('.');
    final isTextWidget = _textWidgets.contains(name.last) ||
        (name.length >= 2 && _textWidgets.contains(name[name.length - 2]));
    if (!isTextWidget) return;
    final first = arguments.arguments.firstOrNull;
    if (first != null && first is! NamedExpression && _isText(first)) {
      onFound(first as StringLiteral);
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (target is Identifier && target.name == 'Intl') return;
    _checkFirstArgument('${target?.toSource() ?? ''}.${node.methodName.name}',
        node.argumentList);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _checkFirstArgument(node.constructorName.toSource(), node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    if (_textArguments.contains(node.name.label.name) &&
        _isText(node.expression)) {
      onFound(node.expression as StringLiteral);
    }
    super.visitNamedExpression(node);
  }
}
