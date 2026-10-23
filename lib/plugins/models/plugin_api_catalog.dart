/// חוזה שיטת SDK: הרשאת הגשר, גרסה ואפשרויות הוולידציה.
class PluginApiMethod {
  const PluginApiMethod(
    this.runtimePermission,
    this.minVersion, {
    String? validationPermission,
    bool validatePermission = true,
    this.hasPermissionHint = false,
    this.documented = true,
  }) : validationPermission = validatePermission
           ? validationPermission ?? runtimePermission
           : null;

  final String? runtimePermission;
  final String? minVersion;
  final String? validationPermission;
  final bool hasPermissionHint;
  final bool documented;
}

/// סמן מפורש לפעולה שהרשאתה נאכפת מחוץ לטבלת המניפסט.
const pluginApiNoManifestPermission = '<none>';

/// מקור האמת לשיטות ה-SDK; נתוני האריזה והריצה נגזרים ממנו.
const Map<String, PluginApiMethod> pluginApiMethods = {
  'app.getInfo': PluginApiMethod(
    'app.info.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'app.getTheme': PluginApiMethod(
    'app.info.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'app.getLocale': PluginApiMethod(
    'app.info.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'app.getGrantedPermissions': PluginApiMethod(
    'app.info.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'app.getConnectivity': PluginApiMethod(
    'app.info.read',
    '0.9.96',
    hasPermissionHint: true,
  ),
  'fonts.resolveFamilies': PluginApiMethod(
    'app.info.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'fonts.listInstalled': PluginApiMethod(
    'app.info.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'app.getUserEmail': PluginApiMethod(
    'app.user_email.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'app.openUrl': PluginApiMethod(
    'app.open_url',
    '0.9.95',
    hasPermissionHint: true,
  ),
  'app.registerShortcut': PluginApiMethod(
    'app.shortcuts',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'app.unregisterShortcut': PluginApiMethod(
    'app.shortcuts',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'app.updateShortcut': PluginApiMethod(
    'app.shortcuts',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'library.findBooks': PluginApiMethod(
    'library.books.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'library.resolveRef': PluginApiMethod(
    'library.books.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'library.getBookMetadata': PluginApiMethod(
    'library.books.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'library.getBookDetails': PluginApiMethod(
    'library.books.read',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'library.getBookProtections': PluginApiMethod(
    'library.books.read',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'library.resolveBooks': PluginApiMethod(
    'library.books.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'library.resolveCategoryPaths': PluginApiMethod(
    'library.books.read',
    '0.9.97',
  ),
  'library.listRecentBooks': PluginApiMethod(
    'library.books.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'library.getTree': PluginApiMethod(
    'library.books.read',
    '0.9.93',
    hasPermissionHint: true,
  ),
  'library.getBookContent': PluginApiMethod(
    'library.content.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'library.openBookFile': PluginApiMethod(
    'library.content.read',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'library.getBookToc': PluginApiMethod(
    'library.content.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'library.listBookAltStructures': PluginApiMethod(
    'library.content.read',
    '0.9.96',
    hasPermissionHint: true,
  ),
  'library.getBookAltToc': PluginApiMethod(
    'library.content.read',
    '0.9.96',
    hasPermissionHint: true,
  ),
  'library.getLinkContent': PluginApiMethod(
    'library.content.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'library.getCommentators': PluginApiMethod(
    'library.links.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'library.getLinks': PluginApiMethod(
    'library.links.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'library.getRawLinks': PluginApiMethod(
    'library.links.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'library.getLinkTargetsSummary': PluginApiMethod(
    'library.links.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'library.refreshUserBooks': PluginApiMethod(
    'library.refresh',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'library.setProviderBooks': PluginApiMethod(
    'library.books.provide',
    '0.9.98',
  ),
  'search.fullText': PluginApiMethod('search.fulltext.read', '0.9.89'),
  'search.query': PluginApiMethod('search.fulltext.read', '0.9.97'),
  'search.getOptions': PluginApiMethod('search.fulltext.read', '0.9.97'),
  'search.setFieldText': PluginApiMethod(
    'search.field_actions',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'search.setFieldActionState': PluginApiMethod(
    'search.field_actions',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'search.endFieldSession': PluginApiMethod(
    'search.field_actions',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.openBook': PluginApiMethod('reader.open', '0.9.89'),
  'reader.openBookAtRef': PluginApiMethod('reader.open', '0.9.89'),
  'reader.printRange': PluginApiMethod(
    'reader.open',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.openSearchTab': PluginApiMethod('reader.open', '0.9.89'),
  'reader.getCurrentState': PluginApiMethod('reader.open', '0.9.89'),
  'reader.getDefaultTextReader': PluginApiMethod(
    'reader.open',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.setDefaultTextReader': PluginApiMethod(
    'reader.open',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.reportTextReaderLocation': PluginApiMethod(
    'reader.open',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.setTextReaderFontSize': PluginApiMethod(
    'reader.open',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.getCurrentRef': PluginApiMethod('reader.open', '0.9.89'),
  'reader.closeTab': PluginApiMethod(
    'reader.open',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'reader.activateTab': PluginApiMethod(
    'reader.open',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'reader.getSelection': PluginApiMethod('reader.open', '0.9.89'),
  'reader.getActiveCommentators': PluginApiMethod(
    'reader.open',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'reader.setActiveCommentators': PluginApiMethod(
    'reader.open',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'reader.getPageShapeLayout': PluginApiMethod('reader.open', '0.9.97'),
  'reader.setPageShapeCommentatorVisibility': PluginApiMethod(
    'reader.open',
    '0.9.97',
  ),
  'reader.scrollToSection': PluginApiMethod(
    'reader.open',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'reader.getHighlightCapabilities': PluginApiMethod(
    'reader.open',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'reader.findTextOccurrences': PluginApiMethod(
    'reader.open',
    '0.9.95',
    hasPermissionHint: true,
  ),
  'reader.getSectionTextMap': PluginApiMethod(
    'reader.open',
    '0.9.95',
    hasPermissionHint: true,
  ),
  'reader.beginCorrectionSession': PluginApiMethod(
    'reader.local_edit',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.getCorrectionSession': PluginApiMethod(
    'reader.local_edit',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.restoreCorrectionDraft': PluginApiMethod(
    'reader.local_edit',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.resetCorrection': PluginApiMethod(
    'reader.local_edit',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.endCorrectionSession': PluginApiMethod(
    'reader.local_edit',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.acknowledgeCorrectionDraft': PluginApiMethod(
    'reader.local_edit',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.listCorrectionDrafts': PluginApiMethod(
    'reader.local_edit',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.getCorrectionDraft': PluginApiMethod(
    'reader.local_edit',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'reader.registerInBookSearchProvider': PluginApiMethod(
    'reader.open',
    '0.9.97',
  ),
  'reader.respondInBookSearch': PluginApiMethod('reader.open', '0.9.97'),
  'reader.registerExternalSearchProvider': PluginApiMethod(
    'reader.open',
    '0.9.97',
  ),
  'reader.respondExternalSearch': PluginApiMethod('reader.open', '0.9.97'),
  'reader.addContextMenuItem': PluginApiMethod(
    'reader.context_menu',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'reader.removeContextMenuItem': PluginApiMethod(
    'reader.context_menu',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'reader.updateContextMenuItem': PluginApiMethod(
    'reader.context_menu',
    '0.9.95',
    hasPermissionHint: true,
  ),
  'reader.addToolbarItem': PluginApiMethod(
    'reader.toolbar',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'reader.removeToolbarItem': PluginApiMethod(
    'reader.toolbar',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'reader.updateToolbarItem': PluginApiMethod(
    'reader.toolbar',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'reader.setHighlight': PluginApiMethod(
    'reader.highlight',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'reader.updateHighlight': PluginApiMethod(
    'reader.highlight',
    '0.9.95',
    hasPermissionHint: true,
  ),
  'reader.getHighlights': PluginApiMethod(
    'reader.highlight',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'reader.revealHighlight': PluginApiMethod(
    'reader.highlight',
    '0.9.96',
    hasPermissionHint: true,
  ),
  'reader.clearHighlight': PluginApiMethod(
    'reader.highlight',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'reader.clearAllHighlights': PluginApiMethod(
    'reader.highlight',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'workspace.list': PluginApiMethod(
    'workspace.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'workspace.getActive': PluginApiMethod(
    'workspace.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'workspace.create': PluginApiMethod(
    'workspace.manage',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'workspace.switch': PluginApiMethod(
    'workspace.manage',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'navigation.goTo': PluginApiMethod('navigation.write', '0.9.89'),
  'notes.list': PluginApiMethod('notes.read', '0.9.89'),
  'notes.getBookNotesSummary': PluginApiMethod('notes.read', '0.9.89'),
  'notes.add': PluginApiMethod('notes.write', '0.9.89'),
  'notes.update': PluginApiMethod('notes.write', '0.9.89'),
  'notes.delete': PluginApiMethod('notes.write', '0.9.89'),
  'ui.showMessage': PluginApiMethod('ui.feedback', '0.9.89'),
  'ui.showSuccess': PluginApiMethod('ui.feedback', '0.9.89'),
  'ui.showError': PluginApiMethod('ui.feedback', '0.9.89'),
  'ui.showConfirm': PluginApiMethod('ui.feedback', '0.9.89'),
  'ui.showWarning': PluginApiMethod('ui.feedback', '0.9.89'),
  'ui.pickFolder': PluginApiMethod(
    'fs.folder_access',
    '0.9.93',
    hasPermissionHint: true,
  ),
  'ui.print': PluginApiMethod(null, '0.9.97'),
  'ui.printFile': PluginApiMethod(null, '0.9.98'),
  'ui.exportPdf': PluginApiMethod(null, '0.9.97'),
  'ui.setUnsavedChanges': PluginApiMethod(null, '0.9.97'),
  'storage.get': PluginApiMethod('plugin.storage.read', '0.9.89'),
  'storage.list': PluginApiMethod('plugin.storage.read', '0.9.89'),
  'storage.set': PluginApiMethod('plugin.storage.write', '0.9.89'),
  'storage.remove': PluginApiMethod('plugin.storage.write', '0.9.89'),
  'settings.get': PluginApiMethod('settings.read', '0.9.89'),
  'settings.getMany': PluginApiMethod('settings.read', '0.9.89'),
  'calendar.getSelectedDate': PluginApiMethod('calendar.read', '0.9.89'),
  'calendar.getDailyTimes': PluginApiMethod('calendar.read', '0.9.92'),
  'calendar.getHalachicTimes': PluginApiMethod('calendar.read', '0.9.92'),
  'calendar.getJewishDate': PluginApiMethod('calendar.read', '0.9.89'),
  'calendar.getEvents': PluginApiMethod('calendar.read', '0.9.89'),
  'calendar.getCities': PluginApiMethod('calendar.read', '0.9.96'),
  'publishedData.upsert': PluginApiMethod('published_data.write', '0.9.89'),
  'publishedData.remove': PluginApiMethod('published_data.write', '0.9.89'),
  'publishedData.listOwn': PluginApiMethod('published_data.write', '0.9.89'),
  'feedback.sendEmail': PluginApiMethod(
    'feedback.send_email',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'feedback.submitBookCorrection': PluginApiMethod(
    'feedback.send_email',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'feedback.report': PluginApiMethod(null, '0.9.97'),
  'feedback.hasReporterEmail': PluginApiMethod(null, '0.9.97'),
  'history.list': PluginApiMethod(
    'history.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'history.listSearches': PluginApiMethod(
    'history.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'history.clear': PluginApiMethod(
    'history.write',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'history.remove': PluginApiMethod(
    'history.write',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'bookmarks.list': PluginApiMethod(
    'bookmarks.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'bookmarks.add': PluginApiMethod(
    'bookmarks.write',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'bookmarks.remove': PluginApiMethod(
    'bookmarks.write',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'tools.gematria': PluginApiMethod(
    'tools.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'tools.dictionary': PluginApiMethod(
    'tools.read',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'tools.biographies': PluginApiMethod(
    'tools.read',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'notifications.showInApp': PluginApiMethod(
    'notifications.send',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'notifications.sendSystem': PluginApiMethod(
    'notifications.system',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'notifications.scheduleSystem': PluginApiMethod(
    'notifications.system',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'notifications.cancel': PluginApiMethod(
    'notifications.system',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'notifications.cancelAll': PluginApiMethod(
    'notifications.system',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'notifications.checkPermissions': PluginApiMethod(
    'notifications.system',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'notifications.requestPermissions': PluginApiMethod(
    'notifications.system',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'database.listSources': PluginApiMethod(
    'database.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'database.describeSource': PluginApiMethod(
    'database.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'database.query': PluginApiMethod(
    'database.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  'database.batchQuery': PluginApiMethod(
    'database.read',
    '0.9.89',
    hasPermissionHint: true,
  ),
  // ברשת ההרשאה בפועל תלויה ביעד; הוולידטור מכיר גם network.localhost.
  'network.fetchStream': PluginApiMethod(
    null,
    '0.9.97',
    validationPermission: 'network.access',
    hasPermissionHint: true,
  ),
  'network.download': PluginApiMethod(
    null,
    '0.9.93',
    validationPermission: 'network.access',
    hasPermissionHint: true,
  ),
  'network.fetchFile': PluginApiMethod(
    null,
    '0.9.98',
    validationPermission: 'network.access',
    hasPermissionHint: true,
  ),
  'fs.extractZip': PluginApiMethod(null, '0.9.93'),
  'fs.deleteFile': PluginApiMethod(null, '0.9.93'),
  'fs.deleteFolder': PluginApiMethod(null, '0.9.98'),
  'fs.moveEntry': PluginApiMethod(null, '0.9.98'),
  'fs.writeFile': PluginApiMethod(null, '0.9.97'),
  'fs.readFile': PluginApiMethod(null, '0.9.97'),
  'fs.listDir': PluginApiMethod(null, '0.9.97'),
  'fs.makeDir': PluginApiMethod(null, '0.9.97'),
  'fs.deleteEntry': PluginApiMethod(null, '0.9.97'),
  'fs.stat': PluginApiMethod(null, '0.9.97'),
  'fs.pickUserFile': PluginApiMethod(
    'fs.user_files.read',
    '0.9.94',
    hasPermissionHint: true,
  ),
  'fs.resolveFileUrl': PluginApiMethod(
    'fs.user_files.read',
    '0.9.94',
    hasPermissionHint: true,
  ),
  'fs.readTextFile': PluginApiMethod(
    'fs.user_files.read',
    '0.9.94',
    hasPermissionHint: true,
  ),
  'fs.revokeFile': PluginApiMethod(
    'fs.user_files.read',
    '0.9.94',
    hasPermissionHint: true,
  ),
  'fs.pickUserFolder': PluginApiMethod(
    'fs.user_files.read',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'fs.listUserFolder': PluginApiMethod(
    'fs.user_files.read',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'fs.openFolderFile': PluginApiMethod(
    'fs.user_files.read',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'fs.revokeFolder': PluginApiMethod(
    'fs.user_files.read',
    '0.9.98',
    hasPermissionHint: true,
  ),
  'fs.beginBinaryWrite': PluginApiMethod(
    'fs.user_files.write',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'fs.commitUserFileWrite': PluginApiMethod(
    'fs.user_files.write',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'fs.abortBinaryWrite': PluginApiMethod(
    'fs.user_files.write',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'shortcut.create': PluginApiMethod(
    'ui.create_shortcut',
    '0.9.94',
    hasPermissionHint: true,
  ),
  'plugin.openSelf': PluginApiMethod(
    'navigation.write',
    '0.9.96',
    hasPermissionHint: true,
  ),
  'plugin.setNewTabPage': PluginApiMethod('navigation.write', '0.9.97'),
  'plugin.openOther': PluginApiMethod(
    'plugin.open_other',
    '0.9.97',
    hasPermissionHint: true,
  ),
  'plugin.listInstalled': PluginApiMethod('app.info.read', '0.9.97'),
  // קריאה פנימית של החנות: מוכרת בגשר, ללא בדיקת הרשאה בעת אריזה.
  'plugin.requestInstall': PluginApiMethod(
    'app.info.read',
    null,
    validatePermission: false,
    documented: false,
  ),
  'plugin.backgroundDone': PluginApiMethod(null, '0.9.97'),
  'plugin.setRestoreState': PluginApiMethod(null, '0.9.98'),
};

final Map<String, String> pluginApiMethodPermissions = Map.unmodifiable({
  for (final entry in pluginApiMethods.entries)
    entry.key: entry.value.runtimePermission ?? pluginApiNoManifestPermission,
});

final Set<String> pluginApiKnownMethods = Set.unmodifiable({
  for (final entry in pluginApiMethods.entries)
    if (entry.value.documented) entry.key,
});

final Set<String> pluginApiUndocumentedMethods = Set.unmodifiable({
  for (final entry in pluginApiMethods.entries)
    if (!entry.value.documented) entry.key,
});

final Map<String, String> pluginApiValidationPermissions = Map.unmodifiable({
  for (final entry in pluginApiMethods.entries)
    entry.key: ?entry.value.validationPermission,
});

final Map<String, String> pluginApiMinVersions = Map.unmodifiable({
  for (final entry in pluginApiMethods.entries)
    entry.key: ?entry.value.minVersion,
});

final Map<String, String> pluginApiPermissionHints = Map.unmodifiable({
  for (final entry in pluginApiMethods.entries)
    if (entry.value.hasPermissionHint)
      entry.key: entry.value.validationPermission!,
});

final Set<String> pluginApiCallsWithoutPermission = Set.unmodifiable({
  for (final entry in pluginApiMethods.entries)
    if (entry.value.runtimePermission == null) entry.key,
});
