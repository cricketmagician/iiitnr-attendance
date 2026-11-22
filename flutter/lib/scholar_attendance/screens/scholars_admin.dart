import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../ui_common.dart';
import 'profile_form.dart';

const _filters = [
  ('pending', 'Pending'),
  ('approved', 'Approved'),
  ('rejected', 'Sent back'),
  ('all', 'All'),
];

/// Attendance office: every scholar with their full details. New registrations
/// wait under "Pending" for approval.
class ScholarsPage extends StatefulWidget {
  final AttendanceApi api;
  const ScholarsPage({super.key, required this.api});
  @override
  State<ScholarsPage> createState() => _ScholarsPageState();
}

class _ScholarsPageState extends State<ScholarsPage> {
  String _status = 'approved';
  String _programme = 'all';
  String? _department;
  String _q = '';
  int _v = 0;
  bool _firstLoad = true;
  final _search = TextEditingController();

  Future<void> _open(Map<String, dynamic> s) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ScholarDetailPage(api: widget.api, id: s['id'] as int)),
    );
    if (changed == true) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      key: ValueKey('$_status|$_q|$_v'),
      load: () async =>
          (await widget.api.get('/admin/scholars', query: {'status': _status, 'q': _q})) as Map<String, dynamic>,
      builder: (context, data, _) {
        final counts = (data['counts'] as Map).cast<String, int>();
        // Open on the pending queue the first time if anyone is waiting.
        if (_firstLoad) {
          _firstLoad = false;
          if ((counts['pending'] ?? 0) > 0 && _status != 'pending') {
            WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _status = 'pending'));
          }
        }
        final all = (data['scholars'] as List).cast<Map<String, dynamic>>();
        final departments = {for (final s in all) (s['department'] ?? '').toString()}.where((d) => d.isNotEmpty).toList()
          ..sort();
        final rows = all
            .where((s) => _programme == 'all' || s['programme'] == _programme)
            .where((s) => _department == null || s['department'] == _department)
            .toList();
        final total = counts.values.fold(0, (a, b) => a + b);

        return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search name, roll number or email',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _search.clear();
                        _q = '';
                      }),
                    ),
            ),
            onSubmitted: (v) => setState(() => _q = v.trim()),
          ),
          const SizedBox(height: 12),
          if ((counts['pending'] ?? 0) > 0 && _status != 'pending') ...[
            _PendingBanner(n: counts['pending']!, onTap: () => setState(() => _status = 'pending')),
            const SizedBox(height: 12),
          ],
          _chips([
            for (final (key, label) in _filters)
              (key, '$label ${key == 'all' ? total : counts[key] ?? 0}'),
          ], _status, (v) => setState(() => _status = v)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _chips(const [('all', 'All'), ('PhD', 'PhD'), ('MTech', 'MTech')], _programme,
                  (v) => setState(() => _programme = v)),
            ),
            PopupMenuButton<String?>(
              tooltip: 'Department',
              onSelected: (v) => setState(() => _department = v == '' ? null : v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: '', child: Text('All departments')),
                for (final d in departments) PopupMenuItem(value: d, child: Text(d)),
              ],
              child: Chip(
                avatar: const Icon(Icons.apartment_rounded, size: 16),
                label: Text(_department ?? 'Dept'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: EmptyState(
                icon: _status == 'pending' ? Icons.how_to_reg_outlined : Icons.groups_outlined,
                title: _status == 'pending' ? 'No new registrations' : 'Nobody here',
                message: _status == 'pending'
                    ? 'Scholars who sign up appear here for you to check.'
                    : 'Change the filters or search.',
              ),
            )
          else if (_status == 'pending')
            // A queue: oldest first, so nobody waits too long
            _card([for (final s in rows.reversed) _row(context, s, showDept: true)])
          else
            ..._grouped(context, rows),
        ]);
      },
    );
  }

  /// PhD / MTech  ->  department  ->  batch (joining year), newest batch first.
  List<Widget> _grouped(BuildContext context, List<Map<String, dynamic>> rows) {
    final out = <Widget>[];
    for (final prog in const ['PhD', 'MTech', '']) {
      final inProg = rows.where((s) => (s['programme'] ?? '') == prog).toList();
      if (inProg.isEmpty) continue;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(children: [
          Text(prog.isEmpty ? 'Not filled yet' : prog, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 8),
          StatusPill('${inProg.length}'),
        ]),
      ));
      final depts = {for (final s in inProg) (s['department'] ?? '').toString()}.toList()..sort();
      for (final d in depts) {
        final inDept = inProg.where((s) => (s['department'] ?? '').toString() == d).toList();
        final batches = {for (final s in inDept) s['batch'] as int?}.toList()
          ..sort((a, b) => (b ?? 0).compareTo(a ?? 0));
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Icon(Icons.apartment_rounded, size: 18, color: AppColors.inkSoft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(d.isEmpty ? 'No department' : d, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text('${inDept.length} ${inDept.length == 1 ? 'scholar' : 'scholars'}',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              for (final b in batches) ...[
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                  child: Text(b == null ? 'NO BATCH' : 'BATCH $b',
                      style: const TextStyle(
                          fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: AppColors.muted)),
                ),
                for (final (i, s) in inDept.where((s) => s['batch'] == b).indexed) ...[
                  if (i > 0) const Divider(indent: 72, height: 1),
                  _row(context, s),
                ],
              ],
            ]),
          ),
        ));
      }
    }
    return out;
  }

  Widget _card(List<Widget> rows) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) const Divider(indent: 72, height: 1),
            r,
          ],
        ]),
      );

  Widget _row(BuildContext context, Map<String, dynamic> s, {bool showDept = false}) => InkWell(
        onTap: () => _open(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            InitialsAvatar(s['name'].toString(), size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['name'].toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  [
                    s['roll_no'],
                    if (showDept) s['programme'],
                    if (showDept) s['department'],
                    if (!showDept && s['programme'] == 'PhD') s['supervisor_name'],
                  ].where((x) => x != null && x.toString().isNotEmpty).join(' · ').ifEmpty(s['email'].toString()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
            ),
            if (s['status'] != 'approved' || s['active'] == false) ...[
              const SizedBox(width: 8),
              statusPill(s),
            ] else
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ]),
        ),
      );

  Widget _chips(List<(String, String)> items, String value, ValueChanged<String> onPick) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (key, label) in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: value == key,
                onSelected: (_) => onPick(key),
              ),
            ),
        ]),
      );
}

