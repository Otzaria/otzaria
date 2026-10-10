import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_action_compiler.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_network_fetch_service.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';
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

  /// מציג הודעת המתנה ומחזיר פעולה שמסתירה רק את ההודעה הזאת.
  void Function() showPending(String message, {required String pluginName});
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

  @override
  void Function() showPending(String message, {required String pluginName}) {
    final owner = Object();
    UiSnack.showChecking(
      PluginMessages.declarativeSnack(message, pluginName),
      owner: owner,
    );
    return () => UiSnack.hide(owner: owner);
  }
}

/// כתיבה לאחסון ה-KV של תוסף מפעולה דקלרטיבית — בלי מנוע JS.
abstract interface class DeclarativeStorageWriter {
  Future<void> set(String pluginId, String key, Object? value);

  Future<void> remove(String pluginId, String key);
}

/// קריאה מאחסון ה-KV של תוסף בזמן לחיצה (`$storage`) — בלי מנוע JS.
abstract interface class DeclarativeStorageReader {
  /// הערך המפוענח, או `null` כשהמפתח אינו קיים.
  Future<Object?> get(String pluginId, String key);
}

/// אותו מחסן ואותו namespace של `storage.get` בגשר ובתכניות.
class PluginKvStorageReader implements DeclarativeStorageReader {
  final PluginRegistryRepository _repository;

  PluginKvStorageReader({PluginRegistryRepository? repository})
    : _repository = repository ?? PluginRegistryRepository();

  @override
  Future<Object?> get(String pluginId, String key) async {
    final raw = await _repository.getKV(
      pluginId,
      kDefaultStorageNamespace,
      key,
    );
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return raw;
    }
  }
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

/// תשובת שירות מקומי ל-`localService.post`.
class DeclarativeLocalServiceResponse {
  final int status;

  /// הגוף כטקסט, עד [PluginLocalServiceClient.maxResponseLength] תווים.
  final String body;

  const DeclarativeLocalServiceResponse({
    required this.status,
    required this.body,
  });

  bool get ok => status >= 200 && status < 300;
}

/// שליחת בקשת `POST` לשירות מקומי. בדיקת ההרשאה וה-allowlist אצל המבצע.
/// שגיאת חיבור או זמן המתנה שעבר נזרקות (`SocketException`,
/// `http.ClientException`, `TimeoutException`), ותשובה שאינה UTF-8 תקין
/// נזרקת כ-`FormatException`.
abstract interface class DeclarativeLocalServiceClient {
  Future<DeclarativeLocalServiceResponse> post(
    Uri uri,
    String jsonBody, {
    required Duration timeout,
  });
}

/// המימוש בפועל: אותו שירות הבקשות של `network.fetchStream`.
class PluginLocalServiceClient implements DeclarativeLocalServiceClient {
  /// הקריאה נעצרת אחרי כך וכך תווים: התשובה נועדה להודעה קצרה בלבד.
  static const int maxResponseLength = 64 * 1024;

  final PluginNetworkFetchService _fetchService;

  PluginLocalServiceClient({PluginNetworkFetchService? fetchService})
    : _fetchService = fetchService ?? PluginNetworkFetchService();

  @override
  Future<DeclarativeLocalServiceResponse> post(
    Uri uri,
    String jsonBody, {
    required Duration timeout,
  }) async {
    final abort = Completer<void>();
    final deadline = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final response = await _fetchService.fetchStream(
        uri,
        method: 'POST',
        headers: const {
          'accept': 'application/json',
          'content-type': 'application/json; charset=utf-8',
        },
        body: jsonBody,
        abortTrigger: abort.future,
      );
      final body = StringBuffer();
      await for (final chunk in response.body) {
        body.write(chunk);
        if (body.length > maxResponseLength) break;
      }
      return DeclarativeLocalServiceResponse(
        status: response.status,
        body: body.toString(),
      );
    } on http.RequestAbortedException {
      throw TimeoutException('Local service request timed out', timeout);
    } finally {
      deadline.cancel();
    }
  }
}

/// לקוח HTTP משותף לכל הלחיצות, הרשום לסגירה בסיום התהליך.
final DeclarativeLocalServiceClient _sharedLocalServiceClient =
    PluginLocalServiceClient();

/// בקשות `localService.post` שעוד רצות (`<plugin> <uri> <body>`): לחיצה
/// כפולה אינה שולחת את אותה בקשה פעמיים.
final Set<String> _localServiceInFlight = {};

/// האם התוסף רשאי לפנות ל-[uri]: אותה בדיקה של `network.fetchStream`
/// (`network.enabled`, הרשאה מוענקת ו-allowlist).
typedef DeclarativeNetworkGate =
    Future<PluginNetworkDecision> Function(Uri uri, InstalledPlugin plugin);

Future<PluginNetworkDecision> _defaultNetworkGate(
  Uri uri,
  InstalledPlugin plugin,
) => evaluatePluginNetworkAccess(
  uri: uri,
  pluginId: plugin.pluginId,
  manifest: plugin.manifest,
  registry: PluginRegistryRepository(),
);

