import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// לרוב ספרי פרויקט השו"ת אין שדה מחבר, ושם המחבר קיים רק כרכיב בנתיב העץ —
/// בלי חיפוש בהקשר, מחברים שלמים אינם ניתנים לאיתור.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataRepository repository;

  /// ספר כפי שהקטלוג בונה אותו: הכותרת היא שם המסכת, והמחבר רכיב בנתיב.
  ExternalLibraryBook book({
    required String title,
    required String refPath,
    required int id,
  }) => ExternalLibraryBook(
    title: title,
    id: id,
    link: null,
    categoryPath: ResponsaCatalogRepository.contextPathOf(refPath),
    externalLibraryId: 'rp:$id',
  );

  setUpAll(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  setUp(() {
    repository = DataRepository()
      ..library = Future.value(Library(categories: []))
      ..localHebrewBooks = Future.value(const [])
      ..responsaBooks = Future.value([
        // מחבר שהוא צומת סוג 3 נכנס לכותרת.
        book(
          title: 'מהרש"א חידושי הלכות בבא בתרא',
          refPath:
              'מפרשים ופוסקים על הבבלי > אחרונים על הבבלי > מהרש"א > '
              'חידושי הלכות > בבא בתרא',
          id: 1,
        ),
        book(
          title: 'רא"ש יבמות',
          refPath: 'מפרשים ופוסקים על הבבלי > רא"ש > יבמות',
          id: 2,
        ),
        book(
          title: 'מהדורא קמא - אורח חיים',
          refPath: 'שו"ת > נודע ביהודה > מהדורא קמא - אורח חיים',
          id: 3,
        ),
        // תווית אוסף נשארת בקטגוריה ולא בכותרת.
        book(
          title: 'שמירת הלשון חלק א שער התורה',
          refPath:
              'ספרי מחשבה ומוסר > ספרי החפץ חיים > שמירת הלשון > חלק א > '
              'שער התורה',
          id: 4,
        ),
      ]);
  });

  Future<List<String>> search(String query) async {
    final found = await repository.findBooks(
      query,
      null,
      includeResponsa: true,
    );
    return found.map((b) => b.externalLibraryId!).toList();
  }

  test('שם המחבר שבכותרת נמצא', () async {
    expect(await search('מהרש"א'), contains('rp:1'));
  });

  test('מחבר שהוא תווית אוסף — נמצא דרך ההקשר', () async {
    // `ספרי החפץ חיים` אינו בכותרת כי התוכנה אינה מכירה אותו כהפניה.
    expect(await search('החפץ חיים'), contains('rp:4'));
  });

  test('מחבר עם שם רב-מילים', () async {
    expect(await search('נודע ביהודה'), contains('rp:3'));
  });

  test('חיפוש מחבר מחזיר את כל ספריו', () async {
    final found = await search('מפרשים ופוסקים על הבבלי');
    expect(found, containsAll(['rp:1', 'rp:2']));
  });

  test('חיפוש כותרת ממשיך לעבוד לצד חיפוש המחבר', () async {
    expect(await search('יבמות'), contains('rp:2'));
  });

  test('שם מחבר שאינו בקטלוג אינו מחזיר דבר', () async {
    expect(await search('מחבר שאינו קיים'), isEmpty);
  });

  /// חלק מהספרים מקבלים שדה מחבר מקובץ העזרה, והוא חייב להיות בר-חיפוש
  /// בדיוק כמו שם שיושב בנתיב.
  test('מחבר שנקרא מקובץ העזרה נמצא בחיפוש', () async {
    repository.responsaBooks = Future.value([
      ExternalLibraryBook(
        title: 'שו"ת אבני נזר חלק אורח חיים',
        id: 7,
        link: null,
        author: 'רבי אברהם בורנשטיין (פולין המאה ה- 19)',
        externalLibraryId: 'rp:7',
      ),
    ]);

    expect(await search('בורנשטיין'), ['rp:7']);
    // ולא כל שאילתה מחזירה אותו.
    expect(await search('סופר'), isEmpty);
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    return value is T ? value : defaultValue;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;
}
