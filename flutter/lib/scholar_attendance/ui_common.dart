import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'api.dart';

// =============================================================== design system
//
// Bold, modern look (patterns from Rocket Money, Copilot and monday.com on Mobbin):
//   * full-bleed indigo -> violet -> magenta gradient headers with white type
//   * soft lavender canvas, white cards with a coloured soft shadow (no borders)
//   * tinted, colour-coded tiles for status; floating dark bottom bar
//   * Plus Jakarta Sans throughout

class AppColors {
  static const brand = Color(0xFF4F46E5); // used sparingly: links, selection
  static const brandSoft = Color(0xFFEEF0FF);
  static const ink = Color(0xFF18181B);
  static const inkSoft = Color(0xFF52525B);
  static const muted = Color(0xFF8E8E96);
  static const canvas = Color(0xFFF6F6F4);
  static const card = Colors.white;
  static const line = Color(0xFFEAEAE7);

  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFE8F5EC);
  static const warning = Color(0xFFB7791F);
  static const warningSoft = Color(0xFFFBF3E4);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFCEBEB);
  static const leave = Color(0xFF2563EB);
  static const leaveSoft = Color(0xFFEAF1FD);
  static const neutralSoft = Color(0xFFF0F0EE);

  /// The one dark surface per screen (hero card, login, bottom bar).
  static const gradient = LinearGradient(
    colors: [Color(0xFF2A2A30), Color(0xFF18181B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppRadius {
  static const card = 24.0;
  static const control = 16.0;
}

final List<BoxShadow> softShadow = [
  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4)),
];

/// The dark hero card at the top of a screen (sits below the status bar, inset from the edges).
/// Put white content inside.
class GradientHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const GradientHeader({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 22)});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          decoration: const BoxDecoration(gradient: AppColors.gradient),
          child: Stack(children: [
            Positioned(right: -70, top: -70, child: _blob(200, 0.05)),
            Padding(padding: padding, child: child),
          ]),
        ),
      ),
    );
  }

  static Widget _blob(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(opacity)),
      );
}

/// Translucent white tile for use on top of the gradient.
class GlassTile extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const GlassTile({super.key, required this.child, this.padding = const EdgeInsets.all(14)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: child,
      );
}

/// Big white button that sits on the gradient.
class OnGradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  const OnGradientButton({super.key, required this.label, required this.icon, this.onPressed, this.busy = false});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 58,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.ink,
            disabledBackgroundColor: Colors.white.withOpacity(0.10),
            disabledForegroundColor: Colors.white.withOpacity(0.85),
            elevation: 0,
            textStyle: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: busy ? null : onPressed,
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(icon, size: 22),
          label: Text(label),
        ),
      );
}

const onGradientTitle = TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.15);
final onGradientBody = TextStyle(color: Colors.white.withOpacity(0.66), fontSize: 14.5, height: 1.4);
final onGradientCaption =
    TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1.0);

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      primary: AppColors.brand,
      surface: AppColors.card,
    ),
    scaffoldBackgroundColor: AppColors.canvas,
  );
  final t = GoogleFonts.plusJakartaSansTextTheme(base.textTheme);
  return base.copyWith(
    textTheme: t.copyWith(
      headlineMedium: t.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: -0.8, height: 1.15),
      headlineSmall: t.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: -0.5),
      titleLarge: t.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: -0.3),
      titleMedium: t.titleMedium?.copyWith(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 16, color: AppColors.ink),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, color: AppColors.inkSoft, height: 1.4),
      bodySmall: t.bodySmall?.copyWith(fontSize: 12.5, color: AppColors.muted, height: 1.35),
      labelLarge: t.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: AppColors.card,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 15.5, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(64, 52),
        side: const BorderSide(color: AppColors.line),
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.brandSoft,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? AppColors.brand : AppColors.muted,
          )),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}

// =============================================================== messages and dates

void showMessage(BuildContext context, Object e, {bool ok = false}) {
  final text = e is ApiException ? e.message : e.toString();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          color: ok ? const Color(0xFF6EE7A0) : const Color(0xFFFFA59E), size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(text)),
    ]),
  ));
}

