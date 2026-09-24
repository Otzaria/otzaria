import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';

/// ספרי פרויקט השו"ת נכנסים לאותו מסלול חיפוש של שאר הספרייה.
/// הבדיקה נועלת שני דברים: שהם מופיעים רק כשהספק מופעל, ושההקשר
/// מהנתיב בעץ נחשב בחיפוש — בלעדיו כותרת כמו "יבמות" אינה ניתנת לאיתור.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataRepository repository;

  ExternalLibraryBook responsaBook() => ExternalLibraryBook(
    title: 'יבמות',
    id: 1524,
    link: null,
    categoryPath: 'מפרשים ופוסקים על הבבלי/רא"ש',
    externalLibraryId: 'rp:1524',
  );

  ExternalLibraryBook otzarBook() => ExternalLibraryBook(
    title: 'ספר אוצר החכמה',
    id: 42,
    link: 'https://tablet.otzar.org/book/book.php?book=42',
    externalLibraryId: 'oh:42',
  );

  setUpAll(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  setUp(() {
    repository = DataRepository()
      ..library = Future.value(Library(categories: []))
      ..responsaBooks = Future.value([responsaBook()])
      ..otzarBooks = Future.value([otzarBook()])
      ..localHebrewBooks = Future.value(const []);
  });

  test('הספק כבוי — ספרי פרויקט השו"ת אינם מופיעים', () async {
    final found = await repository.findBooks('יבמות', null);

    expect(found, isEmpty);
  });

  test('הספק מופעל — הספר מופיע עם המזהה הנכון', () async {
    final found = await repository.findBooks(
      'יבמות',
      null,
      includeResponsa: true,
    );

    expect(found, hasLength(1));
    expect(found.single.externalLibraryId, 'rp:1524');
  });

  test('חיפוש לפי ההקשר מוצא את הספר, לא רק לפי הכותרת', () async {
    // "רא\"ש" אינו בכותרת — הוא בנתיב בעץ. בלי ההקשר הספר אבוד.
    final found = await repository.findBooks(
      'רא"ש',
      null,
      includeResponsa: true,
    );

    expect(found.map((b) => b.externalLibraryId), contains('rp:1524'));
  });

  test('שאילתה שאינה תואמת אינה מחזירה דבר', () async {
    final found = await repository.findBooks(
      'ספר שאינו קיים כלל',
      null,
      includeResponsa: true,
    );

    expect(found, isEmpty);
  });

  /// שני הספקים מוזרקים, ורק אחד מופעל. בלי ההזרקה של אוצר החכמה
  /// הבדיקה לא הייתה יכולה להיכשל: אין ספר כזה במרחב החיפוש.
  test('הפעלת פרויקט השו"ת אינה מכניסה ספרים של ספק אחר', () async {
    expect(
      await repository.findBooks(
        otzarBook().title,
        null,
        includeResponsa: true,
      ),
      isEmpty,
    );
    // ולראיה שהספר אכן במרחב: עם הדגל שלו הוא נמצא.
    expect(
      (await repository.findBooks(
        otzarBook().title,
        null,
        includeOtzar: true,
      )).single.externalLibraryId,
      'oh:42',
    );
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
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }
}
