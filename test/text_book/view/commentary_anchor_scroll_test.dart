// גלילה לקטע המפרש שעוגן-אות מקשר אליו (לחיצה על (א) בשולחן ערוך וכד').
//
// שני באגים שהבדיקות כאן מקבעות:
//  1. היעד היה שם המפרש בלבד, ולכן כשלמפרש כמה קטעים על אותה שורה הרשימה
//     נעצרה תמיד על הראשון — לא על הקטע שהעוגן הצביע אליו.
//  2. הגלילה בוצעה בניסיון יחיד. גובה קטע מפרש נקבע רק אחרי ש-link.content
//     נפתר, ולכן ככל שיש יותר מפרשים על הקטע כך הגלילה נעצרה מוקדם יותר —
//     "לפני" המפרש המקושר.
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentary_scroll_request.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// די מפרשים כדי שהיעד יהיה מחוץ למסך — זה בדיוק התנאי של הבאג — אך עדיין
/// בתוך ה-cacheExtent של הרשימה. הגבול מכוון: מעבר לו
/// `ScrollablePositionedList` עובר למסלול שתי-הרשימות, שנופל בסביבת בדיקה
/// headless מתוך `getOffsetToReveal`. המסלול שבו הבאג חי הוא ממילא הישיר —
/// `animateTo` לאופסט פיקסלים שחושב מהפריסה שברגע ההתחלה.
const int _commentatorCount = 6;

/// כמה קטעים לכל מפרש על אותה שורת מקור. שניים ומעלה הם התנאי לבאג הראשון.
const int _segmentsPerCommentator = 3;

