import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_structure.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_tree_reader.dart';

/// ספר אחד כפי שהסיווג מזהה אותו.
///
/// השורה נבנית מ**שרשרת הצמתים** ולא מהנתיב כמחרוזת, מפני שההחלטה היכן
/// מתחיל שם הספר נקראת מ-`lParam` של כל צומת — ראה [ResponsaStructure].
class ResponsaBookRow {
  /// השרשרת מהשורש ועד הספר עצמו, כולל.
  final List<ResponsaChainNode> chain;

  ResponsaBookRow({required this.chain})
    : assert(chain.isNotEmpty, 'שרשרת ריקה אינה ספר');

  /// שם הצומת בעץ, כפי שהוא. זהו שם היחידה — `אבות`, לא `הון עשיר אבות`.
  String get leafTitle => chain.last.name;

  int get treeParam => chain.last.param;

  int get level => chain.last.level;

  String get refPath => [
    for (final node in chain) node.name,
  ].join(ResponsaTreeReader.pathSeparator);

  String get parentPath => [
    for (final node in chain.sublist(0, chain.length - 1)) node.name,
  ].join(ResponsaTreeReader.pathSeparator);

  ({List<String> nameNodes, List<String> categoryNodes, int workOffset})?
  _parts;
  ({List<String> nameNodes, List<String> categoryNodes, int workOffset})
  get _resolved => _parts ??= ResponsaStructure.decompose(chain)!;

  /// השם שהמשתמש רואה ומחפש לפיו — `מהרש"א חידושי הלכות בבא בתרא`.
  String get title => ResponsaNames.titleOf(_resolved.nameNodes);

  /// רכיבי השם, מהחיבור (או מהשם שמעליו) ומטה.
  List<String> get nameNodes => _resolved.nameNodes;

  /// כמה רכיבי שם יושבים **מעל** החיבור.
  int get workOffset => _resolved.workOffset;

  /// רכיבי הקטגוריה, מהשורש ועד לרכיב שמעל השם.
  List<String> get categoryNodes => _resolved.categoryNodes;

  /// הנתיב שלפיו נקבעת הקטגוריה באוצריא: רכיבי הקטגוריה **ומה שמעל
  /// החיבור**.
  ///
  /// הרכיב שמעל החיבור משרת שני תפקידים בו-זמנית, ושניהם נכונים: הוא
  /// חלק מהשם (`משנה אבות`) והוא גם מדף (`ספרות חז"ל > משנה`). כשנשמרו
  /// רק רכיבי הקטגוריה, 259 ספרים — כל המשנה, התוספתא, הבבלי והמסכתות
  /// הקטנות — נותרו עם `ספרות חז"ל` בלבד ושויכו כולם לתלמוד בבלי.
  List<String> get classificationNodes => [
    ..._resolved.categoryNodes,
    ..._resolved.nameNodes.sublist(0, workOffset),
  ];

  /// מפתח זהות הצומת, לאיתור אותו חיבור שמופיע בעץ בשני נתיבים.
  ///
  /// `null` כשצומת הסיום אינו **צומת חיבור**. ההגבלה חיונית: `param`
  /// הוא מספר סידורי בתוך הענף ולא מזהה ייחודי, ובמישור היחידות הוא
  /// חוזר על עצמו אלפי פעמים. נמדד: בלעדיה נמחקו 4,094 ספרים תקינים.
  /// במישור החיבורים הוא כמעט ייחודי — 1,932 ערכים ל-2,000 צמתים —
  /// ויחד עם השם הוא מפריד גם בין שני החיבורים שחלקו ערך במקרה.
  ({int param, String name})? get identity =>
      ResponsaStructure.kindOf(treeParam) == ResponsaStructure.workKind
      ? (param: treeParam, name: leafTitle)
      : null;
}

class ResponsaCatalogBuildResult {
  final int books;
  final int scannedNodes;
  final Duration elapsed;
  final Map<String, int> idMatching;

  const ResponsaCatalogBuildResult({
    required this.books,
    required this.scannedNodes,
    required this.elapsed,
    required this.idMatching,
  });
}

class ResponsaCatalogBuildException implements Exception {
  final String message;
  const ResponsaCatalogBuildException(this.message);

  @override
  String toString() => message;
}

