import 'package:flutter/material.dart';

import '../api.dart';
import '../ui_common.dart';
import 'leave_apply_page.dart';

class LeaveTab extends StatefulWidget {
  final AttendanceApi api;
  const LeaveTab({super.key, required this.api});
  @override
  State<LeaveTab> createState() => _LeaveTabState();
}

class _LeaveTabState extends State<LeaveTab> {
  int _version = 0;

  void _refresh() => setState(() => _version++);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final done = await Navigator.push<bool>(
              context, MaterialPageRoute(builder: (_) => LeaveApplyPage(api: widget.api)));
          if (done == true) _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Apply'),
      ),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: () async => (await widget.api.get('/leave/mine')) as Map<String, dynamic>,
        builder: (context, data, reload) {
          final b = data['balances'] as Map<String, dynamic>;
          final apps = (data['applications'] as List).cast<Map<String, dynamic>>();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
            Text('Leave year ${shortDate(b['leave_year'][0])} – ${niceDate(b['leave_year'][1])}',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...(b['pools'] as List).map((p) => Card(
                  child: ListTile(
                    dense: true,
                    title: Text(p['label']),
                    trailing: Text('${_n(p['left'])} left of ${_n(p['entitled'])}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                )),
            Text('Maternity (180 days) and paternity (15 days) can each be taken once. '
                'Institute scholars: at most 5 days at a stretch. Weekends and holidays are not counted.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Text('My applications', style: Theme.of(context).textTheme.titleSmall),
            if (apps.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No applications yet.')),
            ...apps.map((a) => Card(
                  child: ListTile(
                    title: Text('${a['type_label']} · ${_n(a['days'])} day${a['days'] == 1 ? '' : 's'}'),
                    subtitle: Text('${shortDate(a['from_date'])} – ${shortDate(a['to_date'])}\n'
                        '${a['status_text']}'
                        '${_notes(a)}'),
                    isThreeLine: true,
                    trailing: (a['status'] as String).startsWith('pending')
                        ? TextButton(
                            onPressed: () async {
                              try {
                                await widget.api.post('/leave/${a['id']}/withdraw');
                                if (context.mounted) showMessage(context, 'Application withdrawn.', ok: true);
                                reload();
                              } catch (e) {
                                if (context.mounted) showMessage(context, e);
                              }
                            },
                            child: const Text('Withdraw'))
                        : null,
                  ),
                )),
          ]);
        },
      ),
    );
  }

  static String _n(dynamic v) => (v is num && v == v.roundToDouble()) ? v.toInt().toString() : '$v';

  static String _notes(Map a) {
    final n = [
      if ((a['supervisor_note'] ?? '').toString().isNotEmpty) 'Supervisor: ${a['supervisor_note']}',
      if ((a['dean_note'] ?? '').toString().isNotEmpty) 'Dean: ${a['dean_note']}',
      if ((a['admin_note'] ?? '').toString().isNotEmpty) 'Admin: ${a['admin_note']}',
    ];
    return n.isEmpty ? '' : '\n${n.join('\n')}';
  }
}
