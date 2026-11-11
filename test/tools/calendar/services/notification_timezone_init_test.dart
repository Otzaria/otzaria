import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repeated notification initialization keeps existing timezone objects', () {
    NotificationService.initializeTimeZones();
    final first = tz.getLocation('Asia/Jerusalem');
    final remote = tz.getLocation('America/Detroit');

    // Repeated calls still restore the configured local zone without
    // re-decoding the entire embedded database.
    tz.setLocalLocation(tz.UTC);
    NotificationService.initializeTimeZones();
    expect(identical(tz.getLocation('Asia/Jerusalem'), first), isTrue);
    expect(identical(tz.getLocation('America/Detroit'), remote), isTrue);
    expect(identical(tz.local, first), isTrue);
  });
}
