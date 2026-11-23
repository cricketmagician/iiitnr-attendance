import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../ui_common.dart';

const _sessionNames = {'M': 'Morning', 'A': 'Afternoon', 'E': 'Evening'};

/// Days with fewer than two sessions: mark Present (with remark) or Absent.
class DayReviewsPage extends StatefulWidget {
  final AttendanceApi api;
  const DayReviewsPage({super.key, required this.api});
  @override
  State<DayReviewsPage> createState() => _DayReviewsPageState();
}

class _DayReviewsPageState extends State<DayReviewsPage> {
  int _v = 0;

  Future<void> _decide(Map r, String decision) async {
    final remark = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(decision == 'present' ? 'Mark present' : 'Mark absent'),
        content: TextField(
          controller: remark,
          maxLines: 3,
          decoration: InputDecoration(
              labelText: decision == 'present' ? 'Remark (required)' : 'Remark (optional)',
              hintText: 'e.g. phone battery dead, seen in lab'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.post('/admin/reviews/${r['id']}', {'decision': decision, 'remark': remark.text.trim()});
      setState(() => _v++);
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Loader<List<dynamic>>(
      key: ValueKey(_v),
      load: () async => (await widget.api.get('/admin/reviews', query: {'status': 'pending'})) as List<dynamic>,
      builder: (context, rows, _) => rows.isEmpty
          ? ListView(children: const [
              SizedBox(height: 40),
              EmptyState(icon: Icons.task_alt_rounded, title: 'No days to review', message: 'Short days appear here after 6:35 pm.'),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
              for (final r in rows.cast<Map<String, dynamic>>())
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        InitialsAvatar(r['scholar']['name'].toString(), size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r['scholar']['name'].toString(), style: Theme.of(context).textTheme.titleMedium),
                            Text('${r['scholar']['roll_no']} · ${r['scholar']['programme']} · ${r['scholar']['department']}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                          ]),
                        ),
                        StatusPill(shortDate(r['date']), tone: PillTone.warning),
                      ]),
                      const SizedBox(height: 14),
                      Text(
                        (r['sessions_marked'] as String).isEmpty
                            ? 'No sessions marked'
                            : 'Marked: ${(r['sessions_marked'] as String).split('').map((s) => _sessionNames[s]).join(', ')}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text((r['scholar_reason'] as String).isNotEmpty ? '“${r['scholar_reason']}”' : 'No reason given yet.',
                          style: Theme.of(context).textTheme.bodyMedium),
                      if ((r['remark'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(12)),
                          child: Text(r['remark'].toString(),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger)),
                        ),
                      ],
                      if ((r['marks'] as List? ?? const []).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 128,
                          child: ListView(scrollDirection: Axis.horizontal, children: [
                            for (final m in (r['marks'] as List).cast<Map<String, dynamic>>())
                              _MarkThumb(api: widget.api, m: m),
                          ]),
                        ),
                      ],
                      if ((r['refused_attempts'] as List).isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            (r['refused_attempts'] as List).map((t) => 'Tried at ${t['at']}: ${t['reason']}').join('\n'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size(0, 46)),
                            onPressed: () => _decide(r, 'absent'),
                            child: const Text('Absent'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                            onPressed: () => _decide(r, 'present'),
                            child: const Text('Present'),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
            ]),
    );
  }
}

class AdminMorePage extends StatelessWidget {
  final AttendanceApi api;
  const AdminMorePage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    void open(String title, Widget page) => Navigator.push(
        context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: page)));
    return ListView(children: [
      ListTile(leading: const Icon(Icons.phone_android), title: const Text('Phone change requests'),
          onTap: () => open('Phone change requests', _DevicesPage(api: api))),
      ListTile(leading: const Icon(Icons.exposure_plus_1), title: const Text('Adjust a leave balance'),
          subtitle: const Text('e.g. carry leave forward by hand'),
          onTap: () => open('Adjust a leave balance', _AdjustPage(api: api))),
      ListTile(leading: const Icon(Icons.celebration), title: const Text('Holidays'),
          onTap: () => open('Holidays', _HolidaysPage(api: api))),
      ListTile(leading: const Icon(Icons.wifi), title: const Text('Campus networks'),
          onTap: () => open('Campus networks', _NetworksPage(api: api))),
      ListTile(leading: const Icon(Icons.download), title: const Text('Export this month\'s register (CSV)'),
          onTap: () async {
            final m = DateFormat('yyyy-MM').format(DateTime.now());
            try {
              final bytes = await api.getBytes('/admin/register', query: {'m': m, 'format': 'csv'});
              await Share.shareXFiles([XFile.fromData(bytes, name: 'attendance-$m.csv', mimeType: 'text/csv')]);
            } catch (e) {
              if (context.mounted) showMessage(context, e);
            }
          }),
    ]);
  }
}

