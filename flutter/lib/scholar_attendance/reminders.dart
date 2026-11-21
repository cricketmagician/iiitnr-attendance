import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'api.dart';

/// Local reminders at the start of each window, plus one 10 minutes before it
/// closes. The server says which days are working days (5-day week, holidays,
/// leave), so no push server is needed. Call [sync] when the app opens and
/// after each marking; it reschedules the next 14 days.
class AttendanceReminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _base = 7000; // IDs 7000–7999 belong to this module
  static bool _ready = false;
  static const payload = 'scholar_attendance';

  static Future<void> init({void Function()? onTap}) async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload == payload) onTap?.call();
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
    _ready = true;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('scholar_attendance', 'Attendance reminders',
        channelDescription: 'Reminders to mark attendance', importance: Importance.high, priority: Priority.high),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> sync(AttendanceApi api) async {
    if (!_ready) await init();
    final j = await api.get('/att/schedule', query: {'days': '14'});
    for (var i = 0; i < 200; i++) {
      await _plugin.cancel(_base + i); // only this module's IDs
    }
    final now = tz.TZDateTime.now(tz.local);
    final windows = (j['windows'] as List).cast<Map<String, dynamic>>();
    var id = _base;
    for (final day in (j['days'] as List).cast<Map<String, dynamic>>()) {
      final date = DateTime.parse(day['date'] as String);
      final marked = (day['marked'] as List).cast<String>().toSet();
      for (final w in windows) {
        if (marked.contains(w['session'])) continue;
        final start = _at(date, w['start'] as String);
        final close = _at(date, w['end'] as String).subtract(const Duration(minutes: 10));
        if (start.isAfter(now)) {
          await _schedule(id++, start, '${w['label']} attendance is open',
              'Mark attendance by ${_fmt(w['end'] as String)}.');
        }
        if (close.isAfter(now)) {
          await _schedule(id++, close, '${w['label']} attendance closes in 10 minutes',
              'Open the app and tap Mark Present.');
        }
        if (id >= _base + 200) return;
      }
    }
  }

  static tz.TZDateTime _at(DateTime d, String hhmm) {
    final p = hhmm.split(':');
    return tz.TZDateTime(tz.local, d.year, d.month, d.day, int.parse(p[0]), int.parse(p[1]));
  }

  static String _fmt(String hhmm) {
    final p = hhmm.split(':');
    var h = int.parse(p[0]);
    final ampm = h >= 12 ? 'pm' : 'am';
    if (h > 12) h -= 12;
    return '$h:${p[1]} $ampm';
  }

  static Future<void> _schedule(int id, tz.TZDateTime when, String title, String body) {
    return _plugin.zonedSchedule(
      id, title, body, when, _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }
}
