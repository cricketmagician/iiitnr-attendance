import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../ui_common.dart';
import 'leave_tab.dart' show leaveTypeIcon, leaveTypeShort;

class LeaveApplyPage extends StatefulWidget {
  final AttendanceApi api;
  const LeaveApplyPage({super.key, required this.api});
  @override
  State<LeaveApplyPage> createState() => _LeaveApplyPageState();
}

class _LeaveApplyPageState extends State<LeaveApplyPage> {
  static const hints = {
    'CASUAL': 'Personal work, travel home, rest',
    'MEDICAL': 'Illness. Certificate needed over 2 days',
    'ACADEMIC': 'Conference, field work, course',
    'MATERNITY': 'Up to 180 days, once',
    'PATERNITY': 'Up to 15 days, once',
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
      helpText: 'Leave dates',
    );
    if (r != null) setState(() => range = r);
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], withData: true);
    if (r != null && r.files.isNotEmpty) {
      final f = r.files.first;
      if (f.size > 5 * 1024 * 1024) {
        if (mounted) showMessage(context, 'Attachment must be under 5 MB.');
        return;
      }
      setState(() => file = f);
    }
  }

  Future<void> _submit() async {
    if (range == null) return showMessage(context, 'Choose the dates.');
    if (reason.text.trim().length < 3) return showMessage(context, 'Write a short reason.');
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
      showMessage(context, 'Sent to your supervisor for approval.', ok: true);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    final days = range == null ? 0 : range!.end.difference(range!.start).inDays + 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for leave')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          _label('Type of leave'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final e in leaveTypeShort.entries) ...[
                if (e.key != leaveTypeShort.keys.first) const Divider(indent: 68),
                ListTile(
                  onTap: () => setState(() => type = e.key),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: type == e.key ? AppColors.ink : AppColors.neutralSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(leaveTypeIcon[e.key], size: 21, color: type == e.key ? Colors.white : AppColors.inkSoft),
                  ),
                  title: Text(e.value, style: Theme.of(context).textTheme.titleMedium),
                  subtitle: Text(hints[e.key]!, style: Theme.of(context).textTheme.bodySmall),
                  trailing: Icon(
                    type == e.key ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: type == e.key ? AppColors.ink : AppColors.line,
                  ),
                ),
              ],
            ]),
          ),
          _label('Dates'),
          AppCard(
            onTap: _pickDates,
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.date_range_rounded, color: AppColors.ink),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    range == null
                        ? 'Choose start and end date'
                        : '${DateFormat('EEE, d MMM').format(range!.start)} – ${DateFormat('EEE, d MMM').format(range!.end)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    range == null
                        ? 'Whole days only. Missing one session needs no leave.'
                        : '$days calendar ${days == 1 ? 'day' : 'days'}. Weekends and holidays are not charged.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ]),
          ),
          _label('Details'),
          TextField(
            controller: reason,
            maxLines: 3,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Reason', alignLabelWithHint: true),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: address,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Address during leave (optional)'),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: contact,
            keyboardType: TextInputType.phone,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Phone number (optional)'),
          ),
          _label(type == 'MEDICAL' ? 'Medical certificate' : 'Document (optional)'),
          AppCard(
            onTap: _pickFile,
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(file == null ? Icons.upload_file_rounded : Icons.description_rounded,
                  color: file == null ? AppColors.ink : AppColors.success),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(file?.name ?? 'Attach a file',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    file == null
                        ? (type == 'MEDICAL' ? 'Needed for medical leave over 2 days · PDF, JPG or PNG' : 'PDF, JPG or PNG, up to 5 MB')
                        : 'Tap to replace',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ]),
              ),
              if (file != null)
                IconButton(
                  onPressed: () => setState(() => file = null),
                  icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                  tooltip: 'Remove',
                ),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: busy ? null : _submit,
            child: busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Send for approval'),
          ),
        ),
      ),
    );
  }
}
