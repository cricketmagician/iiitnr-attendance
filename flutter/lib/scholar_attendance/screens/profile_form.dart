import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ui_common.dart';

/// Scholar details: academic first, then contact. Used by the scholar at registration
/// and by the attendance office to correct details. PhD scholars choose a supervisor;
/// MTech scholars have none.
class ProfileForm extends StatefulWidget {
  final Map<String, dynamic> options; // from GET /registration/options
  final Map<String, dynamic> initial; // a profile (may be mostly empty)
  final String submitLabel;
  final Future<void> Function(Map<String, dynamic> body) onSubmit;
  const ProfileForm({
    super.key,
    required this.options,
    required this.initial,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: _s('name'));
  late final _roll = TextEditingController(text: _s('roll_no'));
  late final _phone = TextEditingController(text: _s('phone'));
  late final _personal = TextEditingController(text: _s('personal_email'));
  late final _address = TextEditingController(text: _s('address'));
  late String? _programme = _opt('programme');
  late String? _department = _opt('department');
  late String? _supervisor = _opt('supervisor_email');
  late String _funding = _opt('funding') ?? 'institute';
  late DateTime? _joining =
      widget.initial['joining_date'] == null ? null : DateTime.tryParse(widget.initial['joining_date'].toString());
  bool _busy = false;
  bool _tried = false;

  String _s(String k) => (widget.initial[k] ?? '').toString();
  String? _opt(String k) => _s(k).isEmpty ? null : _s(k);

  List<String> get _departments => (widget.options['departments'] as List).cast<String>();
  List<Map<String, dynamic>> get _supervisors =>
      (widget.options['supervisors'] as List).cast<Map<String, dynamic>>();
  bool get _needsSupervisor => _programme == 'PhD';

  /// Faculty in the chosen department first; everyone else after, so a cross-department
  /// supervisor can still be picked.
  List<Map<String, dynamic>> get _sortedSupervisors {
    final all = [..._supervisors];
    all.sort((a, b) {
      final ad = a['department'] == _department ? 0 : 1;
      final bd = b['department'] == _department ? 0 : 1;
      return ad != bd ? ad - bd : a['name'].toString().compareTo(b['name'].toString());
    });
    return all;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _joining ?? now,
      firstDate: DateTime(now.year - 8),
      lastDate: now,
      helpText: 'Date you joined the programme',
    );
    if (d != null) setState(() => _joining = d);
  }

  Future<void> _submit() async {
    setState(() => _tried = true);
    final ok = _form.currentState!.validate();
    if (!ok || _programme == null || _joining == null || (_needsSupervisor && _supervisor == null)) {
      showMessage(context, 'Fill in the highlighted fields.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit({
        'name': _name.text.trim(),
        'roll_no': _roll.text.trim(),
        'programme': _programme,
        'department': _department,
        'supervisor_email': _needsSupervisor ? _supervisor : '',
        'joining_date': DateFormat('yyyy-MM-dd').format(_joining!),
        'funding': _funding,
        'phone': _phone.text.trim(),
        'personal_email': _personal.text.trim(),
        'address': _address.text.trim(),
      });
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _label(String text, {String? hint}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(children: [
          Text(text, style: Theme.of(context).textTheme.titleSmall),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ],
        ]),
      );

