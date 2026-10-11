import 'package:flutter/material.dart';

import '../repository/item_repository.dart';
import 'day_screen.dart';
import 'range_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repository});

  final ItemRepository repository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DayScreen(repository: widget.repository),
      RangeScreen(repository: widget.repository),
      SettingsScreen(repository: widget.repository),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.today), label: 'Day'),
                NavigationDestination(
                  icon: Icon(Icons.date_range),
                  label: 'Range',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
            Expanded(
              child: IndexedStack(index: _index, children: pages),
            ),
          ],
        ),
      ),
    );
  }
}