String niceDate(String iso) => DateFormat('EEE d MMM yyyy').format(DateTime.parse(iso));
String shortDate(String iso) => DateFormat('d MMM').format(DateTime.parse(iso));

String dateRange(String fromIso, String toIso) {
  final a = DateTime.parse(fromIso), b = DateTime.parse(toIso);
  if (a == b) return DateFormat('EEE, d MMM').format(a);
  if (a.year == b.year && a.month == b.month) return '${a.day} – ${DateFormat('d MMM').format(b)}';
  return '${DateFormat('d MMM').format(a)} – ${DateFormat('d MMM').format(b)}';
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty && !p.endsWith('.')).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

// =============================================================== register codes

/// Register codes: P, P*, L, A, R (awaiting admin), H, W, - (today, in progress)
Color codeColor(String code, [ColorScheme? cs]) {
  switch (code) {
    case 'P':
      return AppColors.success;
    case 'P*':
      return const Color(0xFF0E9384);
    case 'L':
      return AppColors.leave;
    case 'A':
      return AppColors.danger;
    case 'R':
      return AppColors.warning;
    case 'H':
    case 'W':
      return AppColors.line;
    default:
      return AppColors.neutralSoft;
  }
}

Color codeSoftColor(String code) {
  switch (code) {
    case 'P':
    case 'P*':
      return AppColors.successSoft;
    case 'L':
      return AppColors.leaveSoft;
    case 'A':
      return AppColors.dangerSoft;
    case 'R':
      return AppColors.warningSoft;
    default:
      return Colors.transparent;
  }
}

const codeMeaning = {
  'P': 'Present (2 or more sessions)',
  'P*': 'Present, approved by the office',
  'L': 'On leave',
  'A': 'Absent',
  'R': 'Waiting for office review',
  'H': 'Holiday',
  'W': 'Weekend',
  '-': 'Today, in progress',
};

// =============================================================== building blocks

/// White card with a hairline border.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap, this.color});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.card), boxShadow: softShadow),
        child: Material(
          color: color ?? AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

/// Section title above a group of cards ("Today's sessions", "Applications").
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  const SectionHeader(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 28, 4, 12),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          if (trailing != null) Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

enum PillTone { success, warning, danger, leave, brand, neutral }

/// Small rounded status label.
class StatusPill extends StatelessWidget {
  final String text;
  final PillTone tone;
  final IconData? icon;
  const StatusPill(this.text, {super.key, this.tone = PillTone.neutral, this.icon});

  (Color, Color) get _colors => switch (tone) {
        PillTone.success => (AppColors.successSoft, AppColors.success),
        PillTone.warning => (AppColors.warningSoft, AppColors.warning),
        PillTone.danger => (AppColors.dangerSoft, AppColors.danger),
        PillTone.leave => (AppColors.leaveSoft, AppColors.leave),
        PillTone.brand => (AppColors.ink, Colors.white),
        PillTone.neutral => (AppColors.neutralSoft, AppColors.inkSoft),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ),
      ]),
    );
  }
}

/// Circular avatar with initials.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  const InitialsAvatar(this.name, {super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.neutralSoft, shape: BoxShape.circle),
        child: Text(initials(name),
            style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: AppColors.ink)),
      );
}

/// Friendly empty state.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  const EmptyState({super.key, required this.icon, required this.title, this.message});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: AppColors.neutralSoft, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.muted, size: 26),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ]),
      );
}

/// A label / value row used in detail sheets.
class DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const DetailRow({super.key, required this.icon, required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, size: 20, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.ink)),
          ),
        ]),
      );
}

// =============================================================== loading and errors

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.brand));
}

class ErrorRetry extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorRetry({super.key, required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.muted),
            const SizedBox(height: 14),
            Text("Couldn't load this", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(error is ApiException ? (error as ApiException).message : '$error',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
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
            color: AppColors.brand,
            onRefresh: () async => _reload(),
            child: widget.builder(context, snap.data as T, _reload),
          );
        },
      );
}
