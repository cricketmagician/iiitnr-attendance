import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../attendance_confirm_screen.dart';
import '../face_check.dart';
import '../qr_scanner_screen.dart';
import '../reminders.dart';
import '../ui_common.dart';

class TodayTab extends StatefulWidget {
  final AttendanceApi api;
  final Map<String, dynamic> me;
  final VoidCallback onProfile;
  const TodayTab({super.key, required this.api, required this.me, required this.onProfile});
  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> with WidgetsBindingObserver {
  Map<String, dynamic>? today;
  List<dynamic> reviews = [];
  Object? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.api.get('/att/today');
      final r = await widget.api.get('/att/reviews');
      if (!mounted) return;
      setState(() {
        today = t as Map<String, dynamic>;
        reviews = (r as List).where((x) => x['status'] == 'pending').toList();
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  // ------------------------------------------------------------ marking flow

  Future<void> _mark() async {
    final sessions = (today?['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final open = sessions.where((s) => s['state'] == 'open').toList();
    final label = open.isNotEmpty ? (open.first['label'] as String? ?? 'Session') : 'Attendance';

    // Step 1: scan the guard desk's rotating QR code
    final qrToken = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => QRScannerScreen(sessionLabel: label)),
    );
    if (qrToken == null || !mounted) return;

    // Let the back camera release before the front camera opens
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    // Step 2: live selfie, then confirm
    String? base64Image;
    while (mounted) {
      base64Image = await FaceCheck.captureFace(context, sessionLabel: label);
      if (base64Image == null || !mounted) return;
      final confirmed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceConfirmScreen(
            base64FaceImage: base64Image!,
            qrToken: qrToken,
            sessionLabel: label,
            scholarInfo: today,
          ),
        ),
      );
      if (confirmed == true) break;
    }
    if (base64Image == null || !mounted) return;

    setState(() => busy = true);
    try {
      final r = await widget.api.post('/att/mark', {'face_image': base64Image, 'qr_token': qrToken});
      if (!mounted) return;
      setState(() => today = r['today'] as Map<String, dynamic>);
      _showSuccess(r as Map, label);
      AttendanceReminders.sync(widget.api).catchError((_) {});
    } catch (e) {
      if (mounted) showMessage(context, e);
      _load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _showSuccess(Map r, String label) {
    HapticFeedback.mediumImpact();
    final marked = today?['marked_count'] ?? 1;
    final required = today?['required'] ?? 2;
    final faceStatus = r['face_status']?.toString() ?? '';
    final matchPct = r['match_pct'];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: AppColors.successSoft, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: AppColors.success, size: 36),
            ),
            const SizedBox(height: 20),
            Text('$label marked', style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              marked >= required
                  ? "That's $marked of $required sessions. Today counts as present."
                  : "That's $marked of $required sessions. Mark ${required - marked} more today to be counted present.",
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            const Divider(),
            DetailRow(icon: Icons.schedule_rounded, label: 'Marked at', value: r['marked_at']?.toString() ?? '—'),
            DetailRow(
              icon: Icons.qr_code_2_rounded,
              label: 'Guard QR',
              value: r['qr_status'] == 'Verified' ? 'Verified' : 'Not used',
              valueColor: r['qr_status'] == 'Verified' ? AppColors.success : null,
            ),
            DetailRow(
              icon: Icons.face_retouching_natural_rounded,
              label: 'Face check',
              value: switch (faceStatus) {
                'Verified' => 'Matched ($matchPct%)',
                'Enrolled' => 'Face registered',
                _ => 'Not used',
              },
              valueColor: faceStatus == 'Verified' || faceStatus == 'Enrolled' ? AppColors.success : null,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _giveReason(Map r) async {
    final c = TextEditingController(text: r['scholar_reason'] ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Why was ${shortDate(r['date'])} short?', style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text('The attendance office reads this before deciding the day.',
              style: Theme.of(ctx).textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: c,
            autofocus: true,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(hintText: 'e.g. I was in the research lab running a hardware test'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send to office')),
          ),
        ]),
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.post('/att/reviews/${r['id']}/reason', {'reason': c.text.trim()});
      if (mounted) showMessage(context, 'Sent to the attendance office.', ok: true);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  // ------------------------------------------------------------ build

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    if (today == null && error == null) return const Loading();
    if (today == null) return SafeArea(child: ErrorRetry(error: error!, onRetry: _load));
    final t = today!;
    final sessions = (t['sessions'] as List).cast<Map<String, dynamic>>();
    final firstName = (widget.me['name'] ?? 'Scholar').toString().split(' ').first;

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(DateFormat('EEEE, d MMMM').format(DateTime.parse(t['date'])).toUpperCase(),
                        style: onGradientCaption),
                    const SizedBox(height: 6),
                    Text('${_greeting()},\n$firstName', style: onGradientTitle),
                  ]),
                ),
                GestureDetector(
                  onTap: widget.onProfile,
                  child: Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                    child: Text(initials(widget.me['name']?.toString() ?? '?'),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15)),
                  ),
                ),
              ]),
              const SizedBox(height: 26),
              _hero(t, sessions),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SectionHeader("Today's sessions", trailing: 'Need ${t['required']} of ${sessions.length}'),
              for (final s in sessions) Padding(padding: const EdgeInsets.only(bottom: 10), child: _sessionCard(s)),
              if (reviews.isNotEmpty) ...[
                SectionHeader('Needs your reason', trailing: '${reviews.length}'),
                ...reviews.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _reviewCard(r as Map<String, dynamic>),
                    )),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  /// Ring + what to do now + the one action, all on the gradient.
  Widget _hero(Map<String, dynamic> t, List<Map<String, dynamic>> sessions) {
    final marked = t['marked_count'] as int;
    final required = t['required'] as int;
    final open = sessions.where((s) => s['state'] == 'open').toList();
    final upcoming = sessions.where((s) => s['state'] == 'upcoming').toList();

    late final String title;
    late final String body;
    Widget? action;
    var showSteps = false;

    if (t['working_day'] != true) {
      title = t['holiday'] != null ? 'Holiday' : 'Day off';
      body = t['holiday']?.toString() ?? 'No attendance on weekends. Enjoy!';
    } else if (t['on_leave'] != null) {
      title = "You're on leave";
      body = 'Approved ${t['on_leave'].toString().toLowerCase()} leave covers today.';
    } else if (t['day_complete'] == true) {
      title = 'All done for today';
      body = '$marked sessions marked. Today counts as present.';
    } else if (open.isNotEmpty) {
      final s = open.first;
      title = '${s['label']} is open';
      body = 'Mark before ${s['end']} to keep today on track.';
      showSteps = true;
      action = OnGradientButton(
        label: busy ? 'Marking…' : 'Mark ${s['label'].toString().toLowerCase()} attendance',
        icon: Icons.qr_code_scanner_rounded,
        busy: busy,
        onPressed: _mark,
      );
    } else if (upcoming.isNotEmpty) {
      final s = upcoming.first;
      final left = required - marked;
      title = 'Next: ${s['label']}';
      body = left > 0
          ? 'Opens at ${s['start']}. Mark $left more ${left == 1 ? 'session' : 'sessions'} today.'
          : 'Opens at ${s['start']}. You are on track for today.';
      action = OnGradientButton(label: 'Opens at ${s['start']}', icon: Icons.schedule_rounded);
    } else {
      title = 'Day is short';
      body = '$marked of $required sessions marked. The office will review it; add a reason below.';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: required == 0 ? 0 : (marked / required).clamp(0, 1).toDouble(),
                strokeWidth: 7,
                strokeCap: StrokeCap.round,
                backgroundColor: Colors.white.withOpacity(0.1),
                color: const Color(0xFF4ADE80),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$marked/$required',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
              const SizedBox(height: 2),
              Text('marked', style: onGradientCaption.copyWith(fontSize: 10.5)),
            ]),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(height: 6),
            Text(body, style: onGradientBody),
          ]),
        ),
      ]),
      if (action != null) ...[const SizedBox(height: 22), action],
      if (showSteps) ...[
        const SizedBox(height: 12),
        Row(children: [
          _step('1', 'Scan QR'),
          const SizedBox(width: 8),
          _step('2', 'Selfie'),
          const SizedBox(width: 8),
          _step('3', 'Done'),
        ]),
      ],
    ]);
  }

  Widget _step(String n, String label) => Expanded(
        child: GlassTile(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Text(n, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.ink)),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _sessionCard(Map<String, dynamic> s) {
    final state = s['state'] as String;
    final icon = switch (s['session']) {
      'M' => Icons.wb_twilight_rounded,
      'A' => Icons.wb_sunny_outlined,
      _ => Icons.nights_stay_outlined,
    };
    final done = state == 'marked';
    final pill = switch (state) {
      'marked' => StatusPill('Marked ${s['marked_at'] ?? ''}'.trim(), tone: PillTone.success),
      'open' => const StatusPill('Open now', tone: PillTone.brand),
      'missed' => const StatusPill('Missed', tone: PillTone.danger),
      'upcoming' => StatusPill('At ${s['start']}', icon: Icons.schedule_rounded),
      _ => const StatusPill('No session'),
    };
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: done ? AppColors.ink : AppColors.neutralSoft,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(done ? Icons.check_rounded : icon, color: done ? Colors.white : AppColors.inkSoft, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['label'].toString(), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text('${s['start']} – ${s['end']}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        pill,
      ]),
    );
  }

  Widget _reviewCard(Map<String, dynamic> r) {
    final marked = (r['sessions_marked'] ?? '').toString();
    final hasReason = (r['scholar_reason'] ?? '').toString().isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(DateFormat('d').format(DateTime.parse(r['date'])),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.warning, height: 1)),
            Text(DateFormat('MMM').format(DateTime.parse(r['date'])).toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.warning)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(marked.isEmpty ? 'No sessions marked' : '${marked.length} of 3 sessions marked',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(hasReason ? '“${r['scholar_reason']}”' : 'Waiting for office review',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        TextButton(onPressed: () => _giveReason(r), child: Text(hasReason ? 'Edit' : 'Add reason')),
      ]),
    );
  }
}
