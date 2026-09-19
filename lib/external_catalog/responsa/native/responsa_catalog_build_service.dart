import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_automation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_builder.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_launcher.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_tree_reader.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';

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
    _start(controller, targetPath);
    return controller.stream;
  }

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
    final receive = ReceivePort();

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
      _cleanup(receive, flag);
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
      );
    } catch (error) {
      controller
        ..add(
          ResponsaBuildProgress(
            stage: ResponsaBuildStage.failed,
            error: 'לא ניתן להתחיל את בניית הקטלוג: $error',
          ),
        )
        ..close();
      _cleanup(receive, flag);
      return;
    }

    receive.listen((message) {
      if (message is ResponsaBuildProgress) {
        controller.add(message);
        if (message.stage == ResponsaBuildStage.done ||
            message.stage == ResponsaBuildStage.failed) {
          controller.close();
          _cleanup(receive, flag);
        }
      }
    });
  }

  void _cleanup(ReceivePort receive, Pointer<Int32> flag) {
    receive.close();
    _isolate = null;
    _cancelFlag = null;
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
      if (selection.instances.isEmpty) {
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
      final instance = selection.instances.first;
      final version =
          ResponsaInstallationDiscovery.versionFromWindowTitle(
            ResponsaWin32.windowText(instance.hwnd),
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

      final result = ResponsaCatalogBuilder.build(
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
