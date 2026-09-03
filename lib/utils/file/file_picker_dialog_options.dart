import 'package:file_picker/file_picker.dart';

/// דיאלוגי המערכת נפתחים מודאליים מעל חלון האפליקציה. ההגדרה נפרדת לכל
/// פלטפורמה, ושתיהן חייבות להיקבע יחד — אחרת הדיאלוג מודאלי רק באחת מהן.
const kModalWindowsOptions = WindowsOptions(lockParentWindow: true);
const kModalLinuxOptions = LinuxOptions(lockParentWindow: true);
