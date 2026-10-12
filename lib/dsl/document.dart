import '../models/date_only.dart';
import 'schema.dart';

/// A parsed argument or option value. [text] is its token text.
sealed class Value {
  const Value(this.text);

  final String text;
}

/// `yy-mm-dd`.
class DateValue extends Value {
  const DateValue(super.text, this.date);

  final DateOnly date;
}

/// `yy-mm` — a whole month.
class MonthValue extends Value {
  const MonthValue(super.text, this.year, this.month);

  final int year;
  final int month;

  DateOnly get lastDay => DateOnly.fromDateTime(DateTime(year, month + 1, 0));
}

/// `mo`..`su`, as [weekday] 1 = Mon .. 7 = Sun.
class WeekdayValue extends Value {
  const WeekdayValue(super.text, this.weekday);

  final int weekday;
}

/// A file path relative to the item's folder.
class PathValue extends Value {
  const PathValue(super.text);
}

/// One `keyword arg* (option value)*` clause from the keyword section, or the
/// clause of a `( … )` state line.
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

/// `-> label @target`. An empty [label] means the relationship is unlabeled.
class Relation {
  const Relation({
    required this.label,
    required this.target,
    required this.line,
  });

  final String label;

  /// The other item's file name without extension.
  final String target;
  final int line;
}

/// The error and warning codes from the dsl spec's `language.md`.
enum DiagnosticCode {
  empty('empty'),
  missingArg('missing_arg'),
  invalidValue('invalid_value'),
  unexpectedToken('unexpected_token'),
  duplicateKeyword('duplicate_keyword'),
  conflictingKeywords('conflicting_keywords'),
  invalidRelation('invalid_relation'),
  invalidState('invalid_state'),
  emptyExtra('empty_extra'),
  unknownKeyword('unknown_keyword', isError: false);

  const DiagnosticCode(this.code, {this.isError = true});

  /// The spec's name, e.g. `missing_arg`.
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
    this.body = const [],
    this.clauses = const [],
    this.relations = const [],
    this.state = const [],
    this.unknownLines = const [],
    this.extra,
    this.diagnostics = const [],
  });

  /// Verbatim body lines; blank lines inside kept. Empty only for an empty
  /// file.
  final List<String> body;

  final List<Clause> clauses;
  final List<Relation> relations;
  final List<Clause> state;

  /// Unknown keywords, each with the rest of its line, and whole unknown state
  /// lines, kept raw.
  final List<String> unknownLines;

  /// Verbatim extra lines, or null when the file has no extra marker.
  final List<String>? extra;

  final List<Diagnostic> diagnostics;

  Iterable<Diagnostic> get errors => diagnostics.where((d) => d.code.isError);
  Iterable<Diagnostic> get warnings =>
      diagnostics.where((d) => !d.code.isError);
  bool get isValid => errors.isEmpty;

  Clause? clause(String keyword) =>
      clauses.where((c) => c.keyword == keyword).firstOrNull;
}

const _extraMarker = 'extra';
final _keywordToken = RegExp(r'^[a-z]+$');
final _keywordOpener = RegExp(r'^([a-z]+)(?=\s|$)');
final _stateOpener = RegExp(r'^\(([a-z]+)(?=[\s)]|$)');
final _relationOpener = RegExp(r'^->\s');

bool _isExtraMarker(String line) => line.trimRight() == _extraMarker;

/// Whether a body line (other than the first) starts the keyword section.
bool _isSectionOpener(Schema schema, String line) {
  if (_isExtraMarker(line)) return true;
  if (_relationOpener.hasMatch(line)) {
    return line.trim().split(RegExp(r'\s+')).last.startsWith('@');
  }
  final state = _stateOpener.firstMatch(line)?.group(1);
  if (state != null) return schema.keywords[state]?.role == Role.state;
  final keyword = _keywordOpener.firstMatch(line)?.group(1);
  return schema.keywords[keyword]?.role.opensSection ?? false;
}

/// Parses one item file. Never throws — problems become [Diagnostic]s.
Document parseDocument(Schema schema, String text) {
  final lines = text.split('\n').map((l) => l.replaceAll('\r', '')).toList();

  final first = lines.indexWhere((l) => l.trim().isNotEmpty);
  if (first == -1) {
    return const Document(diagnostics: [Diagnostic(DiagnosticCode.empty)]);
  }

  final boundary = _indexFrom(
    lines,
    first + 1,
    (l) => _isSectionOpener(schema, l),
  );
  final marker = _indexFrom(lines, boundary, _isExtraMarker);

  final parser = _SectionParser(schema);
  for (var i = boundary; i < marker; i++) {
    parser.parseLine(lines[i], i + 1);
  }
  parser.checkExcludes();

  List<String>? extra;
  if (marker < lines.length) {
    extra = _trimBlankEnds(lines.sublist(marker + 1));
    if (extra.isEmpty) {
      parser.diagnostics.add(
        Diagnostic(
          DiagnosticCode.emptyExtra,
          line: marker + 1,
          detail: _extraMarker,
        ),
      );
    }
  }

  return Document(
    body: _trimBlankEnds(lines.sublist(first, boundary)),
    clauses: parser.clauses,
    relations: parser.relations,
    state: parser.state,
    unknownLines: parser.unknownLines,
    extra: extra,
    diagnostics: parser.diagnostics,
  );
}

