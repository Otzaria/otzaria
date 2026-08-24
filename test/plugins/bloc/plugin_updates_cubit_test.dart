import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/plugins/bloc/plugin_updates_cubit.dart';
import 'package:otzaria/plugins/services/plugin_update_check_service.dart';

import '../services/plugin_update_check_service_test.dart' show buildPlugin;

void main() {
  final plugins = [buildPlugin(pluginId: 'org.a', version: '1.0.0')];

  String updateBody() => jsonEncode({
    'updates': [
      {
        'uid': 'org.a',
        'hasUpdate': true,
        'version': '2.0.0',
        'downloadUrl': '/api/plugins/abc@2.0.0/download',
      },
    ],
  });

  /// קוביט עם שירות מדומה, שעון נשלט ומונה קריאות רשת.
  ({
    PluginUpdatesCubit cubit,
    List<http.Request> requests,
    void Function(Duration) advance,
  })
  build({Future<http.Response> Function(http.Request)? handler}) {
    final requests = <http.Request>[];
    var now = DateTime(2026, 8, 23, 10);
    final cubit = PluginUpdatesCubit(
      service: PluginUpdateCheckService(
        client: MockClient((request) {
          requests.add(request);
          return (handler ?? (_) async => http.Response(updateBody(), 200))(
            request,
          );
        }),
        updatesAllowedReader: () => true,
      ),
      appVersionLoader: () async => '0.9.97',
      clock: () => now,
    );
    return (
      cubit: cubit,
      requests: requests,
      advance: (d) => now = now.add(d),
    );
  }

  test('בדיקה מוצלחת ממלאת את המצב', () async {
    final h = build();
    await h.cubit.ensureChecked(plugins);
    expect(h.cubit.state.updateFor('org.a')!.version, '2.0.0');
    expect(h.requests.length, 1);
    await h.cubit.close();
  });

  test('בתוך חלון ה-TTL אין קריאה נוספת; אחריו — יש', () async {
    final h = build();
    await h.cubit.ensureChecked(plugins);
    await h.cubit.ensureChecked(plugins);
    expect(h.requests.length, 1);

    h.advance(PluginUpdatesCubit.checkTtl + const Duration(minutes: 1));
    await h.cubit.ensureChecked(plugins);
    expect(h.requests.length, 2);
    await h.cubit.close();
  });

  test('אחרי כשל ממתינים retryTtl קצר ולא TTL מלא', () async {
    var fail = true;
    final h = build(
      handler: (_) async =>
          fail ? http.Response('busy', 503) : http.Response(updateBody(), 200),
    );
    await h.cubit.ensureChecked(plugins);
    expect(h.cubit.state.updates, isEmpty);

    // עדיין בתוך חלון הניסיון החוזר — אין קריאה
    h.advance(const Duration(minutes: 5));
    await h.cubit.ensureChecked(plugins);
    expect(h.requests.length, 1);

    fail = false;
    h.advance(PluginUpdatesCubit.retryTtl);
    await h.cubit.ensureChecked(plugins);
    expect(h.requests.length, 2);
    expect(h.cubit.state.updateFor('org.a'), isNotNull);
    await h.cubit.close();
  });

  test('קריאות מקבילות מתלכדות לקריאת רשת אחת', () async {
    final gate = Completer<void>();
    final h = build(
      handler: (_) async {
        await gate.future;
        return http.Response(updateBody(), 200);
      },
    );
    final first = h.cubit.ensureChecked(plugins);
    final second = h.cubit.ensureChecked(plugins);
    gate.complete();
    await Future.wait([first, second]);
    expect(h.requests.length, 1);
    await h.cubit.close();
  });

  test('dismiss מסתיר את התוסף גם אחרי בדיקה חדשה', () async {
    final h = build();
    await h.cubit.ensureChecked(plugins);
    h.cubit.dismiss('org.a');
    expect(h.cubit.state.updates, isEmpty);

    h.advance(PluginUpdatesCubit.checkTtl + const Duration(minutes: 1));
    await h.cubit.ensureChecked(plugins);
    expect(h.requests.length, 2);
    expect(h.cubit.state.updates, isEmpty);
    await h.cubit.close();
  });
}
