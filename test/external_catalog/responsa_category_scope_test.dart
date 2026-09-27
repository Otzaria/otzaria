import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// בלי סינון לפי קטגוריה כל ספרי בר אילן מצטרפים לכל חיפוש מקומי, גם בתוך
/// `תנ״ך`, ומציפים את תוצאות הספרים שבאמת שם.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ExternalLibraryBook book(String title, String heCategories, int id) =>
      ExternalLibraryBook(
        title: title,
        id: id,
        link: null,
        heCategories: heCategories,
        externalLibraryId: 'rp:$id',
      );

  Category category(String title, {Category? parent}) {
    final created = Category(
      title: title,
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: parent,
    );
    parent?.subCategories.add(created);
    return created;
  }

  late DataRepository repository;

  setUpAll(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  setUp(() {
    repository = DataRepository()
      ..library = Future.value(Library(categories: []))
      ..localHebrewBooks = Future.value(const [])
      ..responsaBooks = Future.value([
        // `ספרי שאלות ותשובות (שו"ת)` → `שו״ת`
        book('אבני נזר', 'ספרי שאלות ותשובות (שו"ת)', 1),
        // `ספרות חז"ל > מדרשי אגדה` → `מדרש/אגדה`
        book('אבני מדרש', 'ספרות חז"ל > מדרשי אגדה', 2),
        // מדף שאין לו שיוך כלל
        book('אבני יתום', 'מדף שנוסף במהדורה הבאה', 3),
      ]);
  });

  Future<List<String>> inCategory(Category? scope) async {
    final found = await repository.findBooks(
      'אבני',
      scope,
      includeResponsa: true,
    );
    return found.map((b) => b.externalLibraryId!).toList()..sort();
  }

  test('בלי קטגוריה — כל הספרים, כולל מדף שאין לו שיוך', () async {
    expect(await inCategory(null), ['rp:1', 'rp:2', 'rp:3']);
  });

  test('בתוך קטגוריה — רק מה ששויך אליה', () async {
    expect(await inCategory(category('שו״ת')), ['rp:1']);
  });

  test('קטגוריית אב כוללת את מה שמתחתיה', () async {
    final midrash = category('מדרש');
    final agada = category('אגדה', parent: midrash);
    expect(await inCategory(midrash), ['rp:2']);
    expect(await inCategory(agada), ['rp:2']);
  });

  test('קטגוריה שאין בה ספרי בר אילן מחזירה ריק', () async {
    expect(await inCategory(category('תנ״ך')), isEmpty);
  });

  /// `/הלכה` אינו אב של `/הלכות` — השוואת תחילית בלי המפריד הייתה
  /// מכניסה אותו.
  test('שם קטגוריה שהוא תחילית של אחרת אינו נחשב אב', () async {
    repository.responsaBooks = Future.value([
      book('אבני הלכות', 'ספרי הלכה ומנהג', 4),
    ]);
    final target = await inCategory(category('הלכה'));
    expect(target, ['rp:4']);
    expect(await inCategory(category('הל')), isEmpty);
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
