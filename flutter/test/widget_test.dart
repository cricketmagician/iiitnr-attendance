import 'package:flutter_test/flutter_test.dart';
import 'package:iiitnr_scholar_attendance/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const IIITNRAttendanceApp());
    expect(find.byType(IIITNRAttendanceApp), findsOneWidget);
  });
}