class _DevicesPage extends StatefulWidget {
  final AttendanceApi api;
  const _DevicesPage({required this.api});
  @override
  State<_DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<_DevicesPage> {
  int _v = 0;
  @override
  Widget build(BuildContext context) => Loader<List<dynamic>>(
        key: ValueKey(_v),
        load: () async => (await widget.api.get('/admin/devices', query: {'status': 'pending'})) as List<dynamic>,
        builder: (context, rows, _) => ListView(children: [
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No requests.'))),
          for (final d in rows.cast<Map<String, dynamic>>())
            Card(
              child: ListTile(
                title: Text('${d['scholar']} (${d['roll_no']})'),
                subtitle: Text('${d['model']} · ${d['platform']}\nReason: ${d['reason']}'),
                isThreeLine: true,
                trailing: Wrap(children: [
                  IconButton(icon: const Icon(Icons.close), onPressed: () => _decide(d, false)),
                  IconButton(icon: const Icon(Icons.check), onPressed: () => _decide(d, true)),
                ]),
              ),
            ),
        ]),
      );

  Future<void> _decide(Map d, bool approve) async {
    try {
      await widget.api.post('/admin/devices/${d['id']}', {'approve': approve});
      if (mounted) showMessage(context, approve ? 'Approved. The old phone is switched off.' : 'Rejected.', ok: true);
      setState(() => _v++);
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }
}

class _AdjustPage extends StatefulWidget {
  final AttendanceApi api;
  const _AdjustPage({required this.api});
  @override
  State<_AdjustPage> createState() => _AdjustPageState();
}

class _AdjustPageState extends State<_AdjustPage> {
  final email = TextEditingController();
  final days = TextEditingController();
  final remark = TextEditingController();
  String pool = 'ORDINARY';

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: email, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Scholar email', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: pool,
          decoration: const InputDecoration(labelText: 'Balance', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'ORDINARY', child: Text('Ordinary leave (30)')),
            DropdownMenuItem(value: 'MEDICAL', child: Text('Medical part (15)')),
            DropdownMenuItem(value: 'ACADEMIC', child: Text('Academic duty (30)')),
          ],
          onChanged: (v) => setState(() => pool = v!),
        ),
        const SizedBox(height: 12),
        TextField(controller: days, keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
            decoration: const InputDecoration(labelText: 'Days to add (negative to remove)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: remark, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Remark (required)', border: OutlineInputBorder())),
        const SizedBox(height: 4),
        Text('Applies to the scholar\'s current leave year.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            try {
              await widget.api.post('/admin/leave-adjustments', {
                'email': email.text.trim(),
                'pool': pool,
                'days': double.parse(days.text.trim()),
                'remark': remark.text.trim(),
              });
              if (context.mounted) {
                showMessage(context, 'Balance adjusted.', ok: true);
                Navigator.pop(context);
              }
            } on FormatException {
              showMessage(context, 'Enter a number of days.');
            } catch (e) {
              if (context.mounted) showMessage(context, e);
            }
          },
          child: const Text('Save'),
        ),
      ]);
}

class _HolidaysPage extends StatefulWidget {
  final AttendanceApi api;
  const _HolidaysPage({required this.api});
  @override
  State<_HolidaysPage> createState() => _HolidaysPageState();
}

class _HolidaysPageState extends State<_HolidaysPage> {
  int _v = 0;
  final year = DateTime.now().year;

