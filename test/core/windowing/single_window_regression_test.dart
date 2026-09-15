import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/models/books.dart';

/// ⚠️ קידומת ייחודית לסוויטה — [ui.IsolateNameServer] גלובלי לתהליך.
const String _namespace = 'otzaria.test.singlewindow';

/// **הבדיקה שמגנה על 99% מהמשתמשים.**
///
/// שכבת מצב המשתמש המשותף נוספה עבור ריבוי חלונות, אבל היא יושבת על מסלול
/// הכתיבה של **כל** משתמש — כולל מי שלעולם לא יפתח חלון שני. שתי דרישות:
///
/// 1. **אפס המתנה.** אין קריאת בקשה-תשובה על האפיק, כלומר אין מסלול שבו
///    שמירת סימנייה ממתינה ל-timeout.
/// 2. **אפס שינוי התנהגות.** הוספה, הסרה ומחיקה עובדות בדיוק כמו קודם,
///    מול מסד אמיתי.
///
/// ⚠️ **המצב המדויק חשוב כאן.** כל עוד משבצת תפוסה, `broadcast` מוצא למי
/// לשלוח. שתי התצורות נבדקות בנפרד: `[יחיד]` בלי משבצות תפוסות, ו-`[עם
/// שכן]` שמאמת שהתעבורה היחידה היא שידור ולא בקשה חוסמת.
void main() {
  Bookmark bookmark(String title, {int index = 0}) => Bookmark(
    ref: title,
    book: TextBook(title: title),
    index: index,
  );

  late Directory tmp;
  late UserStateDatabase database;
  late UserStateListStore store;

  setUp(() async {
    WindowBus.namespace = _namespace;
    WindowRole.isSecondary = false;
    tmp = Directory.systemTemp.createTempSync('otzaria_single_window_');
    database = UserStateDatabase.openAt('${tmp.path}/user_state.db');
    await database.database;
    store = UserStateListStore(database: database);
    WindowBus.instance.register(asOwner: true);
  });

  tearDown(() async {
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    WindowBus.namespace = 'otzaria.window';
    database.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('[יחיד] היסטוריה: הוספה, קריאה והסרה, בלי אף הודעת אפיק', () async {
    final repo = HistoryRepository(store: store);
    final started = DateTime.now();

    await repo.mutateHistory((current) => [bookmark('בראשית'), ...current]);
    await repo.mutateHistory((current) => [bookmark('שמות'), ...current]);

    expect((await repo.loadHistory()).map((b) => b.book.title), [
      'שמות',
      'בראשית',
    ]);

    await repo.mutateHistory(
      (current) => current.where((b) => b.book.title != 'שמות').toList(),
    );
    expect((await repo.loadHistory()).map((b) => b.book.title), ['בראשית']);

    // ⚠️ המספר הוא הראיה שלא הומתן לשום timeout: `peers` ממתין 800ms
    // ובקשת מארח 8 שניות — אף אחד מהם אינו על המסלול הזה.
    final elapsed = DateTime.now().difference(started);
    expect(elapsed.inMilliseconds, lessThan(500));
  });

  test('[יחיד] סימניות: הוספה ומחיקה נשמרות למסד האמיתי', () async {
    final repo = BookmarkRepository(store: store);

    await repo.mutateBookmarks((current) => [...current, bookmark('ויקרא')]);
    await repo.mutateBookmarks(
      (current) => [...current, bookmark('במדבר', index: 4)],
    );

    // נקרא מהמסד עצמו, כלומר מה שבאמת נכתב.
    expect(await store.read('bookmarks', 'key-bookmarks'), hasLength(2));

    await repo.clearBookmarks();
    expect(await repo.loadBookmarks(), isEmpty);
  });

  test('[עם שכן] כתיבה משדרת, ואינה שולחת בקשה חוסמת לאף אחד', () async {
    final listener = _BusEavesdropper()..register();
    addTearDown(listener.dispose);

    await HistoryRepository(
      store: store,
    ).mutateHistory((current) => [bookmark('דברים'), ...current]);
    // השידור הוא fire-and-forget, ולכן נמתין שיגיע — זו כל הנקודה בכך
    // שהוא אינו מעכב את הכתיבה.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(listener.blockingRequests, 0);
    expect(listener.changeNotices, greaterThan(0));
  });

  test('רשומה פגומה מדולגת בתצוגה ואינה נמחקת בכתיבה', () async {
    // ⚠️ מחיקת נתונים בגלל באג פענוח היא בדיוק מה שאסור. הרשומה אינה
    // מוצגת, אבל היא נשארת על הדיסק לניסיון הבא או לתיקון.
    await store.write('history', 'history', [
      {'this': 'is not a bookmark'},
      bookmark('דברים').toJson(),
    ]);
    final repo = HistoryRepository(store: store);

    expect((await repo.loadHistory()).map((b) => b.book.title), ['דברים']);

    await repo.mutateHistory((current) => [bookmark('יהושע'), ...current]);

    final stored = await store.read('history', 'history');
    expect(stored, hasLength(3));
    expect(
      stored.any((e) => e is Map && e['this'] == 'is not a bookmark'),
      isTrue,
    );
  });

  test('כשל כתיבה מתפשט ואינו נבלע', () async {
    // ⚠️ שלוש שכבות תלויות בכשל הזה: ההודעה למשתמש, הניסיון החוזר
    // ב-PreCloseRegistry, ודיווח ל-Sentry.
    database.close();
    final broken = UserStateDatabase.openAt('${tmp.path}/missing/dir/x.db');
    await expectLater(
      UserStateListStore(
        database: broken,
      ).write('history', 'history', const []),
      throwsA(anything),
    );
  });
}

/// חלון שכן מדומה, שמפריד בין בקשה חוסמת לשידור.
///
/// ⚠️ עצם קיומו משנה את מה שנמדד: כל עוד משבצת תפוסה, `broadcast` מוצא
/// למי לשלוח. לכן הוא נרשם רק בבדיקה שבודקת **סוג** תעבורה, ולא באלה
/// שבודקות שאין תעבורה בכלל.
class _BusEavesdropper {
  final List<ReceivePort> _ports = [];

  /// כל הודעה שמצפה לתשובה — מסלול עם timeout, ואסור שיופיע בכתיבה.
  int blockingRequests = 0;

  /// `userStateChanged` — fire-and-forget, אינו מעכב כלום.
  int changeNotices = 0;

  void register() {
    // משבצת 1 שייכת לחלון הנבדק; 2..N נתפסות כאן.
    for (var slot = 2; slot <= WindowBus.slotCount; slot++) {
      final port = ReceivePort();
      ui.IsolateNameServer.registerPortWithName(
        port.sendPort,
        '$_namespace.$slot',
      );
      port.listen((message) {
        if (message is! Map) return;
        final body = message['body'];
        if (body is Map && body['type'] == UserStateListStore.requestChanged) {
          changeNotices++;
        } else if (message['reply'] is SendPort) {
          blockingRequests++;
        }
        if (message['reply'] is SendPort) {
          (message['reply'] as SendPort).send({'ok': true, 'result': null});
        }
      });
      _ports.add(port);
    }
  }

  void dispose() {
    for (final port in _ports) {
      port.close();
    }
    _ports.clear();
  }
}
