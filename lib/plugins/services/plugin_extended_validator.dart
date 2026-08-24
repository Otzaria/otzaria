import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_program_compiler.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_selection_action.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_toolbar_template_compiler.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';
import 'package:otzaria/plugins/models/plugin_search_dialog_item.dart';
import 'package:otzaria/plugins/models/plugin_startup_contributions.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_settings_access_policy.dart';
import 'package:otzaria/plugins/services/plugin_external_editions_registry.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';
import 'package:path/path.dart' as p;

/// תוצאת ולידציה מורחבת לתוסף.
///
/// `errors` — חסומה (האריזה לא תושלם).
/// `warnings` — מציגה הודעה אך מאפשרת אריזה.
/// `design` — תאימות עיצוב (לפי `DESIGN_GUIDE.md` של Otzaria).
class PluginValidationReport {
  final List<String> errors;
  final List<String> warnings;
  final DesignComplianceReport design;

  const PluginValidationReport({
    required this.errors,
    required this.warnings,
    required this.design,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
}

class DesignComplianceReport {
  final bool compliant;
  final List<String> violations;

  const DesignComplianceReport({
    required this.compliant,
    required this.violations,
  });
}

/// רשימת ה-API methods המוכרים. תואם FALLBACK_API_METHODS ב-pluginValidation.js.
const Set<String> _knownApiMethods = {
  'app.getInfo',
  'app.getTheme',
  'app.getLocale',
  'app.getUserEmail',
  'app.getGrantedPermissions',
  'app.getConnectivity',
  'app.openUrl',
  'library.findBooks',
  'library.getBookMetadata',
  'library.resolveBooks',
  'library.resolveCategoryPaths',
  'library.listRecentBooks',
  'library.getBookContent',
  'library.getBookToc',
  'library.listBookAltStructures',
  'library.getBookAltToc',
  'library.getTree',
  'library.getCommentators',
  'library.getLinks',
  'library.getLinkTargetsSummary',
  'library.getLinkContent',
  'search.fullText',
  'search.query',
  'search.getOptions',
  'reader.openBook',
  'reader.openBookAtRef',
  'reader.openSearchTab',
  'reader.getCurrentState',
  'reader.getCurrentRef',
  'reader.getSelection',
  'reader.getActiveCommentators',
  'reader.setActiveCommentators',
  'reader.scrollToSection',
  'reader.getHighlightCapabilities',
  'reader.addContextMenuItem',
  'reader.removeContextMenuItem',
  'reader.updateContextMenuItem',
  'reader.addToolbarItem',
  'reader.removeToolbarItem',
  'reader.updateToolbarItem',
  'reader.findTextOccurrences',
  'reader.getSectionTextMap',
  'reader.registerInBookSearchProvider',
  'reader.respondInBookSearch',
  'reader.registerExternalSearchProvider',
  'reader.respondExternalSearch',
  'reader.setHighlight',
  'reader.updateHighlight',
  'reader.getHighlights',
  'reader.revealHighlight',
  'reader.clearHighlight',
  'reader.clearAllHighlights',
  'navigation.goTo',
  'plugin.openSelf',
  'plugin.openOther',
  'plugin.backgroundDone',
  'notes.list',
  'notes.getBookNotesSummary',
  'notes.add',
  'notes.update',
  'notes.delete',
  'ui.showMessage',
  'ui.showSuccess',
  'ui.showError',
  'ui.showConfirm',
  'ui.showWarning',
  'ui.pickFolder',
  'fs.extractZip',
  'fs.deleteFile',
  'fs.pickUserFile',
  'fs.resolveFileUrl',
  'fs.readTextFile',
  'fs.revokeFile',
  'fs.beginBinaryWrite',
  'fs.commitUserFileWrite',
  'fs.abortBinaryWrite',
  'fs.writeFile',
  'fs.readFile',
  'fs.listDir',
  'fs.makeDir',
  'fs.deleteEntry',
  'fs.stat',
  'feedback.sendEmail',
  'feedback.report',
  'feedback.hasReporterEmail',
  'history.list',
  'history.listSearches',
  'history.clear',
  'history.remove',
  'bookmarks.list',
  'bookmarks.add',
  'bookmarks.remove',
  'tools.gematria',
  'tools.dictionary',
  'notifications.showInApp',
  'notifications.sendSystem',
  'notifications.scheduleSystem',
  'notifications.cancel',
  'notifications.cancelAll',
  'notifications.checkPermissions',
  'notifications.requestPermissions',
  'storage.get',
  'storage.set',
  'storage.remove',
  'storage.list',
  'settings.get',
  'settings.getMany',
  'calendar.getSelectedDate',
  'calendar.getDailyTimes',
  'calendar.getHalachicTimes',
  'calendar.getJewishDate',
  'calendar.getEvents',
  'calendar.getCities',
  'publishedData.upsert',
  'publishedData.remove',
  'publishedData.listOwn',
  'database.listSources',
  'database.describeSource',
  'database.query',
  'database.batchQuery',
  'network.fetch',
  'network.fetchStream',
  'network.download',
  'shortcut.create',
};

/// APIs קיימות בתוספים אך אינן מתועדות פומבית — לא נאזהיר עליהן.
/// שתיהן מיועדות לתוסף חנות התוספים בלבד; ב-d.ts הן מסומנות `@internal`.
const Set<String> _knownUndocumentedMethods = {
  'plugin.listInstalled',
  'plugin.requestInstall',
};

/// אירועי lifecycle ו-events נתמכים.
const Set<String> _knownEvents = {
  'plugin.boot',
  'plugin.ready',
  'plugin.suspended',
  'plugin.resumed',
  'theme.changed',
  'navigation.changed',
  'reader.current_book_changed',
  'reader.current_ref_changed',
  'reader.selection_changed',
  'reader.sectionContentChanged',
  'reader.context_menu_item_clicked',
  'reader.toolbar_item_clicked',
  'reader.inBookSearch.requested',
  'ui.messageClicked',
  'plugin.page_opened',
  'contextMenu.itemClicked',
  'contextMenu.colorClicked',
  'calendar.date_changed',
  'calendar.city_changed',
  'workspace.changed',
  'settings.changed',
  'plugin.permissions_changed',
  'search.requested',
  // אירוע ממוקד מ-PluginExternalSearchService: בקשת חיפוש חיצוני ממסך
  // החיפוש המובנה. תוסף-ספק מצהיר עליו ב-activationEvents כדי שהבקשה
  // תעיר מנוע רקע במקום לפתוח את דף התוסף.
  'search.external.requested',
};

/// מיפוי `method -> permission` נדרשת (תואם METHOD_REQUIRED_PERMISSION ב-JS).
const Map<String, String> _methodRequiredPermission = {
  'app.getInfo': 'app.info.read',
  'app.getTheme': 'app.info.read',
  'app.getLocale': 'app.info.read',
  'app.getGrantedPermissions': 'app.info.read',
  'app.getConnectivity': 'app.info.read',
  'app.getUserEmail': 'app.user_email.read',
  'app.openUrl': 'app.open_url',
  'library.findBooks': 'library.books.read',
  'library.getBookMetadata': 'library.books.read',
  'library.resolveBooks': 'library.books.read',
  'library.resolveCategoryPaths': 'library.books.read',
  'library.listRecentBooks': 'library.books.read',
  'library.getTree': 'library.books.read',
  'library.getBookContent': 'library.content.read',
  'library.getBookToc': 'library.content.read',
  'library.listBookAltStructures': 'library.content.read',
  'library.getBookAltToc': 'library.content.read',
  'library.getLinkContent': 'library.content.read',
  'library.getCommentators': pluginLinksReadPermission,
  'library.getLinks': pluginLinksReadPermission,
  'library.getLinkTargetsSummary': pluginLinksReadPermission,
  'search.fullText': 'search.fulltext.read',
  'search.query': 'search.fulltext.read',
  'search.getOptions': 'search.fulltext.read',
  'reader.openBook': 'reader.open',
  'reader.openBookAtRef': 'reader.open',
  'reader.openSearchTab': 'reader.open',
  'reader.getCurrentState': 'reader.open',
  'reader.getCurrentRef': 'reader.open',
  'reader.getSelection': 'reader.open',
  'reader.getActiveCommentators': 'reader.open',
  'reader.setActiveCommentators': 'reader.open',
  'reader.scrollToSection': 'reader.open',
  'reader.getHighlightCapabilities': 'reader.open',
  'reader.addContextMenuItem': 'reader.context_menu',
  'reader.removeContextMenuItem': 'reader.context_menu',
  'reader.updateContextMenuItem': 'reader.context_menu',
  'reader.addToolbarItem': 'reader.toolbar',
  'reader.removeToolbarItem': 'reader.toolbar',
  'reader.updateToolbarItem': 'reader.toolbar',
  'reader.findTextOccurrences': 'reader.open',
  'reader.getSectionTextMap': 'reader.open',
  'reader.registerInBookSearchProvider': 'reader.open',
  'reader.respondInBookSearch': 'reader.open',
  'reader.registerExternalSearchProvider': 'reader.open',
  'reader.respondExternalSearch': 'reader.open',
  'reader.setHighlight': 'reader.highlight',
  'reader.updateHighlight': 'reader.highlight',
  'reader.getHighlights': 'reader.highlight',
  'reader.revealHighlight': 'reader.highlight',
  'reader.clearHighlight': 'reader.highlight',
  'reader.clearAllHighlights': 'reader.highlight',
  'navigation.goTo': 'navigation.write',
  'plugin.openSelf': 'navigation.write',
  'plugin.openOther': pluginOpenOtherPermission,
  'notes.list': 'notes.read',
  'notes.getBookNotesSummary': 'notes.read',
  'notes.add': 'notes.write',
  'notes.update': 'notes.write',
  'notes.delete': 'notes.write',
  'ui.showMessage': 'ui.feedback',
  'ui.showSuccess': 'ui.feedback',
  'ui.showError': 'ui.feedback',
  'ui.showConfirm': 'ui.feedback',
  'ui.showWarning': 'ui.feedback',
  'ui.pickFolder': 'fs.folder_access',
  // fs.extractZip/deleteFile מכוונים בכוונה לא להופיע כאן — ה-runtime לא דורש
  // עבורם הרשאת manifest (הם מגודרים ע"י תיקייה שנבחרה ב-ui.pickFolder).
  // כך גם פעולות המרחב הפרטי (writeFile/readFile/listDir/makeDir/
  // deleteEntry/stat) — השורש הפרטי של התוסף הוא הגבול.
  'fs.pickUserFile': 'fs.user_files.read',
  'fs.resolveFileUrl': 'fs.user_files.read',
  'fs.readTextFile': 'fs.user_files.read',
  'fs.revokeFile': 'fs.user_files.read',
  'fs.beginBinaryWrite': 'fs.user_files.write',
  'fs.commitUserFileWrite': 'fs.user_files.write',
  'fs.abortBinaryWrite': 'fs.user_files.write',
  'feedback.sendEmail': 'feedback.send_email',
  'history.list': 'history.read',
  'history.listSearches': 'history.read',
  'history.clear': 'history.write',
  'history.remove': 'history.write',
  'bookmarks.list': pluginBookmarksReadPermission,
  'bookmarks.add': pluginBookmarksWritePermission,
  'bookmarks.remove': pluginBookmarksWritePermission,
  'tools.gematria': pluginToolsReadPermission,
  'tools.dictionary': pluginToolsReadPermission,
  'notifications.showInApp': 'notifications.send',
  'notifications.sendSystem': 'notifications.system',
  'notifications.scheduleSystem': 'notifications.system',
  'notifications.cancel': 'notifications.system',
  'notifications.cancelAll': 'notifications.system',
  'notifications.checkPermissions': 'notifications.system',
  'notifications.requestPermissions': 'notifications.system',
  'storage.get': 'plugin.storage.read',
  'storage.set': 'plugin.storage.write',
  'storage.remove': 'plugin.storage.write',
  'storage.list': 'plugin.storage.read',
  'settings.get': 'settings.read',
  'settings.getMany': 'settings.read',
  'calendar.getSelectedDate': 'calendar.read',
  'calendar.getDailyTimes': 'calendar.read',
  'calendar.getHalachicTimes': 'calendar.read',
  'calendar.getJewishDate': 'calendar.read',
  'calendar.getEvents': 'calendar.read',
  'calendar.getCities': 'calendar.read',
  'publishedData.upsert': 'published_data.write',
  'publishedData.remove': 'published_data.write',
  'publishedData.listOwn': 'published_data.write',
  'database.listSources': 'database.read',
  'database.describeSource': 'database.read',
  'database.query': 'database.read',
  'database.batchQuery': 'database.read',
  'network.fetch': 'network.access',
  'network.fetchStream': 'network.access',
  'network.download': 'network.access',
  'shortcut.create': 'ui.create_shortcut',
};

/// גרסת האפליקציה המינימלית שבה כל API התווסף (`method -> minVersion`).
///
/// מקור-האמת לאכיפה: בעת אריזה, תוסף שקורא ל-API חדש מ-`minAppVersion`
/// שהצהיר ייכשל (שגיאה חוסמת). הטבלה ב-`docs/plugin-sdk/API_REFERENCE.md`
/// ("טבלת גרסאות API") נגזרת ממפה זו, ו-`plugin_method_versions_test.dart`
/// מוודא שהן נשארות זהות. כל API חדש: הוסף שורה כאן + שורה בטבלה במסמך.
///
/// תואם METHOD_MIN_VERSION ב-`pluginValidation.js` (Otzaria_Website)
/// וב-otzaria-plugin-validator — יש לסנכרן את שלושתם יחד.
const Map<String, String> _methodMinVersion = {
  // 0.9.89 — מערכת התוספים הראשונה (כל ה-APIs הבסיסיים).
  'app.getInfo': '0.9.89',
  'app.getTheme': '0.9.89',
  'app.getLocale': '0.9.89',
  'app.getUserEmail': '0.9.89',
  'app.getGrantedPermissions': '0.9.89',
  'library.findBooks': '0.9.89',
  'library.getBookMetadata': '0.9.89',
  'library.resolveBooks': '0.9.97',
  'library.resolveCategoryPaths': '0.9.97',
  'library.listRecentBooks': '0.9.89',
  'library.getBookContent': '0.9.89',
  'library.getBookToc': '0.9.89',
  'library.getCommentators': '0.9.97',
  'library.getLinks': '0.9.97',
  'library.getLinkTargetsSummary': '0.9.97',
  'library.getLinkContent': '0.9.97',
  'search.fullText': '0.9.89',
  'search.query': '0.9.97',
  'search.getOptions': '0.9.97',
  'reader.openBook': '0.9.89',
  'reader.openBookAtRef': '0.9.89',
  'reader.openSearchTab': '0.9.89',
  'reader.getCurrentState': '0.9.89',
  'reader.getCurrentRef': '0.9.89',
  'reader.getSelection': '0.9.89',
  'reader.getActiveCommentators': '0.9.97',
  'reader.addContextMenuItem': '0.9.89',
  'reader.removeContextMenuItem': '0.9.89',
  'reader.updateContextMenuItem': '0.9.95',
  'reader.addToolbarItem': '0.9.97',
  'reader.removeToolbarItem': '0.9.97',
  'reader.updateToolbarItem': '0.9.97',
  'reader.findTextOccurrences': '0.9.95',
  'reader.getSectionTextMap': '0.9.95',
  'reader.registerInBookSearchProvider': '0.9.97',
  'reader.respondInBookSearch': '0.9.97',
  'reader.registerExternalSearchProvider': '0.9.97',
  'reader.respondExternalSearch': '0.9.97',
  'reader.setHighlight': '0.9.89',
  'reader.updateHighlight': '0.9.95',
  'reader.getHighlights': '0.9.89',
  'reader.revealHighlight': '0.9.96',
  'reader.clearHighlight': '0.9.89',
  'reader.clearAllHighlights': '0.9.89',
  'navigation.goTo': '0.9.89',
  'notes.list': '0.9.89',
  'notes.getBookNotesSummary': '0.9.89',
  'notes.add': '0.9.89',
  'notes.update': '0.9.89',
  'notes.delete': '0.9.89',
  'ui.showMessage': '0.9.89',
  'ui.showSuccess': '0.9.89',
  'ui.showError': '0.9.89',
  'ui.showConfirm': '0.9.89',
  'ui.showWarning': '0.9.89',
  'feedback.sendEmail': '0.9.89',
  'feedback.report': '0.9.97',
  'feedback.hasReporterEmail': '0.9.97',
  'history.list': '0.9.89',
  'history.listSearches': '0.9.89',
  'history.clear': '0.9.89',
  'history.remove': '0.9.89',
  'notifications.showInApp': '0.9.89',
  'notifications.sendSystem': '0.9.89',
  'notifications.scheduleSystem': '0.9.89',
  'notifications.cancel': '0.9.89',
  'notifications.cancelAll': '0.9.89',
  'notifications.checkPermissions': '0.9.89',
  'notifications.requestPermissions': '0.9.89',
  'storage.get': '0.9.89',
  'storage.set': '0.9.89',
  'storage.remove': '0.9.89',
  'storage.list': '0.9.89',
  'settings.get': '0.9.89',
  'settings.getMany': '0.9.89',
  'calendar.getSelectedDate': '0.9.89',
  'calendar.getDailyTimes': '0.9.92',
  'calendar.getHalachicTimes': '0.9.92',
  'calendar.getJewishDate': '0.9.89',
  'calendar.getEvents': '0.9.89',
  'calendar.getCities': '0.9.96',
  'publishedData.upsert': '0.9.89',
  'publishedData.remove': '0.9.89',
  'publishedData.listOwn': '0.9.89',
  'database.listSources': '0.9.89',
  'database.describeSource': '0.9.89',
  'database.query': '0.9.89',
  'database.batchQuery': '0.9.89',
  // 0.9.93
  'library.getTree': '0.9.93',
  'network.fetch': '0.9.93',
  'network.fetchStream': '0.9.97',
  'network.download': '0.9.93',
  'fs.deleteFile': '0.9.93',
  'fs.extractZip': '0.9.93',
  'ui.pickFolder': '0.9.93',
  // 0.9.94
  'shortcut.create': '0.9.94',
  'fs.pickUserFile': '0.9.94',
  'fs.readTextFile': '0.9.94',
  'fs.resolveFileUrl': '0.9.94',
  'fs.revokeFile': '0.9.94',
  'fs.beginBinaryWrite': '0.9.97',
  'fs.commitUserFileWrite': '0.9.97',
  'fs.abortBinaryWrite': '0.9.97',
  // 0.9.95
  'app.openUrl': '0.9.95',
  // 0.9.96
  'plugin.openSelf': '0.9.96',
  'plugin.openOther': '0.9.97',
  'library.listBookAltStructures': '0.9.96',
  'library.getBookAltToc': '0.9.96',
  // 0.9.97
  'plugin.backgroundDone': '0.9.97',
  'app.getConnectivity': '0.9.96',
  'fs.writeFile': '0.9.97',
  'fs.readFile': '0.9.97',
  'fs.listDir': '0.9.97',
  'fs.makeDir': '0.9.97',
  'fs.deleteEntry': '0.9.97',
  'fs.stat': '0.9.97',
  'reader.setActiveCommentators': '0.9.97',
  'reader.scrollToSection': '0.9.97',
  'reader.getHighlightCapabilities': '0.9.97',
  'bookmarks.list': '0.9.97',
  'bookmarks.add': '0.9.97',
  'bookmarks.remove': '0.9.97',
  'tools.gematria': '0.9.97',
  'tools.dictionary': '0.9.97',
};

/// שדות שמורים שאינם API methods (כדי שלא ייתפסו ב-shorthand scanner).
const Set<String> _reservedHolderFields = {
  'call',
  'on',
  'off',
  'emit',
  'once',
  'use',
  'init',
  'setup',
  'ready',
};

class PluginExtendedValidator {
  /// חשיפה לבדיקות סנכרון בלבד: מפת `method -> minVersion` ורשימת ה-methods
  /// המוכרים, כדי לוודא שהמפה, הטבלה במסמך ורשימת ה-known נשארות עקביות.
  @visibleForTesting
  static Map<String, String> get methodMinVersions =>
      Map.unmodifiable(_methodMinVersion);

  @visibleForTesting
  static Set<String> get knownApiMethods => _knownApiMethods;

  @visibleForTesting
  static Map<String, String> get methodRequiredPermissions =>
      Map.unmodifiable(_methodRequiredPermission);

  /// מבצע ולידציה מורחבת על תיקיית התוסף.
  ///
  /// תואם ללוגיקה ב-`C:\Otzaria_Website\src\lib\pluginValidation.js`.
  /// [manifest] חייב להיות תקני (`PluginManifest.fromJson` עבר בהצלחה).
  static PluginValidationReport validate({
    required PluginManifest manifest,
    required Map<String, dynamic> manifestJson,
    required String directoryPath,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    final declaredPermissions = manifest.permissions.toSet();

    _validateNetwork(manifestJson, declaredPermissions, errors, warnings);
    _validateStartupContributions(
      manifest,
      manifestJson,
      declaredPermissions,
      errors,
      warnings,
    );
    _checkNameVsToolTabTitle(manifestJson, warnings);

    final files = _collectScannableFiles(directoryPath);
    final apiUsage = <String, Set<String>>{};
    final eventUsage = <String, Set<String>>{};

    for (final entry in files.entries) {
      final relName = entry.key;
      if (!_isCodeLikeFile(relName)) continue;
      String text;
      try {
        text = entry.value.readAsStringSync();
      } catch (_) {
        continue;
      }
      final scan = _scanCodeForApiUsage(text);
      for (final method in scan.methods) {
        apiUsage.putIfAbsent(method, () => <String>{}).add(relName);
      }
      for (final ev in scan.events) {
        eventUsage.putIfAbsent(ev, () => <String>{}).add(relName);
      }
    }

    for (final entry in apiUsage.entries) {
      final method = entry.key;
      if (_knownApiMethods.contains(method) ||
          _knownUndocumentedMethods.contains(method)) {
        continue;
      }
      warnings.add(
        'קריאה ל-API לא מוכר: $method (קבצים: ${entry.value.join(', ')})',
      );
    }

    for (final entry in eventUsage.entries) {
      final ev = entry.key;
      if (_knownEvents.contains(ev)) continue;
      warnings.add(
        'רישום ל-event לא מוכר: $ev (קבצים: ${entry.value.join(', ')})',
      );
    }

    // Cross-check: method משומש אך ההרשאה לא הוכרזה.
    for (final method in apiUsage.keys) {
      final required = _methodRequiredPermission[method];
      if (required == null) continue;
      // הרשאות בסיס ניתנות אוטומטית — אין צורך בהצהרה.
      if (pluginBaselinePermissions.contains(required)) continue;
      if (declaredPermissions.contains(required)) continue;
      // הצהרה ותיקה מכסה הרשאה שפוצלה ממנה (ui.feedback → fs.folder_access).
      if (declaredPermissions.contains(
        pluginLegacyPermissionAliases[required],
      )) {
        continue;
      }
      // קריאות רשת מסתפקות גם ב-network.localhost
      // (גישה לשירות מקומי), לא רק ב-network.access.
      if (required == 'network.access' &&
          declaredPermissions.contains('network.localhost')) {
        continue;
      }
      warnings.add(
        'התוסף משתמש ב-$method אך לא ביקש את ההרשאה "$required" ב-manifest',
      );
    }

    // הרשאת בסיס שהוצהרה — מיותרת; מומלץ להסיר בהזדמנות.
    for (final permission in declaredPermissions) {
      if (pluginBaselinePermissions.contains(permission)) {
        warnings.add(
          'ההרשאה "$permission" ניתנת כיום אוטומטית לכל תוסף — '
          'אפשר להסירה מה-manifest',
        );
      }
    }

    // הרשאה שלא הייתה קיימת בגרסת המינימום תפיל את ההתקנה באוצריא ישנה.
    if (declaredPermissions.contains(pluginFolderAccessPermission)) {
      int? cmp;
      try {
        cmp = PluginVersionUtils.compareCoreVersions(
          _folderAccessPermissionMinVersion,
          manifest.minAppVersion,
        );
      } on PluginVersionFormatException {
        cmp = null; // minAppVersion לא חוקי — נתפס ב-PluginManifestValidator.
      }
      if (cmp != null && cmp > 0) {
        errors.add(
          'ההרשאה "$pluginFolderAccessPermission" קיימת החל מגרסה '
          '$_folderAccessPermissionMinVersion, אך minAppVersion שהוצהר הוא '
          '${manifest.minAppVersion}. עדכן את minAppVersion ל-'
          '$_folderAccessPermissionMinVersion לפחות',
        );
      }
    }

    // Cross-check: method חדש מ-minAppVersion שהוצהר — שגיאה חוסמת. תוסף שקורא
    // ל-API שלא היה קיים בגרסת המינימום שלו יקרוס אצל משתמש בגרסה כזו.
    _checkMethodVersions(apiUsage, manifest.minAppVersion, errors);

    // Cross-check: event subscription דורש הרשאת events.subscribe:X.
    for (final ev in eventUsage.keys) {
      final eventPerm = 'events.subscribe:$ev';
      if (!pluginValidPermissions.contains(eventPerm)) continue;
      if (pluginBaselinePermissions.contains(eventPerm)) continue;
      if (!declaredPermissions.contains(eventPerm)) {
        warnings.add(
          'רישום ל-event "$ev" דורש את ההרשאה "$eventPerm" שלא הוכרזה ב-manifest',
        );
      }
    }

    final design = _checkDesignCompliance(files);

    return PluginValidationReport(
      errors: errors,
      warnings: warnings,
      design: design,
    );
  }

  /// מצליב כל method בשימוש מול גרסת המינימום שבה התווסף. כל method חדש
  /// מ-[minAppVersion] מתווסף כ-error חוסם, עם הנחיה לעדכן את minAppVersion.
  static void _checkMethodVersions(
    Map<String, Set<String>> apiUsage,
    String minAppVersion,
    List<String> errors,
  ) {
    for (final entry in apiUsage.entries) {
      final method = entry.key;
      final since = _methodMinVersion[method];
      if (since == null) continue;
      final int cmp;
      try {
        cmp = PluginVersionUtils.compareCoreVersions(since, minAppVersion);
      } on PluginVersionFormatException {
        continue; // minAppVersion לא חוקי — נתפס ב-PluginManifestValidator.
      }
      if (cmp > 0) {
        errors.add(
          'התוסף משתמש ב-$method הקיים החל מגרסה $since, אך minAppVersion '
          'שהוצהר הוא $minAppVersion. עדכן את minAppVersion ל-$since לפחות '
          '(קבצים: ${entry.value.join(', ')})',
        );
      }
    }
  }

  // ===== Manifest checks =====

  /// הגרסה שבה נוסף מנגנון contributes.startup — נאכף מול minAppVersion.
  static const String _startupContributionsMinVersion = '0.9.96';
  static const String _folderAccessPermissionMinVersion = '0.9.97';
  static const String _declarativeProgramsMinVersion = '0.9.96';

  /// פקודות דקלרטיביות שנוספו אחרי מנגנון ה-programs — נאכפות מול minAppVersion.
  static const Map<String, String> _commandMinVersions = {
    'data.choose': '0.9.97',
    'settings.get': '0.9.97',
    'storage.get': '0.9.97',
  };

  /// פעולות דקלרטיביות (action בפקדים) שנוספו מאוחר — נאכפות מול minAppVersion.
  static const Map<String, String> _actionMinVersions = {
    'storage.set': '0.9.97',
    'storage.remove': '0.9.97',
  };
  static const String _contextMenuActionMinVersion = '0.9.97';
  static const String _searchSubmitRoutingMinVersion = '0.9.97';
  static const String _externalEditionsMinVersion = '0.9.97';
  static const String _whenConditionMinVersion = '0.9.97';

  /// ולידציית תנאי `when`: סכימה, מפתח הגדרה קריא וגרסת מינימום. מפתח
  /// חסום מוערך כ-false בזמן ריצה, ולכן נחשב לשגיאה כבר בהתקנה.
  static void _validateWhenConditions(
    PluginManifest manifest,
    PluginStartupContributions startup,
    Map<String, dynamic> startupMap,
    List<String> errors,
  ) {
    var hasWhen = false;
    void validateRaw(String field, Object? raw) {
      if (raw == null) return;
      hasWhen = true;
      try {
        final condition = PluginWhenCondition.fromJson(raw);
        for (final key in condition.settingKeys) {
          if (!PluginSettingsAccessPolicy.isReadable(key)) {
            errors.add(
              'contributes.startup.$field: when קורא הגדרה שאינה '
              'זמינה לתוספים ("$key")',
            );
          }
        }
      } on PluginWhenConditionException catch (error) {
        errors.add('contributes.startup.$field: when לא תקין: $error');
      }
    }

    final categories = {
      'toolbarItems': startup.toolbarItems,
      'contextMenuItems': startup.contextMenuItems,
      'searchDialogItems': startup.searchDialogItems,
    };
    for (final entry in categories.entries) {
      for (final item in entry.value) {
        validateRaw(entry.key, item['when']);
      }
    }
    final events = startupMap['activationEvents'];
    if (events is List) {
      for (final entry in events) {
        if (entry is Map) validateRaw('activationEvents', entry['when']);
      }
    }
    if (!hasWhen) return;
    try {
      if (PluginVersionUtils.compareCoreVersions(
            _whenConditionMinVersion,
            manifest.minAppVersion,
          ) >
          0) {
        errors.add(
          'תנאי when נתמך החל מגרסה $_whenConditionMinVersion, אך '
          'minAppVersion שהוצהר הוא ${manifest.minAppVersion}',
        );
      }
    } on PluginVersionFormatException {
      // minAppVersion נבדק ב-PluginManifestValidator.
    }
  }

  /// פעולות host על פריטי תפריט הקשר: הצהרת הרשאה וגרסת מינימום. השגיאות
  /// המבניות נתפסות כבר ברישום דרך ContextMenuRegistry.
  static void _validateContextMenuActions(
    PluginManifest manifest,
    List<Map<String, dynamic>> items,
    Set<String> declaredPermissions,
    List<String> errors,
  ) {
    final actions = <Map<String, dynamic>>[];
    void collect(Map<String, dynamic> item) {
      if (item['action'] is Map) {
        actions.add(Map<String, dynamic>.from(item['action'] as Map));
      }
      final children = item['children'];
      if (children is List) {
        for (final child in children.whereType<Map>()) {
          collect(Map<String, dynamic>.from(child));
        }
      }
    }

    for (final item in items) {
      collect(item);
    }
    if (actions.isEmpty) return;

    try {
      if (PluginVersionUtils.compareCoreVersions(
            _contextMenuActionMinVersion,
            manifest.minAppVersion,
          ) >
          0) {
        errors.add(
          'action על פריט תפריט הקשר נתמך החל מגרסה '
          '$_contextMenuActionMinVersion, אך minAppVersion שהוצהר הוא '
          '${manifest.minAppVersion}',
        );
      }
    } on PluginVersionFormatException {
      // minAppVersion נבדק ב-PluginManifestValidator.
    }
    for (final action in actions) {
      try {
        DeclarativeSelectionAction.validateTemplate(
          action,
          declaredPermissions: declaredPermissions,
        );
      } on DeclarativeProgramException catch (error) {
        errors.add('contributes.startup.contextMenuItems לא תקין: $error');
      }
    }
  }

  /// ולידציית contributes.startup: סכימה (דרך אותם parsers של ה-runtime),
  /// הרשאות נדרשות וגרסת מינימום.
  static void _validateStartupContributions(
    PluginManifest manifest,
    Map<String, dynamic> manifestJson,
    Set<String> declaredPermissions,
    List<String> errors,
    List<String> warnings,
  ) {
    final contributes = manifestJson['contributes'];
    final startupRaw = contributes is Map ? contributes['startup'] : null;
    if (startupRaw == null) return;
    if (startupRaw is! Map) {
      errors.add('contributes.startup חייב להיות אובייקט');
      return;
    }
    final startupMap = Map<String, dynamic>.from(startupRaw);

    // בדיקות טיפוס על ה-JSON הגולמי: הפרסינג במודל סובלני (מדלג על ערכים
    // שגויים), ולכן טיפוס שגוי חייב להתגלות כאן ולא להיעלם בשקט.
    var hasTypeErrors = false;
    void checkListField(
      String field,
      bool Function(Object?) elementOk,
      String elementDescription,
    ) {
      final value = startupMap[field];
      if (value == null) return;
      if (value is! List) {
        errors.add('contributes.startup.$field חייב להיות מערך');
        hasTypeErrors = true;
        return;
      }
      if (value.any((element) => !elementOk(element))) {
        errors.add(
          'contributes.startup.$field מכיל ערך שאינו $elementDescription',
        );
        hasTypeErrors = true;
      }
    }

    checkListField('toolbarItems', (e) => e is Map, 'אובייקט');
    checkListField('contextMenuItems', (e) => e is Map, 'אובייקט');
    checkListField('publishedData', (e) => e is Map, 'אובייקט');
    checkListField('programs', (e) => e is Map, 'אובייקט');
    checkListField('searchDialogItems', (e) => e is Map, 'אובייקט');
    checkListField('externalEditions', (e) => e is Map, 'אובייקט');
    checkListField(
      'activationEvents',
      (e) => e is String || (e is Map && e['topic'] is String),
      'מחרוזת או אובייקט עם topic',
    );
    final rawEvents = startupMap['activationEvents'];
    if (rawEvents is List) {
      for (final entry in rawEvents.whereType<Map>()) {
        final unknown = entry.keys.where(
          (key) => key != 'topic' && key != 'when',
        );
        if (unknown.isEmpty) continue;
        errors.add(
          'contributes.startup.activationEvents: שדה לא מוכר '
          '"${unknown.first}" (מותרים topic ו-when בלבד)',
        );
        hasTypeErrors = true;
      }
    }
    final keepAliveRaw = startupMap['keepAlive'];
    if (keepAliveRaw != null && keepAliveRaw is! bool) {
      errors.add('contributes.startup.keepAlive חייב להיות bool');
      hasTypeErrors = true;
    }
    if (hasTypeErrors) return;

    final startup = manifest.startup;
    if (startup == null) return;
    if (startup.keepAlive && !startup.hasBackgroundActivationTrigger) {
      errors.add(
        'contributes.startup.keepAlive דורש פקד או אירוע שמפעיל מנוע רקע',
      );
      return;
    }
    if (startup.isEmpty) {
      warnings.add('contributes.startup ריק — הסר אותו או הוסף תרומות');
      return;
    }

    if (!declaredPermissions.contains(pluginStartupContributionsPermission)) {
      errors.add(
        'contributes.startup דורש את ההרשאה '
        '"$pluginStartupContributionsPermission" ב-manifest',
      );
    }
    try {
      if (PluginVersionUtils.compareCoreVersions(
            _startupContributionsMinVersion,
            manifest.minAppVersion,
          ) >
          0) {
        errors.add(
          'contributes.startup נתמך החל מגרסה '
          '$_startupContributionsMinVersion, אך minAppVersion שהוצהר הוא '
          '${manifest.minAppVersion}. עדכן את minAppVersion',
        );
      }
    } on PluginVersionFormatException {
      // minAppVersion לא חוקי — נתפס ב-PluginManifestValidator.
    }

    _validateWhenConditions(manifest, startup, startupMap, errors);

    if (startup.toolbarItems.isNotEmpty) {
      final hasDeclarativeItems = startup.toolbarItems.any(
        DeclarativeToolbarTemplateCompiler.isDeclarative,
      );
      if (!declaredPermissions.contains('reader.toolbar')) {
        final message =
            'contributes.startup.toolbarItems דורש את ההרשאה "reader.toolbar" '
            'שלא הוכרזה ב-manifest';
        if (hasDeclarativeItems) {
          errors.add(message);
        } else {
          warnings.add(message);
        }
      }
      if (startup.toolbarItems.length >
          PluginToolbarRegistry.maxTopLevelItemsPerPlugin) {
        errors.add(
          'contributes.startup.toolbarItems מוגבל ל-'
          '${PluginToolbarRegistry.maxTopLevelItemsPerPlugin} פריטים',
        );
      }
      final toolbarIds = startup.toolbarItems
          .map((item) => item['id'])
          .whereType<String>()
          .toList();
      if (toolbarIds.toSet().length != toolbarIds.length) {
        errors.add('contributes.startup.toolbarItems מכיל מזהה כפול');
      }
      final registry = PluginToolbarRegistry.detached();
      for (final item in startup.toolbarItems.where(
        (item) => !DeclarativeToolbarTemplateCompiler.isDeclarative(item),
      )) {
        try {
          registry.registerPayload(manifest.id, item);
        } catch (e) {
          errors.add('contributes.startup.toolbarItems לא תקין: $e');
        }
      }
    }

    if (startup.contextMenuItems.isNotEmpty) {
      if (!declaredPermissions.contains('reader.context_menu')) {
        warnings.add(
          'contributes.startup.contextMenuItems דורש את ההרשאה '
          '"reader.context_menu" שלא הוכרזה ב-manifest',
        );
      }
      final registry = ContextMenuRegistry.detached();
      for (final item in startup.contextMenuItems) {
        try {
          registry.registerPayload(manifest.id, item);
        } catch (e) {
          errors.add('contributes.startup.contextMenuItems לא תקין: $e');
        }
      }
      _validateContextMenuActions(
        manifest,
        startup.contextMenuItems,
        declaredPermissions,
        errors,
      );
    }

    if (startup.publishedData.isNotEmpty) {
      if (!declaredPermissions.contains('published_data.write')) {
        warnings.add(
          'contributes.startup.publishedData דורש את ההרשאה '
          '"published_data.write" שלא הוכרזה ב-manifest',
        );
      }
      for (final record in startup.publishedData) {
        final type = record['type'];
        final key = record['key'];
        final scope = record['scope'];
        if (type is! String ||
            type.isEmpty ||
            key is! String ||
            key.isEmpty ||
            record['payload'] == null ||
            (scope != null && scope is! String)) {
          errors.add(
            'רשומת contributes.startup.publishedData חייבת לכלול type, key '
            'ו-payload (ו-scope מחרוזת אם צוין): ${jsonEncode(record)}',
          );
        }
      }
    }

    if (startup.searchDialogItems.isNotEmpty) {
      if (!declaredPermissions.contains('search.dialog')) {
        errors.add(
          'contributes.startup.searchDialogItems דורש את ההרשאה '
          '"search.dialog" שלא הוכרזה ב-manifest',
        );
      }
      if (startup.searchDialogItems.length >
          PluginSearchDialogItem.maxItemsPerPlugin) {
        errors.add(
          'contributes.startup.searchDialogItems מוגבל ל-'
          '${PluginSearchDialogItem.maxItemsPerPlugin} פריטים',
        );
      }
      if (startup.searchDialogItems.any(
        (item) => item['openPluginOnSubmit'] == true,
      )) {
        try {
          if (PluginVersionUtils.compareCoreVersions(
                _searchSubmitRoutingMinVersion,
                manifest.minAppVersion,
              ) >
              0) {
            errors.add(
              'openPluginOnSubmit נתמך החל מגרסה '
              '$_searchSubmitRoutingMinVersion, אך minAppVersion שהוצהר הוא '
              '${manifest.minAppVersion}. עדכן את minAppVersion',
            );
          }
        } on PluginVersionFormatException {
          // minAppVersion נבדק ב-PluginManifestValidator.
        }
      }
      final itemIds = <String>{};
      for (final item in startup.searchDialogItems) {
        try {
          final parsed = PluginSearchDialogItem.fromPayload(item);
          if (!itemIds.add(parsed.id)) {
            errors.add('contributes.startup.searchDialogItems מכיל מזהה כפול');
          }
        } on PluginSearchDialogItemException catch (error) {
          errors.add('contributes.startup.searchDialogItems לא תקין: $error');
        }
      }
    }

    if (startup.externalEditions.isNotEmpty) {
      for (final permission in const ['database.read', 'library.books.read']) {
        if (!declaredPermissions.contains(permission)) {
          errors.add(
            'contributes.startup.externalEditions דורש את ההרשאה '
            '"$permission" ב-manifest',
          );
        }
      }
      if (startup.externalEditions.length >
          PluginExternalEditionsRegistry.maxItemsPerPlugin) {
        errors.add(
          'contributes.startup.externalEditions מוגבל ל-'
          '${PluginExternalEditionsRegistry.maxItemsPerPlugin} תרומות',
        );
      }
      try {
        if (PluginVersionUtils.compareCoreVersions(
              _externalEditionsMinVersion,
              manifest.minAppVersion,
            ) >
            0) {
          errors.add(
            'contributes.startup.externalEditions נתמך החל מגרסה '
            '$_externalEditionsMinVersion, אך minAppVersion שהוצהר הוא '
            '${manifest.minAppVersion}',
          );
        }
      } on PluginVersionFormatException {
        // minAppVersion נבדק ב-PluginManifestValidator.
      }
      final declaredSourceIds = {
        for (final source in manifest.databaseSources)
          if (source['id'] is String) source['id'] as String,
      };
      final editionIds = <String>{};
      for (final item in startup.externalEditions) {
        try {
          final parsed = PluginExternalEditionsRegistry.parsePayload(
            item,
            declaredSourceIds: declaredSourceIds,
          );
          if (!editionIds.add(parsed.id)) {
            errors.add('contributes.startup.externalEditions מכיל מזהה כפול');
          }
        } on PluginExternalEditionsException catch (error) {
          errors.add('contributes.startup.externalEditions לא תקין: $error');
        }
      }
    }

    final compiledPrograms = <String, CompiledDeclarativeProgram>{};
    if (startup.programs.isNotEmpty) {
      if (startup.programs.length > 8) {
        errors.add('contributes.startup.programs מוגבל ל-8 תכניות');
      }
      try {
        if (PluginVersionUtils.compareCoreVersions(
              _declarativeProgramsMinVersion,
              manifest.minAppVersion,
            ) >
            0) {
          errors.add(
            'contributes.startup.programs נתמך החל מגרסה '
            '$_declarativeProgramsMinVersion, אך minAppVersion שהוצהר הוא '
            '${manifest.minAppVersion}',
          );
        }
      } on PluginVersionFormatException {
        // minAppVersion נבדק ב-PluginManifestValidator.
      }
      final usedCommandTypes = <String>{
        for (final program in startup.programs)
          if (program['commands'] case final List commands)
            for (final command in commands.whereType<Map>())
              if (command['type'] case final String type) type,
      };
      for (final entry in _commandMinVersions.entries) {
        if (!usedCommandTypes.contains(entry.key)) continue;
        try {
          if (PluginVersionUtils.compareCoreVersions(
                entry.value,
                manifest.minAppVersion,
              ) >
              0) {
            errors.add(
              '${entry.key} נתמכת החל מגרסה ${entry.value}, אך '
              'minAppVersion שהוצהר הוא ${manifest.minAppVersion}',
            );
          }
        } on PluginVersionFormatException {
          // minAppVersion נבדק ב-PluginManifestValidator.
        }
      }
      final sourceIds = {
        for (final source in manifest.databaseSources)
          if (source['id'] is String) source['id'] as String,
      };
      final compiler = DeclarativeProgramCompiler(
        declaredPermissions: declaredPermissions,
        declaredSourceIds: sourceIds,
      );
      final programIds = <String>{};
      for (final program in startup.programs) {
        try {
          final compiled = compiler.compile(program);
          if (!programIds.add(compiled.id)) {
            errors.add(
              'contributes.startup.programs מכיל מזהה כפול: ${compiled.id}',
            );
          } else {
            compiledPrograms[compiled.id] = compiled;
          }
        } on DeclarativeProgramException catch (error) {
          errors.add('contributes.startup.programs לא תקין: $error');
        }
      }
    }

    final declarativeToolbarItems = startup.toolbarItems
        .where(DeclarativeToolbarTemplateCompiler.isDeclarative)
        .toList();
    if (declarativeToolbarItems.isNotEmpty) {
      final usedActionTypes = <String>{
        for (final item in declarativeToolbarItems) ...[
          if (item['action'] case {'type': final String type}) type,
          if (item['childrenBinding'] case {
            'itemTemplate': {'action': {'type': final String type}},
          })
            type,
        ],
      };
      for (final entry in _actionMinVersions.entries) {
        if (!usedActionTypes.contains(entry.key)) continue;
        try {
          if (PluginVersionUtils.compareCoreVersions(
                entry.value,
                manifest.minAppVersion,
              ) >
              0) {
            errors.add(
              '${entry.key} נתמכת החל מגרסה ${entry.value}, אך '
              'minAppVersion שהוצהר הוא ${manifest.minAppVersion}',
            );
          }
        } on PluginVersionFormatException {
          // minAppVersion נבדק ב-PluginManifestValidator.
        }
      }
      try {
        DeclarativeToolbarTemplateCompiler(
          declaredPermissions: declaredPermissions,
          programs: compiledPrograms,
        ).compileAll(manifest.id, declarativeToolbarItems);
      } on DeclarativeProgramException catch (error) {
        errors.add('contributes.startup.toolbarItems לא תקין: $error');
      } on PluginToolbarException catch (error) {
        errors.add('contributes.startup.toolbarItems לא תקין: $error');
      }
    }

    if (startup.activationEvents.isNotEmpty &&
        !declaredPermissions.contains(pluginRunOnStartupPermission)) {
      warnings.add(
        'contributes.startup.activationEvents מדליק את מנוע התוסף בלי כניסה '
        'לדף שלו, ולכן דורש גם את ההרשאה "$pluginRunOnStartupPermission" '
        'שלא הוכרזה ב-manifest',
      );
    }
    if (startup.keepAlive) {
      if (!declaredPermissions.contains(pluginRunOnStartupPermission)) {
        errors.add(
          'contributes.startup.keepAlive דורש את ההרשאה '
          '"$pluginRunOnStartupPermission"',
        );
      }
      if (!declaredPermissions.contains(pluginBackgroundKeepAlivePermission)) {
        errors.add(
          'contributes.startup.keepAlive דורש את ההרשאה '
          '"$pluginBackgroundKeepAlivePermission"',
        );
      }
    } else if (declaredPermissions.contains(
      pluginBackgroundKeepAlivePermission,
    )) {
      warnings.add(
        'ההרשאה "$pluginBackgroundKeepAlivePermission" הוצהרה ללא '
        'contributes.startup.keepAlive: true',
      );
    }
    for (final topic in startup.activationEvents) {
      if (topic == PluginStartupContributions.startupActivationTopic) continue;
      if (!_knownEvents.contains(topic)) {
        warnings.add(
          'contributes.startup.activationEvents — נושא לא מוכר: $topic',
        );
        continue;
      }
      final permission = 'events.subscribe:$topic';
      if (pluginValidPermissions.contains(permission) &&
          !declaredPermissions.contains(permission)) {
        warnings.add(
          'activation event "$topic" דורש את ההרשאה "$permission" '
          'שלא הוכרזה ב-manifest',
        );
      }
    }
  }

  /// בדיקות network — כל הליקויים כאן מסווגים כ-warnings, כי לפי התיעוד
  /// הרשמי `network.allowlist` הוא "שדה הצהרתי בלבד" (ברירת מחדל `[]`)
  /// וההרשאה בפועל מנוהלת ע"י אוצריא בקוד. אריזה לא תיחסם, אך נציין למפתח
  /// שאם הוא מצהיר על שימוש ברשת — כדאי להצהיר במפורש לאן.
  static void _validateNetwork(
    Map<String, dynamic> manifestJson,
    Set<String> declaredPermissions,
    List<String> errors,
    List<String> warnings,
  ) {
    final network = manifestJson['network'];
    final networkEnabled = network is Map && network['enabled'] == true;
    final networkRequested =
        networkEnabled ||
        declaredPermissions.contains('network.access') ||
        declaredPermissions.contains('network.localhost');
    if (!networkRequested) return;

    final allowlistRaw = network is Map ? network['allowlist'] : null;
    if (allowlistRaw is! List || allowlistRaw.isEmpty) {
      warnings.add(
        'התוסף מבקש גישת רשת (network.access / network.localhost / network.enabled) אך network.allowlist ריק. השדה הוא הצהרתי בלבד (התיעוד בפועל מוגדר באוצריא), אך מומלץ לפרט את הכתובות שבהן התוסף עושה שימוש לטובת שקיפות מול המשתמש',
      );
      return;
    }
    final urlPattern = RegExp(r'^https?://', caseSensitive: false);
    for (final raw in allowlistRaw) {
      if (raw is! String) {
        warnings.add(
          'כתובת לא תקינה ב-network.allowlist: ${jsonEncode(raw)} (מומלץ http(s) URL מלא, או שם host מקומי כמו 127.0.0.1)',
        );
        continue;
      }
      final trimmed = raw.trim();
      // host חשוף ל-loopback (127.0.0.1 / localhost) תקין — מתיר כל פורט
      // על אותו host עבור שירות מקומי (network.localhost).
      if (isLoopbackHost(trimmed)) continue;
      if (!urlPattern.hasMatch(trimmed)) {
        warnings.add(
          'כתובת לא תקינה ב-network.allowlist: ${jsonEncode(raw)} (מומלץ http(s) URL מלא, או שם host מקומי כמו 127.0.0.1)',
        );
      } else if (trimmed.contains('*')) {
        warnings.add('network.allowlist אינו תומך ב-wildcard: $trimmed');
      }
    }
  }

  /// זהות `contributes.toolTab.title` ל-name נאכפת כשגיאה חוסמת ב-
  /// `PluginManifestValidator.validateManifest` (רץ גם בהתקנה וגם באריזה),
  /// לכן אין כאן בדיקה נוספת. נשמר כ-hook עתידי לאזהרות עיצוב סביב הטאב.
  static void _checkNameVsToolTabTitle(
    Map<String, dynamic> manifestJson,
    List<String> warnings,
  ) {
    return;
  }

  // ===== File collection =====

  /// אוסף קבצים נסרקים: manifest.json + קוד (js/mjs/cjs/html/vue/svelte) + סגנון (css/html).
  static Map<String, File> _collectScannableFiles(String directoryPath) {
    final out = <String, File>{};
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) return out;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: directoryPath);
      // נורמליזציה ל-forward slashes כמו ב-zip entries
      final relNorm = rel.replaceAll('\\', '/');
      if (relNorm == 'manifest.json' ||
          _isCodeLikeFile(relNorm) ||
          _isStyleLikeFile(relNorm)) {
        out[relNorm] = entity;
      }
    }
    return out;
  }

