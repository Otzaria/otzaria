import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show WebViewEnvironment;
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/info/app_install_timeline.dart';
import 'package:otzaria/core/info/error_log_reader.dart';
import 'package:otzaria/core/info/info_topic.dart';
import 'package:otzaria/core/info/os_version.dart';
import 'package:otzaria/core/info/personal_folders_info.dart';
import 'package:otzaria/core/info/system_account_info.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/services/data_collection_service.dart';
import 'package:otzaria/update/app_release_version.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// דוח המידע שמוחזר לקישור `otzaria://info/...`.
class AppInfoReport {
  final InfoTopic topic;
  final DateTime generatedAt;

  /// מקטע לכל נושא, לפי [InfoTopic.slug].
  final Map<String, Map<String, dynamic>> sections;

  /// `false` כשהגדרות המשתמש לא נקראו (תיבה חסרה או קריאה שנכשלה) — אז כל
  /// הנתיבים והספירות הם ברירות מחדל ולא המצב בפועל. בלי הדגל הזה דוח
  /// ברירות-מחדל נראה מלא ואמין לצרכן חיצוני.
  final bool settingsLoaded;

  const AppInfoReport({
    required this.topic,
    required this.generatedAt,
    required this.sections,
    this.settingsLoaded = true,
  });

  Map<String, dynamic> toJson() => {
    'topic': topic.slug,
    // UTC עם סיומת Z — חותמת נאיבית אינה ניתנת לפירוש ע"י צרכן חיצוני.
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'settingsLoaded': settingsLoaded,
    ...sections,
  };
}

/// אוסף את דוח המידע של אוצריא — תוכנה, ספרייה, תוספים ושגיאות אחרונות.
///
/// כל מקטע נאסף בנפרד ובאופן עמיד לכשלים: מקטע שנכשל מחזיר `{'error': ...}`
/// ולא מבטל את שאר הדוח.
class AppInfoService {
  const AppInfoService._();

  /// ה-commit שממנו נבנתה התוכנה: כל בניות ה-dev נושאות אותה גרסה ב-pubspec.
  static const String buildCommit = String.fromEnvironment(
    'OTZARIA_BUILD_COMMIT',
  );

  /// אוסף את הדוח עבור [topic].
  ///
  /// [pluginsLoader] — מקור רשימת התוספים. במסלול הגרפי מגיע מ-`PluginSystemBloc`
  /// (שכבר טעון), ובמסלול ה-CLI מ-`PluginRegistryRepository`. הטעינה קורית
  /// בתוך ה-guard של המקטע, כך שכשל בה אינו מפיל את הדוח כולו. ברירת המחדל
  /// היא רשימה ריקה — כדי שהדוח לא יפתח DB תוספים בלי שהתבקש.
  static Future<AppInfoReport> collect(
    InfoTopic topic, {
    Future<List<InstalledPlugin>> Function()? pluginsLoader,
    int errorLimit = 5,
    int fileLimit = PersonalFoldersInfo.defaultFileLimit,
    DateTime? now,
    bool settingsLoaded = true,
  }) async {
    final sections = <String, Map<String, dynamic>>{};

    for (final section in topic.sections) {
      sections[section.slug] = await _guard(
        section,
        () => switch (section) {
          InfoTopic.app => _collectApp(),
          InfoTopic.library => _collectLibrary(),
          InfoTopic.folders => PersonalFoldersInfo.collect(
            fileLimit: fileLimit,
          ),
          InfoTopic.plugins => _collectPlugins(pluginsLoader),
          InfoTopic.errors => _collectErrors(errorLimit),
          InfoTopic.all => throw StateError('all מורחב ל-sections'),
        },
      );
    }

    return AppInfoReport(
      topic: topic,
      generatedAt: now ?? DateTime.now(),
      sections: sections,
      settingsLoaded: settingsLoaded,
    );
  }