final List<String> _commentators = [
  for (var i = 0; i < _commentatorCount; i++) 'מפרש $i',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (final title in _commentators)
          BookCompositeKey.create(
            title: title,
            categoryId: 1,
            fileType: 'txt',
          ): _FakeLibraryProvider(),
      },
      providers: [_FakeLibraryProvider()],
    );
  });

  tearDown(() => LibraryProviderManager.instance.resetForTesting());

  group('commentaryLinkKey', () {
    test('index2 מבדיל בין שני קטעים של אותו מפרש על אותה שורה', () {
      expect(
        commentaryLinkKey(_link(title: 'רש"י', segment: 0)),
        isNot(commentaryLinkKey(_link(title: 'רש"י', segment: 1))),
      );
      expect(
        commentaryLinkKey(_link(title: 'רש"י', segment: 0)),
        commentaryLinkKey(_link(title: 'רש"י', segment: 0)),
      );
    });

    test('מפרשים שונים על אותה שורה אינם חולקים מפתח', () {
      expect(
        commentaryLinkKey(_link(title: 'רש"י', segment: 0)),
        isNot(commentaryLinkKey(_link(title: 'תוספות', segment: 0))),
      );
    });
  });

  group('CommentaryScrollRequest', () {
    test('מזהה בקשה שונה = בקשה שונה, גם עם אותו יעד', () {
      const first = CommentaryScrollRequest(
        title: 'רש"י',
        linkKey: 'k',
        requestId: 1,
      );

      expect(
        first,
        isNot(
          const CommentaryScrollRequest(
            title: 'רש"י',
            linkKey: 'k',
            requestId: 2,
          ),
        ),
      );
      expect(
        first,
        const CommentaryScrollRequest(
          title: 'רש"י',
          linkKey: 'k',
          requestId: 1,
        ),
      );
    });
  });

  group('scrollToCommentator — הקטע המדויק', () {
    testWidgets('קטע שני של אותו מפרש מוצג, ולא הראשון', (tester) async {
      final key = await _pump(tester);
      await _settleAnchorScroll(tester);

      const title = 'מפרש 2';
      final target = _link(title: title, segment: 1);
      key.currentState!.scrollToCommentator(
        title,
        linkKey: commentaryLinkKey(target),
      );
      await _settleAnchorScroll(tester);

      expect(
        _isNearTop(tester, ValueKey(commentaryLinkKey(target))),
        isTrue,
        reason: 'הקטע השני של $title אמור להיות בראש הרשימה',
      );
      // הקטע הראשון נשאר מעל אזור הגלילה — לא הוא היעד.
      final firstSegment = _offsetOf(
        tester,
        ValueKey(commentaryLinkKey(_link(title: title, segment: 0))),
      );
      expect(firstSegment, anyOf(isNull, lessThan(0.0)));
    });

    testWidgets('קטע שלישי מוצג — לא רק "אחד אחרי הראשון"', (tester) async {
      final key = await _pump(tester);
      await _settleAnchorScroll(tester);

      const title = 'מפרש 1';
      final target = _link(title: title, segment: 2);
      key.currentState!.scrollToCommentator(
        title,
        linkKey: commentaryLinkKey(target),
      );
      await _settleAnchorScroll(tester);

      expect(_isNearTop(tester, ValueKey(commentaryLinkKey(target))), isTrue);
    });

    testWidgets('הקטע הראשון גולל לכותרת, כדי ששם המפרש יישאר גלוי', (
      tester,
    ) async {
      final key = await _pump(tester);
      await _settleAnchorScroll(tester);

      const title = 'מפרש 3';
      key.currentState!.scrollToCommentator(
        title,
        linkKey: commentaryLinkKey(_link(title: title, segment: 0)),
      );
      await _settleAnchorScroll(tester);

      expect(
        _isNearTop(tester, find.text(title)),
        isTrue,
        reason: 'כותרת הקבוצה אמורה להיות בראש, לא הקטע שמתחתיה',
      );
    });

    testWidgets('בלי linkKey — התנהגות הכותרת נשמרת', (tester) async {
      final key = await _pump(tester);
      await _settleAnchorScroll(tester);

      const title = 'מפרש 3';
      key.currentState!.scrollToCommentator(title);
      await _settleAnchorScroll(tester);

      expect(_isNearTop(tester, find.text(title)), isTrue);
    });

    testWidgets('linkKey שאינו ברשימה נופל לכותרת המפרש', (tester) async {
      final key = await _pump(tester);
      await _settleAnchorScroll(tester);

      const title = 'מפרש 2';
      key.currentState!.scrollToCommentator(title, linkKey: 'לא_קיים');
      await _settleAnchorScroll(tester);

      expect(_isNearTop(tester, find.text(title)), isTrue);
    });

    testWidgets('מפרש שאינו קיים כלל אינו מזיז את הרשימה', (tester) async {
      final key = await _pump(tester);
      await _settleAnchorScroll(tester);
      final before = _offsetOf(tester, find.text(_commentators.first));

      key.currentState!.scrollToCommentator('מפרש שלא נבחר');
      await _settleAnchorScroll(tester);

      expect(_offsetOf(tester, find.text(_commentators.first)), before);
    });
  });

  group('scrollToCommentator — התייצבות', () {
    testWidgets('בקשה בזמן שתוכן המפרשים עדיין נטען מגיעה ליעד', (
      tester,
    ) async {
      // בלי המתנה מראש: `link.content` של הקטעים עדיין לא נפתר, וגובהם
      // ישתנה תוך כדי — בדיוק המצב שבו ניסיון גלילה יחיד נעצר לפני היעד.
      final key = await _pump(tester);

      const title = 'מפרש 2';
      final target = _link(title: title, segment: 1);
      key.currentState!.scrollToCommentator(
        title,
        linkKey: commentaryLinkKey(target),
      );
      await _settleAnchorScroll(tester);

      expect(_isNearTop(tester, ValueKey(commentaryLinkKey(target))), isTrue);
    });

    testWidgets('יעד בסוף הרשימה מגיע לתצוגה, לא נעצר לפניו', (tester) async {
      final key = await _pump(tester);
      await _settleAnchorScroll(tester);

      final title = _commentators[_commentatorCount - 3];
      final target = _link(title: title, segment: 2);
      key.currentState!.scrollToCommentator(
        title,
        linkKey: commentaryLinkKey(target),
      );
      await _settleAnchorScroll(tester);

      final offset = _offsetOf(tester, ValueKey(commentaryLinkKey(target)));
      expect(offset, isNotNull, reason: 'היעד לא נבנה כלל — לא הייתה גלילה');
      expect(
        offset!,
        lessThan(tester.getRect(_listFinder).height),
        reason: 'היעד נשאר מתחת לתחתית אזור הגלילה',
      );
    });

    testWidgets('בקשה שנייה גוברת על הראשונה', (tester) async {
      final key = await _pump(tester);
      await _settleAnchorScroll(tester);

      final first = _link(title: 'מפרש 1', segment: 2);
      final second = _link(title: 'מפרש 3', segment: 1);
      key.currentState!
        ..scrollToCommentator('מפרש 1', linkKey: commentaryLinkKey(first))
        ..scrollToCommentator('מפרש 3', linkKey: commentaryLinkKey(second));
      await _settleAnchorScroll(tester);

      expect(_isNearTop(tester, ValueKey(commentaryLinkKey(second))), isTrue);
    });
  });

  group('מרוץ מול איפוס הקטע', () {
    // לחיצה על עוגן-אות שולחת קודם `UpdateSelectedIndex(sourceLine)`. שינוי
    // הקטע גורם ל-`_syncSectionScroll` (שרץ בתוך ה-build) לתזמן `scrollToTop`,
    // וזה קופץ ל-index 0 *אחרי* הגלילה לעוגן ומוחק אותה. בממשק זה נראה
    // כאילו נפתח הקטע הראשון של המפרש — שהוא גם הקטע שהעוגן הראשון (א)
    // מצביע אליו, ומכאן הרושם ש"רק א עובד".
    //
    // הכלל נבדק כפונקציה טהורה ולא דרך הווידג'ט: גלילה בזמן שהרשימה מחליפה
    // קטע מפילה את ScrollablePositionedList בפריסה בלתי-חסומה בסביבת בדיקה
    // headless, כך שבדיקת ווידג'ט כאן מודדת את הקריסה ולא את הכלל.
    test('בקשת עוגן ממתינה מבטלת את איפוס הקטע', () {
      expect(
        shouldResetScrollForSectionChange(hasPendingAnchorScroll: true),
        isFalse,
      );
    });

    test('בלי בקשת עוגן — האיפוס נשאר (issue #846)', () {
      expect(
        shouldResetScrollForSectionChange(hasPendingAnchorScroll: false),
        isTrue,
      );
    });

    testWidgets('מעבר קטע בלי בקשת עוגן עדיין מציג מתחילת הרשימה', (
      tester,
    ) async {
      // בקרה חיובית: ההתנהגות של issue #846 לא נשברה.
      await _pump(tester);
      await _settleAnchorScroll(tester);
      await tester.drag(_listFinder, const Offset(0, -300));
      await _settleAnchorScroll(tester);

      _lastBloc!.emitState(_loadedState(selectedLine: 1));
      await _settleAnchorScroll(tester);

      expect(_isNearTop(tester, find.text(_commentators.first)), isTrue);
    });
  });

  group('רצף לחיצות', () {
    // ⚠️ הבדיקות כאן מכסות את ההתנהגות (בקשות רצופות נענות, בקשה באמצע
    // סבב נאספת), אבל **אינן משחזרות** את התקיעה שנצפתה בשדה: ה-Future של
    // `ScrollablePositionedList.scrollTo` אינו מושלם לעולם כשהרשימה נבנית
    // מחדש באמצע המעבר, ובסביבת הבדיקה הוא כן מושלם. אומת שהן עוברות גם
    // עם ה-await החוסם, ולכן אינן ראיה לתיקון.
    //
    // הראיה לתקיעה היא לוג מהאפליקציה: 17 בקשות רצופות בלי אף שורת ניסיון
    // גלילה, אחרי שבקשה #2 נכנסה ל-await. התיקון מסיר את ההמתנה החיצונית
    // לגמרי, כך שהלולאה אינה יכולה להיתלות ב-SPL ללא קשר לפנימיותו.
    testWidgets('לחיצות רצופות ממשיכות להיענות', (tester) async {
      final key = await _pump(tester);
      await _settleAnchorScroll(tester);

      // סדרת יעדים, כמו משתמש שמדלג בין אותיות. אחרי הראשונה כל אחת מהן
      // חייבת עדיין להגיע ליעדה — זו בדיוק הנקודה שבה הרץ נתקע בשדה.
      for (final spec in const [
        ('מפרש 1', 1),
        ('מפרש 2', 2),
        ('מפרש 1', 2),
        ('מפרש 3', 1),
      ]) {
        final target = _link(title: spec.$1, segment: spec.$2);
        key.currentState!.scrollToCommentator(
          spec.$1,
          linkKey: commentaryLinkKey(target),
        );
        await _settleAnchorScroll(tester);

        expect(
          _isNearTop(tester, ValueKey(commentaryLinkKey(target))),
          isTrue,
          reason: 'הבקשה ל-${spec.$1} קטע ${spec.$2} לא נענתה',
        );
      }
    });

    testWidgets('החלפת סדר המפרשים באמצע הגלילה אינה תוקעת את הרץ', (
      tester,
    ) async {
      final key = await _pump(tester);
      await _settleAnchorScroll(tester);

      const promoted = 'מפרש 3';
      final target = _link(title: promoted, segment: 1);
      key.currentState!.scrollToCommentator(
        promoted,
        linkKey: commentaryLinkKey(target),
      );
      // באמצע המעבר: המפרש שנלחץ עולה לראש, ה-key של SPL מתחלף, והרשימה
      // נבנית מחדש — המצב שבו ה-Future של scrollTo אינו מושלם לעולם.
      await tester.pump(const Duration(milliseconds: 60));
      _lastBloc!.emitState(
        _loadedState(
          commentatorsOrder: [
            promoted,
            ..._commentators.where((c) => c != promoted),
          ],
        ),
      );
      await _settleAnchorScroll(tester);

      // הדרישה: בקשה *נוספת* אחרי ההחלפה עדיין נענית. אם הרץ נתקע, שום
      // לחיצה לא תעבוד יותר — וזה מה שנצפה בשדה.
      final next = _link(title: 'מפרש 1', segment: 2);
      key.currentState!.scrollToCommentator(
        'מפרש 1',
        linkKey: commentaryLinkKey(next),
      );
      await _settleAnchorScroll(tester);

      expect(
        _isNearTop(tester, ValueKey(commentaryLinkKey(next))),
        isTrue,
        reason: 'הרץ נתקע — בקשה שאחרי החלפת הרשימה אינה נענית',
      );
    });

    testWidgets('בקשה שנרשמת תוך כדי ריצה נאספת ולא נבלעת', (tester) async {
      final key = await _pump(tester);
      await _settleAnchorScroll(tester);

      final first = _link(title: 'מפרש 1', segment: 1);
      final second = _link(title: 'מפרש 3', segment: 2);

      key.currentState!.scrollToCommentator(
        'מפרש 1',
        linkKey: commentaryLinkKey(first),
      );
      // באמצע הסבב הראשון, לפני שהספיק להסתיים.
      await tester.pump(const Duration(milliseconds: 120));
      key.currentState!.scrollToCommentator(
        'מפרש 3',
        linkKey: commentaryLinkKey(second),
      );
      await _settleAnchorScroll(tester);

      expect(
        _isNearTop(tester, ValueKey(commentaryLinkKey(second))),
        isTrue,
        reason: 'הבקשה השנייה נבלעה בסבב שכבר רץ',
      );
    });
  });

  group('scrollTargetListenable — מסלול "מפרשים בצד"', () {
    testWidgets('בקשה דרך הנוטיפייר גוללת לקטע המדויק', (tester) async {
      final notifier = ValueNotifier<CommentaryScrollRequest?>(null);
      addTearDown(notifier.dispose);
      await _pump(tester, scrollTarget: notifier);
      await _settleAnchorScroll(tester);

      final target = _link(title: 'מפרש 2', segment: 1);
      notifier.value = CommentaryScrollRequest(
        title: 'מפרש 2',
        linkKey: commentaryLinkKey(target),
        requestId: 1,
      );
      await _settleAnchorScroll(tester);

      expect(_isNearTop(tester, ValueKey(commentaryLinkKey(target))), isTrue);
    });

    testWidgets('בקשה שנקבעה לפני בניית הרשימה אינה אובדת', (tester) async {
      // הפאנל נפתח בעקבות אותה לחיצה, ולכן הרשימה עשויה להיבנות רק אחרי
      // שהבקשה כבר נרשמה — ואז אין שינוי ערך ש-listener יתפוס.
      final target = _link(title: 'מפרש 2', segment: 2);
      final notifier = ValueNotifier<CommentaryScrollRequest?>(
        CommentaryScrollRequest(
          title: 'מפרש 2',
          linkKey: commentaryLinkKey(target),
          requestId: 1,
        ),
      );
      addTearDown(notifier.dispose);

      await _pump(tester, scrollTarget: notifier);
      await _settleAnchorScroll(tester);

      expect(_isNearTop(tester, ValueKey(commentaryLinkKey(target))), isTrue);
    });

    testWidgets('לחיצה חוזרת על אותו עוגן גוללת שוב', (tester) async {
      final notifier = ValueNotifier<CommentaryScrollRequest?>(null);
      addTearDown(notifier.dispose);
      await _pump(tester, scrollTarget: notifier);
      await _settleAnchorScroll(tester);

      final target = _link(title: 'מפרש 2', segment: 1);
      final linkKey = commentaryLinkKey(target);
      notifier.value = CommentaryScrollRequest(
        title: 'מפרש 2',
        linkKey: linkKey,
        requestId: 1,
      );
      await _settleAnchorScroll(tester);
      expect(_isNearTop(tester, ValueKey(linkKey)), isTrue);

      // המשתמש גולל הלאה, ואז לוחץ שוב על אותו עוגן.
      await tester.drag(_listFinder, const Offset(0, -300));
      await _settleAnchorScroll(tester);
      expect(_isNearTop(tester, ValueKey(linkKey)), isFalse);

      notifier.value = CommentaryScrollRequest(
        title: 'מפרש 2',
        linkKey: linkKey,
        requestId: 2,
      );
      await _settleAnchorScroll(tester);

      expect(
        _isNearTop(tester, ValueKey(linkKey)),
        isTrue,
        reason: 'מזהה בקשה חדש חייב להפעיל גלילה נוספת',
      );
    });
  });
}