  static final RegExp _codeFileRe = RegExp(
    r'\.(?:js|mjs|cjs|html?|vue|svelte)$',
    caseSensitive: false,
  );
  static final RegExp _styleFileRe = RegExp(
    r'\.(?:css|html?)$',
    caseSensitive: false,
  );

  static bool _isCodeLikeFile(String name) => _codeFileRe.hasMatch(name);
  static bool _isStyleLikeFile(String name) => _styleFileRe.hasMatch(name);

  // ===== Code scanning =====

  static final RegExp _callRe = RegExp(
    r'''Otzaria\s*\.\s*call\s*\(\s*['"]([a-zA-Z][\w.]*)['"]''',
  );
  static final RegExp _onRe = RegExp(
    r'''Otzaria\s*\.\s*on\s*\(\s*['"]([a-zA-Z][\w.]*)['"]''',
  );
  static final RegExp _offRe = RegExp(
    r'''Otzaria\s*\.\s*off\s*\(\s*['"]([a-zA-Z][\w.]*)['"]''',
  );
  static final RegExp _shorthandRe = RegExp(
    r'''Otzaria\s*\.\s*([a-z][a-zA-Z0-9_]*)\s*\.\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\(''',
  );

  static _ApiUsage _scanCodeForApiUsage(String text) {
    final cleaned = _stripCommentsForScan(text);
    final methods = <String>{};
    final events = <String>{};

    for (final m in _callRe.allMatches(cleaned)) {
      methods.add(m.group(1)!);
    }
    for (final m in _shorthandRe.allMatches(cleaned)) {
      final holder = m.group(1)!;
      final method = m.group(2)!;
      if (_reservedHolderFields.contains(holder)) continue;
      methods.add('$holder.$method');
    }
    for (final m in _onRe.allMatches(cleaned)) {
      events.add(m.group(1)!);
    }
    for (final m in _offRe.allMatches(cleaned)) {
      events.add(m.group(1)!);
    }
    return _ApiUsage(methods: methods, events: events);
  }

