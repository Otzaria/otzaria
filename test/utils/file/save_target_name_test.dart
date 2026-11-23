import 'package:otzaria/utils/file/save_target_name.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('empty and invalid characters keep the common filename policy', () {
    expect(saveTargetFileName('   ', 'pdf'), 'מסמך.pdf');
    expect(saveTargetFileName(null, null), 'מסמך');
    expect(saveTargetFileName('a/b\\c:d*e?f"g<h>i|j', 'pdf'), 'abcdefghij.pdf');
  });

  test('leading dots and extension case never append a duplicate suffix', () {
    expect(saveTargetFileName('Report.PDF', '.PDF'), 'Report.PDF');
    expect(saveTargetFileName('Report', '.PDF'), 'Report.pdf');
    expect(saveTargetFileName('Report.txt', 'pdf'), 'Report.txt.pdf');
    expect(() => saveTargetFileName('Report', '../pdf'), throwsArgumentError);
  });

  test('filename cannot escape the selected directory', () {
    final folder = p.join(p.separator, 'tmp', 'documents');
    for (final name in [
      '.',
      '..',
      p.join('..', 'outside.pdf'),
      'nested/file.pdf',
    ]) {
      expect(saveTargetPath(folder: folder, fileName: name), isNull);
    }
    expect(
      saveTargetPath(folder: folder, fileName: 'file.pdf'),
      p.join(folder, 'file.pdf'),
    );
  });

  test('the native dialog always identifies folder selection', () {
    expect(saveTargetFolderDialogTitle('  ייצוא  '), 'בחירת תיקייה — ייצוא');
    expect(saveTargetFolderDialogTitle(null), 'בחירת תיקייה לשמירת הקובץ');
  });
}
