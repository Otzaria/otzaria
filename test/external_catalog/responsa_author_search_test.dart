import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// חיפוש מחבר בספרי פרויקט השו"ת.
///
/// **למאגר אין שדה מחבר.** `FILE07`, שהוא מסד המטא-דאטה של התוכנה, ריק
/// בהתקנה (27 בייטים לא-אפס מתוך 1.47MB), ואין מקור אחר. אבל שם המחבר
/// כן קיים — כרכיב בנתיב עץ הקטלוג.
///
/// נמדד על קטלוג אמיתי בן 8,523 ספרים: `מהרש"א` מופיע ב-78 ספרים בנתיב
/// וב**אפס** כותרות; `נודע ביהודה` ב-9 ובאפס; `רמב"ם` ב-359 מול 14.
/// כלומר בלי חיפוש ההקשר, מחברים שלמים אינם ניתנים לאיתור.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataRepository repository;

  /// ספר כפי שהקטלוג בונה אותו: הכותרת היא שם המסכת, והמחבר הוא רכיב
  /// בנתיב.
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
        book(
          title: 'בבא בתרא',
          refPath: 'מפרשים ופוסקים על הבבלי > מהרש"א > בבא בתרא',
          id: 1,
        ),
        book(
          title: 'יבמות',
          refPath: 'מפרשים ופוסקים על הבבלי > רא"ש > יבמות',
          id: 2,
        ),
        book(
          title: 'מהדורא קמא - אורח חיים',
          refPath: 'שו"ת > נודע ביהודה > מהדורא קמא - אורח חיים',
          id: 3,
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

  test('מחבר שאינו מופיע באף כותרת — נמצא דרך ההקשר', () async {
    // "מהרש"א" אינו בכותרת של אף אחד מספריו. בלי ההקשר הוא אבוד.
    expect(await search('מהרש"א'), contains('rp:1'));
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

  test('שדה המחבר נשאר ריק — אין לו מקור, ואין להמציא לו ערך', () async {
    final books = await repository.responsaBooks;
    expect(books.every((b) => b.author == null), isTrue);
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