class DeclarativeHostActionExecutor {
  final DeclarativeBookOpener bookOpener;
  final DeclarativeStorageWriter? storageWriter;
  final DeclarativeReaderScroller? readerScroller;
  final DeclarativeSearchOpener? searchOpener;
  final DeclarativeSnackPresenter snackPresenter;
  final DeclarativeLocalServiceClient? localServiceClient;
  final DeclarativeNetworkGate? networkGate;

  const DeclarativeHostActionExecutor({
    required this.bookOpener,
    this.storageWriter,
    this.readerScroller,
    this.searchOpener,
    this.snackPresenter = const UiSnackPresenter(),
    this.localServiceClient,
    this.networkGate,
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
      if (action.type == 'localService.post') {
        snackPresenter.show(
          PluginMessages.localServiceBlocked,
          'error',
          pluginName: plugin.name,
        );
        return false;
      }
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
      case 'localService.post':
        return _postToLocalService(action, plugin);
      default:
        throw DeclarativeProgramException(
          'declarative.unknown_command',
          'Unknown Host action "${action.type}"',
        );
    }
  }

  /// שולח בקשה ומציג תשובה או כשל. הצלחה ללא הודעה נשארת שקטה.
  Future<bool> _postToLocalService(
    CompiledDeclarativeAction action,
    InstalledPlugin plugin,
  ) async {
    final args = action.args;
    var settled = false;
    void show(String message, String severity) {
      settled = true;
      snackPresenter.show(message, severity, pluginName: plugin.name);
    }

    bool unavailable() {
      show(
        args['unavailableMessage'] as String? ??
            PluginMessages.localServiceUnavailable,
        'error',
      );
      return false;
    }

    // `$storage` ריק: השירות עוד לא שמר את הפורט שלו, כלומר לא עלה.
    final port = args['port'] as int?;
    if (port == null) return unavailable();
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: args['path'] as String,
    );
    final decision = await (networkGate ?? _defaultNetworkGate)(uri, plugin);
    if (decision != PluginNetworkDecision.allowed) {
      show(PluginMessages.localServiceBlocked, 'error');
      return false;
    }
    final pending = args['pendingMessage'] as String?;
    final body = jsonEncode(args['body'] ?? const <String, Object?>{});
    final requestKey = '${plugin.pluginId} $uri $body';
    if (!_localServiceInFlight.add(requestKey)) return false;
    void Function()? hidePending;
    try {
      hidePending = pending == null
          ? null
          : snackPresenter.showPending(pending, pluginName: plugin.name);
      final DeclarativeLocalServiceResponse response;
      try {
        response = await (localServiceClient ?? _sharedLocalServiceClient).post(
          uri,
          body,
          timeout: switch (args['timeoutMs']) {
            final int ms => Duration(milliseconds: ms),
            _ => PluginNetworkFetchService.defaultTimeout,
          },
        );
      } on SocketException {
        return unavailable();
      } on http.ClientException {
        return unavailable();
      } on TimeoutException {
        return unavailable();
      } on FormatException {
        show(PluginMessages.localServiceFailed, 'error');
        return false;
      } catch (_) {
        // גם חריג לא צפוי מסתיים בהודעה למשתמש; הפרטים ממשיכים ל-onError.
        show(PluginMessages.localServiceFailed, 'error');
        rethrow;
      }
      final reply = _LocalServiceReply.parse(response.body);
      if (reply.message case final message?) {
        show(message, reply.severity ?? (response.ok ? 'success' : 'error'));
      } else if (!response.ok) {
        show(PluginMessages.localServiceFailed, 'error');
      }
      return response.ok;
    } finally {
      _localServiceInFlight.remove(requestKey);
      // הודעת ההמתנה אינה נשארת אחרי תשובה שקטה או חריגה לא צפויה.
      if (!settled) hidePending?.call();
    }
  }
}

/// `{ "message": "...", "severity"?: "info" | "success" | "error" }` בתשובת
/// השירות. כל צורה אחרת — בלי הודעה.
class _LocalServiceReply {
  final String? message;
  final String? severity;

  const _LocalServiceReply(this.message, this.severity);

  static final RegExp _controlChars = RegExp(r'[\u0000-\u001F\u007F]');

  /// סימני כיווניות אינם מוצגים, אבל יכולים להפוך את סדר ההודעה ואת ייחוסה
  /// לתוסף.
  static final RegExp _bidiControls = RegExp(
    r'[\u200E\u200F\u202A-\u202E\u2066-\u2069]',
  );

  factory _LocalServiceReply.parse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return const _LocalServiceReply(null, null);
    }
    if (decoded is! Map) return const _LocalServiceReply(null, null);
    final rawMessage = decoded['message'];
    final message = rawMessage is String
        ? rawMessage
              .replaceAll(_controlChars, ' ')
              .replaceAll(_bidiControls, '')
              .trim()
        : '';
    final severity = decoded['severity'];
    return _LocalServiceReply(
      message.isEmpty ? null : _shorten(message),
      DeclarativeActionCompiler.snackSeverities.contains(severity)
          ? severity as String
          : null,
    );
  }

  static String _shorten(String message) {
    const max = DeclarativeActionCompiler.maxSnackLength;
    return message.length <= max
        ? message
        : '${message.substring(0, max - 1)}…';
  }
}
