import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../ui_common.dart';
import 'admin_pages.dart';
import 'scholar_home.dart' show FloatingNavBar, showProfileSheet;
import 'scholars_admin.dart';
import 'staff_dashboard.dart';

/// Supervisor, HoD, Dean (R&I) and Attendance Office. Starts on a role dashboard;
/// the other tabs depend on what the person may do.
class StaffHome extends StatefulWidget {
  final AttendanceApi api;
  final Map<String, dynamic> me;
  final VoidCallback? onLogout;
  const StaffHome({super.key, required this.api, required this.me, this.onLogout});
  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
  int _tab = 0;
  int _homeVersion = 0;
  Map<String, int> _badges = const {};

  static const _short = {
    'home': 'Home',
    'scholars': 'Scholars',
    'approvals': 'Approve',
    'dean': 'Dean',
    'leave': 'Leave',
    'reviews': 'Reviews',
    'register': 'Register',
    'more': 'Settings',
  };

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  /// Red counts on tabs: what is waiting in each.
  Future<void> _loadBadges() async {
    try {
      final d = await widget.api.get('/admin/dashboard') as Map<String, dynamic>;
      final p = (d['pending'] as Map).cast<String, int>();
      if (!mounted) return;
      setState(() => _badges = {
            'scholars': p['registrations'] ?? 0,
            'approvals': p['leave_supervisor'] ?? 0,
            'dean': p['leave_dean'] ?? 0,
            'leave': p['leave_admin'] ?? 0,
            'reviews': p['reviews'] ?? 0,
            'more': p['devices'] ?? 0,
          });
    } catch (_) {/* badges are a hint only */}
  }

  void _profile() => showProfileSheet(context, widget.me, widget.onLogout);

  @override
  Widget build(BuildContext context) {
    final roles = (widget.me['roles'] as List).cast<String>();
    final isAdmin = roles.contains('admin');
    final canRegister = roles.any((r) => const ['admin', 'hod', 'supervisor', 'dean_ri'].contains(r));

    // key, icon, selected icon, title, page
    final tabs = <(String, IconData, IconData, String, Widget)>[
      ('home', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Home', const SizedBox()),
      if (isAdmin)
        ('scholars', Icons.groups_outlined, Icons.groups_rounded, 'Scholars', ScholarsPage(api: widget.api)),
      if (roles.contains('supervisor'))
        ('approvals', Icons.how_to_reg_outlined, Icons.how_to_reg_rounded, 'Leave to approve',
            LeaveQueue(api: widget.api, role: 'supervisor')),
      if (roles.contains('dean_ri'))
        ('dean', Icons.school_outlined, Icons.school_rounded, 'Dean (R&I) approvals',
            LeaveQueue(api: widget.api, role: 'dean')),
      if (isAdmin)
        ('leave', Icons.fact_check_outlined, Icons.fact_check_rounded, 'Leave to confirm',
            LeaveQueue(api: widget.api, role: 'admin')),
      if (isAdmin) ('reviews', Icons.rule_rounded, Icons.rule_rounded, 'Day reviews', DayReviewsPage(api: widget.api)),
      if (canRegister)
        ('register', Icons.table_chart_outlined, Icons.table_chart_rounded, 'Register', RegisterPage(api: widget.api)),
      if (isAdmin) ('more', Icons.tune_rounded, Icons.tune_rounded, 'Settings', AdminMorePage(api: widget.api)),
    ];
    final i = _tab.clamp(0, tabs.length - 1);

    void open(String key) {
      final target = key == 'devices' ? 'more' : key;
      final j = tabs.indexWhere((t) => t.$1 == target);
      if (j >= 0) setState(() => _tab = j);
    }

    final Widget body = i == 0
        ? StaffDashboard(
            key: ValueKey(_homeVersion), api: widget.api, me: widget.me, onProfile: _profile, onOpen: open)
        : Scaffold(
            appBar: AppBar(
              toolbarHeight: 72,
              title: Text(tabs[i].$4, style: Theme.of(context).textTheme.headlineSmall),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: _profile,
                    child: InitialsAvatar(widget.me['name']?.toString() ?? '?', size: 40),
                  ),
                ),
              ],
            ),
            body: Padding(padding: const EdgeInsets.only(bottom: 96), child: tabs[i].$5),
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        extendBody: true,
        body: body,
        bottomNavigationBar: tabs.length < 2
            ? null
            : FloatingNavBar(
                index: i,
                // Coming back to Home reloads the numbers.
                onTap: (v) {
                  setState(() {
                    if (v == 0 && i != 0) _homeVersion++;
                    _tab = v;
                  });
                  _loadBadges();
                },
                items: [for (final t in tabs) (t.$2, t.$3, _short[t.$1] ?? t.$4)],
                badges: [for (final t in tabs) _badges[t.$1] ?? 0],
              ),
      ),
    );
  }
}

/// Leave waiting for this approver. role: supervisor | dean | admin
class LeaveQueue extends StatefulWidget {
  final AttendanceApi api;
  final String role;
  const LeaveQueue({super.key, required this.api, required this.role});
  @override
  State<LeaveQueue> createState() => _LeaveQueueState();
}

class _LeaveQueueState extends State<LeaveQueue> {
  int _v = 0;

