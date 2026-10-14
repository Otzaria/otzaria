import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/view/plugin_data_folder_unwritable_view.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:path/path.dart' as p;

/// עוטף ווידג'ט בסביבת אפליקציה מינימלית (הכיוון RTL כמו באפליקציה).
Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('he', 'IL'),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

void main() {
  group(
    'checkDataFolderWritable — זיהוי תיקיית נתונים חסומה (issue #1031)',
    () {
      late Directory root;

      setUp(() {
        root = Directory.systemTemp.createTempSync('otzaria_wv_probe');
        AppPaths.debugOverrideDataRootPath(root.path);
      });

      tearDown(() {
        AppPaths.debugOverrideDataRootPath(null);
        WebViewEnvironmentHolder.debugClearUnwritableDataFolder();
        if (root.existsSync()) root.deleteSync(recursive: true);
      });

      test(
        'תיקייה כתיבה — null, ובלי שאריות של קובץ הבדיקה',
        () async {
          expect(
            await WebViewEnvironmentHolder.checkDataFolderWritable(),
            isNull,
          );
          expect(WebViewEnvironmentHolder.unwritableDataFolder, isNull);
          expect(Directory(p.join(root.path, 'webview2')).listSync(), isEmpty);
        },
        skip: !Platform.isWindows,
      );

      test('נתיב שאינו תיקייה — מוחזר כחסום', () async {
        File(p.join(root.path, 'webview2')).writeAsStringSync('');

        expect(
          await WebViewEnvironmentHolder.checkDataFolderWritable(),
          p.join(root.path, 'webview2'),
        );
      }, skip: !Platform.isWindows);

      test('EBWebView חסומה בעוד תיקיית האם תקינה', () async {
        final webview2 = Directory(p.join(root.path, 'webview2'))
          ..createSync(recursive: true);
        File(p.join(webview2.path, 'EBWebView')).writeAsStringSync('');

        expect(
          await WebViewEnvironmentHolder.checkDataFolderWritable(),
          p.join(webview2.path, 'EBWebView'),
          reason:
              'ההרשאות החסומות יושבות על תת-התיקייה שיוצר WebView2 — '
              'בדיקת תיקיית האם בלבד מפספסת אותן',
        );
      }, skip: !Platform.isWindows);

      test('override של בדיקות עוקף את הדיסק', () async {
        WebViewEnvironmentHolder.debugOverrideUnwritableDataFolder(
          r'C:\blocked',
        );

        expect(
          await WebViewEnvironmentHolder.checkDataFolderWritable(),
          r'C:\blocked',
        );
        expect(WebViewEnvironmentHolder.unwritableDataFolder, r'C:\blocked');
      });

      test(
        'initialize בלי בדיקה מוקדמת (מארח הרקע) עוצר על תיקייה חסומה',
        () async {
          WebViewEnvironmentHolder.debugOverrideUnwritableDataFolder(
            r'C:\blocked',
          );

          await expectLater(
            WebViewEnvironmentHolder.initialize(),
            throwsA(
              isA<FileSystemException>().having(
                (e) => e.path,
                'path',
                r'C:\blocked',
              ),
            ),
          );
          expect(WebViewEnvironmentHolder.environment, isNull);
        },
        skip: !Platform.isWindows,
      );
    },
  );

  group('PluginDataFolderUnwritableView', () {
    testWidgets('מציג את הנתיב החסום ומאפשר בדיקה חוזרת', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _wrap(
          PluginDataFolderUnwritableView(
            folderPath: r'C:\Program Files\Otzaria\otzaria_data\webview2',
            onRetry: () => retries++,
          ),
        ),
      );

      expect(
        find.text(r'C:\Program Files\Otzaria\otzaria_data\webview2'),
        findsOneWidget,
      );

      await tester.tap(find.text('בדוק שוב'));
      await tester.pump();
      expect(retries, 1);
    });
  });
}
