import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_toolbar_template_compiler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_startup_contributions.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_external_editions_registry.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/services/plugin_shortcut_registry.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';

typedef _PublishedRecordId = ({String type, String scope, String key});

/// מפעיל את תרומות העלייה הדקלרטיביות של תוספים (`contributes.startup`)
/// בלי להרים מנוע JS: פרסינג המניפסט ב-Dart והזנת ה-registries הקיימים.
///
/// נקרא מ-PluginSystemBloc בכל LoadPlugins, כך שהענקה/שלילה של הרשאה,
/// השבתה, הסרה ועדכון מסונכרנים תמיד עם הרישומים בפועל.
class PluginStartupContributionsService {
  static final PluginStartupContributionsService instance =
      PluginStartupContributionsService._();
  PluginStartupContributionsService._()
    : _toolbar = PluginToolbarRegistry.instance,
      _contextMenu = ContextMenuRegistry.instance,
      _shortcuts = PluginShortcutRegistry.instance,
      _searchDialog = PluginSearchDialogRegistry.instance,
      _searchFieldActions = PluginSearchFieldActionsRegistry.instance,
      _searchFieldSessions = PluginSearchFieldSessionService.instance,
      _externalEditions = PluginExternalEditionsRegistry.instance,
      _libraryBooks = PluginLibraryBooksRegistry.instance,
      _lazyActivation = PluginLazyActivationService.instance,
      _conditions = PluginConditionEvaluator.instance;

  @visibleForTesting
  PluginStartupContributionsService.forTesting({
    required PluginToolbarRegistry toolbarRegistry,
    required ContextMenuRegistry contextMenuRegistry,
    required PluginLazyActivationService activationService,
    PluginShortcutRegistry? shortcutRegistry,
    PluginSearchDialogRegistry? searchDialogRegistry,
    PluginSearchFieldActionsRegistry? searchFieldActionsRegistry,
    PluginSearchFieldSessionService? searchFieldSessions,
    PluginExternalEditionsRegistry? externalEditionsRegistry,
    PluginLibraryBooksRegistry? libraryBooksRegistry,
    PluginConditionEvaluator? conditionEvaluator,
  }) : _conditions = conditionEvaluator ?? PluginConditionEvaluator.instance,
       _toolbar = toolbarRegistry,
       _contextMenu = contextMenuRegistry,
       _shortcuts = shortcutRegistry ?? PluginShortcutRegistry.instance,
       _searchDialog =
           searchDialogRegistry ?? PluginSearchDialogRegistry.instance,
       _searchFieldActions =
           searchFieldActionsRegistry ??
           PluginSearchFieldActionsRegistry.instance,
       _searchFieldSessions =
           searchFieldSessions ?? PluginSearchFieldSessionService.instance,
       _externalEditions =
           externalEditionsRegistry ?? PluginExternalEditionsRegistry.instance,
       _libraryBooks =
           libraryBooksRegistry ?? PluginLibraryBooksRegistry.instance,
       _lazyActivation = activationService;

  final PluginToolbarRegistry _toolbar;
  final ContextMenuRegistry _contextMenu;
  final PluginShortcutRegistry _shortcuts;
  final PluginSearchDialogRegistry _searchDialog;
  final PluginSearchFieldActionsRegistry _searchFieldActions;
  final PluginSearchFieldSessionService _searchFieldSessions;
  final PluginExternalEditionsRegistry _externalEditions;
  final PluginLibraryBooksRegistry _libraryBooks;
  final PluginLazyActivationService _lazyActivation;
  final PluginConditionEvaluator _conditions;
  Future<void> _syncTail = Future<void>.value();

  /// קידומת המפתח של רשומות publishedData שנזרעו מהמניפסט — מבדילה אותן
  /// מרשומות שהתוסף כותב בזמן ריצה, ומאפשרת ניקוי גם אחרי עדכון גרסה.
  static const String seededKeyPrefix = 'manifest:';
  static const String _metadataNamespace = 'otzaria.startup';
  static const String _publishedRecordsMetadataKey = 'published-records';

  /// מה הוחל בפועל — לצורך הסרה נקייה (בלי לגעת ברישומים דינמיים של
  /// התוסף) ולצורך reapply אחרי reload של תוסף פיתוח.
  final Map<String, List<Map<String, dynamic>>> _appliedToolbar = {};
  final Map<String, List<Map<String, dynamic>>> _appliedContextMenu = {};
  final Map<String, List<Map<String, dynamic>>> _appliedShortcuts = {};
  final Map<String, List<Map<String, dynamic>>> _appliedSearchDialog = {};
  final Map<String, List<Map<String, dynamic>>> _appliedSearchFieldActions = {};
  final Map<String, List<Map<String, dynamic>>> _appliedExternalEditions = {};
  final Map<String, List<Map<String, dynamic>>> _appliedLibraryBooks = {};

