/// How the IIITNR app plugs this module in.
class AttendanceConfig {
  /// Base URL of the attendance service, without a trailing slash,
  /// e.g. https://app.iiitnr.edu.in/attendance
  final String baseUrl;

  /// Returns the login token the IIITNR app already holds for the signed-in
  /// user (institute email login). Called before every request.
  final Future<String> Function() getToken;

  const AttendanceConfig({required this.baseUrl, required this.getToken});
}