  /// מסיר הערות HTML/JS לפני סריקת קריאות API. סדר הפעולות:
  ///
  ///   1. הערות בלוקיות (HTML `<!-- -->` ו-JS `/* */`) מוסרות.
  ///   2. **string literals** (single/double/backtick) מוחלפים זמנית
  ///      ב-placeholders — כך ש-`//` בתוך URL לא ייחתך.
  ///   3. **regex literals** (`/.../flags` אחרי הקשר מתאים) נמחקים — כך
  ///      ש-`//` בתוך regex כמו `/https?:\/\/example/` לא יחתוך את שאר
  ///      השורה, ותוכן ה-regex (כולל הטקסט "Otzaria.call") לא ייספר כקריאה.
  ///   4. הערות שורה (`//`) מוסרות — בתחילת שורה וגם inline.
  ///   5. ה-placeholders של ה-strings מוחזרים לקדמותם (regex לא — הוא נמחק).
  ///
  /// זיהוי regex ב-JS הוא קלאסית חצי-החלטה (`/` יכול להיות חלוקה).
  /// אנחנו לא בונים lexer מלא; אנחנו מזהים regex רק כשהוא מופיע אחרי
  /// תווי הקשר ש**לא** יכולים להיות אופרנד שמאלי של חלוקה (כמו `=`,
  /// `(`, `,`, `;`, `return`, `=>`).
  static String _stripCommentsForScan(String text) {
    var stripped = text
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

    // מחליפים מחרוזות בערך תפסן כדי שהריגקס של `//` לא יחתוך URL/regex.
    // הריגקסים תופסים מחרוזות single/double/backtick, ומתעלמים מתווי escape
    // (`\'`, `\"`, ``\` ``) כדי לא לסגור מוקדם.
    final placeholders = <String>[];
    String replaceLiteral(Match m) {
      final idx = placeholders.length;
      placeholders.add(m.group(0)!);
      return '__OTZ_STR_${idx}__';
    }

    // (2) string literals — single/double/backtick. `\\.` תופס escape
    // sequences כדי שמרכאות בורחות לא יסגרו את הספירה מוקדם.
    stripped = stripped.replaceAllMapped(
      RegExp(
        r"'(?:\\.|[^'\\])*'"
        r'|"(?:\\.|[^"\\])*"'
        r'|`(?:\\.|[^`\\])*`',
      ),
      replaceLiteral,
    );

    // (3) regex literals — רק אחרי "הקשר רגקס" (תו או מילת מפתח שמרמזים
    // שהבא הוא ביטוי, לא חלוקה). שומרים את ההקשר ב-group(1) וב-group(2),
    // ואת ה-regex עצמו (group(3)) מוחקים (לא נסרק ולא משוחזר). ה-character-class
    // ‎`\[…\]` בתוך הregex מאפשר `/` בלתי בורח בתוך class (למשל `/[a-z\/]/`).
    stripped = stripped.replaceAllMapped(
      RegExp(
        r'(^|[=(,;:!?~&|+\-*/%<>{}\[\]]|=>|\breturn\b|\bthrow\b|\bin\b|\bof\b|\btypeof\b|\bdelete\b|\bvoid\b|\binstanceof\b|\bnew\b)'
        r'(\s*)'
        r'(/(?:\\.|\[(?:\\.|[^\]\\\n\r])*\]|[^/\\\n\r])+?/[gimsuyd]*)',
      ),
      (m) {
        // regex literals נמחקים מהסריקה (לא משוחזרים): `//` או הטקסט
        // "Otzaria.call" בתוכם אינם קריאה אמיתית ואסור שייספרו.
        return '${m.group(1)}${m.group(2)} ';
      },
    );

    // (4) line comments — בטוח להסיר כעת, כי strings ו-regex כבר
    // הוחלפו ב-placeholders.
    stripped = stripped.replaceAll(RegExp(r'//[^\n\r]*'), '');

    // מחזירים את המחרוזות לקדמותן.
    stripped = stripped.replaceAllMapped(
      RegExp(r'__OTZ_STR_(\d+)__'),
      (m) => placeholders[int.parse(m.group(1)!)],
    );

    return stripped;
  }

