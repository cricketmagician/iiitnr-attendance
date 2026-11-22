import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../ui_common.dart';

class MonthTab extends StatefulWidget {
  final AttendanceApi api;
  const MonthTab({super.key, required this.api});
  @override
  State<MonthTab> createState() => _MonthTabState();
}

class _MonthTabState extends State<MonthTab> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  String get _m => DateFormat('yyyy-MM').format(month);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Month Switcher Banner
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
                icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF1E293B)),
                visualDensity: VisualDensity.compact,
              ),
              Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, size: 18, color: Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('MMMM yyyy').format(month),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
                icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF1E293B)),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: Loader<Map<String, dynamic>>(
            key: ValueKey(_m),
            load: () async => (await widget.api.get('/att/month', query: {'m': _m})) as Map<String, dynamic>,
            builder: (context, data, _) => MonthGrid(data: data),
          ),
        ),
      ],
    );
  }
}

class MonthGrid extends StatelessWidget {
  final Map<String, dynamic> data;
  const MonthGrid({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final days = (data['days'] as List).cast<Map<String, dynamic>>();
    final totals = (data['totals'] as Map).cast<String, dynamic>();
    final first = DateTime.parse(days.first['date']);
    final lead = first.weekday - 1; // Monday first

    final presentCount = (totals['P'] as int? ?? 0) + (totals['P*'] as int? ?? 0);
    final totalEligible = presentCount + (totals['A'] as int? ?? 0) + (totals['R'] as int? ?? 0);
    final attendancePct = totalEligible > 0 ? ((presentCount / totalEligible) * 100).round() : 100;

    final cells = <Widget>[
      for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
        Center(
          child: Text(
            d,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: d == 'S' ? const Color(0xFF94A3B8) : const Color(0xFF475569),
            ),
          ),
        ),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (final d in days) _buildDayCell(context, d),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Attendance Overview Scorecard
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
                child: Center(
                  child: Text(
                    '$attendancePct%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monthly Attendance Score',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$presentCount days present • Required: 85% for stipend',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Calendar Grid
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: cells,
          ),
        ),
        const SizedBox(height: 16),

        // Summary Metric Pills
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _buildStatPill('Present (P)', totals['P'] ?? 0, const Color(0xFFDCFCE7), const Color(0xFF15803D)),
            _buildStatPill('Admin (P*)', totals['P*'] ?? 0, const Color(0xFFCCFBF1), const Color(0xFF0F766E)),
            _buildStatPill('Leave (L)', totals['L'] ?? 0, const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
            _buildStatPill('Absent (A)', totals['A'] ?? 0, const Color(0xFFFFE4E6), const Color(0xFFBE123C)),
            _buildStatPill('Review (R)', totals['R'] ?? 0, const Color(0xFFFEF3C7), const Color(0xFFB45309)),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDayCell(BuildContext context, Map<String, dynamic> d) {
    final code = d['code'] as String? ?? '';
    final date = DateTime.parse(d['date']);
    final isToday = date.year == DateTime.now().year &&
        date.month == DateTime.now().month &&
        date.day == DateTime.now().day;

    Color bg;
    Color textColor;
    String badgeText = code;

    switch (code) {
      case 'P':
        bg = const Color(0xFFDCFCE7);
        textColor = const Color(0xFF15803D);
        break;
      case 'P*':
        bg = const Color(0xFFCCFBF1);
        textColor = const Color(0xFF0F766E);
        break;
      case 'L':
        bg = const Color(0xFFDBEAFE);
        textColor = const Color(0xFF1D4ED8);
        break;
      case 'A':
        bg = const Color(0xFFFFE4E6);
        textColor = const Color(0xFFBE123C);
        break;
      case 'R':
        bg = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFB45309);
        break;
      case 'W':
        bg = const Color(0xFFF1F5F9);
        textColor = const Color(0xFF94A3B8);
        break;
      default:
        bg = const Color(0xFFF8FAFC);
        textColor = const Color(0xFFCBD5E1);
        badgeText = '-';
        break;
    }

    return GestureDetector(
      onTap: () => _detail(context, d),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(color: const Color(0xFF2563EB), width: 2)
              : Border.all(color: Colors.black.withOpacity(0.04)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: isToday ? const Color(0xFF1D4ED8) : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              badgeText,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: textColor,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(String label, dynamic count, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: textColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  void _detail(BuildContext context, Map d) {
    final s = (d['sessions'] as Map).cast<String, dynamic>();
    final lines = <String>[
      codeMeaning[d['code']] ?? 'No record',
      if (s.isNotEmpty)
        'Sessions: ${s.entries.map((e) => '${{'M': 'Morning', 'A': 'Afternoon', 'E': 'Evening'}[e.key]} ${e.value}').join(', ')}',
      if (d['holiday'] != null) 'Holiday: ${d['holiday']}',
      if (d['leave_type'] != null) 'Leave: ${d['leave_type']}',
      if ((d['remark'] ?? '').toString().isNotEmpty) 'Admin remark: ${d['remark']}',
    ];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_note_rounded, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Text(
                  niceDate(d['date']),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const Divider(height: 24),
            ...lines.map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    l,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.3),
                  ),
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