  /// תוספים שסונכרנו עם תרומות פעילות בסשן הנוכחי — מאפשר לדלג על ניקוי DB
  /// עבור שאר התוספים (הרוב), שלא נזרע להם דבר.
  final Set<String> _managedPlugins = {};

  /// מסנכרן את כל התרומות מול רשימת התוספים הנוכחית. לעולם אינו זורק —
  /// תוסף עם סעיף פגום נרשם ללוג וממשיכים הלאה.
  Future<void> sync(
    List<InstalledPlugin> plugins,
    PluginRegistryRepository repository,
  ) {
    final operation = _syncTail.then(
      (_) => _syncSafely(List<InstalledPlugin>.of(plugins), repository),
    );
    _syncTail = operation;
    return operation;
  }

  Future<void> _syncSafely(
    List<InstalledPlugin> plugins,
    PluginRegistryRepository repository,
  ) async {
    try {
      await _syncInternal(plugins, repository);
    } catch (e, stackTrace) {
      debugPrint(
        'PluginStartupContributionsService: sync failed: '
        '$e\n$stackTrace',
      );
    }
  }

  Future<void> _syncInternal(
    List<InstalledPlugin> plugins,
    PluginRegistryRepository repository,
  ) async {
    final seenIds = <String>{};
    for (final plugin in plugins) {
      seenIds.add(plugin.pluginId);
      final startup = plugin.manifest.startup;
      if (startup == null || startup.isEmpty || !plugin.enabled) {
        // ניקוי DB רק אם יש למה — סעיף startup במניפסט או מצב מהסשן הנוכחי.
        if (startup != null || _managedPlugins.contains(plugin.pluginId)) {
          await _removePlugin(plugin.pluginId, repository);
        }
        continue;
      }
      final granted = (await repository.getGrantedPermissionNames(
        plugin.pluginId,
      )).toSet();
      if (!granted.contains(pluginStartupContributionsPermission)) {
        await _removePlugin(plugin.pluginId, repository);
        continue;
      }
      _managedPlugins.add(plugin.pluginId);
      await _conditions.registerStorageKeys(
        plugin.pluginId,
        _collectStorageKeys(startup),
        repository,
      );

      final legacyToolbarItems = startup.toolbarItems
          .where(
            (item) => !DeclarativeToolbarTemplateCompiler.isDeclarative(item),
          )
          .toList();
      if (legacyToolbarItems.isNotEmpty && granted.contains('reader.toolbar')) {
        _applyItems(
          plugin.pluginId,
          legacyToolbarItems,
          applied: _appliedToolbar,
          register: (id, item) => _toolbar.registerPayload(id, item),
          removeItem: _toolbar.remove,
        );
      } else {
        _removeApplied(plugin.pluginId, _appliedToolbar, _toolbar.remove);
      }

      if (startup.contextMenuItems.isNotEmpty &&
          granted.contains('reader.context_menu')) {
        _applyItems(
          plugin.pluginId,
          startup.contextMenuItems,
          applied: _appliedContextMenu,
          register: (id, item) => _contextMenu.registerPayload(id, item),
          removeItem: _contextMenu.remove,
        );
      } else {
        _removeApplied(
          plugin.pluginId,
          _appliedContextMenu,
          _contextMenu.remove,
        );
      }

      // קיצורי מקלדת דקלרטיביים — דורשים את הרשאת `app.shortcuts`.
      if (startup.shortcuts.isNotEmpty && granted.contains('app.shortcuts')) {
        _applyItems(
          plugin.pluginId,
          startup.shortcuts,
          applied: _appliedShortcuts,
          register: (id, item) => _shortcuts.registerPayload(id, item),
          removeItem: _shortcuts.remove,
        );
      } else {
        _removeApplied(plugin.pluginId, _appliedShortcuts, _shortcuts.remove);
      }

      if (startup.searchDialogItems.isNotEmpty &&
          granted.contains('search.dialog')) {
        _applyItems(
          plugin.pluginId,
          startup.searchDialogItems,
          applied: _appliedSearchDialog,
          register: (id, item) => _searchDialog.registerPayload(id, item),
          removeItem: _searchDialog.remove,
        );
      } else {
        _removeApplied(
          plugin.pluginId,
          _appliedSearchDialog,
          _searchDialog.remove,
        );
      }

      if (startup.searchFieldActions.isNotEmpty &&
          granted.contains(pluginSearchFieldActionsPermission)) {
        _applyItems(
          plugin.pluginId,
          startup.searchFieldActions,
          applied: _appliedSearchFieldActions,
          register: _searchFieldActions.registerPayload,
          removeItem: _removeSearchFieldAction,
        );
      } else {
        _removeSearchFieldActions(plugin.pluginId);
      }

      // תרומת מהדורות חיצוניות משתמשת ב-DB של התוסף ובפתרון ספרים —
      // דורשת את שתי ההרשאות שהמנוע הגנרי נשען עליהן.
      if (startup.externalEditions.isNotEmpty &&
          granted.contains('database.read') &&
          granted.contains('library.books.read')) {
        _applyItems(
          plugin.pluginId,
          startup.externalEditions,
          applied: _appliedExternalEditions,
          register: (_, item) =>
              _externalEditions.registerPayload(plugin, item),
          removeItem: _externalEditions.remove,
        );
      } else {
        _removeApplied(
          plugin.pluginId,
          _appliedExternalEditions,
          _externalEditions.remove,
        );
      }

      if (startup.libraryBooks.isNotEmpty &&
          granted.contains(pluginLibraryBooksProvidePermission)) {
        _applyItems(
          plugin.pluginId,
          startup.libraryBooks,
          applied: _appliedLibraryBooks,
          register: (id, item) => _libraryBooks.registerPayload(
            id,
            item,
            fallbackIconName: plugin.manifest.toolTabIconName,
          ),
          removeItem: _libraryBooks.remove,
        );
      } else {
        _removeApplied(
          plugin.pluginId,
          _appliedLibraryBooks,
          _libraryBooks.remove,
        );
      }

      if (startup.publishedData.isNotEmpty &&
          granted.contains('published_data.write')) {
        await _seedPublishedData(
          plugin.pluginId,
          startup.publishedData,
          repository,
        );
      } else {
        await _removeSeededData(plugin.pluginId, repository);
      }

      // כל הדלקת מנוע שלא דרך כניסה לדף התוסף (לחיצה, אירוע, app.startup)
      // דורשת את ההרשאה הרגישה הכבויה כברירת מחדל. בלעדיה הרישומים עדיין
      // חלים, ולחיצה נופלת לפתיחת דף התוסף (ראו PluginRuntimeDispatcher).
      if (!granted.contains(pluginRunOnStartupPermission)) {
        _lazyActivation.removePlugin(plugin.pluginId);
        continue;
      }
      if (!startup.hasBackgroundActivationTrigger) {
        _lazyActivation.removePlugin(plugin.pluginId);
        continue;
      }
      final broadcastTopics = <String>{};
      final activationConditions = <String, PluginWhenCondition>{};
      var scheduleStartup = false;
      for (final topic in startup.activationEvents) {
        final condition = startup.activationConditions[topic];
        if (topic == PluginStartupContributions.startupActivationTopic) {
          scheduleStartup = true;
          if (condition != null) activationConditions[topic] = condition;
          continue;
        }
        // נושא שהוגדרה לו הרשאת subscribe מכובד רק אם ההרשאה הוענקה.
        final permission = 'events.subscribe:$topic';
        if (!pluginValidPermissions.contains(permission) ||
            granted.contains(permission)) {
          broadcastTopics.add(topic);
          if (condition != null) activationConditions[topic] = condition;
        }
      }
      _lazyActivation.syncPlugin(
        plugin.pluginId,
        broadcastTopics: broadcastTopics,
        scheduleStartup: scheduleStartup,
        activationConditions: activationConditions,
        keepAlive:
            startup.keepAlive &&
            granted.contains(pluginBackgroundKeepAlivePermission),
      );
    }

    final knownIds = <String>{..._managedPlugins};
    for (final pluginId in knownIds) {
      if (!seenIds.contains(pluginId)) {
        await _removePlugin(pluginId, repository);
      }
    }
  }