  // ===== Design compliance =====

  static const Set<String> _allowedColorKeywords = {
    'inherit',
    'initial',
    'unset',
    'revert',
    'currentcolor',
    'transparent',
    'none',
  };

  static final RegExp _namedColorRe = RegExp(
    r'\b(black|white|red|green|blue|yellow|gray|grey|purple|orange|pink|brown|cyan|magenta|silver|gold|maroon|navy|teal|olive|aqua|fuchsia|lime|violet|indigo|coral|crimson|salmon|khaki|beige|ivory|wheat|tan|chocolate|tomato|turquoise|orchid)\b',
    caseSensitive: false,
  );
  static final RegExp _hexColorRe = RegExp(r'#[0-9a-fA-F]{3,8}\b');
  static final RegExp _rgbHslRe = RegExp(
    r'\b(?:rgb|rgba|hsl|hsla)\s*\(',
    caseSensitive: false,
  );
  static final RegExp _colorPropRe = RegExp(
    r'(?:^|[\s;{])(color|background(?:-color)?|border(?:-(?:top|right|bottom|left))?(?:-color)?|outline(?:-color)?|fill|stroke)\s*:\s*([^;}]+)',
    caseSensitive: false,
  );

  static DesignComplianceReport _checkDesignCompliance(
    Map<String, File> files,
  ) {
    final violations = <String>[];
    final cssChunks = <_CssChunk>[];
    var sawAnyHtml = false;
    var sawAnyCss = false;

    for (final entry in files.entries) {
      final name = entry.key;
      final file = entry.value;

      if (RegExp(r'\.css$', caseSensitive: false).hasMatch(name)) {
        sawAnyCss = true;
        try {
          cssChunks.add(_CssChunk(name, file.readAsStringSync()));
        } catch (_) {}
      } else if (RegExp(r'\.html?$', caseSensitive: false).hasMatch(name)) {
        sawAnyHtml = true;
        String html;
        try {
          html = file.readAsStringSync();
        } catch (_) {
          continue;
        }

        final rootMatch = RegExp(
          r'<html\b([^>]*)>',
          caseSensitive: false,
        ).firstMatch(html);
        if (rootMatch != null) {
          final attrs = rootMatch.group(1) ?? '';
          if (!RegExp(
            r'''\bdir\s*=\s*['"]\s*rtl\s*['"]''',
            caseSensitive: false,
          ).hasMatch(attrs)) {
            violations.add('$name: תג <html> חייב לכלול dir="rtl"');
          }
          if (!RegExp(
            r'''\blang\s*=\s*['"]\s*he\s*['"]''',
            caseSensitive: false,
          ).hasMatch(attrs)) {
            violations.add('$name: תג <html> חייב לכלול lang="he"');
          }
        }

        final styleRe = RegExp(
          r'<style[^>]*>([\s\S]*?)</style>',
          caseSensitive: false,
        );
        for (final m in styleRe.allMatches(html)) {
          cssChunks.add(_CssChunk('$name (<style>)', m.group(1) ?? ''));
        }
      }
    }

    if (!sawAnyHtml && !sawAnyCss) {
      return const DesignComplianceReport(
        compliant: false,
        violations: [
          'לא נמצאו קבצי HTML/CSS שניתן לבדוק את תאימות העיצוב שלהם',
        ],
      );
    }

    for (final chunk in cssChunks) {
      var stripped = _stripCssComments(chunk.css);
      // הגדרות של CSS custom properties (`--color-foo: #xxx;`,
      // `--font-size-base: 18px;`, וכד') מותרות במפורש לפי DESIGN_GUIDE —
      // הן ברירות מחדל לפני applyTheme. מוציאים אותן מהמחרוזת לפני סריקה
      // כדי שלא יזוהו כהפרה.
      stripped = stripped.replaceAll(
        RegExp(r'--[a-zA-Z_][\w-]*\s*:\s*[^;}]+;?'),
        '',
      );
      final seen = <String>{};
      void addOnce(String type, String message) {
        if (!seen.add(type)) return;
        violations.add(message);
      }

      // 1. צבעי hex
      final hexMatches = _hexColorRe
          .allMatches(stripped)
          .map((m) => m.group(0)!)
          .toList();
      if (hexMatches.isNotEmpty) {
        final sample = hexMatches.toSet().take(3).join(', ');
        addOnce(
          'hex',
          '${chunk.name}: צבעי hex מקודדים ($sample). חובה var(--color-*)',
        );
      }

      // 2. rgb/hsl
      if (_rgbHslRe.hasMatch(stripped)) {
        addOnce(
          'rgb',
          '${chunk.name}: ערכי rgb()/rgba()/hsl()/hsla() מקודדים. חובה var(--color-*)',
        );
      }

      // 3. שמות צבעים באנגלית בערכי color/background/border/outline/fill/stroke
      for (final propMatch in _colorPropRe.allMatches(stripped)) {
        final value = (propMatch.group(2) ?? '').trim();
        if (RegExp(r'var\s*\(').hasMatch(value)) continue;
        final firstToken = value.split(RegExp(r'[\s,]'))[0].toLowerCase();
        if (_allowedColorKeywords.contains(firstToken)) continue;
        if (RegExp(r'^[\d.]+(px|em|rem|%)?$').hasMatch(firstToken)) continue;
        if (_namedColorRe.hasMatch(value)) {
          final preview = value.length > 40 ? value.substring(0, 40) : value;
          addOnce(
            'named',
            '${chunk.name}: שם צבע באנגלית בערך CSS ("$preview"). חובה var(--color-*)',
          );
          break;
        }
      }

      // 4. font-family שאינו var(--font-*)
      for (final m in RegExp(
        r'font-family\s*:\s*([^;}]+)',
        caseSensitive: false,
      ).allMatches(stripped)) {
        final value = (m.group(1) ?? '').trim();
        if (!RegExp(
          r'var\s*\(\s*--font',
          caseSensitive: false,
        ).hasMatch(value)) {
          final preview = value.length > 50 ? value.substring(0, 50) : value;
          addOnce(
            'font-family',
            '${chunk.name}: font-family מקודד ("$preview"). חובה var(--font-main)',
          );
          break;
        }
      }

      // 5. font-size ב-px קבוע
      for (final m in RegExp(
        r'font-size\s*:\s*([^;}]+)',
        caseSensitive: false,
      ).allMatches(stripped)) {
        final value = (m.group(1) ?? '').trim();
        if (RegExp(r'var\s*\(').hasMatch(value)) continue;
        if (RegExp(
          r'^\d+(?:\.\d+)?\s*(?:em|rem|%)$',
          caseSensitive: false,
        ).hasMatch(value)) {
          continue;
        }
        if (RegExp(r'^0(?:px)?$').hasMatch(value)) continue;
        // חריג פס הכותרת: DESIGN_GUIDE מחייב שם גדלים קשיחים ב-px דווקא, כדי
        // שהפס לא יתנפח עם גופן הקריאה של המשתמש. נאכף לפי שם הסלקטור.
        if (_isTopBarSelector(_selectorAtOffset(stripped, m.start))) continue;
        if (RegExp(r'\d+\s*px', caseSensitive: false).hasMatch(value)) {
          final preview = value.length > 30 ? value.substring(0, 30) : value;
          addOnce(
            'font-size-px',
            '${chunk.name}: font-size ב-px קבוע ("$preview"). חובה em/rem או '
                'var(--font-size-base) (px מותר רק בסלקטור פס הכותרת — ראו '
                'DESIGN_GUIDE.md)',
          );
          break;
        }
      }

      // 6. border-radius ב-px ארביטררי
      for (final m in RegExp(
        r'border-radius\s*:\s*([^;}]+)',
        caseSensitive: false,
      ).allMatches(stripped)) {
        final value = (m.group(1) ?? '').trim();
        if (RegExp(r'var\s*\(').hasMatch(value)) continue;
        if (RegExp(r'^0(?:px)?(?:\s+0(?:px)?)*$').hasMatch(value)) continue;
        if (RegExp(r'^\d+(?:\.\d+)?\s*%$').hasMatch(value)) continue;
        if (RegExp(r'\d+\s*px', caseSensitive: false).hasMatch(value)) {
          final preview = value.length > 30 ? value.substring(0, 30) : value;
          addOnce(
            'radius-px',
            '${chunk.name}: border-radius ב-px קבוע ("$preview"). חובה var(--radius-sm/md/lg/pill)',
          );
          break;
        }
      }
    }

    // נדרש שימוש כלשהו ב-var(--color-*)
    final usesColorVar = cssChunks.any(
      (c) =>
          RegExp(r'var\s*\(\s*--color-', caseSensitive: false).hasMatch(c.css),
    );
    if (cssChunks.isNotEmpty && !usesColorVar) {
      violations.add(
        'לא נמצא שימוש כלשהו ב-var(--color-*) — חובה להזין צבעים מ-API לפי תיעוד העיצוב',
      );
    }

    return DesignComplianceReport(
      compliant: violations.isEmpty,
      violations: violations,
    );
  }

