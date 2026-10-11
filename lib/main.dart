import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'repository/item_repository.dart';
import 'screens/home_shell.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(const CalendarApp());
}

class CalendarApp extends StatefulWidget {
  const CalendarApp({super.key});

  @override
  State<CalendarApp> createState() => _CalendarAppState();
}

class _CalendarAppState extends State<CalendarApp> {
  final _repository = ItemRepository();
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _repository.addListener(_onRepositoryChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _repository.removeListener(_onRepositoryChanged);
    _repository.dispose();
    super.dispose();
  }

  void _onRepositoryChanged() => setState(() {});

  Future<void> _bootstrap() async {
    if (Platform.isAndroid) {
      // Full disk access, so the data folder can live anywhere on device.
      await Permission.manageExternalStorage.request();
    }
    await _repository.init();
    if (!mounted) return;
    setState(() => _bootstrapped = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calendar',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (!_bootstrapped) {
      return const _LoadingScaffold(message: 'Starting…');
    }
    if (_repository.folderPath == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Choose a data folder')),
        body: SettingsScreen(repository: _repository),
      );
    }
    // Only the first load blanks the app; a Reload keeps the views (and their
    // selected dates) on screen while it runs.
    if (_repository.isLoading && !_repository.hasLoaded) {
      return const _LoadingScaffold(message: 'Loading items…');
    }
    return HomeShell(repository: _repository);
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}
