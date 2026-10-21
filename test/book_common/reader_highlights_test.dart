import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/book_common/highlights/reader_highlights.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/marker/legacy/legacy_marker_plugin.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_book_cache.dart';
import 'package:otzaria/marker/services/marker_paint.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/storage/marker_database.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../marker/marker_test_helpers.dart';

const _line = 'בראשית ברא אלהים את השמים ואת הארץ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late MarkerDatabase db;
  late MarkerRepository repository;
  late MarkerBookCache previous;

  void pluginHighlight(String pluginId, String id, String phrase) {
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: pluginId,
      payload: {
        'highlightId': id,
        'bookId': 'בראשית',
        'sectionIndex': 0,
        'range': anchorFor(_line, phrase).toJson(),
        'style': {'backgroundColor': '#8BCF8D'},
      },
    );
  }

  List<(String, String)> painted() => [
    for (final highlight in ReaderHighlights.forSection(
      bookTitle: 'בראשית',
      sectionIndex: 0,
      brightness: Brightness.light,
    ))
      (highlight.ownerPluginId, highlight.highlightId),
  ];

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('reader_highlights_');
    Hive.init(hiveDir.path);
    await Hive.openBox<dynamic>(HiveCache.keyName);
    await Settings.init(cacheProvider: HiveCache());
    MarkerSettings.instance.reload();
    final store = openTestMarkerStore();
    db = store.db;
    repository = store.repository;
    previous = MarkerBookCache.instance;
    MarkerBookCache.instance = MarkerBookCache(
      repository: repository,
      changes: store.changes,
    );
    await repository.importHighlights([
      highlightFor('mk-1', [
        segmentFor(0, _line, 'אלהים', legacyId: 'marker-old-1'),
      ], uid: null),
    ]);
    pluginHighlight(kLegacyMarkerPluginId, 'marker-old-1', 'אלהים');
    pluginHighlight('com.other', 'other-1', 'השמים');
    await MarkerBookCache.instance.ensureLoaded('בראשית', null);
  });

  tearDown(() async {
    PluginHighlightRegistry.instance
      ..removePlugin(kLegacyMarkerPluginId)
      ..removePlugin('com.other');
    MarkerBookCache.instance.dispose();
    MarkerBookCache.instance = previous;
    db.close();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('an imported mark is drawn once, from the marker', () {
    expect(
      painted(),
      unorderedEquals([
        (kMarkerHighlightOwner, 'mk-1'),
        ('com.other', 'other-1'),
      ]),
    );
  });

  test(
    'deleting the imported mark does not bring the plugin copy back',
    () async {
      await repository.delete(['mk-1']);
      await pumpEventQueue();
      expect(painted(), [('com.other', 'other-1')]);
    },
  );

  test('hiding the book hides the plugin copy too', () async {
    await MarkerSettings.instance.setBookHidden('בראשית', true);
    expect(painted(), [('com.other', 'other-1')]);
    await MarkerSettings.instance.setBookHidden('בראשית', false);
  });
}
