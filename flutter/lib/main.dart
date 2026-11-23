import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'scholar_attendance/guard_kiosk_screen.dart';
import 'scholar_attendance/scholar_attendance.dart';
import 'scholar_attendance/ui_common.dart'
    show AppColors, buildAppTheme;
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize reminder notifications
  try {
    await AttendanceReminders.init(onTap: () {
      // Tap handler for notifications
    });
  } catch (e) {
    debugPrint('Notifications init error: $e');
  }

  runApp(const IIITNRAttendanceApp());
}

class IIITNRAttendanceApp extends StatelessWidget {
  const IIITNRAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IIITNR Attendance',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AuthGate(),
    );
  }
}

/// Checks if token exists; routes to Login or ScholarAttendanceEntry
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _storage = FlutterSecureStorage();
  static const _kToken = 'iiitnr_auth_token';
  static const _kEmail = 'iiitnr_auth_email';
  static const _kServerUrl = 'iiitnr_server_url';

  String? _token;
  String? _email;
  String _serverUrl = _defaultServer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = await _storage.read(key: _kToken);
    final email = await _storage.read(key: _kEmail);
    final savedUrl = await _storage.read(key: _kServerUrl);
    if (savedUrl != null &&
        savedUrl.isNotEmpty &&
        !savedUrl.contains('127.0.0.1') &&
        !savedUrl.contains('localhost')) {
      _serverUrl = savedUrl;
    } else {
      _serverUrl = _defaultServer;
    }
    setState(() {
      _token = token;
      _email = email;
      _loading = false;
    });
  }

  Future<void> _login(String email, String token, String serverUrl) async {
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kServerUrl, value: serverUrl);
    setState(() {
      _email = email;
      _token = token;
      _serverUrl = serverUrl;
    });
  }

  Future<void> _logout() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kEmail);
    setState(() {
      _token = null;
      _email = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_token == null) {
      return LoginScreen(onLoginSuccess: _login, defaultServerUrl: _serverUrl);
    }

    final config = AttendanceConfig(
      baseUrl: _serverUrl,
      getToken: () async => _token!,
    );

    return ScholarAttendanceEntry(
        config: config, onLogout: () => _confirmLogout(context));
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text('You will need to sign in again as $_email.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) _logout();
  }
}

