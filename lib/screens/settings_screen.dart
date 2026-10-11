import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../repository/item_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.repository});

  final ItemRepository repository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _pickFolder() async {
    setState(() => _busy = true);
    try {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path != null) {
        await widget.repository.setFolder(path);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPermission() async {
    await Permission.manageExternalStorage.request();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Data folder', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(repo.folderPath ?? 'Not set'),
        const SizedBox(height: 4),
        Text('${repo.count} items loaded', style: theme.textTheme.bodySmall),
        if (repo.loadError != null) ...[
          const SizedBox(height: 8),
          Text(
            repo.loadError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _pickFolder,
          child: Text(_busy ? 'Loading…' : 'Choose folder'),
        ),
        if (repo.folderPath != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: repo.isLoading ? null : repo.loadFromDisk,
            child: Text(repo.isLoading ? 'Reloading…' : 'Reload'),
          ),
        ],
        if (repo.errors.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text(
            'Invalid files (${repo.errors.length})',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final error in repo.errors)
            _Problem(
              path: error.path,
              lines: [
                ?error.readError,
                for (final d in error.errors) d.toString(),
              ],
              color: theme.colorScheme.error,
            ),
        ],
        if (repo.itemsWithWarnings.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text(
            'Warnings (${repo.itemsWithWarnings.length})',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final item in repo.itemsWithWarnings)
            _Problem(
              path: item.path,
              lines: [for (final d in item.warnings) d.toString()],
              color: theme.colorScheme.outline,
            ),
        ],
        if (Platform.isAndroid) ...[
          const SizedBox(height: 32),
          Text('Storage permission', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Full disk access is required to read and write the data '
            'folder wherever it lives on the device.',
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _requestPermission,
            child: const Text('Grant full disk access'),
          ),
        ],
      ],
    );
  }
}

/// A file name with one line per problem, e.g. `invalid_value · line 2 · "26-02-30"`.
class _Problem extends StatelessWidget {
  const _Problem({
    required this.path,
    required this.lines,
    required this.color,
  });

  final String path;
  final List<String> lines;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.basename(path)),
          for (final line in lines) Text(line, style: style),
        ],
      ),
    );
  }
}
