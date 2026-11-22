import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'api.dart';
import 'ui_common.dart';

/// Guard desk: a large QR that changes every 3 seconds. Scholars scan it at the gate
/// before their selfie. Opened by a guard's login (api) or by the kiosk key.
class GuardKioskScreen extends StatefulWidget {
  final String? baseUrl;
  final AttendanceApi? api;

  /// Sent as X-Kiosk-Key when the kiosk runs without a logged-in admin/guard.
  final String? kioskKey;

  /// Shown in the header when a guard is signed in.
  final String? guardName;
  final VoidCallback? onLogout;
  const GuardKioskScreen({super.key, this.baseUrl, this.api, this.kioskKey, this.guardName, this.onLogout});

  @override
  State<GuardKioskScreen> createState() => _GuardKioskScreenState();
}

class _GuardKioskScreenState extends State<GuardKioskScreen> {
  String? _qr;
  String _session = '';
  bool _open = true;
  int _slot = 0;
  String? _problem;
  Timer? _fetch;
  Timer? _tick;
  double _left = 1;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    _fetch = Timer.periodic(const Duration(seconds: 1), (_) => _load());
    _tick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      final ms = DateTime.now().millisecondsSinceEpoch % 3000;
      setState(() {
        _left = (3000 - ms) / 3000;
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _fetch?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      Map<String, dynamic> res;
      if (widget.api != null) {
        res = await widget.api!.get('/att/guard/qr') as Map<String, dynamic>;
      } else {
        final base = widget.baseUrl ?? 'https://iiitnr-attendance.onrender.com';
        final r = await http.get(Uri.parse('$base/att/guard/qr'),
            headers: {if (widget.kioskKey != null) 'X-Kiosk-Key': widget.kioskKey!});
        if (r.statusCode != 200) {
          String msg = 'Could not load the QR (${r.statusCode}).';
          try {
            msg = (jsonDecode(r.body)['detail']['message'] ?? msg).toString();
          } catch (_) {}
          throw Exception(msg);
        }
        res = jsonDecode(r.body) as Map<String, dynamic>;
      }
      if (!mounted) return;
      setState(() {
        _problem = null;
        _open = res['window_open'] != false;
        _session = (res['session_label'] ?? '').toString();
        if (res['slot'] != _slot || _qr == null) {
          _slot = res['slot'] as int? ?? 0;
          _qr = res['qr_string'] as String?;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _problem = e is ApiException ? e.message : e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final secs = (_left * 3).ceil().clamp(1, 3);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final qrSize = (c.maxWidth - 96).clamp(200.0, 420.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 36),
                child: Column(children: [
                  // Header
                  Row(children: [
                    if (widget.onLogout == null)
                      IconButton(
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      )
                    else
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
                        child: const Icon(Icons.shield_outlined, color: AppColors.ink, size: 20),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('GUARD DESK', style: onGradientCaption),
                        Text(widget.guardName ?? 'IIIT Naya Raipur',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      ]),
                    ),
                    if (widget.onLogout != null)
                      TextButton(
                        onPressed: widget.onLogout,
                        style: TextButton.styleFrom(foregroundColor: Colors.white70),
                        child: const Text('Sign out'),
                      ),
                  ]),
                  const SizedBox(height: 28),

                  // Session and clock
                  Text(DateFormat('h:mm:ss a').format(_now),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _problem != null
                            ? const Color(0xFFFCA5A5)
                            : (_open ? const Color(0xFF4ADE80) : const Color(0xFFFCD34D)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _problem != null
                          ? 'Not connected'
                          : (_open ? '${_session.isEmpty ? 'Session' : _session} session · live' : 'No session open now'),
                      style: onGradientBody.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ]),
                  const SizedBox(height: 28),

                  // QR
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
                    child: SizedBox(
                      width: qrSize,
                      height: qrSize,
                      child: _qr == null
                          ? Center(
                              child: _problem == null
                                  ? const CircularProgressIndicator(color: AppColors.ink)
                                  : Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(_problem!,
                                          textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                                    ),
                            )
                          : Opacity(
                              opacity: _open && _problem == null ? 1 : 0.15,
                              child: QrImageView(
                                data: _qr!,
                                version: QrVersions.auto,
                                padding: EdgeInsets.zero,
                                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.ink),
                                dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square, color: AppColors.ink),
                                errorCorrectionLevel: QrErrorCorrectLevel.M,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Countdown
                  SizedBox(
                    width: qrSize + 40,
                    child: Column(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _left.clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: Colors.white.withOpacity(0.12),
                          valueColor: const AlwaysStoppedAnimation(Color(0xFF4ADE80)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Text('New code in ${secs}s', style: onGradientBody.copyWith(fontSize: 13)),
                        const Spacer(),
                        Text('#${_slot % 100000}', style: onGradientCaption),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 28),

                  // How it works
                  GlassTile(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      for (final (i, (icon, label)) in const [
                        (Icons.qr_code_scanner_rounded, 'Scholar scans'),
                        (Icons.face_retouching_natural_rounded, 'Takes selfie'),
                        (Icons.check_circle_outline_rounded, 'Marked'),
                      ].indexed) ...[
                        if (i > 0) Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.3), size: 18),
                        Expanded(
                          child: Column(children: [
                            Icon(icon, color: Colors.white, size: 22),
                            const SizedBox(height: 6),
                            Text(label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Text('Keep this screen on and facing the scholars. A photo of the code stops working in 3 seconds.',
                      textAlign: TextAlign.center, style: onGradientBody.copyWith(fontSize: 12.5)),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}