/// בניית קטלוג פרויקט השו"ת מתוך עץ הקטלוג של התוכנה.
///
/// שלושה דברים שהבנייה **לא** עושה, וכל אחד מהם מכוון:
///
/// * אינה שומרת את ההיררכיה המלאה. 1.25M צמתים הם כ-475MB, והם נדרשים
///   רק כדי לזהות את הספרים; הפתיחה נעשית לפי הפניה טקסטואלית.
/// * אינה יוצרת FTS5. הטבלה היא כ-8.5K שורות — קטנה מקטלוג היברובוקס
///   שאוצריא כבר טוענת לזיכרון.
/// * אינה גוזרת מזהה מ-hash של הנתיב. נמדד ש-81% בלבד מהנתיבים שורדים
///   מעבר בין מהדורות, ולכן המזהה מקומי ומתמשך, והתאמה רב-שלבית
///   משמרת אותו בבנייה מחדש.
class ResponsaCatalogBuilder {
  ResponsaCatalogBuilder._();

  /// מקטע = יחידת תוכן בתוך ספר. שני סימנים בלתי-תלויים: מישור ה-param
  /// ושם היחידה. די באחד מהם — נצפו מקטעים ששמם חריג ומקטעים במישור חריג.
  static const int _sectionPlaneBits = 0x1000 | 0x2000;

  static final RegExp _sectionName = RegExp(
    r'^(פרק|פסוק|דף|סימן|סעיף|הלכה|משנה|עמוד|שער|פרשה|אות|מאמר|שורש|מצוה'
    r"|הקדמ|פתיחה|תוכן|מפתח|ברייתא|נוסחא|סי'|עמ'|חלק [א-ת]'?$)",
  );

  static bool isSection(String name, int param) =>
      ((param >> 16) & _sectionPlaneBits) != 0 || _sectionName.hasMatch(name);

  /// מזהה ספרים מתוך זרם הצמתים.
  ///
  /// ספר = הצומת הגבוה ביותר שתוכנו מקטעים **ושיושב תחת צומת חיבור**:
  /// יש לו ילד שהוא מקטע, הוא עצמו אינו מקטע, ויש בשרשרת שמעליו צומת
  /// מסוג חיבור. כלל מבני ולא היוריסטיקת-רמה, כי עומק הספר משתנה בין
  /// ענפים — `בראשית` ברמה 1 ו-`משנה > שבת` ברמה 2, ושניהם ספרים.
  ///
  /// תנאי החיבור הוא שמסלק 58 תוצאות שווא שנמדדו במהדורה המותקנת: צמתי
  /// קטגוריה שיש להם ילד בעל שם של מקטע (`שולחן ערוך`, `ילקוט יוסף`,
  /// `מפרשים על הרמב"ם`, ורשומות `מפתח נושאים בשו"ת`). הם הופיעו בחיפוש
  /// ולא נפתחו לעולם, כי אין מאחוריהם טקסט.
  ///
  /// ## אותו חיבור בשני נתיבים
  ///
  /// העץ מכיל **הפניות**, לא רק היררכיה: אותו צומת חיבור מופיע בשני
  /// מקומות. נמדד ש-`אנציקלופדיות שונות > מנהגי החגים > עשרת ימי תשובה
  /// ויום הכיפורים` מכיל את כל 63 מסכתות המשנה, עם אותם ערכי `lParam`
  /// ואותם מספרי פרקים כמו תחת `ספרות חז"ל > משנה`. אומת בקריאה חוזרת
  /// של אותו ענף בלבד, במופע טרי — התוכן זהה, ולכן זהו מבנה אמיתי
  /// בתוכנה ולא כשל בסריקה.
  ///
  /// הכפילויות האלה הפכו ל-63 ספרים ששמם מורכב מנתיב ההפניה
  /// (`מנהגי החגים עשרת ימי תשובה ויום הכיפורים אבות`) ואינם נפתחים
  /// לעולם. **המופע הראשון בסדר הסריקה הוא הקנוני**, כי הקטגוריות
  /// המסודרות קודמות לאנציקלופדיות בעץ.
  static List<ResponsaBookRow> classify(Iterable<ResponsaTreeNode> nodes) {
    final found = <({int order, ResponsaBookRow row})>[];
    final stack =
        <({ResponsaTreeNode node, int order, bool hasSectionChild})>[];
    var scanned = 0;

    void emit(
      ({ResponsaTreeNode node, int order, bool hasSectionChild}) entry,
    ) {
      final node = entry.node;
      if (node.level == 0 || !entry.hasSectionChild) return;
      if (isSection(node.name, node.param)) return;
      final chain = <ResponsaChainNode>[
        for (final ancestor in stack)
          (
            level: ancestor.node.level,
            param: ancestor.node.param,
            name: ancestor.node.name,
          ),
        (level: node.level, param: node.param, name: node.name),
      ];
      if (ResponsaStructure.decompose(chain) == null) return;
      found.add((order: entry.order, row: ResponsaBookRow(chain: chain)));
    }

    void closeTo(int level) {
      while (stack.isNotEmpty && stack.last.node.level >= level) {
        emit(stack.removeLast());
      }
    }

    for (final node in nodes) {
      closeTo(node.level);
      if (stack.isNotEmpty && isSection(node.name, node.param)) {
        final last = stack.removeLast();
        stack.add((
          node: last.node,
          order: last.order,
          hasSectionChild: true,
        ));
      }
      stack.add((node: node, order: scanned++, hasSectionChild: false));
    }
    closeTo(0);
    while (stack.isNotEmpty) {
      emit(stack.removeLast());
    }

    // הצמתים נפלטים בסדר יציאה מהמחסנית ולא בסדר הסריקה. הסדר חשוב
    // פעמיים: הוא קובע איזה מופע של חיבור כפול נחשב הקנוני, והוא גם
    // סדר הקטלוג שהמשתמש רואה.
    found.sort((a, b) => a.order.compareTo(b.order));
    final seen = <({int param, String name})>{};
    final unique = <ResponsaBookRow>[];
    for (final entry in found) {
      final identity = entry.row.identity;
      if (identity != null && !seen.add(identity)) continue;
      unique.add(entry.row);
    }
    return unique;
  }

