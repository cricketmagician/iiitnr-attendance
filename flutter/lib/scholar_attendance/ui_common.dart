import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';

void showMessage(BuildContext context, Object e, {bool ok = false}) {
  final text = e is ApiException ? e.message : e.toString();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: ok ? Colors.green.shade700 : null,
  ));
}

String niceDate(String iso) => DateFormat('EEE d MMM yyyy').format(DateTime.parse(iso));
String shortDate(String iso) => DateFormat('d MMM').format(DateTime.parse(iso));

/// Register codes: P, P*, L, A, R (awaiting admin), H, W, - (today, in progress)
Color codeColor(String code, ColorScheme cs) {
  switch (code) {
    case 'P':
      return Colors.green.shade600;
    case 'P*':
      return Colors.teal.shade600;
    case 'L':
      return Colors.blue.shade600;
    case 'A':
      return Colors.red.shade600;
    case 'R':
      return Colors.orange.shade700;
    case 'H':
    case 'W':
      return cs.outlineVariant;
    default:
      return cs.surfaceContainerHighest;
  }
}

const codeMeaning = {
  'P': 'Present (2 or more sessions)',
  'P*': 'Present, marked by admin',
  'L': 'Leave',
  'A': 'Absent',
  'R': 'Awaiting admin review',
  'H': 'Holiday',
  'W': 'Weekend',
  '-': 'Today, in progress',
};

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class ErrorRetry extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorRetry({super.key, required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(error is ApiException ? (error as ApiException).message : '$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      );
}

/// Simple async loader: calls [load], shows a spinner, error with retry, or [builder].
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, VoidCallback reload) builder;
  const Loader({super.key, required this.load, required this.builder});
  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _f;
  @override
  void initState() {
    super.initState();
    _f = widget.load();
  }

  void _reload() => setState(() => _f = widget.load());

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Loading();
          if (snap.hasError) return ErrorRetry(error: snap.error!, onRetry: _reload);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: widget.builder(context, snap.data as T, _reload),
          );
        },
      );
}
