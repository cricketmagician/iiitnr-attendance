import 'package:flutter/material.dart';

import '../api.dart';
import '../attendance_confirm_screen.dart';
import '../face_check.dart';
import '../guard_kiosk_screen.dart';
import '../qr_scanner_screen.dart';
import '../reminders.dart';
import '../ui_common.dart';

class TodayTab extends StatefulWidget {
  final AttendanceApi api;
  const TodayTab({super.key, required this.api});
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

  Future<void> _mark() async {
    final sessions = (today?['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final open = sessions.where((s) => s['state'] == 'open').toList();
    final label = open.isNotEmpty ? (open.first['label'] as String? ?? 'Session') : 'Attendance';

    // Step 1: Scan Guard's 3-second Rotating Dynamic QR Code
    final qrToken = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => QRScannerScreen(sessionLabel: label)),
    );
    if (qrToken == null || !mounted) return;

    // Small delay to let Android camera hardware release back sensor before front camera opens
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    // Step 2 & 3: Live Face Verification and Confirmation Screen
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
      final r = await widget.api.post('/att/mark', {
        'face_image': base64Image,
        'qr_token': qrToken,
      });
      if (!mounted) return;
      setState(() => today = r['today'] as Map<String, dynamic>);
      showMessage(context, r['message'], ok: true);
      AttendanceReminders.sync(widget.api).catchError((_) {});
    } catch (e) {
      if (mounted) showMessage(context, e);
      _load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _giveReason(Map r) async {
    final c = TextEditingController(text: r['scholar_reason'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reason for ${niceDate(r['date'])}'),
        content: TextField(controller: c, maxLines: 3, maxLength: 1000,
            decoration: const InputDecoration(hintText: 'e.g. in the lab, phone battery died')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.post('/att/reviews/${r['id']}/reason', {'reason': c.text.trim()});
      if (mounted) showMessage(context, 'Reason sent to the admin office.', ok: true);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null && today == null) return ErrorRetry(error: error!, onRetry: _load);
    if (today == null) return const Loading();
    final t = today!;
    final cs = Theme.of(context).colorScheme;
    final sessions = (t['sessions'] as List).cast<Map<String, dynamic>>();
    final open = sessions.where((s) => s['state'] == 'open').toList();
    final marked = t['marked_count'] as int;
    final required = t['required'] as int;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(niceDate(t['date']), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (t['working_day'] != true)
          Card(child: ListTile(leading: const Icon(Icons.weekend),
              title: Text(t['holiday'] != null ? 'Holiday: ${t['holiday']}' : 'No attendance today (weekend)')))
        else if (t['on_leave'] != null)
          const Card(child: ListTile(leading: Icon(Icons.event_busy), title: Text('You are on leave today.')))
        else ...[
          Card(
            color: t['day_complete'] == true ? Colors.green.shade50 : null,
            child: ListTile(
              leading: Icon(t['day_complete'] == true ? Icons.check_circle : Icons.info_outline,
                  color: t['day_complete'] == true ? Colors.green : cs.primary),
              title: Text('$marked of 3 sessions marked'),
              subtitle: Text(t['day_complete'] == true
                  ? 'Today counts as present.'
                  : 'Mark at least $required sessions for the day to count as present.'),
            ),
          ),
          const SizedBox(height: 8),
          ...sessions.map((s) => Card(
                child: ListTile(
                  leading: _stateIcon(s['state'] as String),
                  title: Text('${s['label']}  ·  ${s['start']}–${s['end']}'),
                  subtitle: Text(_stateText(s)),
                ),
              )),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: (open.isEmpty || busy) ? null : _mark,
              icon: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.qr_code_scanner),
              label: Text(open.isEmpty ? 'No window open now' : 'Scan Guard QR & Mark Present (${open.first['label']})'),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GuardKioskScreen(api: widget.api)),
            ),
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Open Guard Kiosk Screen (Dynamic 3s QR)'),
          ),
          const SizedBox(height: 8),
          Text('Two-Factor Verification: Dynamic 3s Guard QR + AI Face Match',
              style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ],
        if (reviews.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Days sent to the admin office', style: Theme.of(context).textTheme.titleSmall),
          ...reviews.map((r) => Card(
                child: ListTile(
                  title: Text(niceDate(r['date'])),
                  subtitle: Text(r['scholar_reason']?.toString().isNotEmpty == true
                      ? 'Your reason: ${r['scholar_reason']}'
                      : 'Fewer than 2 sessions marked. Add a reason, or apply for leave.'),
                  trailing: TextButton(onPressed: () => _giveReason(r), child: const Text('Reason')),
                ),
              )),
        ],
      ]),
    );
  }

  Widget _stateIcon(String state) {
    switch (state) {
      case 'marked':
        return const Icon(Icons.check_circle, color: Colors.green);
      case 'open':
        return const Icon(Icons.radio_button_checked, color: Colors.orange);
      case 'missed':
        return const Icon(Icons.cancel_outlined, color: Colors.grey);
      default:
        return const Icon(Icons.schedule, color: Colors.grey);
    }
  }

  String _stateText(Map s) {
    switch (s['state']) {
      case 'marked':
        return 'Marked at ${s['marked_at']}';
      case 'open':
        return 'Open now';
      case 'missed':
        return 'Not marked';
      default:
        return 'Opens at ${s['start']}';
    }
  }
}