/// First index at or after [from] whose line satisfies [test], or
/// `lines.length`.
int _indexFrom(List<String> lines, int from, bool Function(String) test) {
  for (var i = from; i < lines.length; i++) {
    if (test(lines[i])) return i;
  }
  return lines.length;
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

class _SectionParser {
  _SectionParser(this.schema);

  final Schema schema;
  final clauses = <Clause>[];
  final relations = <Relation>[];
  final state = <Clause>[];
  final unknownLines = <String>[];
  final diagnostics = <Diagnostic>[];
  final _seen = <String>{};

  bool _isKnownKeyword(_Token t) =>
      !t.quoted && schema.keywords.containsKey(t.text);

  void parseLine(String rawLine, int lineNo) {
    final line = rawLine.trim();
    if (line.isEmpty) return;

    if (line == '->' || _relationOpener.hasMatch(line)) {
      _relation(line, lineNo);
    } else if (line.startsWith('(')) {
      _stateLine(line, lineNo);
    } else {
      _clauseLine(line, lineNo);
    }
  }

  void _relation(String line, int lineNo) {
    final rest = line.substring(2).trim();
    final target = rest.isEmpty ? '' : rest.split(RegExp(r'\s+')).last;
    if (target.length < 2 ||
        !target.startsWith('@') ||
        target.contains('/') ||
        target.contains(r'\')) {
      _error(DiagnosticCode.invalidRelation, lineNo, line);
      return;
    }
    relations.add(
      Relation(
        label: rest.substring(0, rest.length - target.length).trim(),
        target: target.substring(1),
        line: lineNo,
      ),
    );
  }

  void _stateLine(String line, int lineNo) {
    if (!line.endsWith(')')) {
      _error(DiagnosticCode.invalidState, lineNo, line);
      return;
    }
    final tokens = _tokenize(line.substring(1, line.length - 1));
    final keyword = tokens.firstOrNull;
    if (keyword == null ||
        keyword.quoted ||
        !_keywordToken.hasMatch(keyword.text)) {
      _error(DiagnosticCode.invalidState, lineNo, line);
      return;
    }
    final spec = schema.keywords[keyword.text];
    if (spec == null) {
      _unknown(line, lineNo, keyword.text);
      return;
    }
    if (spec.role != Role.state) {
      _error(DiagnosticCode.invalidState, lineNo, line);
      return;
    }
    final parsed = _clause(tokens, 0, lineNo);
    if (parsed == null) return;
    if (parsed.next < tokens.length) {
      _error(DiagnosticCode.unexpectedToken, lineNo, tokens[parsed.next].text);
      return;
    }
    state.add(parsed.clause);
  }

  void _clauseLine(String line, int lineNo) {
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
      if (spec.role == Role.state) {
        _error(DiagnosticCode.unexpectedToken, lineNo, token.text);
        return;
      }
      final parsed = _clause(tokens, i, lineNo);
      if (parsed == null) return;
      clauses.add(parsed.clause);
      i = parsed.next;
    }
  }

  /// The clause whose keyword is `tokens[i]`, and the index after it; null
  /// (with an error reported) when it's malformed.
  ({Clause clause, int next})? _clause(List<_Token> tokens, int i, int lineNo) {
    final spec = schema.keywords[tokens[i].text]!;
    i++;
    if (!_seen.add(spec.name)) {
      _error(DiagnosticCode.duplicateKeyword, lineNo, spec.name);
      return null;
    }

    final args = <Value>[];
    for (final arg in spec.args) {
      if (i >= tokens.length || _isKnownKeyword(tokens[i])) {
        _error(DiagnosticCode.missingArg, lineNo, spec.name);
        return null;
      }
      final value = _value(tokens[i], arg);
      if (value == null) {
        _error(DiagnosticCode.invalidValue, lineNo, tokens[i].text);
        return null;
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
        return null;
      }
      if (i >= tokens.length || _isKnownKeyword(tokens[i])) {
        _error(DiagnosticCode.missingArg, lineNo, name);
        return null;
      }
      final value = _value(tokens[i], spec.options[name]!);
      if (value == null) {
        _error(DiagnosticCode.invalidValue, lineNo, tokens[i].text);
        return null;
      }
      options[name] = value;
      i++;
    }

    return (
      clause: Clause(
        keyword: spec.name,
        line: lineNo,
        args: args,
        options: options,
      ),
      next: i,
    );
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

  /// Only a `path` may be quoted.
  Value? _value(_Token token, ValueSpec spec) {
    for (final type in spec.types) {
      if (token.quoted && type != ValueType.path) continue;
      final value = switch (type) {
        ValueType.date => _date(token.text),
        ValueType.month => _month(token.text),
        ValueType.weekday => _weekday(token.text),
        ValueType.path => _path(token.text),
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
  return date == DateOnly(y, m, d) ? DateValue(text, date) : null;
}

/// `yy-mm`, year 20yy.
MonthValue? _month(String text) {
  final match = RegExp(r'^(\d{2})-(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final m = int.parse(match.group(2)!);
  if (m < 1 || m > 12) return null;
  return MonthValue(text, 2000 + int.parse(match.group(1)!), m);
}

WeekdayValue? _weekday(String text) {
  final weekday = _weekdays[text];
  return weekday == null ? null : WeekdayValue(text, weekday);
}

/// Relative to the item's folder: not empty, no leading `/`, no `\`, no `..`
/// segment.
PathValue? _path(String text) {
  final valid =
      text.isNotEmpty &&
      !text.startsWith('/') &&
      !text.contains(r'\') &&
      !text.split('/').contains('..');
  return valid ? PathValue(text) : null;
}
