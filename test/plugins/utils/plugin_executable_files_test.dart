import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/utils/plugin_executable_files.dart';

void main() {
  test('קבצי הרצה והתקנה מזוהים בלי תלות ברישיות', () {
    for (final name in [
      'OtzariaAIProxy.exe',
      'SETUP.MSI',
      'run.bat',
      'ai_proxy.py',
      'install.ps1',
      'app.apk',
      'tool.AppImage',
    ]) {
      expect(isPluginBlockedExecutable(name), isTrue, reason: name);
    }
  });

  test('נקודות ורווחים בסוף השם אינם מסתירים את הסיומת', () {
    expect(isPluginBlockedExecutable('proxy.exe.'), isTrue);
    expect(isPluginBlockedExecutable('proxy.exe . '), isTrue);
  });

  test('תיקיות רגילות מותרות וחבילות app/pkg נשארות חסומות', () {
    for (final extension in pluginBlockedExecutableExtensions) {
      expect(
        isPluginBlockedExecutable('documents.$extension', isDirectory: true),
        extension == 'app' || extension == 'pkg',
        reason: extension,
      );
    }
    expect(isPluginBlockedExecutable('Tool.APP . ', isDirectory: true), isTrue);
    expect(isPluginBlockedExecutable('notes.txt', isDirectory: true), isFalse);
  });

  test('נתיב מלא נבדק לפי שם הקובץ', () {
    expect(isPluginBlockedExecutable(r'C:\Users\a\Downloads\x.exe'), isTrue);
    expect(isPluginBlockedExecutable('/home/a/x.sh'), isTrue);
    expect(isPluginBlockedExecutable(r'C:\tools.exe\notes.txt'), isFalse);
  });

  test('מסמכים ושמות בלי סיומת מותרים', () {
    for (final name in [
      'חידושים.docx',
      'book.pdf',
      'notes.txt',
      'export.json',
      'proxy.exe.txt',
      'exe',
      '',
    ]) {
      expect(isPluginBlockedExecutable(name), isFalse, reason: name);
    }
  });
}
