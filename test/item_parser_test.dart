import 'dart:io';

import 'package:calendar/models/date_only.dart';
import 'package:calendar/models/item.dart';
import 'package:calendar/models/item_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _examples = 'docs/new_data_format/example_data';

Item _example(String name) {
  final path = '$_examples/$name.txt';
  final result = parseItem(path, File(path).readAsStringSync());
  if (result is ParseError) fail('$name: ${result.message}');
  return (result as ParsedItem).item;
}

String _error(String text) {
  final result = parseItem('x.txt', text);
  if (result is ParsedItem) fail('expected an error for: $text');
  return (result as ParseError).message;
}

void main() {
  group('example data', () {
    test('plain appointment', () {
      final item = _example('26-10-12-1');
      expect(item.title, 'xHain');
      expect(item.notes, isEmpty);
      expect((item.kind as Appointment).date, const DateOnly(2026, 10, 12));
      expect(item.occursOn(const DateOnly(2026, 10, 12)), isTrue);
      expect(item.occursOn(const DateOnly(2026, 10, 13)), isFalse);
    });

    test('appointment with a note line', () {
      final item = _example('26-10-12-2');
      expect(item.title, 'meeting 5pm');
      expect(item.notes, ['(see email)']);
      expect(item.kind, isA<Appointment>());
    });

    test('open-ended recurring', () {
      final item = _example('devops');
      final kind = item.kind as Recurring;
      expect(kind.weekday, DateTime.tuesday);
      expect(kind.until, isNull);
      expect(item.occursOn(const DateOnly(2026, 10, 13)), isTrue);
      expect(item.occursOn(const DateOnly(2030, 1, 1)), isTrue);
      expect(item.occursOn(const DateOnly(2026, 10, 14)), isFalse);
    });

    test('recurring until a year-month, with an unsupported keyword', () {
      final item = _example('hci');
      expect(item.title, 'HCI lecture 4pm-7pm');
      final kind = item.kind as Recurring;
      expect(kind.weekday, DateTime.monday);
      expect(kind.until, const DateOnly(2027, 3, 31));
      expect(item.extraLines, ['iterable d 4 0.4']);
      expect(item.occursOn(const DateOnly(2027, 3, 29)), isTrue);
      expect(item.occursOn(const DateOnly(2027, 4, 5)), isFalse);
    });
  });

  test('recurring until an exact date is inclusive', () {
    final result = parseItem('x.txt', 'x\nrecurring mo until 26-10-12');
    final item = (result as ParsedItem).item;
    expect(item.occursOn(const DateOnly(2026, 10, 12)), isTrue);
    expect(item.occursOn(const DateOnly(2026, 10, 19)), isFalse);
  });

  group('errors', () {
    test('empty file', () => expect(_error('  \n\n'), contains('empty')));
    test('no type keyword', () => expect(_error('x\nprio 3'), isNotEmpty));
    test(
      'both type keywords',
      () => expect(_error('x\nappointment 26-10-12\nrecurring mo'), isNotEmpty),
    );
    test(
      'bad date',
      () => expect(_error('x\nappointment 26-02-30'), isNotEmpty),
    );
    test('missing date', () => expect(_error('x\nappointment'), isNotEmpty));
    test('bad weekday', () => expect(_error('x\nrecurring xx'), isNotEmpty));
    test(
      'bad until',
      () => expect(_error('x\nrecurring mo til 27-03'), isNotEmpty),
    );
    test(
      'note after keyword lines',
      () => expect(_error('x\nappointment 26-10-12\nmore text'), isNotEmpty),
    );
  });
}