  Widget _section(int n, String title, String sub) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 28, 0, 2),
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(sub, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      );

  Widget _choice(List<(String, String)> items, String? value, ValueChanged<String> onPick, {bool error = false}) {
    return Row(children: [
      for (final (i, (v, label)) in items.indexed) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => onPick(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value == v ? AppColors.ink : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: value == v ? AppColors.ink : (error ? AppColors.danger : AppColors.line), width: 1.2),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: value == v ? Colors.white : AppColors.ink, fontSize: 15)),
            ),
          ),
        ),
      ],
    ]);
  }

  String? _required(String? v, String what) => (v == null || v.trim().isEmpty) ? 'Enter your $what' : null;

  @override
  Widget build(BuildContext context) {
    final sups = _sortedSupervisors;
    return Form(
      key: _form,
      autovalidateMode: _tried ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _section(1, 'Academic details', 'As on your admission letter'),
        _label('Full name'),
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Name as in institute records'),
          validator: (v) => _required(v, 'name'),
        ),
        _label('Roll number'),
        TextFormField(
          controller: _roll,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. PHD2024001'),
          validator: (v) => _required(v, 'roll number'),
        ),
        _label('Programme'),
        _choice(const [('PhD', 'PhD'), ('MTech', 'MTech')], _programme, (v) => setState(() => _programme = v),
            error: _tried && _programme == null),
        _label('Department'),
        DropdownButtonFormField<String>(
          value: _departments.contains(_department) ? _department : null,
          isExpanded: true,
          decoration: const InputDecoration(hintText: 'Choose department'),
          items: [for (final d in _departments) DropdownMenuItem(value: d, child: Text(d))],
          onChanged: (v) => setState(() => _department = v),
          validator: (v) => v == null ? 'Choose your department' : null,
        ),
        if (_needsSupervisor) ...[
          _label('Supervisor', hint: 'PhD only'),
          DropdownButtonFormField<String>(
            value: sups.any((s) => s['email'] == _supervisor) ? _supervisor : null,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: sups.isEmpty ? 'No faculty listed yet' : 'Choose your supervisor',
            ),
            items: [
              for (final s in sups)
                DropdownMenuItem(
                  value: s['email'] as String,
                  child: Text(
                    '${s['name']}${(s['department'] ?? '').toString().isEmpty ? '' : ' · ${s['department']}'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _supervisor = v),
            validator: (v) => _needsSupervisor && v == null ? 'Choose your supervisor' : null,
          ),
          if (sups.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text('Ask the attendance office to add your supervisor.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger)),
            ),
        ],
        _label('Joining date'),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(16),
          child: InputDecorator(
            decoration: InputDecoration(
              hintText: 'Choose date',
              errorText: _tried && _joining == null ? 'Choose your joining date' : null,
              suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
            ),
            isEmpty: _joining == null,
            child: _joining == null ? null : Text(DateFormat('d MMMM yyyy').format(_joining!)),
          ),
        ),
        _label('Funding'),
        _choice(const [('institute', 'Institute'), ('external', 'External')], _funding,
            (v) => setState(() => _funding = v)),
        _section(2, 'Contact details', 'Seen only by the attendance office'),
        _label('Mobile number'),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: '10-digit mobile', prefixText: '+91  '),
          validator: (v) {
            final d = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
            return RegExp(r'^\+?[0-9]{10,13}$').hasMatch(d) ? null : 'Enter a valid mobile number';
          },
        ),
        _label('Personal email', hint: 'optional'),
        TextFormField(
          controller: _personal,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'name@gmail.com'),
          validator: (v) {
            final t = (v ?? '').trim();
            return t.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Enter a valid email';
          },
        ),
        _label('Current address', hint: 'optional'),
        TextFormField(
          controller: _address,
          maxLines: 2,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Hostel room or local address'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.submitLabel),
          ),
        ),
      ]),
    );
  }
}

/// Read-only list of a profile, for the pending screen and the office's detail page.
class ProfileDetails extends StatelessWidget {
  final Map<String, dynamic> p;
  const ProfileDetails({super.key, required this.p});

  @override
  Widget build(BuildContext context) {
    String v(String k) => (p[k] ?? '').toString();
    final joining = p['joining_date'] == null ? '—' : DateFormat('d MMM yyyy').format(DateTime.parse(p['joining_date']));
    return Column(children: [
      DetailRow(icon: Icons.badge_outlined, label: 'Roll number', value: v('roll_no').isEmpty ? '—' : v('roll_no')),
      DetailRow(icon: Icons.school_outlined, label: 'Programme', value: v('programme').isEmpty ? '—' : v('programme')),
      DetailRow(icon: Icons.apartment_rounded, label: 'Department', value: v('department').isEmpty ? '—' : v('department')),
      if (v('programme') == 'PhD')
        DetailRow(
            icon: Icons.person_outline_rounded,
            label: 'Supervisor',
            value: v('supervisor_name').isNotEmpty ? v('supervisor_name') : (v('supervisor_email').isEmpty ? '—' : v('supervisor_email'))),
      DetailRow(icon: Icons.event_outlined, label: 'Joined', value: joining),
      DetailRow(
          icon: Icons.account_balance_outlined,
          label: 'Funding',
          value: v('funding') == 'external' ? 'External' : 'Institute'),
      DetailRow(icon: Icons.phone_outlined, label: 'Mobile', value: v('phone').isEmpty ? '—' : v('phone')),
      DetailRow(icon: Icons.alternate_email_rounded, label: 'Institute email', value: v('email')),
      if (v('personal_email').isNotEmpty)
        DetailRow(icon: Icons.mail_outline_rounded, label: 'Personal email', value: v('personal_email')),
      if (v('address').isNotEmpty) DetailRow(icon: Icons.home_outlined, label: 'Address', value: v('address')),
    ]);
  }
}
