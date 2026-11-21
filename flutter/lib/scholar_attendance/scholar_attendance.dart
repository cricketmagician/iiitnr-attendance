/// Scholar Attendance & Leave module for the IIITNR app.
///
/// Usage in the IIITNR app:
///   Navigator.push(context, MaterialPageRoute(builder: (_) => ScholarAttendanceEntry(
///     config: AttendanceConfig(baseUrl: 'https://app.iiitnr.edu.in/attendance',
///                              getToken: () async => authService.token),
///   )));
library scholar_attendance;

import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'device_identity.dart';
import 'reminders.dart';
import 'screens/phone_setup_page.dart';
import 'screens/scholar_home.dart';
import 'screens/staff_home.dart';
import 'ui_common.dart';

export 'config.dart';
export 'reminders.dart' show AttendanceReminders;

class ScholarAttendanceEntry extends StatefulWidget {
  final AttendanceConfig config;
  const ScholarAttendanceEntry({super.key, required this.config});
  @override
  State<ScholarAttendanceEntry> createState() => _ScholarAttendanceEntryState();
}

class _ScholarAttendanceEntryState extends State<ScholarAttendanceEntry> {
  late final AttendanceApi api = AttendanceApi(widget.config, DeviceIdentity());
  Map<String, dynamic>? me;
  ApiException? deviceProblem;
  Object? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      deviceProblem = null;
    });
    try {
      final m = await api.get('/att/me') as Map<String, dynamic>;
      me = m;
      if (m['is_scholar'] == true) {
        try {
          await AttendanceReminders.sync(api);
        } catch (_) {/* reminders are best effort */}
      }
    } on ApiException catch (e) {
      if (e.code.startsWith('DEVICE_')) {
        deviceProblem = e;
      } else {
        error = e;
      }
    } catch (e) {
      error = e;
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Loading());
    if (deviceProblem != null) {
      return PhoneSetupPage(api: api, problem: deviceProblem!, onDone: _load);
    }
    if (error != null) {
      return Scaffold(appBar: AppBar(title: const Text('Attendance')), body: ErrorRetry(error: error!, onRetry: _load));
    }
    final roles = (me!['roles'] as List).cast<String>();
    if (me!['is_scholar'] == true) return ScholarHome(api: api, me: me!);
    if (roles.any((r) => const ['supervisor', 'hod', 'dean_ri', 'admin'].contains(r))) {
      return StaffHome(api: api, me: me!);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: const Center(child: Text('Attendance is for PhD and MTech scholars.')),
    );
  }
}