  /// רושם מחדש את הרישומים הדקלרטיביים של תוסף — אחרי ש-reloadPlugin ניקה
  /// את ה-registries (טעינה מחדש של תוסף פיתוח בלי שינוי מניפסט).
  void reapply(String pluginId) {
    for (final item in _appliedToolbar[pluginId] ?? const []) {
      _tryRegister(pluginId, item, (id, i) => _toolbar.registerPayload(id, i));
    }
    for (final item in _appliedContextMenu[pluginId] ?? const []) {
      _tryRegister(
        pluginId,
        item,
        (id, i) => _contextMenu.registerPayload(id, i),
      );
    }
    for (final item in _appliedShortcuts[pluginId] ?? const []) {
      _tryRegister(
        pluginId,
        item,
        (id, i) => _shortcuts.registerPayload(id, i),
      );
    }
    for (final item in _appliedSearchDialog[pluginId] ?? const []) {
      _tryRegister(
        pluginId,
        item,
        (id, i) => _searchDialog.registerPayload(id, i),
      );
    }
    for (final item in _appliedSearchFieldActions[pluginId] ?? const []) {
      _tryRegister(pluginId, item, _searchFieldActions.registerPayload);
    }
  }

  void _removeSearchFieldAction(String pluginId, String actionId) {
    _searchFieldActions.remove(pluginId, actionId);
    _searchFieldSessions.removeAction(pluginId, actionId);
  }