  /// ההפניה הראשית של כל ספר — **השם המלא של הספר**, בלי תוויות.
  ///
  /// `מהרש"א חידושי הלכות בבא בתרא` ולא `חידושי הלכות בבא בתרא`: זהו
  /// בדיוק השם שהתוכנה נותנת לחלון שהיא פותחת, וגם השם שהמשתמש רואה
  /// ברשימה. השם הקצר שייך לכמה מחברים, ופתיחה לפיו הסתיימה בספר אחר.
  ///
  /// **לא מוסיפים מעל כך.** תוויות המיון אינן חלק משום הפניה שהמנתח
  /// מכיר: `ספרי שאלות ותשובות ... שאגת אריה` נדחה אחרי 19 שניות, ואילו
  /// `שאגת אריה` נפתח מיד. לכן גם `ספרי החפץ חיים`, שהוא תווית אף שהוא
  /// רכיב בשם המוצג, נשאר מחוץ להפניה.
  ///
  /// החד-משמעיות אינה נבדקת מול הקטלוג אלא נמסרת למנתח: ייחודיות
  /// **בקטלוג** אינה ייחודיות **אצל המנתח**, ובחירת הצורה הקצרה רק
  /// מפני שהיא ייחודית בקטלוג היא בדיוק מה שהוליך לספר שגוי. מה שמגן
  /// על הפתיחה הוא אימות כותרת החלון וסולם הנסיגה שמתחתיו.
  static List<String> buildOpenRefs(List<ResponsaBookRow> books) => [
    for (final book in books)
      if (ResponsaNames.referenceOf(book.nameNodes) case final reference)
        // הפניה ריקה מפילה את אימות הבנייה ואיתו את כל הקטלוג, בגלל שם
        // אחד חריג מתוך 8,465. שם הצומת הגולמי הוא מוצא אחרון.
        reference.isEmpty ? book.leafTitle.trim() : reference,
  ];

  /// הפניות חלופיות, לפי סדר יורד של סיכוי — סולם הנסיגה של הפתיחה.
  ///
  /// הסולם נבנה כאן ולא בזמן הפתיחה, מפני שרק כאן ידוע מבנה השרשרת.
  /// בזמן הפתיחה נשארה רק השמטת מילים מההתחלה, שהיא ניחוש: היא פתחה ספר
  /// אחר ב-3 מתוך 40 פתיחות שנמדדו.
  ///
  /// **כל חוליה מתחילה בשם החיבור או מעליו.** חוליה שמתחילה ביחידה
  /// (`פרשת קדושים`, `פסחים`) שייכת לכל פרשן ולכל מסכת, ונמדד שהיא אינה
  /// מוסיפה הצלחות — היא פותחת ספר אחר, והאימות פוסל אותו אחרי ששולם
  /// כבר מחיר הזמן.
  static List<String> alternativeRefs(ResponsaBookRow book, String openRef) {
    final names = book.nameNodes;
    final head = names.first;
    final work = names.sublist(book.workOffset);
    final candidates = <List<String>>[
      // החיבור בלי השם שמעליו — עוזר כשהמנתח אינו מכיר את הצירוף.
      work,
      // ראש השם והיחידה, בלי מה שביניהם. נמדד חי: התוכנה מכנה את הספר
      // `חידושי הגר"ח מגילה`, ואילו המאגר קורא לצומת שמעל המסכת
      // `חידושים על הגמרא` — צירוף שהמנתח אינו מזהה. אותו דפוס בדיוק
      // ב-`שם משמואל ... תורה ... פרשת בהעלותך`.
      if (names.length > 1) [head, names.last],
      // שם החיבור ושם היחידה. נמדד שהתוכנה מקבלת `חומת אנך בראשית פרשת
      // בראשית` אך דוחה `תיבת גמא דברים פרשת האזינו`, ואותו חיבור
      // בדיוק נפתח בצורה הקצרה.
      if (work.length > 2) [work.first, work.last],
      [work.first],
      // 19 שמות במאגר נושאים הסתייגות בסדר הגיוני ולכן אינם מפורקים
      // על ידי `coreOf` — `הלכות קטנות לרי"ף (מנחות) - הלכות ציצית`.
      // גרסה בלי הסוגריים היא החוליה האחרונה לפני כישלון.
    ];
    final seen = <String>{openRef};
    return [
      for (final candidate in candidates)
        if (ResponsaNames.referenceOf(candidate) case final reference)
          if (reference.isNotEmpty && seen.add(reference)) reference,
      for (final reference in [
        ResponsaNames.withoutQualifier(openRef),
        ResponsaNames.withoutQualifier(ResponsaNames.referenceOf(work)),
      ])
        if (reference.isNotEmpty && seen.add(reference)) reference,
    ];
  }

