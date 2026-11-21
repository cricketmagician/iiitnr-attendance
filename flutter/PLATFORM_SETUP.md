# Platform setup for the attendance module

## 1. Copy the code
Copy `lib/scholar_attendance/` into the IIITNR app's `lib/`, and add the packages in
`pubspec_additions.yaml`. Then:

```dart
import 'package:<your_app>/scholar_attendance/scholar_attendance.dart';

// once, at app start (e.g. in main() after WidgetsFlutterBinding.ensureInitialized()):
await AttendanceReminders.init(onTap: () => navigatorKey.currentState?.push(
  MaterialPageRoute(builder: (_) => ScholarAttendanceEntry(config: attendanceConfig))));

// a menu item / tile in the app:
final attendanceConfig = AttendanceConfig(
  baseUrl: 'https://<your-server>/attendance',      // where the backend is reachable
  getToken: () async => authService.currentToken,     // the app's existing institute-email login token
);
Navigator.push(context, MaterialPageRoute(builder: (_) => ScholarAttendanceEntry(config: attendanceConfig)));
```

## 2. Android (`android/app/src/main/AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>

<application ...>
  <!-- flutter_local_notifications: keep reminders after a reboot -->
  <receiver android:exported="false"
      android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
      <action android:name="android.intent.action.BOOT_COMPLETED"/>
      <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
    </intent-filter>
  </receiver>
  <receiver android:exported="false"
      android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
</application>
```

- `MainActivity` must extend `FlutterFragmentActivity` (not `FlutterActivity`) for `local_auth`.
- `minSdkVersion 23` or higher. flutter_secure_storage with encryptedSharedPreferences needs 23+.
- flutter_local_notifications 17 needs core library desugaring enabled in `android/app/build.gradle`
  (`coreLibraryDesugaringEnabled true` + `coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'`).
- Reminders use inexact alarms (no SCHEDULE_EXACT_ALARM permission); Android may deliver them a few
  minutes late. Each window is 30–45 minutes long, so this is fine.

## 3. iOS (`ios/Runner/Info.plist`)

```xml
<key>NSFaceIDUsageDescription</key>
<string>Face ID confirms it is you when you mark attendance.</string>
```

In `AppDelegate.swift`, for notifications tapped while the app is open:
```swift
if #available(iOS 10.0, *) {
  UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
}
```

## 4. Things to check on real phones (pilot)
- Face check on a few Android brands (some only offer fingerprint as "strong" biometric; the
  module accepts fingerprint when face unlock is not available as a strong biometric).
- Reminders arrive Monday to Friday only, and not on holidays or leave days (the server decides).
- Marking works on each campus Wi-Fi network; add any missing ranges under Admin > More > Campus networks.