final Finder _listFinder = find.byType(ScrollablePositionedList);

/// מריץ את לולאת הגלילה עד סופה.
///
/// `pumpAndSettle` לבדו אינו מספיק: בין ניסיון לניסיון הלולאה ממתינה
/// ב-`Future.delayed` ואין פריים מתוזמן, ולכן הוא חוזר באמצע. קידום השעון
/// המפורש מפעיל את הטיימר, וה-`scrollTo` שאחריו מתזמן את הפריים הבא.
Future<void> _settleAnchorScroll(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pumpAndSettle();
}

/// ההיסט האנכי של הפריט ביחס לראש אזור הגלילה, או null אם אינו בנוי.
double? _offsetOf(WidgetTester tester, Object target) {
  if (_listFinder.evaluate().isEmpty) return null;
  final finder = target is Finder ? target : find.byKey(target as Key);
  if (finder.evaluate().isEmpty) return null;
  return tester.getTopLeft(finder.first).dy - tester.getRect(_listFinder).top;
}

/// האם הפריט נמצא בראש אזור הגלילה. הסבילות מכסה גובה מפריד/ריפוד.
bool _isNearTop(WidgetTester tester, Object target) {
  final offset = _offsetOf(tester, target);
  return offset != null && offset >= -8 && offset < 48;
}

