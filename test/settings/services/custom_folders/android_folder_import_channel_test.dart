import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/custom_folders/android_folder_import_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const importer = AndroidFolderImportChannel();
  final calls = <MethodCall>[];

  void mockChannel(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidFolderImportChannel.channel, (
          call,
        ) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidFolderImportChannel.channel, null);
  });

  test('ביטול העתקה נשלח לערוץ והתוצאה מסומנת כמבוטלת', () async {
    mockChannel(
      (call) => call.method == 'copyTree'
          ? {'copied': <String>[], 'errors': <Map>[], 'cancelled': true}
          : null,
    );

    await importer.cancelCopy();
    final result = await importer.copyFolder('content://tree/x', '/d', ['txt']);

    expect(calls.first.method, 'cancelCopy');
    expect(result.cancelled, isTrue);
  });

  test('ביטול בבורר מחזיר null', () async {
    mockChannel((_) => null);

    expect(await importer.pickFolder(), isNull);
    expect(calls.single.method, 'pickTree');
  });

  test('תיקייה שנבחרה מחזירה URI ושם', () async {
    mockChannel(
      (_) => {'uri': 'content://tree/primary%3ABooks', 'name': 'Books'},
    );

    final folder = await importer.pickFolder();

    expect(folder!.uri, 'content://tree/primary%3ABooks');
    expect(folder.name, 'Books');
  });

  test('סריקה מעבירה URI וסיומות ומחזירה ספירה וגודל', () async {
    mockChannel((_) => {'fileCount': 3, 'totalBytes': 5000000000});

    final scan = await importer.scanFolder('content://tree/x', ['pdf', 'txt']);

    expect(scan.fileCount, 3);
    expect(scan.totalBytes, 5000000000);
    expect(calls.single.method, 'scanTree');
    expect(calls.single.arguments, {
      'uri': 'content://tree/x',
      'extensions': ['pdf', 'txt'],
    });
  });

  test('העתקה מחזירה נתיבים שהועתקו ושגיאות לפי קובץ', () async {
    mockChannel(
      (_) => {
        'copied': ['/data/books/Books/a.txt'],
        'errors': [
          {'path': 'sub/b.pdf', 'message': 'No space left on device'},
        ],
      },
    );

    final result = await importer.copyFolder(
      'content://tree/x',
      '/data/books/Books',
      ['txt'],
    );

    expect(result.copiedPaths, ['/data/books/Books/a.txt']);
    expect(result.errors.single.path, 'sub/b.pdf');
    expect(result.errors.single.message, 'No space left on device');
    expect(result.cancelled, isFalse);
    expect(calls.single.arguments, {
      'uri': 'content://tree/x',
      'destDir': '/data/books/Books',
      'extensions': ['txt'],
    });
  });
}
