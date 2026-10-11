import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/date_only.dart';
import '../models/item.dart';
import '../models/item_parser.dart';

const _prefsFolderKey = 'data_folder';

/// Reads and parses every `*.txt` file directly inside [folderPath]. Runs in a
/// background isolate via [compute] so scanning a large folder never blocks the
/// UI thread. A file that can't be read or parsed becomes a [ParseError], never
/// a failure of the whole load.
List<ParseResult> parseFolderIsolate(String folderPath) {
  final dir = Directory(folderPath);
  final results = <ParseResult>[];
  if (!dir.existsSync()) return results;

  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.toLowerCase().endsWith('.txt')) {
      continue;
    }
    try {
      results.add(parseItem(entity.path, entity.readAsStringSync()));
    } catch (e) {
      results.add(ParseError(entity.path, 'Could not read file: $e'));
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

  List<Item> _items = [];
  List<ParseError> _errors = [];

  int get count => _items.length;

  List<Item> get items => List.unmodifiable(_items);

  /// Files that couldn't be parsed, by path.
  List<ParseError> get errors => List.unmodifiable(_errors);

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
      final parsed = await compute(parseFolderIsolate, folderPath!);
      _items = [
        for (final r in parsed)
          if (r is ParsedItem) r.item,
      ];
      _errors = parsed.whereType<ParseError>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
    } catch (e) {
      loadError = e.toString();
      _items = [];
      _errors = [];
    }

    isLoading = false;
    hasLoaded = true;
    notifyListeners();
  }

  /// Every item occurring on [day], sorted by title.
  List<Item> itemsOn(DateOnly day) =>
      _items.where((i) => i.occursOn(day)).toList()
        ..sort((a, b) => a.title.compareTo(b.title));
}
