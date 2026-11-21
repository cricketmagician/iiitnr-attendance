import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../api.dart';
import '../device_identity.dart';
import '../ui_common.dart';

/// Shown when this phone is not (yet) the scholar's registered phone.
class PhoneSetupPage extends StatefulWidget {
  final AttendanceApi api;
  final ApiException problem;
  final VoidCallback onDone;
  const PhoneSetupPage({super.key, required this.api, required this.problem, required this.onDone});
  @override
  State<PhoneSetupPage> createState() => _PhoneSetupPageState();
}

class _PhoneSetupPageState extends State<PhoneSetupPage> {
  final _reason = TextEditingController();
  bool _busy = false;
  bool? _accountHasPhone;

  @override
  void initState() {
    super.initState();
    if (widget.problem.code == 'DEVICE_NOT_REGISTERED') _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final s = await widget.api.get('/att/device/status');
      setState(() => _accountHasPhone = s['account_has_active_phone'] == true);
    } catch (_) {
      setState(() => _accountHasPhone = false);
    }
  }

  Future<void> _register({bool freshKey = false}) async {
    setState(() => _busy = true);
    try {
      if (freshKey) await widget.api.identity.reset();
      await widget.api.identity.ensure();
      final r = await widget.api.post('/att/device/register', {
        'device_id': widget.api.identity.deviceId,
        'hardware_id': await DeviceIdentity.hardwareId(),
        'public_key': widget.api.identity.publicKeyBase64,
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'model': await DeviceIdentity.model(),
        'reason': _reason.text.trim(),
      });
      if (!mounted) return;
      showMessage(context,
          r['status'] == 'active' ? 'This phone is now registered.' : 'Request sent to the admin office.', ok: true);
      widget.onDone();
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.problem.code;
    final children = <Widget>[];
    if (code == 'DEVICE_NOT_REGISTERED') {
      if (_accountHasPhone == null) return const Scaffold(body: Loading());
      if (_accountHasPhone == false) {
        children.addAll([
          const Text('Register this phone', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Attendance can be marked only from one phone: the one you register now. '
              'Changing phones later needs the admin office\'s approval.'),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : () => _register(), child: const Text('Register this phone')),
        ]);
      } else {
        children.addAll(_changeRequest('Your account is registered to another phone.'));
      }
    } else if (code == 'DEVICE_PENDING') {
      children.addAll([
        const Icon(Icons.hourglass_top, size: 48),
        const SizedBox(height: 12),
        const Text('Waiting for the admin office to approve this phone.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton.tonal(onPressed: widget.onDone, child: const Text('Check again')),
      ]);
    } else {
      // DEVICE_REVOKED / DEVICE_REJECTED
      children.addAll(_changeRequest(widget.problem.message));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: ListView(padding: const EdgeInsets.all(24), children: children),
    );
  }

  List<Widget> _changeRequest(String why) => [
        Text(why, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('To use this phone instead, send a phone-change request. The admin office approves it, '
            'and your old phone stops working for attendance.'),
        const SizedBox(height: 16),
        TextField(
          controller: _reason,
          decoration: const InputDecoration(
              labelText: 'Reason (old phone lost, damaged, replaced…)', border: OutlineInputBorder()),
          maxLength: 300,
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (_reason.text.trim().length < 3) {
                    showMessage(context, 'Give a reason for the change.');
                    return;
                  }
                  _register(freshKey: widget.problem.code != 'DEVICE_NOT_REGISTERED');
                },
          child: const Text('Request phone change'),
        ),
      ];
}
