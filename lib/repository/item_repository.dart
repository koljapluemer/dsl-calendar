import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dsl/schema.dart';
import '../models/date_only.dart';
import '../models/item.dart';
import '../models/item_parser.dart';

const _prefsFolderKey = 'data_folder';
const _schemaAsset = 'assets/dsl/keywords.yaml';

/// Reads and parses every `*.txt` file directly inside [folderPath]. Runs in a
/// background isolate via [compute] so scanning a large folder never blocks the
/// UI thread. A file that can't be read or parsed becomes a [ParseError], never
/// a failure of the whole load.
List<ParseResult> parseFolderIsolate((Schema, String) args) {
  final (schema, folderPath) = args;
  final dir = Directory(folderPath);
  final results = <ParseResult>[];
  if (!dir.existsSync()) return results;

  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.toLowerCase().endsWith('.txt')) {
      continue;
    }
    try {
      results.add(parseItem(schema, entity.path, entity.readAsStringSync()));
    } catch (e) {
      results.add(ParseError(entity.path, const [], readError: '$e'));
    }
  }
  return results;
}

/// The data folder's items, held in memory. Read-only: the files are edited
/// elsewhere, and [loadFromDisk] picks up those changes.
class ItemRepository extends ChangeNotifier {
  String? folderPath;
  bool isLoading = false;

  /// Whether a load has finished at least once since launch.
  bool hasLoaded = false;
  String? loadError;

  Schema? _schema;
  List<Item> _items = [];
  List<Item> _itemsWithWarnings = [];
  List<ParseError> _errors = [];

  int get count => _items.length;

  /// Items that fall on some day. Plain notes in the same folder (no primary
  /// keyword the calendar knows) aren't held, so a folder of many notes stays
  /// cheap to keep and to query day by day.
  List<Item> get items => List.unmodifiable(_items);

  /// Files that aren't valid items, by path.
  List<ParseError> get errors => List.unmodifiable(_errors);

  /// Valid items that still have warnings, by path, notes included.
  List<Item> get itemsWithWarnings => List.unmodifiable(_itemsWithWarnings);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    folderPath = prefs.getString(_prefsFolderKey);
    if (folderPath != null) await loadFromDisk();
  }

  Future<void> setFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsFolderKey, path);
    folderPath = path;
    await loadFromDisk();
  }

  Future<void> loadFromDisk() async {
    if (folderPath == null) return;
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      final schema = _schema ??= Schema.fromYaml(
        await rootBundle.loadString(_schemaAsset),
      );
      final parsed = await compute(parseFolderIsolate, (schema, folderPath!));
      final valid = [
        for (final r in parsed)
          if (r is ParsedItem) r.item,
      ];
      _items = valid.where((i) => i.kind != null).toList();
      _itemsWithWarnings = valid.where((i) => i.warnings.isNotEmpty).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      _errors = parsed.whereType<ParseError>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
    } catch (e) {
      loadError = e.toString();
      _items = [];
      _itemsWithWarnings = [];
      _errors = [];
    }

    isLoading = false;
    hasLoaded = true;
    notifyListeners();
  }

  /// Every item occurring on [day], sorted by heading.
  List<Item> itemsOn(DateOnly day) =>
      _items.where((i) => i.occursOn(day)).toList()
        ..sort((a, b) => a.heading.compareTo(b.heading));
}
