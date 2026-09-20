import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_automation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_writer.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation_discovery.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_launcher.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_tree_reader.dart';

/// שלב בבניית הקטלוג, לתצוגה למשתמש.
enum ResponsaBuildStage { starting, scanning, classifying, done, failed }

class ResponsaBuildProgress {
  final ResponsaBuildStage stage;

  /// כמה צמתים נסרקו עד כה. בהתקנה מלאה מדובר בכ-1.25 מיליון.
  final int scannedNodes;

  /// כמה ספרים נמצאו. זמין רק בסיום.
  final int books;

  final String? error;

  const ResponsaBuildProgress({
    required this.stage,
    this.scannedNodes = 0,
    this.books = 0,
    this.error,
  });
}

/// בניית קטלוג פרויקט השו"ת — הליכה חיה בעץ ובנייה, באיזולט רקע.
///
/// הבנייה ארוכה מטבעה: היא סורקת את כל עץ הקטלוג של התוכנה, שהוא כ-1.25
/// מיליון צמתים, ולוקחת כ-6 דקות. לכן היא מדווחת התקדמות וניתנת לביטול
/// אמיתי.
///
/// **היא אינה רצה מאליה.** הקטלוג נבנה רק כשהמשתמש מבקש, או כשההתקנה
/// השתנתה והוא אישר בנייה מחדש.
class ResponsaCatalogBuildService {
  ResponsaCatalogBuildService();

  Pointer<Int32>? _cancelFlag;
  Isolate? _isolate;

  bool get isRunning => _isolate != null;

  /// מבטל בנייה שרצה. הביטול אמיתי — הסריקה נעצרת בנקודת הבדיקה הבאה.
  void cancel() {
    final flag = _cancelFlag;
    if (flag != null) flag.value = 1;
  }

  /// בונה את הקטלוג ומדווח התקדמות.
  ///
  /// [targetPath] הוא היעד הסופי; הבנייה עצמה נכתבת לקובץ צדדי ומוחלפת
  /// אטומית רק אחרי שעברה אימות.
  Stream<ResponsaBuildProgress> build({required String targetPath}) {
    final controller = StreamController<ResponsaBuildProgress>();
    // בנייה אחת בכל רגע **בכל האפליקציה**. שתי בניות כותבות לאותו קובץ
    // צדדי (`<target>.building`), והשנייה מוחקת את זה של הראשונה תוך
    // כדי כתיבה. זה קרה כשמשתמש יצא ממסך ההגדרות באמצע בנייה — המסך
    // ננטש, האיזולט המשיך, וחזרה למסך יצרה שירות חדש שמתחיל בנייה
    // שנייה מול אותה תוכנה ואותו קובץ.
    if (_active) {
      controller
        ..add(
          const ResponsaBuildProgress(
            stage: ResponsaBuildStage.failed,
            error: 'בניית קטלוג כבר מתבצעת. יש להמתין לסיומה.',
          ),
        )
        ..close();
      return controller.stream;
    }
    _start(controller, targetPath);
    return controller.stream;
  }

  /// האם בנייה כלשהי רצה כרגע — גם כזו שהתחיל מסך שכבר נסגר.
  static bool _active = false;

  Future<void> _start(
    StreamController<ResponsaBuildProgress> controller,
    String targetPath,
  ) async {
    if (!Platform.isWindows) {
      controller
        ..add(
          const ResponsaBuildProgress(
            stage: ResponsaBuildStage.failed,
            error: 'פרויקט השו"ת נתמך ב-Windows בלבד.',
          ),
        )
        ..close();
      return;
    }

    final flag = calloc<Int32>();
    _cancelFlag = flag;
    _active = true;
    final receive = ReceivePort();
    final exit = ReceivePort();
    final error = ReceivePort();

    controller.add(
      const ResponsaBuildProgress(stage: ResponsaBuildStage.starting),
    );

    // הקטלוג נקרא מעץ הקטלוג של התוכנה החיה — אין בהתקנה קובץ שמכיל את
    // רשימת הספרים. לכן בנייה כשהתוכנה כבויה חייבת להעלות אותה, ולא
    // לדרוש מהמשתמש לפתוח אותה בעצמו: הוא הדליק הגדרה באוצריא וביקש
    // לרענן, ואין סיבה שיידרש לצעד ידני בתוכנה אחרת.
    // בלי העדפת נתיב: הבנייה עצמה בוחרת התקנה ב-`selectInstallation`,
    // וההעלאה משתמשת באותה בחירה בדיוק.
    final launch = await ResponsaLauncher.ensureRunning();
    if (!launch.running) {
      controller
        ..add(
          ResponsaBuildProgress(
            stage: ResponsaBuildStage.failed,
            error: launch.message ?? 'לא ניתן להפעיל את בר אילן.',
          ),
        )
        ..close();
      _cleanup(receive, exit, error, flag);
      return;
    }

    try {
      _isolate = await Isolate.spawn(
        _buildEntry,
        _BuildRequest(
          sendPort: receive.sendPort,
          targetPath: targetPath,
          cancelFlagAddress: flag.address,
        ),
        onExit: exit.sendPort,
        onError: error.sendPort,
      );
    } catch (spawnError) {
      controller
        ..add(
          ResponsaBuildProgress(
            stage: ResponsaBuildStage.failed,
            error: 'לא ניתן להתחיל את בניית הקטלוג: $spawnError',
          ),
        )
        ..close();
      _cleanup(receive, exit, error, flag);
      return;
    }

    var finished = false;
    void finish(ResponsaBuildProgress? last) {
      if (finished) return;
      finished = true;
      if (last != null) controller.add(last);
      controller.close();
      _cleanup(receive, exit, error, flag);
    }

    receive.listen((message) {
      if (message is ResponsaBuildProgress) {
        if (finished) return;
        controller.add(message);
        if (message.stage == ResponsaBuildStage.done ||
            message.stage == ResponsaBuildStage.failed) {
          finish(null);
        }
      }
    });

    // איזולט שמת בלי לדווח — קריסה בקוד ה-native, חוסר זיכרון, הרג
    // חיצוני — השאיר את המסך ב"בונה..." לנצח: המתג נשאר מושבת והכפתור
    // היחיד שנותר כתב לדגל שאיש לא קרא. שתי היציאות האלה סוגרות את זה.
    error.listen((message) {
      debugPrint('ResponsaCatalogBuildService: isolate error: $message');
      finish(
        const ResponsaBuildProgress(
          stage: ResponsaBuildStage.failed,
          error: 'בניית הקטלוג נכשלה באופן בלתי צפוי.',
        ),
      );
    });
    exit.listen((_) {
      finish(
        const ResponsaBuildProgress(
          stage: ResponsaBuildStage.failed,
          error: 'בניית הקטלוג הסתיימה ללא תוצאה.',
        ),
      );
    });
  }

