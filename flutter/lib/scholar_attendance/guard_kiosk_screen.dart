import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'api.dart';

/// Guard Desk Kiosk Screen:
/// Displays a dynamic, high-visibility QR code that rotates every 3 seconds.
/// Any phone or tablet positioned at the department gate can run this screen.
class GuardKioskScreen extends StatefulWidget {
  final String? baseUrl;
  final AttendanceApi? api;
  const GuardKioskScreen({super.key, this.baseUrl, this.api});

  @override
  State<GuardKioskScreen> createState() => _GuardKioskScreenState();
}

class _GuardKioskScreenState extends State<GuardKioskScreen> {
  String? _qrString;
  String _sessionLabel = 'Morning';
  int _slot = 0;
  Timer? _fetchTimer;
  Timer? _ticker;
  double _progress = 1.0;
  int _msRemaining = 3000;

  @override
  void initState() {
    super.initState();
    _fetchQR();
    _fetchTimer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchQR());
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final ms = DateTime.now().millisecondsSinceEpoch % 3000;
      if (mounted) {
        setState(() {
          _msRemaining = 3000 - ms;
          _progress = (3000 - ms) / 3000.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _fetchTimer?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _fetchQR() async {
    try {
      Map<String, dynamic>? res;
      if (widget.api != null) {
        res = await widget.api!.get('/att/guard/qr') as Map<String, dynamic>;
      } else {
        final base = widget.baseUrl ?? 'https://iiitnr-attendance.onrender.com';
        final response = await http.get(Uri.parse('$base/att/guard/qr'));
        if (response.statusCode == 200) {
          res = jsonDecode(response.body) as Map<String, dynamic>;
        }
      }
      if (res != null && mounted) {
        if (res['slot'] != _slot || _qrString == null) {
          setState(() {
            _slot = res!['slot'] as int? ?? 0;
            _qrString = res['qr_string'] as String?;
            _sessionLabel = res['session_label'] as String? ?? 'Session';
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Guard Desk Kiosk'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchQR,
            tooltip: 'Force refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.shield, color: Colors.blue, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'IIIT NAYA RAIPUR',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$_sessionLabel Session',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: Colors.green, size: 8),
                          SizedBox(width: 6),
                          Text('LIVE', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // QR Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.12),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    if (_qrString != null)
                      QrImageView(
                        data: _qrString!,
                        version: QrVersions.auto,
                        size: 260.0,
                        gapless: false,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      )
                    else
                      const SizedBox(
                        width: 260,
                        height: 260,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    const SizedBox(height: 16),
                    // Timer & progress
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined, size: 16, color: Colors.blue),
                            const SizedBox(width: 6),
                            Text(
                              'Rotates in ${(_msRemaining / 1000).toStringAsFixed(1)}s',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                            ),
                          ],
                        ),
                        Text(
                          'Slot #${_slot.toString().padLeft(6, '0').substring((_slot.toString().length - 6).clamp(0, 6))}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Info Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Keep this screen visible to scholars at the entrance. Each QR code is cryptographically signed and expires within 3 seconds to prevent proxy marking.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
