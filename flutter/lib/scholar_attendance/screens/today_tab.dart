import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

    // Small delay to let camera hardware release back sensor before front camera opens
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
      _showSuccessCelebration(context, r, label);
      AttendanceReminders.sync(widget.api).catchError((_) {});
    } catch (e) {
      if (mounted) showMessage(context, e);
      _load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _showSuccessCelebration(BuildContext context, Map r, String label) {
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 25, offset: Offset(0, -5)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFD1FAE5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.25),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF059669), Color(0xFF10B981)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.check_rounded, color: Colors.white, size: 36),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Attendance Verified! 🎉',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$label Session marked present with Guard 3s QR & Live Face match.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        'TODAY\'S PROGRESS',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${today?['marked_count'] ?? 1} / ${today?['required'] ?? 2} Sessions',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
                  const Column(
                    children: [
                      Text(
                        'ACTIVE STREAK',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Text('🔥', style: TextStyle(fontSize: 14)),
                          SizedBox(width: 4),
                          Text(
                            '14 Days',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFD97706)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _giveReason(Map r) async {
    final c = TextEditingController(text: r['scholar_reason'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reason for ${niceDate(r['date'])}'),
        content: TextField(
          controller: c,
          maxLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(
            hintText: 'e.g. working in research lab, hardware test setup',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.post('/att/reviews/${r['id']}/reason', {'reason': c.text.trim()});
      if (mounted) showMessage(context, 'Reason submitted for office review.', ok: true);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildWeeklyStrip() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekDays = List.generate(6, (i) => monday.add(Duration(days: i))); // Mon - Sat

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: weekDays.map((d) {
          final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
          final isPast = d.isBefore(DateTime(now.year, now.month, now.day));
          final dayName = ['M', 'T', 'W', 'T', 'F', 'S'][d.weekday - 1];

          return Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isToday
                  ? const Color(0xFF2563EB)
                  : (isPast ? const Color(0xFFF1F5F9) : Colors.white),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isToday ? const Color(0xFF1D4ED8) : const Color(0xFFE2E8F0),
                width: isToday ? 1.5 : 1,
              ),
              boxShadow: isToday
                  ? [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Text(
                  dayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isToday ? Colors.white.withOpacity(0.85) : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${d.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isToday ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                if (isPast) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (error != null && today == null) return ErrorRetry(error: error!, onRetry: _load);
    if (today == null) return const Loading();
    final t = today!;
    final sessions = (t['sessions'] as List).cast<Map<String, dynamic>>();
    final open = sessions.where((s) => s['state'] == 'open').toList();
    final marked = t['marked_count'] as int;
    final required = t['required'] as int;
    final isComplete = t['day_complete'] == true;
    final progress = required > 0 ? (marked / required).clamp(0.0, 1.0) : 0.0;

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF2563EB),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Personalized Greeting Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_getGreeting()}, Scholar! 👋',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    niceDate(t['date']),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.blueGrey.shade600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, size: 14, color: Color(0xFF2563EB)),
                    SizedBox(width: 4),
                    Text(
                      'Biometric 2FA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 2. Weekly Day Strip (Mobbin: Joi & Insight Timer pattern)
          _buildWeeklyStrip(),

          // 3. Weekend or Leave Banner Check
          if (t['working_day'] != true)
            _buildSpecialStatusCard(
              icon: Icons.beach_access_rounded,
              color: Colors.indigo,
              title: t['holiday'] != null ? 'Institute Holiday: ${t['holiday']}' : 'Weekend (No Attendance Required)',
              subtitle: 'Attendance windows are closed for official weekend holiday.',
            )
          else if (t['on_leave'] != null)
            _buildSpecialStatusCard(
              icon: Icons.event_available_rounded,
              color: Colors.teal,
              title: 'On Approved Leave Today',
              subtitle: 'Your leave application is approved. No penalty applies.',
            )
          else ...[
            // 4. Hero Attendance Progress Card (Modern Gradient & Radial Meter)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0B192C), Color(0xFF1E3E62), Color(0xFF000000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E3E62).withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Radial Progress Ring
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 7,
                              strokeCap: StrokeCap.round,
                              backgroundColor: Colors.white.withOpacity(0.12),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isComplete ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                              ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$marked/$required',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  isComplete ? 'DONE' : 'SESSIONS',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: isComplete ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      // Text info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isComplete ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isComplete ? 'DAY COMPLETE' : 'IN PROGRESS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                    color: isComplete ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isComplete ? 'Marked Present for Today! 🎉' : '$marked of 3 Sessions Marked',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isComplete
                                  ? 'Attendance criteria met. Your daily stipend is secured.'
                                  : 'Need at least 2 sessions to count as full day present.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.7),
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Micro Stats Chips
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Row(
                          children: [
                            Text('🔥', style: TextStyle(fontSize: 14)),
                            SizedBox(width: 6),
                            Text(
                              '14-Day Streak',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                          ],
                        ),
                        Text('•', style: TextStyle(color: Colors.white38)),
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, size: 14, color: Color(0xFF38BDF8)),
                            SizedBox(width: 6),
                            Text(
                              'Guard QR + Face Match',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 5. Interactive Timeline Session Cards
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TODAY\'S TIME WINDOWS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  '3 Slots / Day',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            ...sessions.map((s) => _buildSessionTimelineCard(s)),
            const SizedBox(height: 20),

            // 6. Main Heroic CTA Button: Scan QR & Mark Attendance
            if (open.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: busy ? null : _mark,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 24),
                          const SizedBox(width: 12),
                          Text(
                            busy ? 'Verifying 2FA...' : 'Scan Guard QR & Mark (${open.first['label']})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.grey.shade600, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isComplete
                            ? 'All attendance requirements completed for today! 🎉'
                            : 'No attendance window is open right now. Next session opens soon.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 14),

            // 7. Quick Tool: Guard Kiosk Launcher
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GuardKioskScreen(api: widget.api)),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 20, color: Color(0xFF0F172A)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Launch Guard Desk Kiosk (Dynamic 3s QR)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ],

          // 8. Days Awaiting Office Review (if any)
          if (reviews.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFD97706)),
                const SizedBox(width: 6),
                Text(
                  'ATTENDANCE REVIEWS (${reviews.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFD97706),
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...reviews.map((r) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              niceDate(r['date']),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF92400E)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              r['scholar_reason']?.toString().isNotEmpty == true
                                  ? 'Note: ${r['scholar_reason']}'
                                  : 'Fewer than 2 sessions marked. Tap to explain.',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFDE68A),
                          foregroundColor: const Color(0xFF78350F),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _giveReason(r),
                        child: const Text('Explain', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSessionTimelineCard(Map<String, dynamic> s) {
    final state = s['state'] as String;
    final isMarked = state == 'marked';
    final isOpen = state == 'open';

    Color cardBg;
    Border border;
    Widget statusBadge;
    Widget iconWidget;

    if (isMarked) {
      cardBg = const Color(0xFFF0FDF4);
      border = Border.all(color: const Color(0xFFBBF7D0), width: 1.2);
      iconWidget = Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Color(0xFFDCFCE7),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20),
      );
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'MARKED AT ${s['marked_at']}',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF15803D)),
        ),
      );
    } else if (isOpen) {
      cardBg = const Color(0xFFEFF6FF);
      border = Border.all(color: const Color(0xFF60A5FA), width: 1.5);
      iconWidget = Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFDBEAFE),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withOpacity(0.3),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(Icons.radio_button_checked_rounded, color: Color(0xFF2563EB), size: 20),
      );
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '⚡ LIVE NOW',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      );
    } else {
      cardBg = Colors.white;
      border = Border.all(color: const Color(0xFFE2E8F0));
      iconWidget = Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Color(0xFFF1F5F9),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.schedule_rounded, color: Color(0xFF94A3B8), size: 20),
      );
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          state == 'missed' ? 'NOT MARKED' : 'OPENS AT ${s['start']}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: state == 'missed' ? const Color(0xFFEF4444) : const Color(0xFF64748B),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          iconWidget,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${s['label']} Session',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    statusBadge,
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Time window: ${s['start']} – ${s['end']}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialStatusCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