  /// כפתור שנעלם סוגר גם את הסשן שלו — אחרת התוסף היה ממשיך לכתוב לשדה.
  void _removeSearchFieldActions(String pluginId) {
    _removeApplied(
      pluginId,
      _appliedSearchFieldActions,
      _removeSearchFieldAction,
    );
    _searchFieldSessions.removePlugin(pluginId);
  }

  /// מפתחות ה-KV שתנאי ה-`when` של התרומות קוראים. תנאי פגום מדולג כאן —
  /// הפריט עצמו נדחה בפרסינג של ה-registry.
  Set<String> _collectStorageKeys(PluginStartupContributions startup) {
    final keys = <String>{};
    for (final item in [
      ...startup.toolbarItems,
      ...startup.contextMenuItems,
      ...startup.searchDialogItems,
      ...startup.libraryBooks,
    ]) {
      final raw = item['when'];
      if (raw == null) continue;
      try {
        keys.addAll(PluginWhenCondition.fromJson(raw).storageKeys);
      } on PluginWhenConditionException {
        continue;
      }
    }
    for (final condition in startup.activationConditions.values) {
      keys.addAll(condition.storageKeys);
    }
    return keys;
  }

  void _applyItems(
    String pluginId,
    List<Map<String, dynamic>> items, {
    required Map<String, List<Map<String, dynamic>>> applied,
    required void Function(String pluginId, Map<String, dynamic> item) register,
    required void Function(String pluginId, String itemId) removeItem,
  }) {
    // הסרת פריטי הסבב הקודם שאינם במניפסט הנוכחי — לפני הרישום, אחרת
    // החלפה מלאה של שני פריטים במזהים חדשים נדחית על מכסת שני הפריטים.
    final declaredIds = items.map((item) => item['id']).toSet();
    for (final previous
        in applied[pluginId] ?? const <Map<String, dynamic>>[]) {
      final id = previous['id'];
      if (id is String && !declaredIds.contains(id)) removeItem(pluginId, id);
    }
    final registered = <Map<String, dynamic>>[];
    for (final item in items) {
      if (_tryRegister(pluginId, item, register)) registered.add(item);
    }
    if (registered.isEmpty) {
      applied.remove(pluginId);
    } else {
      applied[pluginId] = registered;
    }
  }

  bool _tryRegister(
    String pluginId,
    Map<String, dynamic> item,
    void Function(String pluginId, Map<String, dynamic> item) register,
  ) {
    try {
      register(pluginId, item);
      return true;
    } catch (e) {
      PluginSystemDatabase.instance.writeLog(
        pluginId,
        'ERROR',
        'startup contribution rejected: $e',
      );
      return false;
    }
  }

  void _removeApplied(
    String pluginId,
    Map<String, List<Map<String, dynamic>>> applied,
    void Function(String pluginId, String itemId) removeItem,
  ) {
    final items = applied.remove(pluginId);
    if (items == null) return;
    for (final item in items) {
      final id = item['id'];
      if (id is String) removeItem(pluginId, id);
    }
  }