  Future<void> _add() async {
    final d = await showDatePicker(
        context: context, firstDate: DateTime(year - 1), lastDate: DateTime(year + 2), initialDate: DateTime.now());
    if (d == null || !mounted) return;
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(DateFormat('d MMM yyyy').format(d)),
        content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Holiday name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.post('/admin/holidays', {'date': DateFormat('yyyy-MM-dd').format(d), 'name': name.text.trim()});
      setState(() => _v++);
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
        body: Loader<List<dynamic>>(
          key: ValueKey(_v),
          load: () async => (await widget.api.get('/admin/holidays', query: {'year': '$year'})) as List<dynamic>,
          builder: (context, rows, _) => ListView(children: [
            for (final h in rows.cast<Map<String, dynamic>>())
              ListTile(title: Text(h['name']), subtitle: Text(niceDate(h['date']))),
          ]),
        ),
      );
}

class _NetworksPage extends StatefulWidget {
  final AttendanceApi api;
  const _NetworksPage({required this.api});
  @override
  State<_NetworksPage> createState() => _NetworksPageState();
}

class _NetworksPageState extends State<_NetworksPage> {
  int _v = 0;
  final cidr = TextEditingController();
  final label = TextEditingController();

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        key: ValueKey(_v),
        load: () async => (await widget.api.get('/admin/settings')) as Map<String, dynamic>,
        builder: (context, s, _) => ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Marking is accepted only from these networks (the campus Wi-Fi/LAN as the server sees it).'),
          for (final n in (s['campus_networks'] as List).cast<Map<String, dynamic>>())
            ListTile(title: Text(n['cidr']), subtitle: Text(n['label'] ?? '')),
          const Divider(),
          TextField(controller: cidr, decoration: const InputDecoration(labelText: 'Network, e.g. 10.20.0.0/16')),
          TextField(controller: label, decoration: const InputDecoration(labelText: 'Label, e.g. Academic block Wi-Fi')),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              try {
                await widget.api.post('/admin/settings/campus-networks', {'cidr': cidr.text.trim(), 'label': label.text.trim()});
                cidr.clear();
                label.clear();
                setState(() => _v++);
              } catch (e) {
                if (context.mounted) showMessage(context, e);
              }
            },
            child: const Text('Add network'),
          ),
        ]),
      );
}


/// One mark in a day review: the selfie, session and what the checks said.
class _MarkThumb extends StatelessWidget {
  final AttendanceApi api;
  final Map<String, dynamic> m;
  const _MarkThumb({required this.api, required this.m});

  @override
  Widget build(BuildContext context) {
    final live = m['live_score'] as num?;
    final flagged = m['flagged'] == true;
    final label = const {'M': 'Morning', 'A': 'Afternoon', 'E': 'Evening'}[m['session']] ?? m['session'];
    return Container(
      width: 96,
      margin: const EdgeInsets.only(right: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 96,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.neutralSoft,
              border: flagged ? Border.all(color: AppColors.danger, width: 2) : null,
            ),
            child: m['has_selfie'] == true
                ? FutureBuilder(
                    future: api.getBytes('/att/guard/marks/${m['id']}/selfie'),
                    builder: (context, snap) => snap.hasData
                        ? GestureDetector(
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                clipBehavior: Clip.antiAlias,
                                child: Image.memory(snap.data!, fit: BoxFit.contain),
                              ),
                            ),
                            child: Image.memory(snap.data!, fit: BoxFit.cover),
                          )
                        : const Center(child: Icon(Icons.image_outlined, color: AppColors.muted)),
                  )
                : const Center(child: Icon(Icons.no_photography_outlined, color: AppColors.muted)),
          ),
        ),
        const SizedBox(height: 4),
        Text('$label ${m['time']}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
        Text(
          flagged
              ? (m['flagged_by'] == 'auto' ? 'Photo check failed' : 'Flagged by guard')
              : [
                  if (m['proof'] == 'bluetooth') 'Near gate' else if (m['proof'] == 'qr') 'QR backup',
                  if (live != null) 'Live ${(live * 100).round()}%',
                ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: flagged ? AppColors.danger : AppColors.muted, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}
