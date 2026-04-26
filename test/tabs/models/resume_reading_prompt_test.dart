import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  test('שומר מיקום המשך בטאב של ספר טקסט', () {
    final tab = OpenedTab.fromBook(
      TextBook(title: 'ספר בדיקה'),
      0,
      resumeIndex: 42,
      resumeRef: 'ספר בדיקה, פרק ב',
    );

    expect(tab, isA<TextBookTab>());
    final textTab = tab as TextBookTab;
    expect(textTab.index, 0);
    expect(textTab.resumeIndex, 42);
    expect(textTab.resumeRef, 'ספר בדיקה, פרק ב');
  });

  test('שומר מיקום המשך בטאב של PDF', () {
    final tab = OpenedTab.fromBook(
      PdfBook(title: 'PDF בדיקה', path: 'book.pdf'),
      1,
      resumeIndex: 9,
      resumeRef: 'PDF בדיקה עמוד 9',
    );

    expect(tab, isA<PdfBookTab>());
    final pdfTab = tab as PdfBookTab;
    expect(pdfTab.pageNumber, 1);
    expect(pdfTab.resumePageNumber, 9);
    expect(pdfTab.resumeRef, 'PDF בדיקה עמוד 9');
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  bool containsKey(String key) => _values.containsKey(key);

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
  Set getKeys() => _values.keys.toSet();

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
  Future<void> init() async {}

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
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
