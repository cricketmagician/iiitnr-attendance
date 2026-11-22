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

/// Floating bottom bar: icon with its name under it, the current tab in a dark pill.
/// Works for 3 to 6 tabs.
class FloatingNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, IconData, String)> items;

  /// Optional red counts on tabs (same order as items); 0 hides the badge.
  final List<int>? badges;
  const FloatingNavBar({super.key, required this.index, required this.onTap, required this.items, this.badges});

  @override
  Widget build(BuildContext context) {
    final compact = items.length > 4;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        height: 74,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 28, offset: const Offset(0, 10)),
          ],
        ),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                label: items[i].$3,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (i != index) HapticFeedback.selectionClick();
                    onTap(i);
                  },
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Stack(clipBehavior: Clip.none, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: i == index ? (compact ? 46 : 58) : 40,
                        height: 32,
                        decoration: BoxDecoration(
                          color: i == index ? AppColors.ink : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          i == index ? items[i].$2 : items[i].$1,
                          size: 21,
                          color: i == index ? Colors.white : AppColors.muted,
                        ),
                      ),
                      if ((badges?.elementAtOrNull(i) ?? 0) > 0)
                        Positioned(
                          right: -2,
                          top: -3,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 17),
                            height: 17,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.danger,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: Text('${badges![i] > 99 ? '99+' : badges![i]}',
                                style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      items[i].$3,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: compact ? 10.5 : 11.5,
                        fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                        color: i == index ? AppColors.ink : AppColors.muted,
                        letterSpacing: -0.1,
                      ),
                    ),
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