class _PendingBanner extends StatelessWidget {
  final int n;
  final VoidCallback onTap;
  const _PendingBanner({required this.n, required this.onTap});
  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        color: AppColors.ink,
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text('$n new ${n == 1 ? 'registration' : 'registrations'} to check',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white70),
        ]),
      );
}

Widget statusPill(Map<String, dynamic> s) {
  if (s['active'] == false) return const StatusPill('Inactive');
  return switch (s['status']) {
    'pending' => const StatusPill('Pending', tone: PillTone.warning),
    'approved' => const StatusPill('Approved', tone: PillTone.success),
    'rejected' => const StatusPill('Sent back', tone: PillTone.danger),
    _ => const StatusPill('Not filled'),
  };
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// One scholar: all details, and the office's actions.
class ScholarDetailPage extends StatefulWidget {
  final AttendanceApi api;
  final int id;
  const ScholarDetailPage({super.key, required this.api, required this.id});
  @override
  State<ScholarDetailPage> createState() => _ScholarDetailPageState();
}

class _ScholarDetailPageState extends State<ScholarDetailPage> {
  int _v = 0;
  bool _changed = false;

  void _done(String msg) {
    _changed = true;
    showMessage(context, msg, ok: true);
    setState(() => _v++);
  }

  Future<void> _approve(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve registration?'),
        content: Text('${s['name']} can start marking attendance and applying for leave.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.post('/admin/scholars/${widget.id}/decision', {'approve': true});
      if (mounted) _done('Approved.');
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  Future<void> _reject(Map<String, dynamic> s) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send back to scholar'),
        content: TextField(
          controller: note,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'What should they fix?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send back')),
        ],
      ),
    );
    if (ok != true) return;
    if (note.text.trim().isEmpty) {
      if (mounted) showMessage(context, 'Write what the scholar should fix.');
      return;
    }
    try {
      await widget.api.post('/admin/scholars/${widget.id}/decision', {'approve': false, 'note': note.text.trim()});
      if (mounted) _done('Sent back to the scholar.');
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  Future<void> _edit(Map<String, dynamic> s) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _EditPage(api: widget.api, profile: s)),
    );
    if (saved == true && mounted) _done('Details saved.');
  }

  Future<void> _setActive(Map<String, dynamic> s, bool active) async {
    try {
      await widget.api.post('/admin/scholars/${widget.id}/active', {'active': active});
      if (mounted) _done(active ? 'Account turned on.' : 'Account turned off.');
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Scholar')),
        body: Loader<Map<String, dynamic>>(
          key: ValueKey(_v),
          load: () async => (await widget.api.get('/admin/scholars/${widget.id}')) as Map<String, dynamic>,
          builder: (context, s, _) {
            final pending = s['status'] == 'pending';
            final text = Theme.of(context).textTheme;
            return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
              Row(children: [
                InitialsAvatar(s['name'].toString(), size: 60),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['name'].toString(), style: text.headlineSmall),
                    const SizedBox(height: 2),
                    Text(s['email'].toString(), style: text.bodySmall),
                    const SizedBox(height: 8),
                    statusPill(s),
                  ]),
                ),
              ]),
              if (s['status'] == 'rejected' && (s['note'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(14)),
                  child: Text('Sent back: ${s['note']}', style: const TextStyle(color: AppColors.danger)),
                ),
              ],
              const SectionHeader('Details'),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ProfileDetails(p: s),
              ),
              const SectionHeader('Record'),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(children: [
                  DetailRow(
                    icon: Icons.send_outlined,
                    label: 'Registered',
                    value: s['registered_at'] == null
                        ? 'Added by the office'
                        : DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(s['registered_at'])),
                  ),
                  if ((s['reviewed_by'] ?? '').toString().isNotEmpty)
                    DetailRow(
                      icon: Icons.verified_outlined,
                      label: 'Checked by',
                      value:
                          '${s['reviewed_by']}${s['reviewed_at'] == null ? '' : ', ${DateFormat('d MMM').format(DateTime.parse(s['reviewed_at']))}'}',
                    ),
                  DetailRow(
                    icon: Icons.face_retouching_natural_outlined,
                    label: 'Face',
                    value: s['face_enrolled'] == true ? 'Enrolled' : 'Not yet',
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              if (pending) ...[
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size(0, 52)),
                      onPressed: () => _reject(s),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Send back'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                      onPressed: () => _approve(s),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: () => _edit(s),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit details'),
              ),
              if (s['status'] == 'approved') ...[
                const SizedBox(height: 10),
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: s['active'] == false ? AppColors.ink : AppColors.danger),
                  onPressed: () => _setActive(s, s['active'] == false),
                  child: Text(s['active'] == false ? 'Turn account back on' : 'Turn account off (left the institute)'),
                ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

class _EditPage extends StatelessWidget {
  final AttendanceApi api;
  final Map<String, dynamic> profile;
  const _EditPage({required this.api, required this.profile});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit details')),
        body: Loader<Map<String, dynamic>>(
          load: () async => (await api.get('/registration/options')) as Map<String, dynamic>,
          builder: (context, options, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              ProfileForm(
                options: options,
                initial: profile,
                submitLabel: 'Save details',
                onSubmit: (body) async {
                  await api.put('/admin/scholars/${profile['id']}', body);
                  if (context.mounted) Navigator.pop(context, true);
                },
              ),
            ],
          ),
        ),
      );
}
