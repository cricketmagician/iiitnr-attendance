import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../ui_common.dart';
import 'profile_form.dart';

/// What a scholar sees until the attendance office approves them:
/// the form (new or sent back), or a "waiting for approval" screen.
class RegistrationFlow extends StatefulWidget {
  final AttendanceApi api;
  final Map<String, dynamic> me;
  final VoidCallback onRefresh; // reloads /att/me; an approved scholar then moves on
  final VoidCallback? onLogout;
  const RegistrationFlow({super.key, required this.api, required this.me, required this.onRefresh, this.onLogout});

  @override
  State<RegistrationFlow> createState() => _RegistrationFlowState();
}

class _RegistrationFlowState extends State<RegistrationFlow> {
  bool _editing = false;
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Loader<(Map<String, dynamic>, Map<String, dynamic>)>(
        key: ValueKey(_v),
        load: () async {
          final r = await Future.wait([widget.api.get('/registration'), widget.api.get('/registration/options')]);
          return (r[0] as Map<String, dynamic>, r[1] as Map<String, dynamic>);
        },
        builder: (context, data, _) {
          final (profile, options) = data;
          final status = profile['status'] as String;
          if (status == 'pending' && !_editing) {
            return _Pending(
              profile: profile,
              onRefresh: widget.onRefresh,
              onEdit: () => setState(() => _editing = true),
              onLogout: widget.onLogout,
            );
          }
          return _FormScreen(
            profile: profile,
            options: options,
            editingPending: status == 'pending',
            onLogout: widget.onLogout,
            onCancel: _editing ? () => setState(() => _editing = false) : null,
            onSubmit: (body) async {
              await widget.api.post('/registration', body);
              if (!mounted) return;
              setState(() {
                _editing = false;
                _v++;
              });
            },
          );
        },
      ),
    );
  }
}

class _FormScreen extends StatelessWidget {
  final Map<String, dynamic> profile;
  final Map<String, dynamic> options;
  final bool editingPending;
  final VoidCallback? onLogout;
  final VoidCallback? onCancel;
  final Future<void> Function(Map<String, dynamic>) onSubmit;
  const _FormScreen({
    required this.profile,
    required this.options,
    required this.editingPending,
    required this.onSubmit,
    this.onLogout,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final rejected = profile['status'] == 'rejected';
    final note = (profile['note'] ?? '').toString();
    final first = (profile['name'] ?? '').toString().split(' ').first;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          Row(children: [
            if (onCancel != null)
              IconButton(onPressed: onCancel, icon: const Icon(Icons.arrow_back_rounded))
            else
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
              ),
            const Spacer(),
            if (onLogout != null)
              TextButton(
                onPressed: onLogout,
                style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                child: const Text('Sign out'),
              ),
          ]),
          const SizedBox(height: 20),
          Text(editingPending ? 'Edit your details' : (rejected ? 'Fix your details' : 'Welcome, $first'),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.15)),
          const SizedBox(height: 8),
          Text(
            editingPending
                ? 'Your changes go back to the attendance office for approval.'
                : 'Tell us a little about your programme. The attendance office checks it once, then you can mark attendance.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft, height: 1.45),
          ),
          if (rejected && note.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(16)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.danger, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('The office sent this back',
                        style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(note, style: const TextStyle(color: AppColors.danger, height: 1.35)),
                  ]),
                ),
              ]),
            ),
          ],
          ProfileForm(
            options: options,
            initial: profile,
            submitLabel: editingPending || rejected ? 'Send again for approval' : 'Send for approval',
            onSubmit: onSubmit,
          ),
        ]),
      ),
    );
  }
}

class _Pending extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onRefresh;
  final VoidCallback onEdit;
  final VoidCallback? onLogout;
  const _Pending({required this.profile, required this.onRefresh, required this.onEdit, this.onLogout});

  @override
  Widget build(BuildContext context) {
    final sent = profile['registered_at'] == null
        ? ''
        : 'Sent ${DateFormat('d MMM, h:mm a').format(DateTime.parse(profile['registered_at']))}';
    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.ink,
        onRefresh: () async => onRefresh(),
        child: ListView(padding: EdgeInsets.zero, children: [
          GradientHeader(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('REGISTRATION', style: onGradientCaption),
                const Spacer(),
                if (onLogout != null)
                  GestureDetector(
                    onTap: onLogout,
                    child: Text('Sign out', style: onGradientBody.copyWith(fontSize: 13)),
                  ),
              ]),
              const SizedBox(height: 18),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.hourglass_top_rounded, color: Color(0xFFFCD34D), size: 28),
              ),
              const SizedBox(height: 16),
              const Text('Waiting for the\nattendance office', style: onGradientTitle),
              const SizedBox(height: 8),
              Text(
                'They check your details once. You can mark attendance as soon as they approve.',
                style: onGradientBody,
              ),
              const SizedBox(height: 20),
              Row(children: [
                const _Step(label: 'Details sent', done: true),
                _line(),
                const _Step(label: 'Office checks', done: false, current: true),
                _line(),
                const _Step(label: 'Start marking', done: false),
              ]),
              const SizedBox(height: 22),
              OnGradientButton(label: 'Check status', icon: Icons.refresh_rounded, onPressed: onRefresh),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SectionHeader('What you sent', trailing: sent),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ProfileDetails(p: profile),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit details'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  static Widget _line() => Expanded(
        child: Container(height: 2, margin: const EdgeInsets.only(bottom: 22), color: Colors.white.withOpacity(0.15)),
      );
}

class _Step extends StatelessWidget {
  final String label;
  final bool done;
  final bool current;
  const _Step({required this.label, required this.done, this.current = false});

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? const Color(0xFF4ADE80) : (current ? Colors.white : Colors.white.withOpacity(0.12)),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 15, color: AppColors.ink)
              : (current
                  ? const Padding(
                      padding: EdgeInsets.all(7),
                      child: DecoratedBox(decoration: BoxDecoration(color: AppColors.ink, shape: BoxShape.circle)))
                  : null),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(done || current ? 0.9 : 0.5), fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]);
}