/// ה-bloc של ההרצה האחרונה, כדי שבדיקה תוכל לדחוף מצב חדש (מעבר קטע).
_TestTextBookBloc? _lastBloc;

Future<GlobalKey<CommentaryListBaseState>> _pump(
  WidgetTester tester, {
  ValueListenable<CommentaryScrollRequest?>? scrollTarget,
  Size? surfaceSize,
}) async {
  if (surfaceSize != null) {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  final key = GlobalKey<CommentaryListBaseState>();
  final bloc = _TestTextBookBloc(_loadedState());
  _lastBloc = bloc;
  addTearDown(() => _lastBloc = null);
  final settingsBloc = _TestSettingsBloc(SettingsState.initial());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    await bloc.close();
    await settingsBloc.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: CommentaryListBase(
              key: key,
              openBookCallback: (_) {},
              fontSize: 18,
              showSearch: true,
              shrinkWrap: false,
              scrollTargetListenable: scrollTarget,
              onSelectedCommentatorsOverrideChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return key;
}

/// שורות המקור בבדיקה. שתיים ומעלה נדרשות כדי לדמות "מעבר קטע", שהוא
/// מה שלחיצה על עוגן גורמת לו דרך `UpdateSelectedIndex`.
const int _lineCount = 2;

/// קישור לקטע [segment] של [title] על שורת המקור [line].
///
/// כל הקישורים של אותה שורה חולקים `index1` ונבדלים ב-`index2` — בדיוק
/// המצב שבו מפרש אחד מופיע כמה פעמים על אותו סעיף.
Link _link({required String title, required int segment, int line = 0}) => Link(
  heRef: 'קטע ${segment + 1}',
  index1: line + 1,
  path2: '$title.txt',
  index2: line * _segmentsPerCommentator + segment + 1,
  connectionType: LinkTypes.commentary,
  targetCategoryId: 1,
  targetFileType: 'txt',
);

List<Link> _linksForLine(int line) => [
  for (final title in _commentators)
    for (var segment = 0; segment < _segmentsPerCommentator; segment++)
      _link(title: title, segment: segment, line: line),
];

List<Link> _allLinks() => [
  for (var line = 0; line < _lineCount; line++) ..._linksForLine(line),
];

/// [commentatorsOrder] מדמה את `activatePreviewCommentator`, שמביא את המפרש
/// שנלחץ לראש הרשימה — וזה מחליף את ה-`key` של `ScrollablePositionedList`.
TextBookLoaded _loadedState({
  int selectedLine = 0,
  List<String>? commentatorsOrder,
}) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: const ['שורה א', 'שורה ב'],
  fontSize: 18,
  showSplitView: false,
  activeCommentators: commentatorsOrder ?? _commentators,
  commentatorGroups: [
    CommentatorGroup(title: 'ראשונים', commentators: _commentators),
  ],
  availableCommentators: _commentators,
  links: _allLinks(),
  visibleLinks: const [],
  linksByLine: {
    for (var line = 0; line < _lineCount; line++) line + 1: _linksForLine(line),
  },
  linksLoading: false,
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: [selectedLine],
  selectedIndex: selectedLine,
  selectedIndices: {selectedLine},
  pinLeftPane: false,
  searchText: '',
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  /// דוחף מצב חדש, כדי לדמות את `UpdateSelectedIndex` שלחיצה על עוגן שולחת.
  void emitState(TextBookState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibraryProvider implements LibraryProvider {
  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 0;

  @override
  String get providerId => 'fake';

  @override
  String get sourceIndicator => 'T';

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async => throw UnimplementedError();

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async => const [];

  @override
  Future<Set<String>> getAvailableBookTitles() async => {
    for (final title in _commentators) '$title|1|txt',
  };

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async => null;

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async => const [];

  /// תוכן ארוך ומזוהה: האורך מייצר רשימה גלילה, והמספר מאפשר לזהות איזה
  /// קטע מוצג בפועל.
  @override
  Future<String> getLinkContent(Link link) async =>
      'קטע ${link.index2} של ${link.path2}. ' * 4;

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      true;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}