  Future<void> _decide(Map a, bool yes) async {
    final note = TextEditingController();
    final isAdmin = widget.role == 'admin';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(yes ? (isAdmin ? 'Confirm leave' : 'Approve leave') : (isAdmin ? 'Return to scholar' : 'Decline leave')),
        content: TextField(controller: note, maxLines: 3,
            decoration: InputDecoration(labelText: (!yes && isAdmin) ? 'Note (required)' : 'Note (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final path = {'supervisor': 'approve', 'dean': 'dean', 'admin': 'confirm'}[widget.role]!;
      final body = isAdmin ? {'confirm': yes, 'note': note.text.trim()} : {'approve': yes, 'note': note.text.trim()};
      await widget.api.post('/leave/${a['id']}/$path', body);
      if (mounted) showMessage(context, 'Done.', ok: true);
      setState(() => _v++);
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.role == 'admin';
    return Loader<List<dynamic>>(
      key: ValueKey(_v),
      load: () async => (await widget.api.get('/leave/queue', query: {'role': widget.role})) as List<dynamic>,
      builder: (context, rows, _) => rows.isEmpty
          ? ListView(children: const [
              SizedBox(height: 40),
              EmptyState(icon: Icons.inbox_outlined, title: 'All caught up', message: 'No leave is waiting for you.'),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
              for (final a in rows.cast<Map<String, dynamic>>())
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        InitialsAvatar(a['scholar']['name'].toString(), size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a['scholar']['name'].toString(), style: Theme.of(context).textTheme.titleMedium),
                            Text('${a['scholar']['roll_no']} · ${a['scholar']['programme']}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ]),
                        ),
                        StatusPill('${a['days']} ${a['days'] == 1 ? 'day' : 'days'}', tone: PillTone.leave),
                      ]),
                      const SizedBox(height: 14),
                      Text('${a['type_label']}', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(dateRange(a['from_date'], a['to_date']), style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      Text('“${a['reason']}”', style: Theme.of(context).textTheme.bodyMedium),
                      if ((a['supervisor_note'] ?? '').toString().isNotEmpty ||
                          (a['dean_note'] ?? '').toString().isNotEmpty ||
                          a['needs_dean'] == true ||
                          a['has_attachment'] == true) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            [
                              if ((a['supervisor_note'] ?? '').toString().isNotEmpty) 'Supervisor: ${a['supervisor_note']}',
                              if ((a['dean_note'] ?? '').toString().isNotEmpty) 'Dean: ${a['dean_note']}',
                              if (a['needs_dean'] == true) 'Academic duty beyond 30 days needs the Dean (R&I).',
                              if (a['has_attachment'] == true) 'Document attached (open it on the web register).',
                            ].join('\n'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(_balanceLine(a['balances'] as Map<String, dynamic>), style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size(0, 46)),
                            onPressed: () => _decide(a, false),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: Text(isAdmin ? 'Return' : 'Decline'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                            onPressed: () => _decide(a, true),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text(isAdmin ? 'Confirm' : 'Approve'),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
            ]),
    );
  }

  static String _balanceLine(Map<String, dynamic> b) => (b['pools'] as List)
      .map((p) => '${{'ORDINARY': 'Ordinary', 'MEDICAL': 'Medical', 'SEMESTER': 'Semester', 'ACADEMIC': 'Academic'}[p['pool']] ?? p['label']} ${p['left']} left')
      .join(' · ');
}

/// Monthly register for the scholars this person may see.
class RegisterPage extends StatefulWidget {
  final AttendanceApi api;
  const RegisterPage({super.key, required this.api});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String get _m => DateFormat('yyyy-MM').format(month);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
            icon: const Icon(Icons.chevron_left)),
        Text(DateFormat('MMMM yyyy').format(month), style: Theme.of(context).textTheme.titleMedium),
        IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
            icon: const Icon(Icons.chevron_right)),
      ]),
      Expanded(
        child: Loader<List<dynamic>>(
          key: ValueKey(_m),
          load: () async => (await widget.api.get('/admin/register', query: {'m': _m})) as List<dynamic>,
          builder: (context, rows, _) {
            if (rows.isEmpty) return ListView(children: const [Center(child: Text('No scholars.'))]);
            final days = (rows.first['days'] as List).length;
            return ListView(children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 4,
                  horizontalMargin: 8,
                  headingRowHeight: 32,
                  dataRowMinHeight: 28,
                  dataRowMaxHeight: 32,
                  columns: [
                    const DataColumn(label: Text('Scholar')),
                    for (var d = 1; d <= days; d++) DataColumn(label: Text('$d')),
                    const DataColumn(label: Text('P')),
                    const DataColumn(label: Text('L')),
                    const DataColumn(label: Text('A')),
                    const DataColumn(label: Text('R')),
                  ],
                  rows: [
                    for (final r in rows.cast<Map<String, dynamic>>())
                      DataRow(cells: [
                        DataCell(Text(r['name'], overflow: TextOverflow.ellipsis)),
                        for (final d in (r['days'] as List).cast<Map<String, dynamic>>())
                          DataCell(Container(
                            width: 24,
                            alignment: Alignment.center,
                            color: codeColor(d['code'], cs).withOpacity(d['code'] == '' ? 0.15 : 0.35),
                            child: Text(d['code'], style: const TextStyle(fontSize: 11)),
                          )),
                        DataCell(Text('${r['totals']['P'] + r['totals']['P*']}')),
                        DataCell(Text('${r['totals']['L']}')),
                        DataCell(Text('${r['totals']['A']}')),
                        DataCell(Text('${r['totals']['R']}')),
                      ]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(codeMeaning.entries.map((e) => '${e.key} ${e.value}').join(' · '),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}
