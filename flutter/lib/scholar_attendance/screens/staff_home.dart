import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../ui_common.dart';
import 'admin_pages.dart';

/// Supervisor, Dean (R&I), HoD and central admin screens.
class StaffHome extends StatefulWidget {
  final AttendanceApi api;
  final Map<String, dynamic> me;
  const StaffHome({super.key, required this.api, required this.me});
  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final roles = (widget.me['roles'] as List).cast<String>();
    final isAdmin = roles.contains('admin');
    final tabs = <(String, IconData, Widget)>[
      if (roles.contains('supervisor')) ('Approve leave', Icons.how_to_reg, LeaveQueue(api: widget.api, role: 'supervisor')),
      if (roles.contains('dean_ri')) ('Dean (R&I)', Icons.school, LeaveQueue(api: widget.api, role: 'dean')),
      if (isAdmin) ('Confirm leave', Icons.fact_check, LeaveQueue(api: widget.api, role: 'admin')),
      if (isAdmin) ('Day reviews', Icons.rule, DayReviewsPage(api: widget.api)),
      if (roles.any((r) => const ['admin', 'hod', 'supervisor'].contains(r)))
        ('Register', Icons.table_chart, RegisterPage(api: widget.api)),
      if (isAdmin) ('More', Icons.settings, AdminMorePage(api: widget.api)),
    ];
    if (tabs.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('Attendance')), body: const Center(child: Text('Nothing here.')));
    }
    final i = _tab.clamp(0, tabs.length - 1);
    return Scaffold(
      appBar: AppBar(title: Text(tabs[i].$1)),
      body: tabs[i].$3,
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: i,
              onDestinationSelected: (v) => setState(() => _tab = v),
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: t.$1)],
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
          ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nothing waiting.')))])
          : ListView(padding: const EdgeInsets.all(12), children: [
              for (final a in rows.cast<Map<String, dynamic>>())
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${a['scholar']['name']} (${a['scholar']['roll_no']}, ${a['scholar']['programme']})',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${a['type_label']} · ${a['days']} day(s) · '
                          '${shortDate(a['from_date'])} – ${shortDate(a['to_date'])}'),
                      Text('Reason: ${a['reason']}'),
                      if ((a['supervisor_note'] ?? '').toString().isNotEmpty) Text('Supervisor: ${a['supervisor_note']}'),
                      if ((a['dean_note'] ?? '').toString().isNotEmpty) Text('Dean: ${a['dean_note']}'),
                      if (a['needs_dean'] == true) const Text('Academic duty beyond 30 days: Dean (R&I) approval needed.'),
                      if (a['has_attachment'] == true) const Text('Document attached (open on the web register).'),
                      const SizedBox(height: 6),
                      Text(_balanceLine(a['balances'] as Map<String, dynamic>),
                          style: Theme.of(context).textTheme.bodySmall),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(onPressed: () => _decide(a, false), child: Text(isAdmin ? 'Return' : 'Decline')),
                        FilledButton(onPressed: () => _decide(a, true), child: Text(isAdmin ? 'Confirm' : 'Approve')),
                      ]),
                    ]),
                  ),
                ),
            ]),
    );
  }

  static String _balanceLine(Map<String, dynamic> b) => (b['pools'] as List)
      .map((p) => '${p['label']}: ${p['left']} left')
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
