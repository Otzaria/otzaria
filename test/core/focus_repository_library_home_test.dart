import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';

class _HomeOwner {
  int calls = 0;

  void onHome() => calls++;
}

/// בקשת "בית הספרייה" (קיצור אופציונלי): מתבצעת מיד כשהספרייה רשומה, וממתינה
/// לרישום שלה כשהספרייה עוד לא נבנתה (היא נבנית רק כשמבקשים אותה).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FocusRepository repo;

  setUp(() {
    repo = FocusRepository.forWindow(
      AppWindowKeys(id: const AppWindowId('library-home-probe')),
    );
  });

  tearDown(() => repo.resetForTesting());

  test('ספרייה רשומה — הבקשה מתבצעת מיד, בכל בקשה', () {
    var calls = 0;
    repo.registerLibraryHomeHandler(() => calls++);

    repo.requestLibraryHome();
    repo.requestLibraryHome();

    expect(calls, 2);
  });

  testWidgets('ספרייה שטרם נבנתה — הבקשה ממתינה ומתבצעת אחרי הרישום', (
    tester,
  ) async {
    var calls = 0;
    repo.requestLibraryHome();
    expect(calls, 0);

    repo.registerLibraryHomeHandler(() => calls++);
    // הביצוע נדחה ל-frame, כשהספרייה כבר בעץ ויכולה לקבל פוקוס.
    expect(calls, 0);
    await tester.pump();
    expect(calls, 1);

    // הבקשה הממתינה נצרכת פעם אחת בלבד.
    repo.registerLibraryHomeHandler(() => calls++);
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('מטפל שבוטל הרישום שלו לפני ה-frame לא מופעל', (tester) async {
    var calls = 0;
    void handler() => calls++;
    repo.requestLibraryHome();
    repo.registerLibraryHomeHandler(handler);
    repo.unregisterLibraryHomeHandler(handler);

    await tester.pump();

    expect(calls, 0);
  });

  test('ביטול רישום של מטפל ישן לא מסיר מטפל חדש יותר', () {
    var oldCalls = 0;
    var newCalls = 0;
    void oldHandler() => oldCalls++;
    repo.registerLibraryHomeHandler(oldHandler);
    repo.registerLibraryHomeHandler(() => newCalls++);

    repo.unregisterLibraryHomeHandler(oldHandler);
    repo.requestLibraryHome();

    expect(oldCalls, 0);
    expect(newCalls, 1);
  });

  testWidgets('אחרי ביטול רישום, בקשה חדשה ממתינה ומתבצעת ברישום הבא', (
    tester,
  ) async {
    var calls = 0;
    void handler() => calls++;
    repo.registerLibraryHomeHandler(handler);
    repo.unregisterLibraryHomeHandler(handler);

    repo.requestLibraryHome();
    expect(calls, 0);

    var nextCalls = 0;
    repo.registerLibraryHomeHandler(() => nextCalls++);
    await tester.pump();

    expect(calls, 0);
    expect(nextCalls, 1);
  });

  test('tear-off של מתודת מופע: ביטול הרישום באמת מסיר את המטפל', () {
    // כמו LibraryBrowser: רישום ב-initState וביטול ב-dispose, בכל פעם עם
    // tear-off חדש של אותה מתודה (אובייקטים שונים, אבל שווים ב-==).
    final owner = _HomeOwner();
    repo.registerLibraryHomeHandler(owner.onHome);
    repo.unregisterLibraryHomeHandler(owner.onHome);

    repo.requestLibraryHome();

    expect(owner.calls, 0);
  });

  test('לכל חלון הספרייה והבקשות שלו', () {
    final other = FocusRepository.forWindow(
      AppWindowKeys(id: const AppWindowId('library-home-probe-2')),
    );
    addTearDown(other.resetForTesting);
    var calls = 0, otherCalls = 0;
    repo.registerLibraryHomeHandler(() => calls++);
    other.registerLibraryHomeHandler(() => otherCalls++);

    repo.requestLibraryHome();

    expect(calls, 1);
    expect(otherCalls, 0);
  });
}
