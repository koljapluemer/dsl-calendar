import 'date_only.dart';
import 'item.dart';

/// Every reserved keyword from the language spec. A line after the title whose
/// first word is one of these is a keyword line; any other line is a note.
const reservedKeywords = {
  'appointment',
  'recurring',
  'goal',
  'weekly',
  'prio',
  'reconsider',
  'raincheck',
  'finishable',
  'next',
  'iterable',
};

const _weekdays = {
  'mo': DateTime.monday,
  'tu': DateTime.tuesday,
  'we': DateTime.wednesday,
  'th': DateTime.thursday,
  'fr': DateTime.friday,
  'sa': DateTime.saturday,
  'su': DateTime.sunday,
};

sealed class ParseResult {
  const ParseResult();
}

class ParsedItem extends ParseResult {
  const ParsedItem(this.item);

  final Item item;
}

/// A file that couldn't be turned into an [Item], and why.
class ParseError extends ParseResult {
  const ParseError(this.path, this.message);

  final String path;
  final String message;
}

/// Parses the full text of one item file. Never throws — anything wrong comes
/// back as a [ParseError].
ParseResult parseItem(String path, String text) {
  final lines = [
    for (final raw in text.split('\n'))
      if (raw.trim().isNotEmpty) raw.trim(),
  ];
  if (lines.isEmpty) return ParseError(path, 'File is empty');

  final title = lines.first;
  final notes = <String>[];
  final extraLines = <String>[];
  final kinds = <ItemKind>[];
  var inKeywords = false;

  for (final line in lines.skip(1)) {
    final words = line.split(RegExp(r'\s+'));
    final keyword = words.first;
    if (!reservedKeywords.contains(keyword)) {
      if (inKeywords) {
        return ParseError(path, 'Text line after keyword lines: "$line"');
      }
      notes.add(line);
      continue;
    }
    inKeywords = true;
    final args = words.skip(1).toList();
    switch (keyword) {
      case 'appointment':
        final date = args.length == 1 ? _parseDate(args[0]) : null;
        if (date == null) {
          return ParseError(path, 'Expected "appointment yy-mm-dd": "$line"');
        }
        kinds.add(Appointment(date));
      case 'recurring':
        final kind = _parseRecurring(args);
        if (kind == null) {
          return ParseError(
            path,
            'Expected "recurring <weekday> [until <date>]": "$line"',
          );
        }
        kinds.add(kind);
      default:
        extraLines.add(line);
    }
  }

  if (kinds.isEmpty) {
    return ParseError(path, 'Needs an "appointment" or "recurring" line');
  }
  if (kinds.length > 1) {
    return ParseError(path, 'Has more than one "appointment"/"recurring" line');
  }
  return ParsedItem(
    Item(
      path: path,
      title: title,
      notes: notes,
      kind: kinds.single,
      extraLines: extraLines,
    ),
  );
}

Recurring? _parseRecurring(List<String> args) {
  if (args.isEmpty) return null;
  final weekday = _weekdays[args[0]];
  if (weekday == null) return null;
  if (args.length == 1) return Recurring(weekday);
  if (args.length != 3 || args[1] != 'until') return null;
  final until = _parseDate(args[2]) ?? _parseYearMonthEnd(args[2]);
  if (until == null) return null;
  return Recurring(weekday, until: until);
}

/// `yy-mm-dd`, read as 20yy. Null unless it's a real calendar date.
DateOnly? _parseDate(String value) {
  final match = RegExp(r'^(\d{2})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final y = 2000 + int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  final d = int.parse(match.group(3)!);
  final date = DateOnly.fromDateTime(DateTime(y, m, d));
  return date == DateOnly(y, m, d) ? date : null;
}

/// `yy-mm`, read as the last day of that month (20yy).
DateOnly? _parseYearMonthEnd(String value) {
  final match = RegExp(r'^(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final y = 2000 + int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  if (m < 1 || m > 12) return null;
  return DateOnly.fromDateTime(DateTime(y, m + 1, 0));
}
