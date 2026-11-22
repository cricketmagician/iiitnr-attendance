import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../ui_common.dart';

/// Home for Supervisor, HoD, Dean (R&I) and the Attendance Office.
/// Shows their scholars today, the month so far, and what is waiting for them.
class StaffDashboard extends StatelessWidget {
  final AttendanceApi api;
  final Map<String, dynamic> me;
  final VoidCallback onProfile;

  /// Opens another tab by key: approvals, dean, leave, reviews, register, devices.
  final void Function(String key) onOpen;
  const StaffDashboard({super.key, required this.api, required this.me, required this.onProfile, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      load: () async => (await api.get('/admin/dashboard')) as Map<String, dynamic>,
      builder: (context, d, _) => _Body(d: d, me: me, onProfile: onProfile, onOpen: onOpen),
    );
  }
}

class _Body extends StatelessWidget {
  final Map<String, dynamic> d;
  final Map<String, dynamic> me;
  final VoidCallback onProfile;
  final void Function(String key) onOpen;
  const _Body({required this.d, required this.me, required this.onProfile, required this.onOpen});

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final today = (d['today'] as Map).cast<String, dynamic>();
    final total = d['scholars'] as int;
    final checked = today['checked_in'] as int;
    final onLeave = today['on_leave'] as int;
    final notSeen = today['not_seen'] as int;
    final name = (me['name'] ?? '').toString();
    final first = name.split(' ').where((w) => w.isNotEmpty).take(2).join(' ');
    final roster = (d['roster'] as List).cast<Map<String, dynamic>>();
    final attention = (d['attention'] as List).cast<Map<String, dynamic>>();

    return ListView(padding: EdgeInsets.zero, children: [
      GradientHeader(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d['title'].toString().toUpperCase(), style: onGradientCaption),
                const SizedBox(height: 6),
                Text('$_greeting,\n$first', style: onGradientTitle),
              ]),
            ),
            GestureDetector(
              onTap: onProfile,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle),
                child: Text(initials(name),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
              '${DateFormat('EEEE, d MMMM').format(DateTime.parse(d['date']))} · ${d['scope']}',
              style: onGradientBody),
          const SizedBox(height: 22),
          Row(children: [
            _Ring(value: total == 0 ? 0 : (checked + onLeave) / total, label: '$checked/$total'),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  d['working_day'] == true
                      ? (total == 0 ? 'No scholars yet' : '$checked of $total checked in')
                      : (d['holiday'] != null ? 'Holiday: ${d['holiday']}' : 'Weekend, no sessions'),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  total == 0
                      ? 'Scholars linked to you will appear here.'
                      : d['working_day'] == true
                          ? 'Marked at least one session today.'
                          : 'Sessions resume on the next working day.',
                  style: onGradientBody.copyWith(fontSize: 13.5),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            _Glass(value: checked, label: 'Checked in', dot: const Color(0xFF4ADE80)),
            const SizedBox(width: 8),
            _Glass(value: onLeave, label: 'On leave', dot: const Color(0xFF7DD3FC)),
            const SizedBox(width: 8),
            _Glass(value: notSeen, label: 'Not seen', dot: const Color(0xFFFCA5A5)),
          ]),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // What is waiting for this person
          SectionHeader('Needs you', trailing: _pendingTotal == 0 ? null : '$_pendingTotal waiting'),
          ..._pendingCards(context),

          // Sessions today
          const SectionHeader('Sessions today'),
          Row(children: [
            for (final (i, s) in (today['sessions'] as List).cast<Map<String, dynamic>>().indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _SessionTile(s: s, total: total)),
            ],
          ]),

          // Month
          SectionHeader('This month', trailing: d['month']['label'].toString()),
          _MonthCard(month: (d['month'] as Map).cast<String, dynamic>(), onOpen: () => onOpen('register')),

          if (attention.isNotEmpty) ...[
            const SectionHeader('Below 75%', trailing: 'This month'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                for (final (i, r) in attention.indexed) ...[
                  if (i > 0) const Divider(indent: 72, height: 1),
                  _PersonRow(r: r, trailing: _pctBadge(r['pct'] as int)),
                ],
              ]),
            ),
          ],

          SectionHeader('Scholars today', trailing: total == 0 ? null : '$total total'),
          if (roster.isEmpty)
            const AppCard(
              child: EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No scholars yet',
                  message: 'Scholars appear here once the office links them to you.'),
            )
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                for (final (i, r) in roster.take(30).indexed) ...[
                  if (i > 0) const Divider(indent: 72, height: 1),
                  _PersonRow(r: r, trailing: _todayPill(r)),
                ],
              ]),
            ),
          if (roster.length > 30) ...[
            const SizedBox(height: 10),
            Center(
              child: TextButton(onPressed: () => onOpen('register'), child: Text('See all ${roster.length} in the register')),
            ),
          ],
          const SizedBox(height: 8),
          Text('Present = 2 of 3 sessions marked. Pull down to refresh.', style: text.bodySmall),
        ]),
      ),
    ]);
  }

  Map<String, int> get _pending => (d['pending'] as Map).cast<String, int>();
  int get _pendingTotal => _pending.values.fold(0, (a, b) => a + b);

  List<Widget> _pendingCards(BuildContext context) {
    const meta = {
      'leave_supervisor': ('approvals', Icons.how_to_reg_rounded, 'Leave to approve', 'From your scholars'),
      'leave_dean': ('dean', Icons.school_rounded, 'Academic leave', 'Beyond 30 days, needs the Dean'),
      'leave_admin': ('leave', Icons.fact_check_rounded, 'Leave to confirm', 'Approved, waiting for the office'),
      'reviews': ('reviews', Icons.rule_rounded, 'Day reviews', 'Days with only one session marked'),
      'devices': ('devices', Icons.smartphone_rounded, 'Phone changes', 'Scholars asking to switch phone'),
    };
    final items = [for (final e in _pending.entries) if (meta.containsKey(e.key)) (meta[e.key]!, e.value)];
    if (items.isEmpty) return const [];
    if (_pendingTotal == 0) {
      return [
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.done_all_rounded, color: AppColors.success, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('All caught up', style: Theme.of(context).textTheme.titleMedium),
                Text('Nothing is waiting for you.', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ]),
        ),
      ];
    }
    return [
      AppCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          for (final (i, ((key, icon, title, sub), n)) in items.indexed) ...[
            if (i > 0) const Divider(indent: 72, height: 1),
            InkWell(
              onTap: () => onOpen(key),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: n > 0 ? AppColors.ink : AppColors.neutralSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 21, color: n > 0 ? Colors.white : AppColors.muted),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      Text(sub, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                  if (n > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 28),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(999)),
                      child: Text('$n',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    )
                  else
                    const Text('None', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ]),
              ),
            ),
          ],
        ]),
      ),
    ];
  }

  static Widget _todayPill(Map<String, dynamic> r) => switch (r['today']) {
        'present' => const StatusPill('Present', tone: PillTone.success),
        'partial' => StatusPill('Only ${_sessionNames(r['sessions_today'])}', tone: PillTone.warning),
        'leave' => const StatusPill('On leave', tone: PillTone.leave),
        'off' => const StatusPill('Off today'),
        _ => const StatusPill('Not seen'),
      };

  static String _sessionNames(String s) =>
      s.split('').map((c) => const {'M': 'Morning', 'A': 'Afternoon', 'E': 'Evening'}[c] ?? c).join(', ');

  static Widget _pctBadge(int pct) => Text('$pct%',
      style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800, color: pct < 60 ? AppColors.danger : AppColors.warning));
}

