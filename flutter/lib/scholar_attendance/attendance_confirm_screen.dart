import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Step 3: Attendance Confirmation Screen.
/// Shows the captured selfie preview, scholar details, session info,
/// and dynamic Guard QR verification confirmation before the scholar submits.
class AttendanceConfirmScreen extends StatelessWidget {
  final String base64FaceImage;
  final String qrToken;
  final String sessionLabel;
  final Map<String, dynamic>? scholarInfo;

  const AttendanceConfirmScreen({
    super.key,
    required this.base64FaceImage,
    required this.qrToken,
    required this.sessionLabel,
    this.scholarInfo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Uint8List? imageBytes;
    try {
      imageBytes = base64Decode(base64FaceImage);
    } catch (_) {}

    final scholarName = scholarInfo?['name'] as String? ?? 'Scholar';
    final scholarEmail = scholarInfo?['email'] as String? ?? '';
    final scholarRoll = scholarInfo?['roll_no'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Attendance'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Step Progress Tracker
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Step 3 of 3: Final Identity Confirmation',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Face Preview Avatar
              Center(
                child: Container(
                  width: 170,
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.blueAccent, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.15),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: imageBytes != null
                      ? Image.memory(imageBytes, fit: BoxFit.cover)
                      : const Icon(Icons.person, size: 80, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 20),

              // Scholar Details Card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: cs.primary.withOpacity(0.1),
                          child: Icon(Icons.school, color: cs.primary),
                        ),
                        title: Text(scholarName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text(scholarRoll.isNotEmpty ? '$scholarRoll • $scholarEmail' : scholarEmail),
                      ),
                      const Divider(),
                      const SizedBox(height: 6),
                      _detailRow(Icons.access_time, 'Attendance Session', sessionLabel),
                      const SizedBox(height: 10),
                      _detailRow(Icons.qr_code_2, 'Guard QR Token', 'Scanned & Attached ✅'),
                      const SizedBox(height: 10),
                      _detailRow(Icons.face, 'Live Face Selfie', 'Captured & Ready ✅'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Confirm Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.verified, size: 22),
                  label: const Text('Confirm & Mark Present', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),

              // Retake Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retake Selfie'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blueGrey),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
