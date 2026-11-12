import 'dart:convert';
import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_user_folder_grants.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:path/path.dart' as p;

import '../../test_helpers/memory_cache_provider.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

/// KV והרשאות בזיכרון. משותף בין מופעי אדפטר, כדי לדמות reload של התוסף.
class _Registry extends PluginRegistryRepository {
  final Map<String, String> kv = {};
  final Map<String, bool> permissions = {
    'fs.user_files.read': true,
    'fs.user_files.write': true,
    'library.content.read': true,
  };

  @override
  Future<bool?> getPermission(String pluginId, String permission) async =>
      permissions[permission];

  @override
  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async => kv['$namespace/$key'] = valueJson;

  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      kv['$namespace/$key'];
}

InstalledPlugin _plugin() => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'Test Plugin',
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const [
      'fs.user_files.read',
      'fs.user_files.write',
      'library.content.read',
    ],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Test',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Matcher _throwsCode(String code) => throwsA(
  isA<Exception>().having((e) => e.toString(), 'message', contains(code)),
);

Category _category(String title, {List<Book> books = const []}) => Category(
  title: title,
  description: '',
  shortDescription: '',
  order: 0,
  subCategories: [],
  books: [...books],
  parent: null,
);

void _attach(Category parent, List<Category> children) {
  for (final child in children) {
    child.parent = parent;
    parent.subCategories.add(child);
  }
}