  static String normalizedPath(String refPath) => refPath
      .split(ResponsaTreeReader.pathSeparator)
      .map(ResponsaHebrew.spellingKey)
      .join(ResponsaTreeReader.pathSeparator);

  /// משייך `external_key` לכל ספר, תוך שימור מזהים קיימים.
  ///
  /// ההתאמה רב-שלבית ולפי סדר ביטחון יורד, וכל שלב דורש חד-ערכיות
  /// **בשני הצדדים**. התאמה עמומה = ספר חדש: שיוך מזהה ישן על סמך
  /// התאמה חלשה גרוע מלהקצות חדש, כי הוא מעביר סימניות והיסטוריה
  /// לספר אחר.
  static ({List<String> keys, Map<String, int> stats}) assignExternalKeys(
    List<ResponsaBookRow> books,
    List<({String key, String refPath, int? treeParam})> existing,
  ) {
    final assigned = List<String?>.filled(books.length, null);
    final stats = {'exact': 0, 'normalized': 0, 'parentParam': 0, 'new': 0};
    final taken = <String>{};
    var unmatched = List<int>.generate(books.length, (i) => i);

    if (existing.isNotEmpty) {
      final stages =
          <
            (
              String,
              String Function(ResponsaBookRow),
              String Function(({String key, String refPath, int? treeParam})),
            )
          >[
            ('exact', (b) => b.refPath, (e) => e.refPath),
            (
              'normalized',
              (b) => normalizedPath(b.refPath),
              (e) => normalizedPath(e.refPath),
            ),
            (
              'parentParam',
              (b) => '${normalizedPath(b.parentPath)}|${b.treeParam}',
              (e) =>
                  '${normalizedPath(_parentOf(e.refPath))}|${e.treeParam ?? -1}',
            ),
          ];

      for (final (name, bookKey, existingKey) in stages) {
        final available = existing.where((e) => !taken.contains(e.key));
        final index = _uniqueIndex(available, existingKey);
        final newIndex = _uniqueIndex(unmatched, (i) => bookKey(books[i]));
        final still = <int>[];
        for (final position in unmatched) {
          final key = bookKey(books[position]);
          final match = index[key];
          if (match == null || newIndex[key] != position) {
            still.add(position);
            continue;
          }
          assigned[position] = match.key;
          taken.add(match.key);
          stats[name] = stats[name]! + 1;
        }
        unmatched = still;
      }
    }

    var next =
        1 +
        existing
            .map((e) => int.tryParse(e.key) ?? 0)
            .fold<int>(0, (a, b) => a > b ? a : b);
    for (final position in unmatched) {
      while (taken.contains('$next')) {
        next++;
      }
      assigned[position] = '$next';
      taken.add('$next');
      stats['new'] = stats['new']! + 1;
      next++;
    }

    return (keys: [for (final key in assigned) key!], stats: stats);
  }

  static String _parentOf(String refPath) {
    final parts = refPath.split(ResponsaTreeReader.pathSeparator);
    return parts
        .sublist(0, parts.length - 1)
        .join(
          ResponsaTreeReader.pathSeparator,
        );
  }

  static Map<String, T> _uniqueIndex<T>(
    Iterable<T> items,
    String Function(T) keyOf,
  ) {
    final index = <String, T>{};
    final duplicated = <String>{};
    for (final item in items) {
      final key = keyOf(item);
      if (index.containsKey(key)) {
        duplicated.add(key);
      } else {
        index[key] = item;
      }
    }
    for (final key in duplicated) {
      index.remove(key);
    }
    return index;
  }
}