  Future<void> _seedPublishedData(
    String pluginId,
    List<Map<String, dynamic>> records,
    PluginRegistryRepository repository,
  ) async {
    // LoadPlugins רץ על כל פעולה (הצמדה, סדר...) — כותבים רק רשומות שהשתנו
    // בפועל, כדי לא לשחוק את ה-DB ולא לאפס updated_at לחינם.
    final existing = await repository.getPluginPublishedRecords(pluginId);
    final existingPayloads = {
      for (final record in existing)
        '${record.type}|${record.scope}|${record.key}': record.payloadJson,
    };
    final previousOwned = await _loadOwnedPublishedRecords(
      pluginId,
      repository,
    );
    final currentOwned = <_PublishedRecordId>{};
    for (final record in records) {
      final type = record['type'];
      final key = record['key'];
      final payload = record['payload'];
      if (type is! String || key is! String || payload == null) {
        PluginSystemDatabase.instance.writeLog(
          pluginId,
          'ERROR',
          'startup publishedData record requires type, key and payload',
        );
        continue;
      }
      final scopeValue = record['scope'];
      if (scopeValue != null && scopeValue is! String) {
        PluginSystemDatabase.instance.writeLog(
          pluginId,
          'ERROR',
          'startup publishedData scope must be a string',
        );
        continue;
      }
      final scope = scopeValue as String? ?? 'global';
      final prefixedKey = '$seededKeyPrefix$key';
      final id = '$type|$scope|$prefixedKey';
      currentOwned.add((type: type, scope: scope, key: prefixedKey));
      final payloadJson = jsonEncode(payload);
      if (existingPayloads[id] == payloadJson) continue;
      await repository.publishRecord(
        pluginId,
        type,
        scope,
        prefixedKey,
        payloadJson,
        null,
      );
    }
    for (final record in previousOwned.difference(currentOwned)) {
      await repository.unpublishRecord(
        pluginId,
        record.type,
        record.scope,
        record.key,
      );
    }
    await _saveOwnedPublishedRecords(pluginId, currentOwned, repository);
  }

  Future<void> _removeSeededData(
    String pluginId,
    PluginRegistryRepository repository,
  ) async {
    final owned = await _loadOwnedPublishedRecords(pluginId, repository);
    for (final record in owned) {
      await repository.unpublishRecord(
        pluginId,
        record.type,
        record.scope,
        record.key,
      );
    }
    await repository.removeKV(
      pluginId,
      _metadataNamespace,
      _publishedRecordsMetadataKey,
    );
  }

  Future<Set<_PublishedRecordId>> _loadOwnedPublishedRecords(
    String pluginId,
    PluginRegistryRepository repository,
  ) async {
    final encoded = await repository.getKV(
      pluginId,
      _metadataNamespace,
      _publishedRecordsMetadataKey,
    );
    if (encoded == null) return const {};
    Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } catch (error) {
      PluginSystemDatabase.instance.writeLog(
        pluginId,
        'ERROR',
        'startup publishedData ownership metadata is invalid: $error',
      );
      return const {};
    }
    if (decoded is! List) return const {};
    return {
      for (final entry in decoded)
        if (entry is Map &&
            entry['type'] is String &&
            entry['scope'] is String &&
            entry['key'] is String)
          (
            type: entry['type'] as String,
            scope: entry['scope'] as String,
            key: entry['key'] as String,
          ),
    };
  }

  Future<void> _saveOwnedPublishedRecords(
    String pluginId,
    Set<_PublishedRecordId> records,
    PluginRegistryRepository repository,
  ) async {
    if (records.isEmpty) {
      await repository.removeKV(
        pluginId,
        _metadataNamespace,
        _publishedRecordsMetadataKey,
      );
      return;
    }
    final sorted = records.toList()
      ..sort((a, b) {
        final typeComparison = a.type.compareTo(b.type);
        if (typeComparison != 0) return typeComparison;
        final scopeComparison = a.scope.compareTo(b.scope);
        return scopeComparison != 0 ? scopeComparison : a.key.compareTo(b.key);
      });
    await repository.setKV(
      pluginId,
      _metadataNamespace,
      _publishedRecordsMetadataKey,
      jsonEncode([
        for (final record in sorted)
          {'type': record.type, 'scope': record.scope, 'key': record.key},
      ]),
    );
  }

  Future<void> _removePlugin(
    String pluginId,
    PluginRegistryRepository repository,
  ) async {
    _managedPlugins.remove(pluginId);
    _removeApplied(pluginId, _appliedToolbar, _toolbar.remove);
    _removeApplied(pluginId, _appliedContextMenu, _contextMenu.remove);
    _removeApplied(pluginId, _appliedShortcuts, _shortcuts.remove);
    _removeApplied(pluginId, _appliedSearchDialog, _searchDialog.remove);
    _removeSearchFieldActions(pluginId);
    _removeApplied(
      pluginId,
      _appliedExternalEditions,
      _externalEditions.remove,
    );
    _removeApplied(pluginId, _appliedLibraryBooks, _libraryBooks.remove);
    _lazyActivation.removePlugin(pluginId);
    _conditions.removePlugin(pluginId);
    await _removeSeededData(pluginId, repository);
  }
}