void main() {
  late Directory temp;
  late _Registry registry;
  late PluginFileServer fileServer;
  late HttpClient client;
  String? pickedFolder;
  var folderPickerCalls = 0;
  var consent = true;
  final consentDialogs = <({String title, String content, String subtitle})>[];

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('doc_folders_test_');
    registry = _Registry();
    fileServer = PluginFileServer();
    client = HttpClient();
    pickedFolder = null;
    folderPickerCalls = 0;
    consent = true;
    consentDialogs.clear();
  });

  tearDown(() async {
    client.close(force: true);
    await fileServer.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  PluginBridgeAdapter buildAdapter() => PluginBridgeAdapter(
    _plugin(),
    dependencies: PluginBridgeDependencies(
      historyBloc: _MockHistoryBloc(),
      tabsBloc: _MockTabsBloc(),
      navigationBloc: _MockNavigationBloc(),
      calendarCubit: _MockCalendarCubit(),
      workspaceBloc: _MockWorkspaceBloc(),
      searchRepository: _MockSearchRepository(),
      personalNotesRepository: _MockPersonalNotesRepository(),
      bookOpenCoordinator: _MockBookOpenCoordinator(),
      themePayloadBuilder: () => <String, dynamic>{},
      showConfirmDialog: ({required title, required content}) async => true,
      showWarningDialog:
          ({required title, required content, required subtitle}) async {
            consentDialogs.add((
              title: title,
              content: content,
              subtitle: subtitle,
            ));
            return consent;
          },
      pickFolder: ({title}) async {
        folderPickerCalls++;
        return pickedFolder;
      },
      pickFile: ({allowedExtensions, title}) async => null,
    ),
    pluginRepository: registry,
    fileServer: fileServer,
  );

  Future<String> fetch(String url) async {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    expect(response.statusCode, 200);
    return utf8.decode(await response.expand((c) => c).toList());
  }

  /// תיקייה מאושרת עם מבנה קטן: שני מסמכים, תת-תיקייה ושאריות שמסוננות.
  Future<({PluginBridgeAdapter adapter, String token, Directory root})>
  grantedFolder() async {
    final root = Directory(p.join(temp.path, 'שיעורים'))..createSync();
    File(p.join(root.path, 'בראשית.docx')).writeAsStringSync('docx-bytes');
    File(p.join(root.path, 'notes.txt')).writeAsStringSync('txt');
    File(p.join(root.path, r'~$בראשית.docx')).writeAsStringSync('lock');
    Directory(p.join(root.path, 'חורף')).createSync();
    File(p.join(root.path, 'חורף', 'נח.docx')).writeAsStringSync('noach');
    pickedFolder = root.path;
    final adapter = buildAdapter();
    final res = await adapter.execute('fs', 'pickUserFolder', {}) as Map;
    return (
      adapter: adapter,
      token: res['folderToken'] as String,
      root: root,
    );
  }

  group('fs.pickUserFolder', () {
    test('ביטול מחזיר {cancelled:true} בלי grant', () async {
      final res = await buildAdapter().execute('fs', 'pickUserFolder', {});
      expect(res, {'cancelled': true});
      expect(registry.kv['_internal/user_folder_grants'], isNull);
    });

    test('מחזיר folderToken, name ו-path ומתמיד את ה-grant', () async {
      final g = await grantedFolder();
      expect(g.token, isNotEmpty);
      final grants =
          jsonDecode(registry.kv['_internal/user_folder_grants']!) as Map;
      expect(grants.keys, [g.token]);

      pickedFolder = g.root.path;
      final again =
          await buildAdapter().execute('fs', 'pickUserFolder', {}) as Map;
      expect(again['cancelled'], isFalse);
      expect(again['folderToken'], g.token, reason: 'תיקייה שכבר אושרה');
      expect(again['name'], 'שיעורים');
      expect(
        p.equals(again['path'] as String, g.root.resolveSymbolicLinksSync()),
        isTrue,
      );
      expect(folderPickerCalls, 2);
      expect(
        consentDialogs,
        hasLength(1),
        reason: 'תיקייה שכבר אושרה חוזרת בלי דיאלוג ההסכמה',
      );
    });

    test('דיאלוג ההסכמה: קבוע, שם התוסף והתיקייה, ואישור מתמיד', () async {
      await grantedFolder();
      final dialog = consentDialogs.single;
      expect(dialog.title, 'גישה קבועה לתיקייה');
      expect(
        dialog.content,
        'התוסף „Test Plugin” מבקש גישה קבועה לתיקייה „שיעורים”: לקרוא ולכתוב '
        'בה גם בהפעלות הבאות של אוצריא, בלי לשאול שוב.',
      );
      expect(dialog.subtitle, 'אפשר לבטל את הגישה בכל עת בהגדרות התוסף.');
      expect(registry.kv['_internal/user_folder_grants'], isNotNull);
    });

    test('סירוב בדיאלוג ההסכמה — cancelled ושום דבר לא נשמר', () async {
      final root = Directory(p.join(temp.path, 'שיעורים'))..createSync();
      pickedFolder = root.path;
      consent = false;
      final res = await buildAdapter().execute('fs', 'pickUserFolder', {});
      expect(res, {'cancelled': true});
      expect(consentDialogs, hasLength(1));
      expect(registry.kv['_internal/user_folder_grants'], isNull);
    });

    test('תיקייה מוגנת נדחית ב-error.forbidden', () async {
      pickedFolder = p.dirname(Platform.resolvedExecutable);
      await expectLater(
        buildAdapter().execute('fs', 'pickUserFolder', {}),
        _throwsCode('error.forbidden'),
      );
      expect(registry.kv['_internal/user_folder_grants'], isNull);
    });
  });

  group('fs.listUserFolder', () {
    test('שורש: תיקיות קודם, סינון נעילה, ו-grant ששורד מופע חדש', () async {
      final g = await grantedFolder();
      // מופע אדפטר חדש = reload של התוסף; ה-grant נקרא מה-KV.
      final res =
          await buildAdapter().execute('fs', 'listUserFolder', {
                'folderToken': g.token,
              })
              as Map;
      expect(res['folderToken'], g.token);
      expect(res['name'], 'שיעורים');
      expect(res['path'], '');
      expect(res['truncated'], isFalse);
      final entries = (res['entries'] as List).cast<Map>();
      expect(entries.map((e) => e['name']), [
        'חורף',
        'notes.txt',
        'בראשית.docx',
      ]);
      expect(entries.first['type'], 'dir');
    });

    test('extensions ותת-תיקייה', () async {
      final g = await grantedFolder();
      final root =
          await g.adapter.execute('fs', 'listUserFolder', {
                'folderToken': g.token,
                'extensions': ['.DOCX'],
              })
              as Map;
      expect((root['entries'] as List).map((e) => e['name']), [
        'חורף',
        'בראשית.docx',
      ]);
      final sub =
          await g.adapter.execute('fs', 'listUserFolder', {
                'folderToken': g.token,
                'path': 'חורף',
              })
              as Map;
      expect(sub['path'], 'חורף');
      expect((sub['entries'] as List).single['path'], 'חורף/נח.docx');
    });

    test('.. ונתיב מוחלט נדחים ב-error.forbidden', () async {
      final g = await grantedFolder();
      for (final bad in ['..', 'חורף/../..', temp.path, '/']) {
        await expectLater(
          g.adapter.execute('fs', 'listUserFolder', {
            'folderToken': g.token,
            'path': bad,
          }),
          _throwsCode('error.forbidden'),
          reason: bad,
        );
      }
    });

    test('token לא מוכר ותיקייה שנעלמה — not_found, וה-grant נשמר', () async {
      final g = await grantedFolder();
      await expectLater(
        g.adapter.execute('fs', 'listUserFolder', {'folderToken': 'nope'}),
        _throwsCode('error.not_found: unknown folder token'),
      );
      await g.root.delete(recursive: true);
      await expectLater(
        g.adapter.execute('fs', 'listUserFolder', {'folderToken': g.token}),
        _throwsCode('error.not_found: folder no longer exists'),
      );
      final grants =
          jsonDecode(registry.kv['_internal/user_folder_grants']!) as Map;
      expect(grants.containsKey(g.token), isTrue);
    });

    test('החלפת תיקייה מאושרת בקישור אינה מעבירה את ההרשאה ליעד', () async {
      final g = await grantedFolder();
      final replacement = Directory(p.join(temp.path, 'replacement'))
        ..createSync();
      final otherFile = File(p.join(replacement.path, 'other.docx'))
        ..writeAsStringSync('other');
      await g.root.rename(p.join(temp.path, 'moved'));
      await Link(g.root.path).create(replacement.path);

      await expectLater(
        g.adapter.execute('fs', 'listUserFolder', {'folderToken': g.token}),
        _throwsCode('error.forbidden'),
      );
      await expectLater(
        g.adapter.execute('fs', 'deleteFile', {'path': otherFile.path}),
        _throwsCode('error.forbidden'),
      );
      expect(otherFile.existsSync(), isTrue);
    });
  });

  group('fs.openFolderFile', () {
    test('מחזיר צורת pickUserFile, מגיש את הקובץ ו-resolve עובד', () async {
      final g = await grantedFolder();
      final res =
          await g.adapter.execute('fs', 'openFolderFile', {
                'folderToken': g.token,
                'path': 'חורף/נח.docx',
              })
              as Map;
      expect(res.keys.toSet(), {
        'cancelled',
        'token',
        'url',
        'name',
        'size',
        'access',
      });
      expect(res['cancelled'], isFalse);
      expect(res['name'], 'נח.docx');
      expect(res['size'], 'noach'.length);
      expect(res['access'], 'read');
      expect(await fetch(res['url'] as String), 'noach');

      final resolved =
          await buildAdapter().execute('fs', 'resolveFileUrl', {
                'token': res['token'],
              })
              as Map;
      expect(await fetch(resolved['url'] as String), 'noach');
    });

    test('פתיחה חוזרת מחזירה אותו token; readwrite משדרג אותו', () async {
      final g = await grantedFolder();
      Future<Map> open(String access) async =>
          await g.adapter.execute('fs', 'openFolderFile', {
                'folderToken': g.token,
                'path': 'בראשית.docx',
                'access': access,
              })
              as Map;
      final first = await open('read');
      final second = await open('read');
      expect(second['token'], first['token']);
      final writable = await open('readwrite');
      expect(writable['token'], first['token']);
      expect(writable['access'], 'readwrite');
      // grant לכתיבה אינו מורד בפתיחה לקריאה.
      expect((await open('read'))['access'], 'readwrite');
      final grants =
          jsonDecode(registry.kv['_internal/user_file_grants']!) as Map;
      expect(grants, hasLength(1));
    });

    test('readwrite בלי fs.user_files.write נדחה', () async {
      final g = await grantedFolder();
      registry.permissions['fs.user_files.write'] = false;
      await expectLater(
        g.adapter.execute('fs', 'openFolderFile', {
          'folderToken': g.token,
          'path': 'בראשית.docx',
          'access': 'readwrite',
        }),
        _throwsCode('error.permission_denied'),
      );
    });

    test('תיקייה, קובץ חסר ויציאה מהשורש', () async {
      final g = await grantedFolder();
      File(p.join(temp.path, 'outside.docx')).writeAsStringSync('x');
      Future<void> expectCode(String path, String code) => expectLater(
        g.adapter.execute('fs', 'openFolderFile', {
          'folderToken': g.token,
          'path': path,
        }),
        _throwsCode(code),
        reason: path,
      );
      await expectCode('חורף', 'error.not_found');
      await expectCode('אין.docx', 'error.not_found');
      await expectCode('../outside.docx', 'error.forbidden');
      await expectCode(p.join(temp.path, 'outside.docx'), 'error.forbidden');
    });
  });

  test(
    'fs.revokeFolder מסיר את התיקייה, אידמפוטנטי, ואינו נוגע בקבצים',
    () async {
      final g = await grantedFolder();
      final file =
          await g.adapter.execute('fs', 'openFolderFile', {
                'folderToken': g.token,
                'path': 'בראשית.docx',
              })
              as Map;
      expect(
        await g.adapter.execute('fs', 'revokeFolder', {'folderToken': g.token}),
        isTrue,
      );
      expect(
        await g.adapter.execute('fs', 'revokeFolder', {'folderToken': g.token}),
        isTrue,
      );
      await expectLater(
        g.adapter.execute('fs', 'listUserFolder', {'folderToken': g.token}),
        _throwsCode('error.not_found: unknown folder token'),
      );
      final resolved =
          await g.adapter.execute('fs', 'resolveFileUrl', {
                'token': file['token'],
              })
              as Map;
      expect(resolved['token'], file['token']);
    },
  );

  group('גישה קבועה כוללת את ההרשאה של ui.pickFolder', () {
    test(
      'אחרי מופע חדש: מחיקה והעברה בתוך התיקייה מותרות, מחוצה לה לא',
      () async {
        final g = await grantedFolder();
        final outside = File(p.join(temp.path, 'outside.txt'))
          ..writeAsStringSync('x');

        // מופע חדש = הפעלה מחדש; אין ui.pickFolder בריצה הזו.
        final adapter = buildAdapter();
        final notes = p.join(g.root.path, 'notes.txt');
        expect(
          await adapter.execute('fs', 'deleteFile', {'path': notes}),
          isTrue,
        );
        expect(File(notes).existsSync(), isFalse);
        expect(
          await adapter.execute('fs', 'moveEntry', {
            'from': p.join(g.root.path, 'בראשית.docx'),
            'to': p.join(g.root.path, 'חורף', 'בראשית.docx'),
          }),
          isTrue,
        );
        expect(
          File(p.join(g.root.path, 'חורף', 'בראשית.docx')).existsSync(),
          isTrue,
        );

        await expectLater(
          adapter.execute('fs', 'deleteFile', {'path': outside.path}),
          _throwsCode('error.forbidden'),
        );
        await expectLater(
          adapter.execute('fs', 'moveEntry', {
            'from': p.join(g.root.path, 'חורף', 'נח.docx'),
            'to': p.join(temp.path, 'נח.docx'),
          }),
          _throwsCode('error.forbidden'),
        );
        expect(outside.existsSync(), isTrue);
        expect(consentDialogs, hasLength(1));
      },
    );

    test('revokeFolder מסיר גם את הקבועה וגם את זו של ui.pickFolder', () async {
      final g = await grantedFolder();
      pickedFolder = g.root.path;
      expect(
        await g.adapter.execute('ui', 'pickFolder', {}),
        {'path': g.root.path},
      );
      await g.adapter.execute('fs', 'revokeFolder', {'folderToken': g.token});

      final notes = p.join(g.root.path, 'notes.txt');
      await expectLater(
        g.adapter.execute('fs', 'deleteFile', {'path': notes}),
        _throwsCode('error.forbidden'),
      );
      await expectLater(
        buildAdapter().execute('fs', 'deleteFile', {'path': notes}),
        _throwsCode('error.forbidden'),
      );
      expect(File(notes).existsSync(), isTrue);
    });

    test('ביטול חיצוני (מסך ההגדרות) חל על מופע שכבר רץ', () async {
      final g = await grantedFolder();
      pickedFolder = g.root.path;
      await g.adapter.execute('ui', 'pickFolder', {});
      final otherAdapter = buildAdapter();
      await otherAdapter.execute('ui', 'pickFolder', {});
      final notes = p.join(g.root.path, 'notes.txt');
      await PluginUserFolderGrants(registry).revoke('test.plugin', g.token);
      await expectLater(
        g.adapter.execute('fs', 'deleteFile', {'path': notes}),
        _throwsCode('error.forbidden'),
      );
      await expectLater(
        otherAdapter.execute('fs', 'deleteFile', {'path': notes}),
        _throwsCode('error.forbidden'),
      );
    });
  });

  group('library.getTree types / library.openBookFile', () {
    late File personalDocx;
    late File libraryDocx;
    late DocxBook personal;
    late DocxBook official;
    late TextBook text;

    setUp(() {
      personalDocx = File(p.join(temp.path, 'אישי.docx'))
        ..writeAsStringSync('personal');
      libraryDocx = File(p.join(temp.path, 'ספרייה.docx'))
        ..writeAsStringSync('library');
      personal = DocxBook(
        id: 7,
        title: 'אישי',
        path: personalDocx.path,
        filePath: personalDocx.path,
        source: BookSource.user,
      );
      official = DocxBook(
        id: 8,
        title: 'ספרייה',
        path: libraryDocx.path,
        filePath: libraryDocx.path,
      );
      text = TextBook(id: 9, title: 'בראשית', fileType: 'txt');
      final tanach = _category('תנך', books: [text]);
      final torah = _category('תורה', books: [text]);
      final mine = _category('ספרים אישיים');
      final lessons = _category('שיעורים', books: [personal]);
      final halacha = _category('הלכה', books: [official]);
      _attach(tanach, [torah]);
      _attach(mine, [lessons]);
      final library = Library(categories: []);
      _attach(library, [tanach, mine, halacha]);
      DataRepository.instance.library = Future.value(library);
    });

    test('types גוזם ענפים בלי ספרים מתאימים', () async {
      final tree =
          await buildAdapter().execute('library', 'getTree', {
                'types': ['DOCX'],
              })
              as Map;
      final top = (tree['categories'] as List).cast<Map>();
      expect(top.map((c) => c['title']), ['ספרים אישיים', 'הלכה']);
      final lessons = (top.first['categories'] as List).single as Map;
      expect(lessons['path'], '/ספרים אישיים/שיעורים');
      expect((lessons['books'] as List).single['title'], 'אישי');
      expect(top.first['books'], isEmpty);

      final noBooks =
          await buildAdapter().execute('library', 'getTree', {
                'types': ['docx'],
                'includeBooks': false,
              })
              as Map;
      expect((noBooks['categories'] as List).length, 2);
      expect(noBooks.containsKey('books'), isFalse);

      final empty =
          await buildAdapter().execute('library', 'getTree', {
                'path': '/תנך',
                'types': ['docx'],
              })
              as Map;
      expect(empty['title'], 'תנך');
      expect(empty['categories'], isEmpty);
      expect(empty['books'], isEmpty);

      final full =
          await buildAdapter().execute('library', 'getTree', const {}) as Map;
      expect((full['categories'] as List).length, 3, reason: 'בלי types');
    });

    test('ספר אישי: readwrite, אותו token כמו פתיחה מתיקייה', () async {
      final adapter = buildAdapter();
      final res =
          await adapter.execute('library', 'openBookFile', {
                'bookUid': PluginBookIdentity.uidOf(personal),
                'access': 'readwrite',
              })
              as Map;
      expect(res.keys.toSet(), {
        'token',
        'url',
        'name',
        'size',
        'access',
        'source',
      });
      expect(res['source'], 'user');
      expect(res['access'], 'readwrite');
      expect(res['name'], 'אישי.docx');
      expect(await fetch(res['url'] as String), 'personal');

      pickedFolder = temp.path;
      final folder = await adapter.execute('fs', 'pickUserFolder', {}) as Map;
      final fromFolder =
          await adapter.execute('fs', 'openFolderFile', {
                'folderToken': folder['folderToken'],
                'path': 'אישי.docx',
              })
              as Map;
      expect(fromFolder['token'], res['token']);
      expect(fromFolder['access'], 'readwrite');
    });

    test('ספר הספרייה: קריאה בלבד', () async {
      final adapter = buildAdapter();
      await expectLater(
        adapter.execute('library', 'openBookFile', {
          'bookId': 'ספרייה',
          'type': 'docx',
          'access': 'readwrite',
        }),
        _throwsCode('error.permission_denied: library books are read-only'),
      );
      final res =
          await adapter.execute('library', 'openBookFile', {
                'id': 8,
                'type': 'docx',
              })
              as Map;
      expect(res['source'], 'library');
      expect(res['access'], 'read');
      expect(await fetch(res['url'] as String), 'library');
    });

    test('readwrite לספר אישי בלי fs.user_files.write נדחה', () async {
      registry.permissions['fs.user_files.write'] = false;
      await expectLater(
        buildAdapter().execute('library', 'openBookFile', {
          'bookUid': PluginBookIdentity.uidOf(personal),
          'access': 'readwrite',
        }),
        _throwsCode('error.permission_denied: fs.user_files.write'),
      );
    });

    test('ספר טקסט, ספר לא מוכר וקובץ שנמחק', () async {
      final adapter = buildAdapter();
      await expectLater(
        adapter.execute('library', 'openBookFile', {
          'bookUid': PluginBookIdentity.uidOf(text),
        }),
        _throwsCode('error.unsupported'),
      );
      await expectLater(
        adapter.execute('library', 'openBookFile', {'bookId': 'אין כזה'}),
        _throwsCode('error.not_found'),
      );
      await expectLater(
        adapter.execute('library', 'openBookFile', const {}),
        _throwsCode('error.invalid_params'),
      );
      libraryDocx.deleteSync();
      await expectLater(
        adapter.execute('library', 'openBookFile', {'id': 8, 'type': 'docx'}),
        _throwsCode('error.not_found'),
      );
    });
  });
}
