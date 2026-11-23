import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'api.dart';
import 'proximity.dart';
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
  Timer? _feedTimer;
  double _left = 1;
  DateTime _now = DateTime.now();

  // Bluetooth beacon and the live list of marks
  final _beacon = GateBeacon();
  BeaconState _beaconState = BeaconState.idle;
  List<Map<String, dynamic>> _feed = const [];
  final Map<int, Uint8List?> _photos = {};
  final Set<int> _busyFlags = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadFeed();
    _fetch = Timer.periodic(const Duration(seconds: 1), (_) => _load());
    _feedTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadFeed());
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
    _feedTimer?.cancel();
    _beacon.stop();
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
      final ble = res['ble'] as Map?;
      if (ble != null && res['window_open'] != false) {
        _beacon.advertise(ble['uuid'].toString()).then((st) {
          if (mounted && st != _beaconState) setState(() => _beaconState = st);
        });
      }
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

  Future<dynamic> _getJson(String path) async {
    if (widget.api != null) return widget.api!.get(path);
    final base = widget.baseUrl ?? 'https://iiitnr-attendance.onrender.com';
    final r = await http.get(Uri.parse('$base$path'), headers: {'X-Kiosk-Key': widget.kioskKey ?? ''});
    if (r.statusCode != 200) throw Exception('(${r.statusCode})');
    return jsonDecode(r.body);
  }

  Future<dynamic> _postJson(String path, Map<String, dynamic> body) async {
    if (widget.api != null) return widget.api!.post(path, body);
    final base = widget.baseUrl ?? 'https://iiitnr-attendance.onrender.com';
    final r = await http.post(Uri.parse('$base$path'),
        headers: {'X-Kiosk-Key': widget.kioskKey ?? '', 'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (r.statusCode != 200) {
      String msg = 'Failed (${r.statusCode})';
      try {
        msg = jsonDecode(r.body)['detail']['message'].toString();
      } catch (_) {}
      throw Exception(msg);
    }
    return jsonDecode(r.body);
  }

  Future<void> _loadFeed() async {
    try {
      final res = await _getJson('/att/guard/feed') as Map<String, dynamic>;
      final marks = (res['marks'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() => _feed = marks);
      for (final m in marks.take(12)) {
        final id = m['id'] as int;
        if (m['has_selfie'] == true && !_photos.containsKey(id)) {
          _photos[id] = null;
          _photo(id);
        }
      }
    } catch (_) {/* the QR matters more; the list retries in 3 s */}
  }

  Future<void> _photo(int id) async {
    try {
      Uint8List bytes;
      if (widget.api != null) {
        bytes = await widget.api!.getBytes('/att/guard/marks/$id/selfie');
      } else {
        final base = widget.baseUrl ?? 'https://iiitnr-attendance.onrender.com';
        final r = await http.get(Uri.parse('$base/att/guard/marks/$id/selfie'),
            headers: {'X-Kiosk-Key': widget.kioskKey ?? ''});
        if (r.statusCode != 200) return;
        bytes = r.bodyBytes;
      }
      if (mounted) setState(() => _photos[id] = bytes);
    } catch (_) {}
  }

  Future<void> _flag(Map<String, dynamic> m) async {
    final id = m['id'] as int;
    if (m['flagged'] == true) {
      setState(() => _busyFlags.add(id));
      try {
        await _postJson('/att/guard/marks/$id/unflag', {});
      } catch (e) {
        if (mounted) showMessage(context, e is ApiException ? e.message : e.toString().replaceFirst('Exception: ', ''));
      }
      if (mounted) setState(() => _busyFlags.remove(id));
      _loadFeed();
      return;
    }
    final note = TextEditingController(text: 'Nobody was at the desk');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Flag ${m['name']}?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('This mark stops counting and goes to the attendance office to check.'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in const ['Nobody was at the desk', 'Different person', 'Showed a phone screen'])
              ActionChip(label: Text(t), onPressed: () => note.text = t),
          ]),
          const SizedBox(height: 8),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'What did you see?')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Flag'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyFlags.add(id));
    try {
      await _postJson('/att/guard/marks/$id/flag', {'note': note.text.trim()});
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) showMessage(context, e is ApiException ? e.message : e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _busyFlags.remove(id));
    _loadFeed();
  }

  Widget _feedRow(Map<String, dynamic> m) {
    final id = m['id'] as int;
    final flagged = m['flagged'] == true;
    final photo = _photos[id];
    final t = DateFormat('HH:mm:ss').parse(m['time'].toString());
    final at = DateTime(_now.year, _now.month, _now.day, t.hour, t.minute, t.second);
    final fresh = _now.difference(at).inSeconds.abs() < 12;
    final (badgeText, badgeColor) = switch (m['near_gate']) {
      true => ('Near gate', const Color(0xFF4ADE80)),
      false => ('No Bluetooth', const Color(0xFFFCD34D)),
      _ => ('Not checked', Colors.white54),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: flagged ? AppColors.danger.withOpacity(0.18) : Colors.white.withOpacity(fresh ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: fresh && !flagged ? Colors.white54 : Colors.transparent, width: 1.2),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 56,
            height: 56,
            color: Colors.white12,
            child: photo != null
                ? Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true)
                : Center(
                    child: Text(initials(m['name'].toString()),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m['name'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text('${m['roll_no']} · ${m['session_label']} · ${DateFormat('h:mm a').format(at)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
            const SizedBox(height: 6),
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: flagged ? const Color(0xFFFCA5A5) : badgeColor, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(flagged ? 'Flagged' : badgeText,
                  style: TextStyle(
                      color: flagged ? const Color(0xFFFCA5A5) : Colors.white.withOpacity(0.85),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        _busyFlags.contains(id)
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: flagged ? Colors.white : const Color(0xFFFCA5A5),
                  side: BorderSide(color: flagged ? Colors.white38 : const Color(0xFFFCA5A5)),
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _flag(m),
                child: Text(flagged ? 'Undo' : 'Flag'),
              ),
      ]),
    );
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

                  // Bluetooth beacon status
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      Icon(
                        _beaconState == BeaconState.on ? Icons.bluetooth_connected_rounded : Icons.bluetooth_disabled_rounded,
                        color: _beaconState == BeaconState.on ? const Color(0xFF4ADE80) : const Color(0xFFFCD34D),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _beaconState == BeaconState.on
                              ? 'Bluetooth signal on. Phones near this desk can mark.'
                              : beaconStateText(_beaconState),
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  // Live list: who just marked
                  Row(children: [
                    const Text('Just marked',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('${_feed.length} today', style: onGradientBody.copyWith(fontSize: 13)),
                  ]),
                  const SizedBox(height: 4),
                  Text('Flag anyone whose name appears when nobody is at the desk.',
                      style: onGradientBody.copyWith(fontSize: 12.5)),
                  const SizedBox(height: 12),
                  if (_feed.isEmpty)
                    GlassTile(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        for (final (i, (icon, label)) in const [
                          (Icons.bluetooth_searching_rounded, 'Phone near desk'),
                          (Icons.qr_code_scanner_rounded, 'Scans QR'),
                          (Icons.face_retouching_natural_rounded, 'Selfie'),
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
                    )
                  else
                    for (final m in _feed.take(15)) _feedRow(m),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}
