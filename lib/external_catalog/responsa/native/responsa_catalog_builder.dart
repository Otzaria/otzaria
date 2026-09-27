import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_structure.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_tree_reader.dart';

/// נבנה משרשרת הצמתים ולא מהנתיב כמחרוזת: היכן מתחיל שם הספר נקרא
/// מ-`lParam` של כל צומת (ראה [ResponsaStructure]).
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

  /// של צומת החיבור ולא של הספר: רק שם הבית הנמוך הוא מזהה החיבור, ביחידות
  /// שתחתיו הוא מספר סידורי ומחבר שנקרא לפיו שייך לחיבור אחר.
  int get workParam =>
      chain[chain.length - _resolved.nameNodes.length + workOffset].param;

  /// רכיבי הקטגוריה, מהשורש ועד לרכיב שמעל השם.
  List<String> get categoryNodes => _resolved.categoryNodes;

  /// כולל את מה שמעל החיבור: הוא גם חלק מהשם (`משנה אבות`) וגם מדף, ובלעדיו
  /// כל המשנה והתוספתא נופלות ל`ספרות חז"ל` בלבד.
  List<String> get classificationNodes => [
    ..._resolved.categoryNodes,
    ..._resolved.nameNodes.sublist(0, workOffset),
  ];

  /// רק שמות ברמת החיבור: שם היחידה (`בראשית` של `רש"י בראשית`) מייחס
  /// מהדורה של ספר אחר, וזה גרוע מהיעדר מהדורה.
  List<String> get bibliographyNames {
    final names = _resolved.nameNodes;
    final work = names[workOffset];
    return [
      ResponsaNames.coreOf(work),
      if (workOffset > 0)
        ResponsaNames.referenceOf(names.sublist(0, workOffset + 1)),
      if (workOffset > 0) ResponsaNames.coreOf(names.first),
    ];
  }

  /// לאיתור חיבור שמופיע בשני נתיבים. רק לצומת חיבור: במישור היחידות `param`
  /// חוזר אלפי פעמים, ודה-דופליקציה לפיו מוחקת ספרים תקינים.
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

/// המזהה אינו hash של הנתיב: רק כ-81% מהנתיבים שורדים מעבר מהדורה, ולכן
/// הוא מקומי ומתמשך ונשמר בבנייה מחדש בהתאמה רב-שלבית.
class ResponsaCatalogBuilder {
  ResponsaCatalogBuilder._();

  /// מקטע = יחידת תוכן בתוך ספר. די באחד משני הסימנים (מישור ה-param או השם):
  /// יש מקטעים ששמם חריג ויש שהמישור שלהם חריג.
  static const int _sectionPlaneBits = 0x1000 | 0x2000;

  static final RegExp _sectionName = RegExp(
    r'^(פרק|פסוק|דף|סימן|סעיף|הלכה|משנה|עמוד|שער|פרשה|אות|מאמר|שורש|מצוה'
    r"|הקדמ|פתיחה|תוכן|מפתח|ברייתא|נוסחא|סי'|עמ'|חלק [א-ת]'?$)",
  );

  static bool isSection(String name, int param) =>
      ((param >> 16) & _sectionPlaneBits) != 0 || _sectionName.hasMatch(name);

  /// ספר = הצומת הגבוה ביותר שתוכנו מקטעים ושיושב תחת צומת חיבור (בלי התנאי
  /// קטגוריות כמו `שולחן ערוך` נראות כספרים). כלל מבני, כי עומק הספר משתנה.
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

    // העץ מכיל הפניות: אותו חיבור מופיע בשני נתיבים. הקנוני הוא הראשון בסדר
    // הסריקה (הקטגוריות המסודרות קודמות), ולא בסדר היציאה מהמחסנית.
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

  /// השם המלא בלי תוויות מיון: השם הקצר שייך לכמה מחברים, ותוויות אינן חלק
  /// מהפניה שהמנתח מכיר. ייחודיות בקטלוג אינה ייחודיות אצל המנתח.
  static List<String> buildOpenRefs(List<ResponsaBookRow> books) => [
    for (final book in books)
      if (ResponsaNames.referenceOf(book.nameNodes) case final reference)
        // הפניה ריקה מפילה את אימות הבנייה ואיתו את כל הקטלוג בגלל שם חריג
        // אחד; שם הצומת הגולמי הוא מוצא אחרון.
        reference.isEmpty ? book.leafTitle.trim() : reference,
  ];

  /// סולם הנסיגה של הפתיחה, נבנה כאן כי רק כאן ידוע מבנה השרשרת. כל חוליה
  /// מתחילה בשם החיבור או מעליו: יחידה לבדה (`פסחים`) פותחת ספר אחר.
  static List<String> alternativeRefs(ResponsaBookRow book, String openRef) {
    final names = book.nameNodes;
    final head = names.first;
    final work = names.sublist(book.workOffset);
    final candidates = <List<String>>[
      // החיבור בלי השם שמעליו — עוזר כשהמנתח אינו מכיר את הצירוף.
      work,
      // ראש השם והיחידה בלבד: צמתי ביניים כמו `חידושים על הגמרא` אינם
      // מוכרים למנתח (`חידושי הגר"ח מגילה`).
      if (names.length > 1) [head, names.last],
      // המנתח דוחה חלק מהצירופים המלאים של חיבור + ספר + יחידה.
      if (work.length > 2) [work.first, work.last],
      [work.first],
    ];
    // שם החיבור בלי התחום שנדבק לו - אחרונות כי הן מקצרות את שם החיבור,
    // ולכן המסוכנות ביותר.
    final unit = work.length > 1 ? work.last : null;
    final scoped = [
      for (final shortened in ResponsaNames.withoutScope(
        ResponsaNames.coreOf(work.first),
      )) ...[
        if (unit != null)
          ResponsaNames.referenceOf([shortened, ResponsaNames.coreOf(unit)]),
        shortened,
      ],
    ];

    final seen = <String>{openRef};
    return [
      for (final candidate in candidates)
        if (ResponsaNames.referenceOf(candidate) case final reference)
          if (reference.isNotEmpty && seen.add(reference)) reference,
      // יש שמות שההסתייגות בהם באמצע ו-`coreOf` לא מפרק אותם.
      for (final reference in [
        ResponsaNames.withoutQualifier(openRef),
        ResponsaNames.withoutQualifier(ResponsaNames.referenceOf(work)),
        ...scoped,
      ])
        if (reference.isNotEmpty && seen.add(reference)) reference,
    ];
  }

  static String normalizedPath(String refPath) => refPath
      .split(ResponsaTreeReader.pathSeparator)
      .map(ResponsaHebrew.spellingKey)
      .join(ResponsaTreeReader.pathSeparator);

  /// כל שלב דורש חד-ערכיות בשני הצדדים; התאמה עמומה = ספר חדש, כי מזהה ישן
  /// בהתאמה חלשה מעביר סימניות והיסטוריה לספר אחר.
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
