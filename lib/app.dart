import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'ui/report_screen.dart';
import 'ui/session_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';

class GoSleepApp extends StatelessWidget {
  const GoSleepApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoSleep 呼吸催眠',
      debugShowCheckedModeBanner: false,
      theme: buildSleepTheme(),
      home: HomePage(state: state),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            SessionScreen(state: widget.state),
            ReportScreen(state: widget.state),
            SettingsScreen(state: widget.state),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bedtime_outlined),
            selectedIcon: Icon(Icons.bedtime),
            label: '睡眠',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: '报告',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
