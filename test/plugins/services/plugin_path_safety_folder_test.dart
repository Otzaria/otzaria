import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_path_safety.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_folder_safety');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('תיקייה רגילה מאושרת', () async {
    final folder = await Directory(p.join(tempDir.path, 'data')).create();
    expect(
      await pluginFolderRejectionReason(
        folder.path,
        protectedRoots: const [],
        exactOnlyFolders: const [],
      ),
      isNull,
    );
  });

  test('שורש כונן נדחה', () async {
    final root = p.rootPrefix(p.absolute(tempDir.path));
    expect(
      await pluginFolderRejectionReason(
        root,
        protectedRoots: const [],
        exactOnlyFolders: const [],
      ),
      isNotNull,
    );
  });

  test('תיקיית הבית עצמה נדחית אך תת-תיקייה שלה מותרת', () async {
    final home = await Directory(p.join(tempDir.path, 'home')).create();
    final documents = await Directory(p.join(home.path, 'docs')).create();

    expect(
      await pluginFolderRejectionReason(
        home.path,
        protectedRoots: const [],
        exactOnlyFolders: [home.path],
      ),
      isNotNull,
    );
    expect(
      await pluginFolderRejectionReason(
        documents.path,
        protectedRoots: const [],
        exactOnlyFolders: [home.path],
      ),
      isNull,
    );
  });

  test('תיקייה מוגנת נדחית גם עבור תת-תיקייה שלה', () async {
    final protectedRoot = await Directory(
      p.join(tempDir.path, 'program files'),
    ).create();
    final inner = await Directory(p.join(protectedRoot.path, 'app')).create();

    expect(
      await pluginFolderRejectionReason(
        protectedRoot.path,
        protectedRoots: [protectedRoot.path],
        exactOnlyFolders: const [],
      ),
      isNotNull,
    );
    expect(
      await pluginFolderRejectionReason(
        inner.path,
        protectedRoots: [protectedRoot.path],
        exactOnlyFolders: const [],
      ),
      isNotNull,
    );
  });

  test('path-traversal אל תוך תיקייה מוגנת נדחה', () async {
    final protectedRoot = await Directory(
      p.join(tempDir.path, 'otzaria_data'),
    ).create();
    final sibling = await Directory(p.join(tempDir.path, 'other')).create();

    expect(
      await pluginFolderRejectionReason(
        p.join(sibling.path, '..', 'otzaria_data', 'books'),
        protectedRoots: [protectedRoot.path],
        exactOnlyFolders: const [],
      ),
      isNotNull,
    );
  });

  test('symlink שמצביע לתוך תיקייה מוגנת נדחה', () async {
    final protectedRoot = await Directory(
      p.join(tempDir.path, 'otzaria_data'),
    ).create();
    await Directory(p.join(protectedRoot.path, 'books')).create();
    final linkPath = p.join(tempDir.path, 'shortcut');
    try {
      await Link(linkPath).create(p.join(protectedRoot.path, 'books'));
    } on FileSystemException {
      return; // אין הרשאת יצירת symlink (Windows ללא Developer Mode)
    }

    expect(
      await pluginFolderRejectionReason(
        linkPath,
        protectedRoots: [protectedRoot.path],
        exactOnlyFolders: const [],
      ),
      isNotNull,
    );
  });

  test('יעד חדש שטרם נוצר מתחת ל-symlink מוגן נדחה', () async {
    final protectedRoot = await Directory(
      p.join(tempDir.path, 'otzaria_data'),
    ).create();
    final linkPath = p.join(tempDir.path, 'shortcut');
    try {
      await Link(linkPath).create(protectedRoot.path);
    } on FileSystemException {
      return;
    }

    expect(
      await pluginFolderRejectionReason(
        p.join(linkPath, 'new', 'nested'),
        protectedRoots: [protectedRoot.path],
        exactOnlyFolders: const [],
      ),
      isNotNull,
    );
  });

  test(
    'נתיב UNC נדחה',
    () async {
      for (final path in [r'\\localhost\c$\Windows', '//localhost/c\$']) {
        expect(
          await pluginFolderRejectionReason(
            path,
            protectedRoots: const [],
            exactOnlyFolders: const [],
          ),
          contains('רשת'),
        );
      }
    },
    skip: !Platform.isWindows,
  );

  test('שורשי ההגנה כוללים את תיקיית ההרצה של האפליקציה', () async {
    final roots = await pluginProtectedFolderRoots();
    expect(roots, contains(p.dirname(Platform.resolvedExecutable)));
  });

  test('שורשי ההגנה כוללים את נתיב הספרייה שהמשתמש הזיז', () async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
    final movedLibrary = await Directory(
      p.join(tempDir.path, 'MovedLibrary', 'books'),
    ).create(recursive: true);
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      movedLibrary.path,
    );

    final roots = await pluginProtectedFolderRoots();
    expect(roots, contains(movedLibrary.path));
    expect(roots, contains(p.dirname(movedLibrary.path)));

    expect(
      await pluginFolderRejectionReason(
        movedLibrary.path,
        protectedRoots: roots,
        exactOnlyFolders: const [],
      ),
      isNotNull,
    );
  });

  test('שורשי ההגנה מכסים את תיקיות ההפעלה-אוטומטית של מערכת ההפעלה', () async {
    final roots = await pluginProtectedFolderRoots();
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        expect(
          roots,
          contains(
            p.join(
              appData,
              'Microsoft',
              'Windows',
              'Start Menu',
              'Programs',
              'Startup',
            ),
          ),
        );
      }
    } else {
      expect(roots, containsAll(<String>['/etc', '/usr', '/bin']));
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        expect(roots, contains(p.join(home, '.ssh')));
        expect(roots, contains(p.join(home, '.config')));
      }
    }
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

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
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) =>
      _values[key] as T? ?? defaultValue;

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}
