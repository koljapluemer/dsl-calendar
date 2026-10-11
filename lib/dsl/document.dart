import '../models/date_only.dart';
import 'schema.dart';

/// A parsed argument or option value.
sealed class Value {
  const Value();
}

/// `yy-mm-dd`.
class DateValue extends Value {
  const DateValue(this.date);

  final DateOnly date;
}

/// `yy-mm` — a whole month.
class MonthValue extends Value {
  const MonthValue(this.year, this.month);

  final int year;
  final int month;

  DateOnly get lastDay => DateOnly.fromDateTime(DateTime(year, month + 1, 0));
}

/// `mo`..`su`, as [weekday] 1 = Mon .. 7 = Sun.
class WeekdayValue extends Value {
  const WeekdayValue(this.weekday);

  final int weekday;
}

/// One `keyword arg* (option value)*` clause from the keyword section.
class Clause {
  const Clause({
    required this.keyword,
    required this.line,
    required this.args,
    required this.options,
  });

  final String keyword;
  final int line;
  final List<Value> args;
  final Map<String, Value> options;
}

/// The error and warning codes from the dsl spec's `language.md`.
enum DiagnosticCode {
  empty('empty'),
  noPrimary('no_primary'),
  missingArg('missing_arg'),
  invalidValue('invalid_value'),
  unexpectedToken('unexpected_token'),
  duplicateKeyword('duplicate_keyword'),
  conflictingKeywords('conflicting_keywords'),
  unknownKeyword('unknown_keyword', isError: false);

  const DiagnosticCode(this.code, {this.isError = true});

  /// The spec's name, e.g. `no_primary`.
  final String code;
  final bool isError;
}

class Diagnostic {
  const Diagnostic(this.code, {this.line, this.detail});

  final DiagnosticCode code;

  /// 1-based line number in the file, when the problem has one.
  final int? line;

  /// The offending keyword or token.
  final String? detail;

  @override
  String toString() => [
    code.code,
    if (line != null) 'line $line',
    if (detail != null) '"$detail"',
  ].join(' · ');
}

/// A file parsed per the dsl spec, before any frontend gives its keywords
/// meaning. When [isValid] is false, [clauses] may be incomplete.
class Document {
  const Document({
    this.title = '',
    this.description = const [],
    this.clauses = const [],
    this.unknownLines = const [],
    this.diagnostics = const [],
  });

  final String title;

  /// Verbatim lines between title and boundary; blank lines inside kept.
  final List<String> description;

  final List<Clause> clauses;

  /// Unknown keywords, each with the rest of its line, kept raw.
  final List<String> unknownLines;

  final List<Diagnostic> diagnostics;

  Iterable<Diagnostic> get errors => diagnostics.where((d) => d.code.isError);
  Iterable<Diagnostic> get warnings =>
      diagnostics.where((d) => !d.code.isError);
  bool get isValid => errors.isEmpty;

  Clause? clause(String keyword) =>
      clauses.where((c) => c.keyword == keyword).firstOrNull;
}

final _keywordToken = RegExp(r'^[a-z]+$');
final _boundary = RegExp(r'^([a-z]+)(?=\s|$)');

/// Parses one item file. Never throws — problems become [Diagnostic]s.
Document parseDocument(Schema schema, String text) {
  final lines = text.split('\n').map((l) => l.replaceAll('\r', '')).toList();

  final titleIndex = lines.indexWhere((l) => l.trim().isNotEmpty);
  if (titleIndex == -1) {
    return const Document(diagnostics: [Diagnostic(DiagnosticCode.empty)]);
  }
  final title = lines[titleIndex].trim();

  int? boundary;
  for (var i = titleIndex + 1; i < lines.length; i++) {
    final word = _boundary.firstMatch(lines[i])?.group(1);
    if (word != null && (schema.keywords[word]?.primary ?? false)) {
      boundary = i;
      break;
    }
  }

  final description = _trimBlankEnds(
    lines.sublist(titleIndex + 1, boundary ?? lines.length),
  );
  if (boundary == null) {
    return Document(
      title: title,
      description: description,
      diagnostics: const [Diagnostic(DiagnosticCode.noPrimary)],
    );
  }

  final parser = _KeywordParser(schema);
  for (var i = boundary; i < lines.length; i++) {
    parser.parseLine(lines[i], i + 1);
  }
  parser.checkExcludes();

  return Document(
    title: title,
    description: description,
    clauses: parser.clauses,
    unknownLines: parser.unknownLines,
    diagnostics: parser.diagnostics,
  );
}

List<String> _trimBlankEnds(List<String> lines) {
  var start = 0;
  var end = lines.length;
  while (start < end && lines[start].trim().isEmpty) {
    start++;
  }
  while (end > start && lines[end - 1].trim().isEmpty) {
    end--;
  }
  return lines.sublist(start, end);
}

class _Token {
  const _Token(this.text, this.start, {required this.quoted});

  final String text;

  /// Offset in the (trimmed) line, for keeping unknown keywords' lines raw.
  final int start;
  final bool quoted;
}

