import 'package:flutter/material.dart';

import 'home_tab.dart';
import 'my_courses_tab.dart';
import 'meetings_tab.dart';
import 'account_tab.dart';
import '../theme/app_theme.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _refreshNonce = 0;

  final List<Widget> _tabs = const [
    HomeTab(),
    MyCoursesTab(),
    MeetingsTab(),
    AccountTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _tabs.map((tab) => KeyedSubtree(
          key: ValueKey('$_refreshNonce-${tab.runtimeType}'),
          child: tab,
        )).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          setState(() => _index = index);
        },
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.emeraldLight,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: 'كورساتي'),
          NavigationDestination(icon: Icon(Icons.video_camera_front_outlined), selectedIcon: Icon(Icons.video_camera_front), label: 'المحاضرات'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'حسابي'),
        ],
      ),
    );
  }
}