/// Sign in screen with Institute Domain & Quick Dev Selector
class LoginScreen extends StatefulWidget {
  final Function(String email, String token, String serverUrl) onLoginSuccess;
  final String defaultServerUrl;

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
    required this.defaultServerUrl,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Developer sign-in shows in debug builds, or in a test release built with
/// `flutter build apk --release --dart-define=DEV_LOGIN=true`. Never in a production release.
const _showDevLogin = !kReleaseMode || bool.fromEnvironment('DEV_LOGIN');

/// Server the app talks to. Override with --dart-define=SERVER_URL=... for a local test build.
const _defaultServer = String.fromEnvironment('SERVER_URL', defaultValue: 'https://iiitnr-attendance.onrender.com');

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController(text: 'scholar1@iiitnr.edu.in');
  late final _serverCtrl = TextEditingController(text: widget.defaultServerUrl);
  bool _busy = false;
  String? _error;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '734399685844-rocm7a76g418k6scthl5s7lvhajt4km4.apps.googleusercontent.com',
    scopes: ['email', 'profile', 'openid'],
    hostedDomain: 'iiitnr.edu.in',
  );

  final List<Map<String, String>> _sampleAccounts = [
    {'label': 'New scholar (registers)', 'email': 'new.scholar@iiitnr.edu.in'},
    {'label': 'PhD Scholar 1', 'email': 'scholar1@iiitnr.edu.in'},
    {'label': 'MTech Scholar 1', 'email': 'mtech1@iiitnr.edu.in'},
    {'label': 'Research Guide', 'email': 'guide1@iiitnr.edu.in'},
    {'label': 'Head of Dept (HoD)', 'email': 'hod.sm@iiitnr.edu.in'},
    {'label': 'Dean (R&I)', 'email': 'dean.ri@iiitnr.edu.in'},
    {'label': 'Attendance Office', 'email': 'attendance.office@iiitnr.edu.in'},
    {'label': 'Guard (gate QR)', 'email': 'guard.main@iiitnr.edu.in'},
  ];

  Future<void> _signInWithGoogle() async {
    final serverUrl = _serverCtrl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Unable to obtain Google ID Token.');
      }

      final res = await http.post(
        Uri.parse('$serverUrl/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final token = data['token'] as String;
        final personEmail = data['person']['email'] as String;
        widget.onLoginSuccess(personEmail, token, serverUrl);
      } else {
        try {
          final data = jsonDecode(res.body);
          final msg = data['detail']?['message'] ?? res.body;
          setState(() => _error = 'Google login rejected: $msg');
        } catch (_) {
          setState(() =>
              _error = 'Google login failed (${res.statusCode}): ${res.body}');
        }
      }
    } catch (e) {
      setState(() => _error = 'Google Sign-in error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final serverUrl = _serverCtrl.text.trim();

    if (!email.endsWith('@iiitnr.edu.in')) {
      setState(
          () => _error = 'Please enter an authorized @iiitnr.edu.in email');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await http.post(
        Uri.parse('$serverUrl/auth/dev-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final token = data['token'] as String;
        widget.onLoginSuccess(email, token, serverUrl);
      } else {
        setState(
            () => _error = 'Sign in failed (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      setState(() => _error = 'Server connection error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openKiosk() async {
    final baseUrl = _serverCtrl.text.trim().isNotEmpty
        ? _serverCtrl.text.trim()
        : 'https://iiitnr-attendance.onrender.com';
    final keyCtrl = TextEditingController();
    final kioskKey = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guard kiosk key'),
        content: TextField(
          controller: keyCtrl,
          obscureText: true,
          decoration:
              const InputDecoration(labelText: 'Kiosk key (from the admin)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, keyCtrl.text.trim()),
              child: const Text('Open')),
        ],
      ),
    );
    if (kioskKey == null || kioskKey.isEmpty || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              GuardKioskScreen(baseUrl: baseUrl, kioskKey: kioskKey)),
    );
  }

  // Developer sign-in lives in a sheet so the main screen stays clean.
  Future<void> _openDevSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final text = Theme.of(ctx).textTheme;
          void pick(VoidCallback f) {
            setSheet(f);
            setState(() {});
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Developer sign-in', style: text.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Test accounts. Not in production builds.', style: text.bodySmall),
                  const SizedBox(height: 20),
                  Text('Account', style: text.titleSmall),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in _sampleAccounts)
                        ChoiceChip(
                          label: Text(a['label']!),
                          selected: _emailCtrl.text == a['email'],
                          onSelected: (_) => pick(() {
                            _emailCtrl.text = a['email']!;
                            _error = null;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Institute email'),
                    onChanged: (_) => pick(() {}),
                  ),
                  const SizedBox(height: 20),
                  Text('Server', style: text.titleSmall),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, children: [
                    for (final e in const {
                      'Render': 'https://iiitnr-attendance.onrender.com',
                      'USB': 'http://127.0.0.1:8040',
                      'Wi-Fi': 'http://192.168.2.6:8040',
                    }.entries)
                      ChoiceChip(
                        label: Text(e.key),
                        selected: _serverCtrl.text == e.value,
                        onSelected: (_) => pick(() => _serverCtrl.text = e.value),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _serverCtrl,
                    decoration: const InputDecoration(labelText: 'Server URL'),
                    onChanged: (_) => pick(() {}),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _signIn();
                      },
                      child: const Text('Sign in as test user'),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          // Brand row
                          Row(children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(11)),
                              child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 10),
                            const Text('IIIT Naya Raipur',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                            const Spacer(),
                            if (_showDevLogin)
                              IconButton(
                                tooltip: 'Developer sign-in',
                                onPressed: _busy ? null : _openDevSheet,
                                icon: const Icon(Icons.code_rounded, color: AppColors.muted, size: 20),
                              ),
                          ]),

                          const Spacer(),
                          const SizedBox(height: 24),
                          const _Rise(delay: 0, child: _AppPreview()),
                          const Spacer(),
                          const SizedBox(height: 24),

                          // Copy
                          const _Rise(
                            delay: 120,
                            child: Text('Your attendance,\none tap away.',
                                style: TextStyle(
                                    fontSize: 34,
                                    height: 1.1,
                                    letterSpacing: -1.2,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ink)),
                          ),
                          const SizedBox(height: 12),
                          const _Rise(
                            delay: 180,
                            child: Text('Stand near the guard, take a selfie, done. Your month and leave live here too.',
                                style: TextStyle(fontSize: 15.5, height: 1.45, color: AppColors.inkSoft)),
                          ),
                          const SizedBox(height: 28),

                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(14)),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(_error!,
                                        style: const TextStyle(color: AppColors.danger, fontSize: 13.5, height: 1.35))),
                              ]),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // Primary action
                          _Rise(
                            delay: 240,
                            child: SizedBox(
                              height: 58,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.ink,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                ),
                                onPressed: _busy ? null : _signInWithGoogle,
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        Container(
                                          width: 26,
                                          height: 26,
                                          alignment: Alignment.center,
                                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                          child: const Text('G',
                                              style: TextStyle(
                                                  fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
                                        ),
                                        const SizedBox(width: 12),
                                        const Text('Continue with Google',
                                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                      ]),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.muted),
                            SizedBox(width: 6),
                            Text('Only @iiitnr.edu.in accounts',
                                style: TextStyle(fontSize: 13, color: AppColors.muted)),
                          ]),
                          const SizedBox(height: 20),
                          const Divider(height: 1),
                          const SizedBox(height: 4),

                          // Guard kiosk: secondary, quiet
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.ink,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _busy ? null : _openKiosk,
                            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.qr_code_2_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('Guard desk? Open the QR kiosk',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts its child in once, on first build.
class _Rise extends StatelessWidget {
  final int delay;
  final Widget child;
  const _Rise({required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 520 + delay),
      curve: Interval(delay / (520 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

/// Hero: a line-art student (Icons8, Notion Line Art) on a soft disc, with a
/// floating chip that hints at what the app does.
class _AppPreview extends StatelessWidget {
  const _AppPreview();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        Container(
          width: 250,
          height: 250,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
        Transform.translate(
          offset: const Offset(14, 0),
          child: Image.asset(
            'assets/illustrations/login_student.png',
            height: 270,
            filterQuality: FilterQuality.high,
          ),
        ),
        const Positioned(
          left: 0,
          top: 6,
          child: _Chip(
            angle: -0.04,
            icon: Icons.check_rounded,
            iconBg: AppColors.successSoft,
            iconFg: AppColors.success,
            title: 'Morning marked',
            subtitle: '09:12 · Main gate',
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final double angle;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String subtitle;
  const _Chip({
    required this.angle,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 14, backgroundColor: iconBg, child: Icon(icon, size: 16, color: iconFg)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
            Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ]),
        ]),
      ),
    );
  }
}
