import 'dart:convert';

import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';

abstract interface class DeclarativeBookOpener {
  Future<bool> openUnique(
    Map<String, dynamic> identity, {
    required int index,
    required String searchQuery,
    bool inSidePane,
    ExternalBookMatches? externalMatches,
  });
}

/// גלילת הספר **הפתוח** להפניה, בלי לפתוח אותו מחדש.
abstract interface class DeclarativeReaderScroller {
  Future<bool> scrollToRef(String ref, {bool highlight});
}

/// פתיחת כרטיסיית חיפוש עם שאילתה.
abstract interface class DeclarativeSearchOpener {
  Future<bool> openSearch(String query, {bool autoSearch});
}

/// הצגת הודעת מערכת. המימוש הדיפולטי הוא UiSnack.
abstract interface class DeclarativeSnackPresenter {
  void show(String message, String severity, {required String pluginName});
}

class UiSnackPresenter implements DeclarativeSnackPresenter {
  const UiSnackPresenter();

  @override
  void show(String message, String severity, {required String pluginName}) {
    final text = PluginMessages.declarativeSnack(message, pluginName);
    switch (severity) {
      case 'success':
        UiSnack.showSuccess(text);
      case 'error':
        UiSnack.showError(text);
      default:
        UiSnack.show(text);
    }
  }
}

/// כתיבה לאחסון ה-KV של תוסף מפעולה דקלרטיבית — בלי מנוע JS.
abstract interface class DeclarativeStorageWriter {
  Future<void> set(String pluginId, String key, Object? value);

  Future<void> remove(String pluginId, String key);
}

/// המימוש בפועל: אותו מחסן ואותו namespace של `storage.set` בגשר, כולל
/// עדכון ה-snapshot של מעריך התנאים כדי שתנאי `when` יגיבו מיד.
class PluginKvStorageWriter implements DeclarativeStorageWriter {
  final PluginRegistryRepository _repository;
  final PluginConditionEvaluator _conditions;

  PluginKvStorageWriter({
    PluginRegistryRepository? repository,
    PluginConditionEvaluator? conditions,
  }) : _repository = repository ?? PluginRegistryRepository(),
       _conditions = conditions ?? PluginConditionEvaluator.instance;

  @override
  Future<void> set(String pluginId, String key, Object? value) async {
    await _repository.setKV(
      pluginId,
      kDefaultStorageNamespace,
      key,
      jsonEncode(value),
    );
    _conditions.onStorageValueChanged(pluginId, key, value);
  }

  @override
  Future<void> remove(String pluginId, String key) async {
    await _repository.removeKV(pluginId, kDefaultStorageNamespace, key);
    _conditions.onStorageRemoved(pluginId, key);
  }
}

class DeclarativeHostActionExecutor {
  final DeclarativeBookOpener bookOpener;
  final DeclarativeStorageWriter? storageWriter;
  final DeclarativeReaderScroller? readerScroller;
  final DeclarativeSearchOpener? searchOpener;
  final DeclarativeSnackPresenter snackPresenter;

  const DeclarativeHostActionExecutor({
    required this.bookOpener,
    this.storageWriter,
    this.readerScroller,
    this.searchOpener,
    this.snackPresenter = const UiSnackPresenter(),
  });

  Future<bool> execute({
    required CompiledDeclarativeAction action,
    required InstalledPlugin plugin,
    required Set<String> grantedPermissions,
    required String currentContextSignature,
    required int currentProgramGeneration,
  }) async {
    if (!plugin.enabled) {
      throw const DeclarativeProgramException(
        'declarative.plugin_disabled',
        'The plugin is disabled',
      );
    }
    if (!grantedPermissions.contains(action.requiredPermission)) {
      throw const DeclarativeProgramException(
        'declarative.permission_denied',
        'The action permission is no longer granted',
      );
    }
    if (currentContextSignature != action.contextSignature ||
        currentProgramGeneration != action.programGeneration) {
      throw const DeclarativeProgramException(
        'declarative.stale_action',
        'The action belongs to an outdated program generation',
      );
    }
    switch (action.type) {
      case 'reader.openBook':
      case 'reader.openBookInSidePane':
        final matchPages = (action.args['matchPages'] as List?)
            ?.whereType<int>()
            .toList();
        return bookOpener.openUnique(
          Map<String, dynamic>.from(action.args['identity'] as Map),
          index: action.args['index'] as int? ?? 0,
          searchQuery: action.args['searchQuery'] as String? ?? '',
          inSidePane: action.type == 'reader.openBookInSidePane',
          externalMatches: matchPages == null || matchPages.isEmpty
              ? null
              : ExternalBookMatches(
                  pages: matchPages,
                  matchedTerms:
                      (action.args['matchedTerms'] as List? ?? const [])
                          .whereType<String>()
                          .toList(),
                  query: action.args['searchQuery'] as String? ?? '',
                ),
        );
      case 'storage.set':
        final writer = storageWriter ?? PluginKvStorageWriter();
        await writer.set(
          plugin.pluginId,
          action.args['key'] as String,
          action.args['value'],
        );
        return true;
      case 'storage.remove':
        final writer = storageWriter ?? PluginKvStorageWriter();
        await writer.remove(plugin.pluginId, action.args['key'] as String);
        return true;
      case 'reader.scrollToRef':
        final scroller = readerScroller;
        if (scroller == null) {
          throw const DeclarativeProgramException(
            'declarative.service_unavailable',
            'reader.scrollToRef is not available',
          );
        }
        return scroller.scrollToRef(
          action.args['ref'] as String,
          highlight: action.args['highlight'] as bool? ?? false,
        );
      case 'search.open':
        final opener = searchOpener;
        if (opener == null) {
          throw const DeclarativeProgramException(
            'declarative.service_unavailable',
            'search.open is not available',
          );
        }
        return opener.openSearch(
          action.args['query'] as String,
          autoSearch: action.args['autoSearch'] as bool? ?? true,
        );
      case 'ui.showSnack':
        snackPresenter.show(
          action.args['message'] as String,
          action.args['severity'] as String? ?? 'info',
          pluginName: plugin.name,
        );
        return true;
      default:
        throw DeclarativeProgramException(
          'declarative.unknown_command',
          'Unknown Host action "${action.type}"',
        );
    }
  }
}
