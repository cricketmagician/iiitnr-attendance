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
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () async {
          final done = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => LeaveApplyPage(api: widget.api)),
          );
          if (done == true) _refresh();
        },
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Apply Leave', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: () async => (await widget.api.get('/leave/mine')) as Map<String, dynamic>,
        builder: (context, data, reload) {
          final b = data['balances'] as Map<String, dynamic>;
          final apps = (data['applications'] as List).cast<Map<String, dynamic>>();
          final pools = (b['pools'] as List).cast<Map<String, dynamic>>();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              // Header Banner
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'LEAVE BALANCES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 1.1,
                    ),
                  ),
                  Text(
                    'Year: ${shortDate(b['leave_year'][0])} – ${shortDate(b['leave_year'][1])}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Visual Gradient Balance Cards
              Row(
                children: pools.map((p) {
                  final left = p['left'] as num? ?? 0;
                  final entitled = p['entitled'] as num? ?? 1;
                  final label = p['label'] as String? ?? 'Leave';
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                _n(left),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                '/${_n(entitled)}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: entitled > 0 ? (left / entitled).clamp(0.0, 1.0) : 0,
                              minHeight: 4,
                              backgroundColor: const Color(0xFFF1F5F9),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                left > 2 ? const Color(0xFF2563EB) : const Color(0xFFEF4444),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Color(0xFF64748B)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Institute scholars: at most 5 days at a stretch. Weekends & holidays are exempt.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Applications Section
              const Text(
                'MY APPLICATIONS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),

              if (apps.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Center(
                    child: Text('No leave applications yet.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  ),
                )
              else
                ...apps.map((a) {
                  final status = a['status'] as String? ?? '';
                  final isPending = status.startsWith('pending');
                  final isApproved = status == 'confirmed';

                  Color badgeBg = isApproved
                      ? const Color(0xFFDCFCE7)
                      : isPending
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFFFE4E6);
                  Color badgeText = isApproved
                      ? const Color(0xFF15803D)
                      : isPending
                          ? const Color(0xFFB45309)
                          : const Color(0xFFBE123C);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${a['type_label']} · ${_n(a['days'])} Day${a['days'] == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                a['status_text'] ?? status,
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: badgeText),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${shortDate(a['from_date'])} – ${shortDate(a['to_date'])}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        if (_notes(a).isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(_notes(a).trim(), style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                        ],
                        if (isPending) ...[
                          const Divider(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFEF4444),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                try {
                                  await widget.api.post('/leave/${a['id']}/withdraw');
                                  if (context.mounted) showMessage(context, 'Application withdrawn.', ok: true);
                                  reload();
                                } catch (e) {
                                  if (context.mounted) showMessage(context, e);
                                }
                              },
                              child: const Text('Withdraw Request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  static String _n(dynamic v) => (v is num && v == v.roundToDouble()) ? v.toInt().toString() : '$v';

  static String _notes(Map a) {
    final n = [
      if ((a['supervisor_note'] ?? '').toString().isNotEmpty) 'Guide: ${a['supervisor_note']}',
      if ((a['dean_note'] ?? '').toString().isNotEmpty) 'Dean: ${a['dean_note']}',
      if ((a['admin_note'] ?? '').toString().isNotEmpty) 'Admin: ${a['admin_note']}',
    ];
    return n.isEmpty ? '' : '\n${n.join('\n')}';
  }
}
