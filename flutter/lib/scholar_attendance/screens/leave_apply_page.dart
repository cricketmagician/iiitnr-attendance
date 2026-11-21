import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../ui_common.dart';

class LeaveApplyPage extends StatefulWidget {
  final AttendanceApi api;
  const LeaveApplyPage({super.key, required this.api});
  @override
  State<LeaveApplyPage> createState() => _LeaveApplyPageState();
}

class _LeaveApplyPageState extends State<LeaveApplyPage> {
  static const types = {
    'CASUAL': 'Casual / ordinary leave',
    'MEDICAL': 'Medical leave',
    'ACADEMIC': 'Academic duty (conference, field work, course)',
    'MATERNITY': 'Maternity leave',
    'PATERNITY': 'Paternity leave',
  };
  String type = 'CASUAL';
  DateTimeRange? range;
  final reason = TextEditingController();
  final address = TextEditingController();
  final contact = TextEditingController();
  PlatformFile? file;
  bool busy = false;

  final _fmt = DateFormat('yyyy-MM-dd');

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: now.add(const Duration(days: 400)),
      initialDateRange: range,
    );
    if (r != null) setState(() => range = r);
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], withData: true);
    if (r != null && r.files.isNotEmpty) {
      final f = r.files.first;
      if ((f.size) > 5 * 1024 * 1024) {
        if (mounted) showMessage(context, 'Attachment must be under 5 MB.');
        return;
      }
      setState(() => file = f);
    }
  }

  Future<void> _submit() async {
    if (range == null) return showMessage(context, 'Choose the dates.');
    if (reason.text.trim().length < 3) return showMessage(context, 'Give a reason.');
    setState(() => busy = true);
    try {
      await widget.api.post('/leave', {
        'leave_type': type,
        'from_date': _fmt.format(range!.start),
        'to_date': _fmt.format(range!.end),
        'reason': reason.text.trim(),
        'address': address.text.trim(),
        'contact': contact.text.trim(),
        if (file?.bytes != null) 'attachment_name': file!.name,
        if (file?.bytes != null) 'attachment_base64': base64Encode(file!.bytes!),
      });
      if (!mounted) return;
      showMessage(context, 'Sent to your supervisor.', ok: true);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for leave')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          value: type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Leave type', border: OutlineInputBorder()),
          items: types.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => setState(() => type = v!),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickDates,
          icon: const Icon(Icons.date_range),
          label: Text(range == null
              ? 'Choose dates'
              : '${DateFormat('d MMM yyyy').format(range!.start)} – ${DateFormat('d MMM yyyy').format(range!.end)}'),
        ),
        const SizedBox(height: 4),
        Text('Whole days only. One skipped session in a day needs no leave.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        TextField(controller: reason, maxLines: 3, maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder())),
        TextField(controller: address, maxLength: 300,
            decoration: const InputDecoration(labelText: 'Address during leave', border: OutlineInputBorder())),
        TextField(controller: contact, keyboardType: TextInputType.phone, maxLength: 40,
            decoration: const InputDecoration(labelText: 'Contact number', border: OutlineInputBorder())),
        OutlinedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.attach_file),
          label: Text(file == null ? 'Attach document (PDF/JPG/PNG)' : file!.name),
        ),
        if (type == 'MEDICAL')
          Text('A medical certificate is needed for medical leave over 2 days.',
              style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 20),
        FilledButton(onPressed: busy ? null : _submit, child: const Text('Submit')),
      ]),
    );
  }
}
