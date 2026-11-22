import 'package:flutter/material.dart';

import '../api.dart';
import '../ui_common.dart';
import 'leave_apply_page.dart';

const leaveTypeShort = {
  'CASUAL': 'Casual leave',
  'MEDICAL': 'Medical leave',
  'ACADEMIC': 'Academic duty',
  'MATERNITY': 'Maternity leave',
  'PATERNITY': 'Paternity leave',
};

const leaveTypeIcon = {
  'CASUAL': Icons.beach_access_rounded,
  'MEDICAL': Icons.medical_services_outlined,
  'ACADEMIC': Icons.school_outlined,
  'MATERNITY': Icons.child_friendly_outlined,
  'PATERNITY': Icons.child_friendly_outlined,
};

const leaveTypeColors = {
  'CASUAL': [Color(0xFF38BDF8), Color(0xFF0284C7)],
  'MEDICAL': [Color(0xFFFB7185), Color(0xFFE11D48)],
  'ACADEMIC': [Color(0xFFA78BFA), Color(0xFF6D28D9)],
  'MATERNITY': [Color(0xFFF472B6), Color(0xFFDB2777)],
  'PATERNITY': [Color(0xFF34D399), Color(0xFF059669)],
};

StatusPill leaveStatusPill(Map<String, dynamic> a) {
  final status = a['status'] as String? ?? '';
  final text = const {
        'pending_supervisor': 'With supervisor',
        'pending_dean': 'With Dean (R&I)',
        'pending_admin': 'With office',
        'confirmed': 'Approved',
        'declined': 'Declined',
        'returned': 'Returned',
        'withdrawn': 'Withdrawn',
        'cancelled': 'Cancelled',
      }[status] ??
      (a['status_text'] ?? status).toString();
  final tone = switch (status) {
    'confirmed' => PillTone.success,
    'declined' => PillTone.danger,
    'returned' => PillTone.warning,
    'pending_supervisor' || 'pending_dean' || 'pending_admin' => PillTone.brand,
    _ => PillTone.neutral,
  };
  return StatusPill(text, tone: tone);
}

class LeaveTab extends StatefulWidget {
  final AttendanceApi api;
  const LeaveTab({super.key, required this.api});
  @override
  State<LeaveTab> createState() => _LeaveTabState();
}

class _LeaveTabState extends State<LeaveTab> {
  int _version = 0;

  void _refresh() => setState(() => _version++);

  Future<void> _apply() async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LeaveApplyPage(api: widget.api)),
    );
    if (done == true) _refresh();
  }

  Future<void> _withdraw(Map<String, dynamic> a, VoidCallback reload) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw this application?'),
        content: Text('${leaveTypeShort[a['leave_type']] ?? 'Leave'}, ${dateRange(a['from_date'], a['to_date'])}. '
            'You can apply again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.post('/leave/${a['id']}/withdraw');
      if (mounted) showMessage(context, 'Application withdrawn.', ok: true);
      reload();
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      key: ValueKey(_version),
      load: () async => (await widget.api.get('/leave/mine')) as Map<String, dynamic>,
      builder: (context, data, reload) {
        final b = data['balances'] as Map<String, dynamic>;
        final apps = (data['applications'] as List).cast<Map<String, dynamic>>();
        final pools = {
          for (final p in (b['pools'] as List).cast<Map<String, dynamic>>()) p['pool'] as String: p,
        };
        final ordinary = pools['ORDINARY'];

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Leave', style: onGradientTitle),
                const SizedBox(height: 22),
                if (ordinary != null) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_fmt(ordinary['left']),
                        style: const TextStyle(
                            fontSize: 56, fontWeight: FontWeight.w800, color: Colors.white, height: 1, letterSpacing: -2)),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('days of leave\nleft this year', style: onGradientBody.copyWith(height: 1.25)),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (ordinary['entitled'] as num) <= 0
                          ? 0
                          : ((ordinary['used'] as num) / (ordinary['entitled'] as num)).clamp(0, 1).toDouble(),
                      minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_fmt(ordinary['used'])} of ${_fmt(ordinary['entitled'])} used · '
                    '${shortDate(b['leave_year'][0])} – ${shortDate(b['leave_year'][1])}',
                    style: onGradientBody.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                ],
                Row(children: [
                  if (pools['MEDICAL'] != null) _glassPool('Medical', pools['MEDICAL']!),
                  if (pools['SEMESTER'] != null) ...[const SizedBox(width: 8), _glassPool('Semester', pools['SEMESTER']!)],
                  if (pools['ACADEMIC'] != null) ...[const SizedBox(width: 8), _glassPool('Academic', pools['ACADEMIC']!)],
                ]),
                const SizedBox(height: 20),
                OnGradientButton(label: 'Apply for leave', icon: Icons.add_rounded, onPressed: _apply),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.neutralSoft, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.inkSoft),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Max 5 days in a row for institute scholars. Weekends and holidays are free.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),
                ),
              ]),
            ),

            SectionHeader('Applications', trailing: apps.isEmpty ? null : '${apps.length}'),
            if (apps.isEmpty)
              const AppCard(
                child: EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No applications yet',
                  message: 'Leave you apply for will show here with its approval status.',
                ),
              )
            else
              ...apps.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _applicationCard(a, reload),
                  )),
              ]),
            ),
          ],
        );
      },
    );
  }

  String _fmt(Object? v) {
    final n = (v as num?) ?? 0;
    return n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
  }

  Widget _glassPool(String label, Map<String, dynamic> p) => Expanded(
        child: GlassTile(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmt(p['left']),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
              Text(' /${_fmt(p['entitled'])}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7))),
            ]),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.85))),
          ]),
        ),
      );

  Widget _poolRow(String label, Map<String, dynamic> p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Text('${_fmt(p['left'])} left',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
          Text(' / ${_fmt(p['entitled'])}', style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  Widget _applicationCard(Map<String, dynamic> a, VoidCallback reload) {
    final status = a['status'] as String? ?? '';
    final isPending = status.startsWith('pending');
    final days = a['days'] as num? ?? 0;
    final notes = [
      if ((a['supervisor_note'] ?? '').toString().isNotEmpty) 'Supervisor: ${a['supervisor_note']}',
      if ((a['dean_note'] ?? '').toString().isNotEmpty) 'Dean: ${a['dean_note']}',
      if ((a['admin_note'] ?? '').toString().isNotEmpty) 'Office: ${a['admin_note']}',
    ];
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: AppColors.neutralSoft, borderRadius: BorderRadius.circular(15)),
            child: Icon(leaveTypeIcon[a['leave_type']] ?? Icons.event_note_rounded, color: AppColors.ink, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(leaveTypeShort[a['leave_type']] ?? a['type_label'].toString(),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text('${dateRange(a['from_date'], a['to_date'])} · ${_fmt(days)} ${days == 1 ? 'day' : 'days'}',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Flexible(child: leaveStatusPill(a)),
          const Spacer(),
          if (isPending)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger, visualDensity: VisualDensity.compact),
              onPressed: () => _withdraw(a, reload),
              child: const Text('Withdraw'),
            ),
        ]),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(12)),
            child: Text(notes.join('\n'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),
          ),
        ],
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  final num used;
  final num total;
  final Color color;
  const _Bar({required this.used, required this.total, required this.color});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: total <= 0 ? 0 : (used / total).clamp(0, 1).toDouble(),
          minHeight: 8,
          backgroundColor: AppColors.neutralSoft,
          color: color,
        ),
      );
}
