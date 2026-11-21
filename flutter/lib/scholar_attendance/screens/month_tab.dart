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
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(
            onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
            icon: const Icon(Icons.chevron_left)),
        Text(DateFormat('MMMM yyyy').format(month), style: Theme.of(context).textTheme.titleMedium),
        IconButton(
            onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
            icon: const Icon(Icons.chevron_right)),
      ]),
      Expanded(
        child: Loader<Map<String, dynamic>>(
          key: ValueKey(_m),
          load: () async => (await widget.api.get('/att/month', query: {'m': _m})) as Map<String, dynamic>,
          builder: (context, data, _) => MonthGrid(data: data),
        ),
      ),
    ]);
  }
}

class MonthGrid extends StatelessWidget {
  final Map<String, dynamic> data;
  const MonthGrid({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = (data['days'] as List).cast<Map<String, dynamic>>();
    final totals = data['totals'] as Map<String, dynamic>;
    final first = DateTime.parse(days.first['date']);
    final lead = first.weekday - 1; // Monday first
    final cells = <Widget>[
      for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
        Center(child: Text(d, style: const TextStyle(fontWeight: FontWeight.w600))),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (final d in days)
        GestureDetector(
          onTap: () => _detail(context, d),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: codeColor(d['code'] as String, cs).withOpacity(d['code'] == '' ? 0.3 : 0.85),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${DateTime.parse(d['date']).day}', style: const TextStyle(fontSize: 12)),
              Text(d['code'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 12)),
            ]),
          ),
        ),
    ];
    return ListView(padding: const EdgeInsets.all(12), children: [
      GridView.count(
          crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), children: cells),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final k in const ['P', 'P*', 'L', 'A', 'R'])
          Chip(label: Text('$k ${totals[k] ?? 0}'), backgroundColor: codeColor(k, cs).withOpacity(0.2)),
      ]),
      const SizedBox(height: 8),
      for (final e in codeMeaning.entries)
        Text('${e.key}  ${e.value}', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  void _detail(BuildContext context, Map d) {
    final s = (d['sessions'] as Map).cast<String, dynamic>();
    final lines = <String>[
      codeMeaning[d['code']] ?? 'No record',
      if (s.isNotEmpty) 'Sessions: ${s.entries.map((e) => '${{'M': 'Morning', 'A': 'Afternoon', 'E': 'Evening'}[e.key]} ${e.value}').join(', ')}',
      if (d['holiday'] != null) 'Holiday: ${d['holiday']}',
      if (d['leave_type'] != null) 'Leave: ${d['leave_type']}',
      if ((d['remark'] ?? '').toString().isNotEmpty) 'Admin remark: ${d['remark']}',
    ];
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(niceDate(d['date']), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...lines.map(Text.new),
        ]),
      ),
    );
  }
}