  void _cleanup(
    ReceivePort receive,
    ReceivePort exit,
    ReceivePort error,
    Pointer<Int32> flag,
  ) {
    receive.close();
    exit.close();
    error.close();
    _isolate = null;
    _cancelFlag = null;
    _active = false;
    calloc.free(flag);
  }

  // -------------------------------------------------- מה שרץ באיזולט

  static void _buildEntry(_BuildRequest request) {
    final send = request.sendPort;
    final flag = Pointer<Int32>.fromAddress(request.cancelFlagAddress);
    bool cancelled() => flag.value != 0;

    try {
      // ההתקנה נבחרת **לפני** המופע, והמופע נבחר כדי להתאים לה.
      // יכולים לרוץ כמה מופעים, ולכל אחד יכול להיות אתר נתונים אחר:
      // בנייה ממופע אחד שתויגה בטביעת אצבע של התקנה אחרת מתארת מאגר
      // שאינו קיים. זה קרה בפועל — קטלוג בן 2,179 ספרים במקום 8,523.
      final selection = ResponsaInstallationDiscovery.selectInstallation();
      if (selection == null) {
        send.send(
          const ResponsaBuildProgress(
            stage: ResponsaBuildStage.failed,
            error: 'לא נמצאה התקנה של בר אילן (פרויקט השו"ת) במחשב.',
          ),
        );
        return;
      }
      final installation = selection.installation;
      // מופע חונה מחוץ למסך עונה לפקודות, ולכן הבנייה הייתה מצליחה
      // מולו — אבל היא לוקחת כחמש דקות, והמשתמש לא היה רואה דבר קורה.
      final instance = ResponsaInstance.pick(selection.instances);
      if (instance == null) {
        send.send(
          ResponsaBuildProgress(
            stage: ResponsaBuildStage.failed,
            error:
                'בר אילן (${installation.displayName}) אינו פעיל. '
                'יש לפתוח אותו ולנסות שוב.',
          ),
        );
        return;
      }
      final version =
          ResponsaInstallationDiscovery.versionFromWindowTitle(
            instance.title,
          ) ??
          installation.version;
      final automation = ResponsaAutomation(
        pid: instance.pid,
        profile: ResponsaVersionProfile.forVersion(version),
      )..cancelled = cancelled;

      // עץ הקטלוג יושב בדיאלוג העיון; צריך לפתוח אותו כדי להגיע אליו.
      final dialog = automation.ensureCitationDialog(
        ResponsaDeadline(const Duration(seconds: 60)),
      );
      final tree =
          ResponsaTreeReader.findCatalogTree(dialog.hwnd) ??
          ResponsaTreeReader.findCatalogTree(dialog.container);
      if (tree == null) {
        send.send(
          const ResponsaBuildProgress(
            stage: ResponsaBuildStage.failed,
            error: 'לא נמצא עץ הקטלוג בחלון העיון של פרויקט השו"ת.',
          ),
        );
        return;
      }

      send.send(
        const ResponsaBuildProgress(stage: ResponsaBuildStage.scanning),
      );
      final nodes = ResponsaTreeReader.walk(
        pid: instance.pid,
        treeHandle: tree,
        progressEvery: 2000,
        shouldStop: cancelled,
        onProgress: (scanned) => send.send(
          ResponsaBuildProgress(
            stage: ResponsaBuildStage.scanning,
            scannedNodes: scanned,
          ),
        ),
      );

      if (cancelled()) {
        send.send(
          const ResponsaBuildProgress(
            stage: ResponsaBuildStage.failed,
            error: 'בניית הקטלוג בוטלה.',
          ),
        );
        return;
      }

      send.send(
        ResponsaBuildProgress(
          stage: ResponsaBuildStage.classifying,
          scannedNodes: nodes.length,
        ),
      );

      final result = ResponsaCatalogWriter.build(
        nodes: nodes,
        fingerprint: ResponsaInstallationDiscovery.fingerprint(installation),
        targetPath: request.targetPath,
      );
      send.send(
        ResponsaBuildProgress(
          stage: ResponsaBuildStage.done,
          scannedNodes: result.scannedNodes,
          books: result.books,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('ResponsaCatalogBuildService: $error\n$stackTrace');
      send.send(
        ResponsaBuildProgress(
          stage: ResponsaBuildStage.failed,
          error: 'בניית הקטלוג נכשלה: $error',
        ),
      );
    }
  }
}

class _BuildRequest {
  final SendPort sendPort;
  final String targetPath;
  final int cancelFlagAddress;

  const _BuildRequest({
    required this.sendPort,
    required this.targetPath,
    required this.cancelFlagAddress,
  });
}
