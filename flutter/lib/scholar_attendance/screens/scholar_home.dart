import 'package:flutter/material.dart';

import '../api.dart';
import 'leave_tab.dart';
import 'month_tab.dart';
import 'today_tab.dart';

class ScholarHome extends StatefulWidget {
  final AttendanceApi api;
  final Map<String, dynamic> me;
  const ScholarHome({super.key, required this.api, required this.me});
  @override
  State<ScholarHome> createState() => _ScholarHomeState();
}

class _ScholarHomeState extends State<ScholarHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayTab(api: widget.api),
      MonthTab(api: widget.api),
      LeaveTab(api: widget.api),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(['Attendance', 'My month', 'Leave'][_tab])),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fingerprint), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Month'),
          NavigationDestination(icon: Icon(Icons.event_busy), label: 'Leave'),
        ],
      ),
    );
  }
}
