import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../ui_common.dart';
import 'leave_tab.dart';
import 'month_tab.dart';
import 'today_tab.dart';

class ScholarHome extends StatefulWidget {
  final AttendanceApi api;
  final Map<String, dynamic> me;
  final VoidCallback? onLogout;
  const ScholarHome({super.key, required this.api, required this.me, this.onLogout});
  @override
  State<ScholarHome> createState() => _ScholarHomeState();
}

class _ScholarHomeState extends State<ScholarHome> {
  int _tab = 0;

  void _openProfile() => showProfileSheet(context, widget.me, widget.onLogout);

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayTab(api: widget.api, me: widget.me, onProfile: _openProfile),
      MonthTab(api: widget.api),
      LeaveTab(api: widget.api),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(index: _tab, children: pages),
        bottomNavigationBar: FloatingNavBar(
          index: _tab,
          onTap: (i) => setState(() => _tab = i),
          items: const [
            (Icons.check_circle_outline_rounded, Icons.check_circle_rounded, 'Today'),
            (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Calendar'),
            (Icons.beach_access_outlined, Icons.beach_access_rounded, 'Leave'),
          ],
        ),
      ),
    );
  }
}

/// Dark, rounded bottom bar that floats above the content.
class FloatingNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, IconData, String)> items;
  const FloatingNavBar({super.key, required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        height: 68,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [BoxShadow(color: AppColors.ink.withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: i == index ? Colors.white : null,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(i == index ? items[i].$2 : items[i].$1,
                        size: 22, color: i == index ? AppColors.ink : Colors.white.withOpacity(0.5)),
                    if (i == index && items.length <= 3) ...[
                      const SizedBox(width: 8),
                      Text(items[i].$3,
                          style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 13.5)),
                    ],
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Profile sheet: who is signed in, and sign out. Shared by scholar and staff homes.
void showProfileSheet(BuildContext context, Map<String, dynamic> me, VoidCallback? onLogout) {
  final name = (me['name'] ?? 'Scholar').toString();
  final roles = (me['roles'] as List?)?.cast<String>() ?? const [];
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            InitialsAvatar(name, size: 56),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text((me['email'] ?? '').toString(), style: Theme.of(ctx).textTheme.bodyMedium),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          if ((me['roll_no'] ?? '').toString().isNotEmpty)
            DetailRow(icon: Icons.badge_outlined, label: 'Roll number', value: me['roll_no'].toString()),
          if (me['programme'] != null)
            DetailRow(icon: Icons.school_outlined, label: 'Programme', value: me['programme'].toString()),
          if ((me['department'] ?? '').toString().isNotEmpty)
            DetailRow(icon: Icons.apartment_rounded, label: 'Department', value: me['department'].toString()),
          if (roles.isNotEmpty)
            DetailRow(icon: Icons.verified_user_outlined, label: 'Role', value: roles.join(', ')),
          if (me['device'] != null)
            DetailRow(
                icon: Icons.smartphone_rounded,
                label: 'This phone',
                value: me['device']['status'] == 'active' ? 'Registered' : me['device']['status'].toString()),
          const SizedBox(height: 16),
          if (onLogout != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () {
                  Navigator.pop(ctx);
                  onLogout();
                },
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text('Sign out'),
              ),
            ),
        ]),
      ),
    ),
  );
}
