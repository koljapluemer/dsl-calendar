import 'date_only.dart';

/// What makes an item show up on a given day. Exactly one per item.
sealed class ItemKind {
  const ItemKind();

  bool occursOn(DateOnly day);
}

/// `appointment <date>` — a single day.
class Appointment extends ItemKind {
  const Appointment(this.date);

  final DateOnly date;

  @override
  bool occursOn(DateOnly day) => day == date;
}

/// `recurring <weekday> [until <date>]` — every [weekday] (1 = Mon .. 7 = Sun),
/// with no start bound, up to and including [until] when set.
class Recurring extends ItemKind {
  const Recurring(this.weekday, {this.until});

  final int weekday;
  final DateOnly? until;

  @override
  bool occursOn(DateOnly day) =>
      day.weekday == weekday && (until == null || day.compareTo(until!) <= 0);
}

/// One item, parsed from one `.txt` file in the data folder. See
/// `docs/data-format.md` for the language.
class Item {
  const Item({
    required this.path,
    required this.title,
    required this.kind,
    this.notes = const [],
    this.extraLines = const [],
  });

  final String path;

  /// The first line, verbatim.
  final String title;

  /// Free-text lines between the title and the first keyword line.
  final List<String> notes;

  final ItemKind kind;

  /// Keyword lines using reserved keywords that aren't supported yet (e.g.
  /// `iterable d 4 0.4`), kept raw and otherwise ignored.
  final List<String> extraLines;

  bool occursOn(DateOnly day) => kind.occursOn(day);
}