  /// חותמת UTC עם סיומת `Z`, או null.
  static String? _utc(DateTime? value) => utcIso(value);

  static Future<Map<String, dynamic>> _guard(
    InfoTopic section,
    Future<Map<String, dynamic>> Function() collect,
  ) async {
    try {
      return await collect();
    } catch (error, stackTrace) {
      debugPrint('AppInfoService: ${section.slug} failed: $error\n$stackTrace');
      return {'error': '$error'};
    }
  }

  // ── תוכנה ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _collectApp() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final timeline = AppInstallTimelineStore.read();
    final account = await SystemAccountProbe.detect();
    final installType = await _resolveInstallType();

    return {
      'name': packageInfo.appName,
      'packageName': packageInfo.packageName,
      'version': canonicalAppVersion(packageInfo),
      'buildNumber': packageInfo.buildNumber,
      // באותו פורמט של previousVersion, כדי שהשוואה מכונתית תהיה אפשרית.
      'fullVersion': _fullVersion(packageInfo),
      if (buildCommit.isNotEmpty) 'buildCommit': buildCommit,
      'installedAt': _utc(timeline.installedAt),
      'installedAtSource': timeline.installedAtSource.name,
      'updatedAt': _utc(timeline.updatedAt),
      'previousVersion': timeline.previousVersion,
      'installType': installType,
      'accountType': account.accountType.name,
      'elevated': account.isElevated,
      'platform': _platformName(),
      'operatingSystem': _operatingSystemDescription(),
      'dataRootPath': await AppPaths.getDataRootPath(),
    };
  }

  /// `version+buildNumber`, זהה לפורמט שנרשם ב-[AppInstallTimelineStore].
  static String _fullVersion(PackageInfo packageInfo) {
    final version = canonicalAppVersion(packageInfo);
    final build = packageInfo.buildNumber.trim();
    if (version.isEmpty) return build.isEmpty ? 'unknown' : build;
    if (build.isEmpty || version.endsWith('+$build')) return version;
    return '$version+$build';
  }

  /// `portable` / `allUsers` / `perUser` — נייד תמיד קודם, כי התקנה ניידת
  /// לעולם אינה מערכתית ([AppPaths.detectInstallMode]).
  static Future<String> _resolveInstallType() async {
    if (AppPaths.isPortable) return 'portable';
    final mode = await AppPaths.detectInstallMode();
    return mode == InstallMode.systemWide ? 'allUsers' : 'perUser';
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem;
  }

  static String? _operatingSystemDescription() =>
      kIsWeb ? null : displayOsVersion();

  // ── ספרייה ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _collectLibrary() async {
    // ה-DB נגזר מנתיב הספרייה ה*מפוענח*, לא מ-Settings הגולמי. הפער חשוב
    // בתהליך שאינו יכול לכתוב הגדרות (ה-CLI): שם התיקון שהיה מבצע
    // getLibraryPath אינו נשמר, ו-getDatabasePath היה מחזיר נתיב מיושן —
    // ואז 'path' ו-'databasePath' באותו JSON סותרים זה את זה.
    final libraryPath = await AppPaths.getLibraryPath();
    final databasePath = DatabaseConstants.getDatabasePathForLibrary(
      libraryPath,
    );
    final version = await DataCollectionService().readLibraryVersion(
      databasePath: databasePath,
    );
    final databaseFile = File(databasePath);
    final databaseExists = await databaseFile.exists();
    final stat = databaseExists ? await databaseFile.stat() : null;

    final books = await _loadBooks();
    final personalBooks = books?.where((book) => book.isUserBook).length;
    final attached = await _collectAttachedLibraries();

    return {
      'version': version == 'unknown' ? null : version,
      // עדכון ספרייה כותב מחדש את seforim.db, ולכן זמן השינוי של הקובץ הוא
      // תאריך העדכון האחרון בפועל.
      'lastUpdatedAt': _utc(stat?.modified),
      'path': libraryPath,
      'indexPath': await AppPaths.getIndexPath(),
      'databasePath': databasePath,
      'databaseExists': databaseExists,
      'databaseSizeBytes': stat?.size,
      'freeSpaceBytes': await libraryFreeSpaceBytes(libraryPath),
      'totalBooks': books?.length,
      'personalBooks': personalBooks,
      'officialBooks': (books == null || personalBooks == null)
          ? null
          : books.length - personalBooks,
      'pdfBooks': books?.whereType<PdfBook>().length,
      'attachedLibraryCount': attached?.length,
      'attachedLibraries': attached,
    };
  }

  /// מסדי הספרים האישיים שצורפו (`seforim.db` נוספים), או null כשהרשימה
  /// השמורה פגומה ואינה ידועה.
  static Future<List<Map<String, dynamic>>?> _collectAttachedLibraries() async {
    final libraries = AttachedLibraryRegistry.instance.librariesIfKnown;
    if (libraries == null) return null;
    return [
      for (final library in libraries)
        {
          'name': library.displayName,
          'slug': library.slug,
          'path': library.path,
          'status': library.status.name,
          if (library.problem != null) 'problem': library.problem!.name,
          'mode': library.mode.name,
          'placement': library.placement.name,
          'hidden': library.hidden,
          'origin': library.isImported ? 'imported' : 'folder',
          'bookCount': library.bookCount,
          'sizeBytes': await _fileSize(library.path),
        },
    ];
  }

  static Future<int?> _fileSize(String path) async {
    try {
      final file = File(path);
      return await file.exists() ? (await file.stat()).size : null;
    } catch (_) {
      return null;
    }
  }

  /// המקום הפנוי בכונן של [libraryPath], או null כשאינו ידוע.
  @visibleForTesting
  static Future<int?> libraryFreeSpaceBytes(
    String libraryPath, {
    Future<DiskSpaceInfo> Function(String path) diskSpace = getDiskSpaceInfo,
  }) async {
    final freeBytes = (await diskSpace(libraryPath)).freeBytes;
    return freeBytes < 0 ? null : freeBytes;
  }

  static Future<List<Book>?> _loadBooks() async {
    try {
      return (await DataRepository.instance.library).getAllBooks();
    } catch (error) {
      // ספרייה שלא נטענה (התקנה חדשה, DB חסר) — הספירות יוצאות null.
      debugPrint('AppInfoService: library books unavailable: $error');
      return null;
    }
  }

  // ── תוספים ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _collectPlugins(
    Future<List<InstalledPlugin>> Function()? loader,
  ) async {
    final plugins = loader == null ? const <InstalledPlugin>[] : await loader();
    final sorted = plugins.toList()
      ..sort((a, b) => a.pluginId.compareTo(b.pluginId));

    return {
      'webViewVersion': await _webViewVersion(),
      'installedCount': sorted.length,
      'enabledCount': sorted.where((plugin) => plugin.enabled).length,
      'installed': [
        for (final plugin in sorted)
          {
            'id': plugin.pluginId,
            'name': plugin.name,
            'version': plugin.version,
            'enabled': plugin.enabled,
            'source': plugin.sourceType,
            'installedAt': plugin.installedAt.toIso8601String(),
            'updatedAt': plugin.updatedAt.toIso8601String(),
          },
      ],
    };
  }

  /// גרסת WebView2 הזמינה במחשב. רלוונטי ל-Windows בלבד; בשאר הפלטפורמות
  /// ה-WebView הוא רכיב מערכת ואין לו גרסה נגישה מכאן.
  static Future<String?> _webViewVersion() async {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      return await WebViewEnvironment.getAvailableVersion();
    } catch (error) {
      debugPrint('AppInfoService: WebView version unavailable: $error');
      return null;
    }
  }

  // ── שגיאות ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _collectErrors(int limit) async {
    final report = await ErrorLogReader.collect(limit: limit);
    return report.toJson();
  }
}