class _PersonRow extends StatelessWidget {
  final Map<String, dynamic> r;
  final Widget trailing;
  const _PersonRow({required this.r, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final pct = r['pct'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(children: [
        InitialsAvatar(r['name'].toString(), size: 42),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['name'].toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
            Text(
              [
                r['roll_no'],
                r['programme'],
                if (pct != null) '$pct% this month',
              ].where((x) => x != null && x.toString().isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Flexible(flex: 0, child: trailing),
      ]),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Map<String, dynamic> s;
  final int total;
  const _SessionTile({required this.s, required this.total});

  @override
  Widget build(BuildContext context) {
    final open = s['open'] == true;
    final marked = s['marked'] as int;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: open ? AppColors.ink : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(s['label'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: open ? Colors.white70 : AppColors.muted)),
          ),
          if (open)
            Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 8),
        Text.rich(TextSpan(children: [
          TextSpan(
              text: '$marked',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: open ? Colors.white : AppColors.ink)),
          TextSpan(
              text: '/$total',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: open ? Colors.white54 : AppColors.muted)),
        ])),
        const SizedBox(height: 4),
        Text('${s['start']}–${s['end']}',
            style: TextStyle(fontSize: 11.5, color: open ? Colors.white54 : AppColors.muted)),
      ]),
    );
  }
}

class _MonthCard extends StatelessWidget {
  final Map<String, dynamic> month;
  final VoidCallback onOpen;
  const _MonthCard({required this.month, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = (month['totals'] as Map).cast<String, int>();
    final present = t['P']! + t['P*']!;
    final parts = [
      (present, AppColors.ink, 'Present'),
      (t['L']!, AppColors.leave, 'Leave'),
      (t['R']!, AppColors.warning, 'Review'),
      (t['A']!, AppColors.danger, 'Absent'),
    ];
    final sum = parts.fold<int>(0, (a, p) => a + p.$1);
    final pct = month['pct'];
    return AppCard(
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (pct == null)
            const Text('No days decided yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink))
          else ...[
            Text('$pct%',
                style:
                    const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1, color: AppColors.ink)),
            const SizedBox(width: 10),
            const Padding(
              padding: EdgeInsets.only(bottom: 7),
              child: Text('present on decided days', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
          ],
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: sum == 0
                ? Container(color: AppColors.neutralSoft)
                : Row(children: [
                    for (final p in parts)
                      if (p.$1 > 0) Expanded(flex: p.$1, child: Container(color: p.$2)),
                  ]),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 16, runSpacing: 8, children: [
          for (final p in parts)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: p.$2, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('${p.$3} ${p.$1}', style: Theme.of(context).textTheme.bodySmall),
            ]),
        ]),
        const SizedBox(height: 6),
        Text('Scholar-days across everyone you can see.', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class _Ring extends StatelessWidget {
  final double value;
  final String label;
  const _Ring({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 76,
        height: 76,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value.clamp(0, 1),
              strokeWidth: 7,
              strokeCap: StrokeCap.round,
              color: const Color(0xFF4ADE80),
              backgroundColor: Colors.white.withOpacity(0.12),
            ),
          ),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _Glass extends StatelessWidget {
  final int value;
  final String label;
  final Color dot;
  const _Glass({required this.value, required this.label, required this.dot});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GlassTile(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$value',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
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
