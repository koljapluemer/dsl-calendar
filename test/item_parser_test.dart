import 'dart:io';

import 'package:calendar/dsl/document.dart';
import 'package:calendar/dsl/schema.dart';
import 'package:calendar/models/date_only.dart';
import 'package:calendar/models/item.dart';
import 'package:calendar/models/item_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _examples = 'docs/new_data_format/example_data';
final _schema = Schema.fromYaml(
  File('assets/dsl/keywords.yaml').readAsStringSync(),
);

Item _item(String text) {
  final result = parseItem(_schema, 'x.txt', text);
  if (result is ParseError) fail('unexpected errors: ${result.errors}');
  return (result as ParsedItem).item;
}

Item _example(String name) =>
    _item(File('$_examples/$name.txt').readAsStringSync());

/// The spec codes of [text]'s errors, as `code@line`.
List<String> _errors(String text) {
  final result = parseItem(_schema, 'x.txt', text);
  if (result is ParsedItem) fail('expected errors for: $text');
  return [
    for (final d in (result as ParseError).errors) '${d.code.code}@${d.line}',
  ];
}

void main() {
  group('example data', () {
    test('plain appointment', () {
      final item = _example('26-10-12-1');
      expect(item.title, 'xHain');
      expect(item.description, isEmpty);
      expect((item.kind as Appointment).date, const DateOnly(2026, 10, 12));
      expect(item.warnings, isEmpty);
    });

    test('appointment with a description line', () {
      final item = _example('26-10-12-2');
      expect(item.title, 'meeting 5pm');
      expect(item.description, ['(see email) ']);
    });

    test('open-ended recurring', () {
      final item = _example('devops');
      final kind = item.kind as Recurring;
      expect(kind.weekday, DateTime.tuesday);
      expect(kind.until, isNull);
      expect(item.occursOn(const DateOnly(2030, 1, 1)), isTrue);
    });

    test('recurring until a month, with an unknown keyword', () {
      final item = _example('hci');
      final kind = item.kind as Recurring;
      expect(kind.weekday, DateTime.monday);
      expect(kind.until, const DateOnly(2027, 3, 31));
      expect(item.occursOn(const DateOnly(2027, 3, 29)), isTrue);
      expect(item.occursOn(const DateOnly(2027, 4, 5)), isFalse);
      expect(item.warnings.map((d) => d.code), [DiagnosticCode.unknownKeyword]);
    });
  });

  group('structure', () {
    test('title is never parsed for keywords', () {
      final item = _item('appointment w/ dentist\nappointment 26-10-12');
      expect(item.title, 'appointment w/ dentist');
    });

    test('only a primary at column 0 starts the keyword section', () {
      final item = _item(
        'x\n'
        'iterable is not a primary\n'
        '  recurring, indented\n'
        'recurring mo',
      );
      expect(item.description, [
        'iterable is not a primary',
        '  recurring, indented',
      ]);
      expect(item.kind, isA<Recurring>());
    });

    test('description keeps inner blank lines, drops outer ones', () {
      final item = _item('\n\nx\n\na\n\nb\n\nappointment 26-10-12\n');
      expect(item.title, 'x');
      expect(item.description, ['a', '', 'b']);
    });

    test('several clauses on one line', () {
      final doc = parseDocument(
        _schema,
        'x\nappointment 26-10-12 recurring mo',
      );
      expect(doc.clauses.map((c) => c.keyword), ['appointment', 'recurring']);
    });

    test('unknown keyword keeps the rest of its line raw', () {
      final doc = parseDocument(
        _schema,
        'x\nrecurring mo\nprio 7 "some text"\n(next "call")',
      );
      expect(doc.isValid, isTrue);
      expect(doc.unknownLines, ['prio 7 "some text"', '(next "call")']);
    });

    test('until accepts an exact date, inclusive', () {
      final item = _item('x\nrecurring mo until 26-10-12');
      expect(item.occursOn(const DateOnly(2026, 10, 12)), isTrue);
      expect(item.occursOn(const DateOnly(2026, 10, 19)), isFalse);
    });
  });

  group('errors', () {
    test('empty', () => expect(_errors(' \n\n'), ['empty@null']));
    test('no_primary', () => expect(_errors('x\nprio 3'), ['no_primary@null']));
    test(
      'missing_arg',
      () => expect(_errors('x\nappointment'), ['missing_arg@2']),
    );
    test(
      'missing_arg before the next keyword',
      () => expect(_errors('x\nappointment recurring mo'), ['missing_arg@2']),
    );
    test(
      'missing option value',
      () => expect(_errors('x\nrecurring mo until'), ['missing_arg@2']),
    );
    test(
      'invalid_value: not a real date',
      () => expect(_errors('x\nappointment 26-02-30'), ['invalid_value@2']),
    );
    test(
      'invalid_value: weekday',
      () => expect(_errors('x\nrecurring xx'), ['invalid_value@2']),
    );
    test(
      'unexpected_token',
      () => expect(_errors('x\nappointment 26-10-12 5pm'), [
        'unexpected_token@2',
      ]),
    );
    test(
      'duplicate_keyword',
      () => expect(_errors('x\nrecurring mo\nrecurring tu'), [
        'duplicate_keyword@3',
      ]),
    );
    test(
      'duplicate option',
      () => expect(_errors('x\nrecurring mo until 27-03 until 27-04'), [
        'duplicate_keyword@2',
      ]),
    );
    test(
      'conflicting_keywords',
      () => expect(_errors('x\nappointment 26-10-12\nrecurring mo'), [
        'conflicting_keywords@3',
      ]),
    );
  });

  test(
    'vendored schema matches the sibling dsl repo',
    () {
      final upstream = File('../dsl/spec/keywords.yaml');
      expect(
        File('assets/dsl/keywords.yaml').readAsStringSync(),
        upstream.readAsStringSync(),
        reason: 'run `just sync-spec`',
      );
    },
    skip: File('../dsl/spec/keywords.yaml').existsSync() ? false : 'no ../dsl',
  );
}
