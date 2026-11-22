import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'scholar_attendance/guard_kiosk_screen.dart';
import 'scholar_attendance/scholar_attendance.dart';
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
    const primaryNavy = Color(0xFF0B2545);
    const secondaryBlue = Color(0xFF134074);
    const accentTeal = Color(0xFF00A896);

    return MaterialApp(
      title: 'IIITNR Scholar Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryNavy,
          primary: primaryNavy,
          secondary: secondaryBlue,
          tertiary: accentTeal,
          surface: const Color(0xFFF8F9FA),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardTheme(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primaryNavy,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
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
  String _serverUrl = 'https://iiitnr-attendance.onrender.com';
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
    if (savedUrl != null && savedUrl.isNotEmpty && !savedUrl.contains('127.0.0.1') && !savedUrl.contains('localhost')) {
      _serverUrl = savedUrl;
    } else {
      _serverUrl = 'https://iiitnr-attendance.onrender.com';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('IIITNR Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: ScholarAttendanceEntry(config: config),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: Text('Log out of account $_email?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout')),
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

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController(text: 'scholar1@iiitnr.edu.in');
  late final _serverCtrl = TextEditingController(text: widget.defaultServerUrl);
  bool _busy = false;
  String? _error;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '734399685844-rocm7a76g418k6scthl5s7lvhajt4km4.apps.googleusercontent.com',
    scopes: ['email', 'profile', 'openid'],
    hostedDomain: 'iiitnr.edu.in',
  );

  final List<Map<String, String>> _sampleAccounts = [
    {'label': 'PhD Scholar 1', 'email': 'scholar1@iiitnr.edu.in'},
    {'label': 'MTech Scholar 1', 'email': 'mtech1@iiitnr.edu.in'},
    {'label': 'Research Guide', 'email': 'guide1@iiitnr.edu.in'},
    {'label': 'Head of Dept (HoD)', 'email': 'hod.sm@iiitnr.edu.in'},
    {'label': 'Dean (R&I)', 'email': 'dean.ri@iiitnr.edu.in'},
    {'label': 'Attendance Office', 'email': 'attendance.office@iiitnr.edu.in'},
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
          setState(() => _error = 'Google login failed (${res.statusCode}): ${res.body}');
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
      setState(() => _error = 'Please enter an authorized @iiitnr.edu.in email');
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
        setState(() => _error = 'Sign in failed (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      setState(() => _error = 'Server connection error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Institute Logo / Header Icon
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B2545).withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.school, size: 44, color: Color(0xFF0B2545)),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'IIIT Naya Raipur',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0B2545)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Scholar Attendance & Leave Portal',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.black54),
                  ),
                  const SizedBox(height: 32),

                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                    ),

                  // Official Google Workspace Sign-In Button
                  Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDADCE0), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _busy ? null : _signInWithGoogle,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.verified_user_outlined, size: 22, color: Color(0xFF4285F4)),
                              const SizedBox(width: 12),
                              Text(
                                _busy ? 'Verifying with Google...' : 'Sign In with Google (@iiitnr.edu.in)',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F1F1F),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR LOCAL / DEMO LOGIN',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Email input
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Institute Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      hintText: 'scholar@iiitnr.edu.in',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Server URL input
                  TextField(
                    controller: _serverCtrl,
                    decoration: InputDecoration(
                      labelText: 'Attendance Server URL',
                      prefixIcon: const Icon(Icons.dns_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      helperText: 'Select connection mode below or type custom URL',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.cloud_done, size: 16, color: Colors.teal),
                        label: const Text('Render Cloud', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => setState(() => _serverCtrl.text = 'https://iiitnr-attendance.onrender.com'),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.usb, size: 16),
                        label: const Text('USB (127.0.0.1)', style: TextStyle(fontSize: 12)),
                        onPressed: () => setState(() => _serverCtrl.text = 'http://127.0.0.1:8040'),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.wifi, size: 16),
                        label: const Text('Wi-Fi (192.168.2.6)', style: TextStyle(fontSize: 12)),
                        onPressed: () => setState(() => _serverCtrl.text = 'http://192.168.2.6:8040'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Sign In button
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _signIn,
                      icon: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.login),
                      label: Text(_busy ? 'Authenticating...' : 'Sign In to Portal'),
                    ),
                  ),

                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text(
                    'Quick Switch Demo Account:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),

                  // Quick test selector chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _sampleAccounts.map((a) {
                      final isSelected = _emailCtrl.text == a['email'];
                      return ActionChip(
                        avatar: Icon(
                          isSelected ? Icons.check_circle : Icons.person_outline,
                          size: 16,
                          color: isSelected ? Colors.white : const Color(0xFF0B2545),
                        ),
                        label: Text(a['label']!, style: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF0B2545),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        )),
                        backgroundColor: isSelected ? const Color(0xFF0B2545) : Colors.grey.shade100,
                        onPressed: () {
                          setState(() {
                            _emailCtrl.text = a['email']!;
                            _error = null;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () {
                      final baseUrl = _serverCtrl.text.trim().isNotEmpty
                          ? _serverCtrl.text.trim()
                          : 'https://iiitnr-attendance.onrender.com';
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GuardKioskScreen(baseUrl: baseUrl),
                        ),
                      );
                    },
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text('Open Guard Desk Kiosk (3s QR)'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