/// Whitespace-separated tokens; a token starting with `"` runs to the next
/// unescaped `"` (or the end of the line) and may contain spaces.
List<_Token> _tokenize(String line) {
  final tokens = <_Token>[];
  var i = 0;
  bool isSpace(int at) => line[at].trim().isEmpty;
  while (i < line.length) {
    if (isSpace(i)) {
      i++;
      continue;
    }
    final start = i;
    if (line[i] == '"') {
      final buf = StringBuffer();
      i++;
      while (i < line.length && line[i] != '"') {
        if (line[i] == r'\' && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i += 2;
        } else {
          buf.write(line[i]);
          i++;
        }
      }
      i++; // the closing quote
      tokens.add(_Token(buf.toString(), start, quoted: true));
    } else {
      while (i < line.length && !isSpace(i)) {
        i++;
      }
      tokens.add(_Token(line.substring(start, i), start, quoted: false));
    }
  }
  return tokens;
}

class _KeywordParser {
  _KeywordParser(this.schema);

  final Schema schema;
  final clauses = <Clause>[];
  final unknownLines = <String>[];
  final diagnostics = <Diagnostic>[];
  final _seen = <String>{};

  bool _isKnownKeyword(_Token t) =>
      !t.quoted && schema.keywords.containsKey(t.text);

  void parseLine(String rawLine, int lineNo) {
    final line = rawLine.trim();
    if (line.isEmpty) return;

    // Reserved for written-back state; treated like an unknown keyword line.
    if (line.startsWith('(')) {
      _unknown(line, lineNo, '(');
      return;
    }

    final tokens = _tokenize(line);
    var i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      if (token.quoted || !_keywordToken.hasMatch(token.text)) {
        _error(DiagnosticCode.unexpectedToken, lineNo, token.text);
        return;
      }
      final spec = schema.keywords[token.text];
      if (spec == null) {
        _unknown(line.substring(token.start), lineNo, token.text);
        return;
      }
      i++;
      if (!_seen.add(spec.name)) {
        _error(DiagnosticCode.duplicateKeyword, lineNo, spec.name);
        return;
      }

      final args = <Value>[];
      for (final arg in spec.args) {
        if (i >= tokens.length || _isKnownKeyword(tokens[i])) {
          _error(DiagnosticCode.missingArg, lineNo, spec.name);
          return;
        }
        final value = _value(tokens[i], arg);
        if (value == null) {
          _error(DiagnosticCode.invalidValue, lineNo, tokens[i].text);
          return;
        }
        args.add(value);
        i++;
      }

      final options = <String, Value>{};
      while (i < tokens.length &&
          !tokens[i].quoted &&
          spec.options.containsKey(tokens[i].text)) {
        final name = tokens[i].text;
        i++;
        if (options.containsKey(name)) {
          _error(DiagnosticCode.duplicateKeyword, lineNo, name);
          return;
        }
        if (i >= tokens.length || _isKnownKeyword(tokens[i])) {
          _error(DiagnosticCode.missingArg, lineNo, name);
          return;
        }
        final value = _value(tokens[i], spec.options[name]!);
        if (value == null) {
          _error(DiagnosticCode.invalidValue, lineNo, tokens[i].text);
          return;
        }
        options[name] = value;
        i++;
      }

      clauses.add(
        Clause(keyword: spec.name, line: lineNo, args: args, options: options),
      );
    }
  }

  /// Reports each excluded pair once, on the later clause's line.
  void checkExcludes() {
    for (var a = 0; a < clauses.length; a++) {
      for (var b = a + 1; b < clauses.length; b++) {
        final first = clauses[a].keyword;
        final second = clauses[b].keyword;
        final excluded =
            schema.keywords[first]!.excludes.contains(second) ||
            schema.keywords[second]!.excludes.contains(first);
        if (excluded) {
          _error(
            DiagnosticCode.conflictingKeywords,
            clauses[b].line,
            '$first, $second',
          );
        }
      }
    }
  }

  void _error(DiagnosticCode code, int line, String detail) =>
      diagnostics.add(Diagnostic(code, line: line, detail: detail));

  void _unknown(String raw, int line, String keyword) {
    unknownLines.add(raw);
    diagnostics.add(
      Diagnostic(DiagnosticCode.unknownKeyword, line: line, detail: keyword),
    );
  }

  Value? _value(_Token token, ValueSpec spec) {
    if (token.quoted) return null;
    for (final type in spec.types) {
      final value = switch (type) {
        ValueType.date => _date(token.text),
        ValueType.month => _month(token.text),
        ValueType.weekday => _weekday(token.text),
      };
      if (value != null) return value;
    }
    return null;
  }
}

const _weekdays = {
  'mo': DateTime.monday,
  'tu': DateTime.tuesday,
  'we': DateTime.wednesday,
  'th': DateTime.thursday,
  'fr': DateTime.friday,
  'sa': DateTime.saturday,
  'su': DateTime.sunday,
};

/// `yy-mm-dd`, year 20yy, only when it's a real calendar date.
DateValue? _date(String text) {
  final match = RegExp(r'^(\d{2})-(\d{2})-(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final y = 2000 + int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  final d = int.parse(match.group(3)!);
  final date = DateOnly.fromDateTime(DateTime(y, m, d));
  return date == DateOnly(y, m, d) ? DateValue(date) : null;
}

/// `yy-mm`, year 20yy.
MonthValue? _month(String text) {
  final match = RegExp(r'^(\d{2})-(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final m = int.parse(match.group(2)!);
  if (m < 1 || m > 12) return null;
  return MonthValue(2000 + int.parse(match.group(1)!), m);
}

WeekdayValue? _weekday(String text) {
  final weekday = _weekdays[text];
  return weekday == null ? null : WeekdayValue(weekday);
}
