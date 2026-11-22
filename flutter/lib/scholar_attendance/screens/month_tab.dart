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

  bool get _isCurrentMonth {
    final n = DateTime.now();
    return month.year == n.year && month.month == n.month;
  }

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      key: ValueKey(_m),
      load: () async => (await widget.api.get('/att/month', query: {'m': _m})) as Map<String, dynamic>,
      builder: (context, data, _) => MonthGrid(
        data: data,
        month: month,
        onPrev: () => setState(() => month = DateTime(month.year, month.month - 1)),
        onNext: () => setState(() => month = DateTime(month.year, month.month + 1)),
        onToday: _isCurrentMonth ? null : () => setState(() => month = DateTime(DateTime.now().year, DateTime.now().month)),
      ),
    );
  }
}

class MonthGrid extends StatelessWidget {
  final Map<String, dynamic> data;
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onToday;
  const MonthGrid({super.key, required this.data, required this.month, required this.onPrev, required this.onNext, this.onToday});

  @override
  Widget build(BuildContext context) {
    final days = (data['days'] as List).cast<Map<String, dynamic>>();
    final totals = (data['totals'] as Map).cast<String, dynamic>();
    final first = DateTime.parse(days.first['date']);
    final lead = first.weekday - 1; // Monday first
    int n(String k) => totals[k] as int? ?? 0;

    final present = n('P') + n('P*');
    final decided = present + n('A');
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        GradientHeader(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Calendar', style: onGradientTitle)),
              if (onToday != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: onToday,
                  child: const Text('This month'),
                ),
            ]),
            const SizedBox(height: 14),
            GlassTile(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(children: [
                IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded, color: Colors.white)),
                Expanded(
                  child: Text(DateFormat('MMMM yyyy').format(month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded, color: Colors.white)),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              _Stat(label: 'Present', value: present, dot: const Color(0xFF4ADE80)),
              const SizedBox(width: 8),
              _Stat(label: 'Leave', value: n('L'), dot: const Color(0xFF7DD3FC)),
              const SizedBox(width: 8),
              _Stat(label: 'Review', value: n('R'), dot: const Color(0xFFFCD34D)),
              const SizedBox(width: 8),
              _Stat(label: 'Absent', value: n('A'), dot: const Color(0xFFFCA5A5)),
            ]),
            if (decided > 0) ...[
              const SizedBox(height: 12),
              Text('${(present * 100 / decided).round()}% present on decided days', style: onGradientBody),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Calendar
        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(children: [
            Row(
              children: [
                for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Expanded(
                    child: Center(
                      child: Text(d,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              children: [
                for (var i = 0; i < lead; i++) const SizedBox(),
                for (final d in days) _DayCell(day: d, onTap: () => _detail(context, d)),
              ],
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Legend
        Wrap(spacing: 16, runSpacing: 10, children: const [
          _Legend(color: AppColors.ink, label: 'Present'),
          _Legend(color: AppColors.leave, label: 'Leave'),
          _Legend(color: AppColors.warning, label: 'In review'),
          _Legend(color: AppColors.danger, label: 'Absent'),
          _Legend(color: AppColors.line, label: 'Weekend / holiday'),
        ]),
        const SizedBox(height: 12),
        Text('A day counts as present when 2 of the 3 sessions are marked. Tap a day for details.',
            style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ],
    );
  }

  void _detail(BuildContext context, Map d) {
    final s = (d['sessions'] as Map).cast<String, dynamic>();
    final code = d['code'] as String;
    const names = {'M': 'Morning', 'A': 'Afternoon', 'E': 'Evening'};
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('EEEE, d MMMM').format(DateTime.parse(d['date'])),
                style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 8),
            _codePill(code),
            const SizedBox(height: 12),
            const Divider(),
            for (final k in const ['M', 'A', 'E'])
              DetailRow(
                icon: s.containsKey(k) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                label: names[k]!,
                value: s.containsKey(k) ? 'Marked ${s[k]}' : '—',
                valueColor: s.containsKey(k) ? AppColors.success : AppColors.muted,
              ),
            if (d['holiday'] != null) DetailRow(icon: Icons.celebration_outlined, label: 'Holiday', value: d['holiday']),
            if (d['leave_type'] != null)
              DetailRow(icon: Icons.beach_access_outlined, label: 'Leave', value: d['leave_type'].toString()),
            if ((d['remark'] ?? '').toString().isNotEmpty)
              DetailRow(icon: Icons.notes_rounded, label: 'Office remark', value: d['remark'].toString()),
          ]),
        ),
      ),
    );
  }

  Widget _codePill(String code) => switch (code) {
        'P' || 'P*' => StatusPill(codeMeaning[code]!, tone: PillTone.success),
        'L' => StatusPill(codeMeaning[code]!, tone: PillTone.leave),
        'A' => StatusPill(codeMeaning[code]!, tone: PillTone.danger),
        'R' => StatusPill(codeMeaning[code]!, tone: PillTone.warning),
        '-' => StatusPill(codeMeaning[code]!, tone: PillTone.brand),
        _ => StatusPill(codeMeaning[code] ?? 'No record'),
      };
}

class _DayCell extends StatelessWidget {
  final Map<String, dynamic> day;
  final VoidCallback onTap;
  const _DayCell({required this.day, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final code = day['code'] as String;
    final date = DateTime.parse(day['date']);
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;

    Color bg = Colors.transparent;
    Color fg = AppColors.ink;
    FontWeight weight = FontWeight.w500;
    switch (code) {
      case 'P':
      case 'P*':
        bg = AppColors.ink;
        fg = Colors.white;
        weight = FontWeight.w700;
      case 'L':
        bg = AppColors.leaveSoft;
        fg = AppColors.leave;
        weight = FontWeight.w700;
      case 'A':
        bg = AppColors.dangerSoft;
        fg = AppColors.danger;
        weight = FontWeight.w700;
      case 'R':
        bg = AppColors.warningSoft;
        fg = AppColors.warning;
        weight = FontWeight.w700;
      case 'W':
      case 'H':
        fg = AppColors.muted.withOpacity(0.7);
      case '':
        fg = date.isAfter(now) ? AppColors.inkSoft : AppColors.muted;
    }

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Center(
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: isToday ? Border.all(color: AppColors.ink, width: 1.5) : null,
          ),
          child: Text('${date.day}', style: TextStyle(fontSize: 14, fontWeight: weight, color: fg)),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color dot;
  const _Stat({required this.label, required this.value, required this.dot});
  @override
  Widget build(BuildContext context) => Expanded(
        child: GlassTile(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$value', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
            const SizedBox(height: 6),
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.85))),
              ),
            ]),
          ]),
        ),
      );
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