  /// הסלקטור של הכלל שבתוכו נמצא ההיסט — לחריגים תלויי-סלקטור בסריקת ה-CSS.
  /// (סריקה טקסטואלית: נסוגים אל ה-'{' הפותח, והסלקטור הוא מה שלפניו עד סוף
  ///  הכלל/הבלוק הקודם.)
  @visibleForTesting
  static String selectorAtOffset(String css, int index) =>
      _selectorAtOffset(css, index);

  static String _selectorAtOffset(String css, int index) {
    final open = css.lastIndexOf('{', index);
    if (open <= 0) return '';
    final start = [
      css.lastIndexOf('}', open - 1),
      css.lastIndexOf('{', open - 1),
    ].reduce((a, b) => a > b ? a : b);
    return css.substring(start + 1, open).trim();
  }

  /// פס כותרת התוסף — הסלקטור המוסכם ב-DESIGN_GUIDE (`.topbar` / `.top-bar`).
  static bool _isTopBarSelector(String selector) =>
      RegExp(r'top-?bar', caseSensitive: false).hasMatch(selector);

  static String _stripCssComments(String css) =>
      css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
}

class _ApiUsage {
  final Set<String> methods;
  final Set<String> events;
  _ApiUsage({required this.methods, required this.events});
}

class _CssChunk {
  final String name;
  final String css;
  _CssChunk(this.name, this.css);
}
