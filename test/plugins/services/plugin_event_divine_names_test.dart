import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/commentary_plugin_menu_entries.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_divine_names_filter.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reader_plugin_menu_entries.dart';
import 'package:otzaria/text_book/view/selection/plugin_selection_payload.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

import '../../helpers/memory_settings_cache.dart';

const _lines = ['ויאמר אלהים יהוה', 'וידבר אלהים אל משה'];

final _spans =
    (DivineNameSpansBuilder()
          ..add(0, 6, 11, DivineNameKind.elohim)
          ..add(0, 12, 16, DivineNameKind.hvyh)
          ..add(1, 6, 11, DivineNameKind.elohim))
        .build();

TextDisplayPolicy _policy(
  HolyNameDisplay holyName, {
  bool substitute = false,
}) => TextDisplayPolicy(
  general: TextDisplayLayer({
    TextDisplaySlot.root: TextDisplayPatch(
      holyName: holyName,
      divineNames: substitute
          ? DivineNamesDisplay.substitute
          : DivineNamesDisplay.asIs,
    ),
  }),
  tanach: TextDisplayLayer.empty,
);

Future<void> _saveSetting(
  HolyNameDisplay holyName, {
  bool substitute = false,
}) => Settings.setValue<String>(
  SettingsRepository.keyTextDisplayPolicy,
  jsonEncode(_policy(holyName, substitute: substitute).toJson()),
);

/// כרטיסייה שנטענה כשההגדרה הייתה יקוק עם החלפת שאר השמות.
TextBookLoaded _state() =>
    TextBookLoaded.initial(
      book: TextBook(title: 'ספר', categoryId: 1),
      index: 0,
      showLeftPane: false,
      splitView: false,
    ).copyWith(
      content: _lines,
      divineNames: _spans,
      displayPolicy: _policy(HolyNameDisplay.kufKuf, substitute: true),
    );

RenderSettings _shown(TextBookLoaded state) =>
    RenderSettings.fromProfile(state.bodyDisplayProfile);

class _Repo extends Fake implements PluginRegistryRepository {
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;
  @override
  Future<bool?> getPermission(String pluginId, String permission) async => true;
}

class _Controller extends Fake implements InAppWebViewController {
  bool paused = false;
  final List<String> delivered = [];

  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    paused = false;
  }

  @override
  Future<void> setMemoryUsageTargetLevel(MemoryUsageTargetLevel level) async {}

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (!paused) delivered.add(source);
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  tearDown(() async {
    await Settings.setValue<String>(
      SettingsRepository.keyTextDisplayPolicy,
      '',
    );
  });

  group('payload של בחירה בקורא', () {
    test('לפי ההגדרה העדכנית; raw כפי שנשמר; המקור והעוגן נשארים', () async {
      await _saveSetting(HolyNameDisplay.daletDalet);
      final state = _state();
      final payload = buildPluginSelectionPayload(
        state: state,
        rawText: _lines[0],
        selectedText: 'אלקים יקוק',
        sectionIndex: 0,
        startHint: null,
        settings: _shown(state),
      );
      expect(
        () => jsonEncode(payload),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );

      final filtered = PluginDivineNamesPayload.select(payload);
      expect(filtered.containsKey(PluginDivineNamesPayload.key), isFalse);
      expect(filtered['text'], 'אלהים ידוד');
      expect(filtered['renderedSelectedText'], 'אלהים ידוד');
      expect(filtered['normalizedSelectedText'], 'אלהים ידוד');
      expect(filtered['sourceSelectedText'], 'אלהים יהוה');
      expect(
        (filtered['sourceRange'] as Map)['exactText'],
        'אלהים יהוה',
      );
      // השמות שונים מהמסך: גם העוגן המוצג נבנה מולם, ולא מוסר את יקוק.
      final renderedRange = filtered['renderedRange'] as Map;
      expect(renderedRange['exactText'], 'אלהים ידוד');
      expect((renderedRange['start'] as Map)['grapheme'], 6);
      expect((renderedRange['end'] as Map)['grapheme'], 16);
      final shownRange =
          PluginDivineNamesPayload.resolve(
                payload,
                const PluginDivineNamesDisplay(
                  holyName: HolyNameDisplay.kufKuf,
                  otherNames: DivineNamesDisplay.substitute,
                ),
              )['renderedRange']
              as Map;
      expect(shownRange['exactText'], 'אלקים יקוק');

      final raw = PluginDivineNamesPayload.select(payload, raw: true);
      expect(raw['text'], 'אלהים יהוה');
      expect(raw['renderedSelectedText'], 'אלהים יהוה');
      expect(raw['normalizedSelectedText'], 'אלהים יהוה');
      expect(raw['sourceSelectedText'], 'אלהים יהוה');
      expect((raw['renderedRange'] as Map)['exactText'], 'אלהים יהוה');
      expect(jsonEncode(raw), isNot(contains(PluginDivineNamesPayload.key)));
    });

    test('שינוי ההגדרה בלי טעינת הכרטיסייה חל על payload חדש', () async {
      final state = _state();
      Map<String, dynamic> build() => PluginDivineNamesPayload.select(
        buildPluginSelectionPayload(
          state: state,
          rawText: _lines[0],
          selectedText: 'ויאמר אלקים יקוק',
          sectionIndex: 0,
          startHint: null,
          settings: _shown(state),
        ),
      );
      await _saveSetting(HolyNameDisplay.kufKuf, substitute: true);
      expect(build()['text'], 'ויאמר אלקים יקוק');
      await _saveSetting(HolyNameDisplay.hehApostrophe);
      expect(build()['text'], "ויאמר אלהים ה'");
    });

    test('מחבר המילים מוסר מכל שדה טקסט ונשאר רק בעוגן המוצג', () async {
      await _saveSetting(HolyNameDisplay.kufKuf, substitute: true);
      const line = 'אל שדי';
      final state = _state().copyWith(
        content: [line],
        divineNames:
            (DivineNameSpansBuilder()..add(0, 3, 6, DivineNameKind.shaddai))
                .build(),
      );
      final payload = PluginDivineNamesPayload.select(
        buildPluginSelectionPayload(
          state: state,
          rawText: line,
          selectedText: 'ש-\u2060די',
          sectionIndex: 0,
          startHint: 3,
          settings: _shown(state),
        ),
      );
      expect(payload['text'], 'ש-די');
      expect(payload['renderedSelectedText'], 'ש-די');
      expect(payload['normalizedSelectedText'], 'ש-די');
      expect((payload['renderedRange'] as Map)['exactText'], 'ש-\u2060די');
    });

    test('בחירה חוצת פסקאות — כל פסקה והטקסט המלא', () async {
      await _saveSetting(HolyNameDisplay.daletDalet);
      final state = _state();
      final payload = buildPluginMultiSectionSelectionPayload(
        state: state,
        rawTexts: _lines,
        selectedText: 'ויאמר אלקים יקוק\nוידבר אלקים אל משה',
        firstSectionIndex: 0,
        startHint: 0,
        settings: _shown(state),
      );
      final filtered = PluginDivineNamesPayload.select(payload);
      final sections = (filtered['sections'] as List).cast<Map>();
      expect(sections.map((s) => s['renderedSelectedText']), [
        'ויאמר אלהים ידוד',
        'וידבר אלהים אל משה',
      ]);
      expect(filtered['text'], 'ויאמר אלהים ידוד\nוידבר אלהים אל משה');

      final raw = PluginDivineNamesPayload.select(payload, raw: true);
      expect(raw['text'], 'ויאמר אלהים יהוה\nוידבר אלהים אל משה');
      expect(
        (raw['sections'] as List).cast<Map>().map(
          (s) => s['sourceSelectedText'],
        ),
        ['ויאמר אלהים יהוה', 'וידבר אלהים אל משה'],
      );
    });

    test('בחירה חוצת פסקאות — העוגן המוצג של כל פסקה לפי השמות', () async {
      await _saveSetting(HolyNameDisplay.daletDalet);
      final state = _state();
      final payload = buildPluginMultiSectionSelectionPayload(
        state: state,
        rawTexts: _lines,
        selectedText: 'ויאמר אלקים יקוק\nוידבר אלקים אל משה',
        firstSectionIndex: 0,
        startHint: 0,
        settings: _shown(state),
      );
      final sections =
          (PluginDivineNamesPayload.select(payload)['sections'] as List)
              .cast<Map>();
      expect(
        sections.map((s) => (s['renderedRange'] as Map)['exactText']),
        ['ויאמר אלהים ידוד', 'וידבר אלהים אל משה'],
      );
    });

    test('אירוע selection_changed — text לפי ההגדרה או כפי שנשמר', () async {
      await _saveSetting(HolyNameDisplay.daletDalet);
      final state = _state();
      final payload = withSelectionEventDivineNames(
        {'text': 'אלקים יקוק', 'renderedSelectedText': 'אלקים יקוק'},
        state: state,
        lines: _lines,
        paragraphIndex: 0,
        anchor: (
          lineStart: 0,
          lineEnd: 0,
          startColumn: null,
          pointerColumn: null,
        ),
        settings: _shown(state),
      );
      expect(PluginDivineNamesPayload.select(payload), {
        'text': 'אלהים ידוד',
        'renderedSelectedText': 'אלהים ידוד',
      });
      expect(PluginDivineNamesPayload.select(payload, raw: true), {
        'text': 'אלהים יהוה',
        'renderedSelectedText': 'אלהים יהוה',
      });

      // ההגדרה כמו במסך: הטקסט שעל המסך, בלי מחברי מילים.
      await _saveSetting(HolyNameDisplay.kufKuf, substitute: true);
      final unchanged = withSelectionEventDivineNames(
        {'text': 'ש-⁠די יקוק'},
        state: state,
        lines: _lines,
        paragraphIndex: 0,
        anchor: (
          lineStart: 0,
          lineEnd: 0,
          startColumn: null,
          pointerColumn: null,
        ),
        settings: _shown(state),
      );
      expect(PluginDivineNamesPayload.select(unchanged), {'text': 'ש-די יקוק'});
    });
  });

  group('לחיצה בתפריט ההקשר', () {
    Map<String, dynamic> click(
      PluginContextMenuItem item,
      Map<String, dynamic> selection,
    ) {
      final sent = <Map<String, dynamic>>[];
      buildPluginContextMenuEntries(
        records: [('plugin', item)],
        selection: selection,
        context: 'reader-commentary-selection',
        selectionActionDispatcher: (_, _, payload) async => sent.add(payload),
      ).single.onTap!();
      return sent.single;
    }

    PluginContextMenuItem item({bool raw = false}) =>
        ContextMenuRegistry.detached().parseTopLevel({
          'id': 'save',
          'title': 'שמור',
          'contexts': ['reader-commentary-selection'],
          'rawDivineNames': ?(raw ? true : null),
          'action': {
            'type': 'storage.set',
            'args': {
              'key': 'last',
              'value': {r'$selection': 'selectedText'},
            },
          },
        });

    test(
      'מפרש: שם הוי"ה לפי ההגדרה; פריט עם rawDivineNames — כפי שהוצג',
      () async {
        await _saveSetting(HolyNameDisplay.kufKuf);
        final selection = buildCommentaryPluginPayload(
          target: (
            book: TextBook(title: 'רש"י'),
            sectionIndex: 2,
            currentRef: null,
          ),
          mainBook: (
            book: TextBook(title: 'ספר'),
            currentRef: null,
            sectionIndex: 0,
            pageNumber: null,
          ),
          selectedText: 'אמר יהוה',
        );
        final filtered = click(item(), selection);
        expect(filtered['selectedText'], 'אמר יקוק');
        expect((filtered['selection'] as Map)['text'], 'אמר יקוק');
        expect(
          jsonEncode(filtered),
          isNot(contains(PluginDivineNamesPayload.key)),
        );

        final raw = click(item(raw: true), selection);
        expect(raw['selectedText'], 'אמר יהוה');
      },
    );

    test('rawDivineNames חייב להיות בוליאני ועובר לילדים', () {
      expect(
        () => ContextMenuRegistry.detached().parseTopLevel({
          'id': 'x',
          'title': 'x',
          'rawDivineNames': 'yes',
        }),
        throwsA(isA<PluginContextMenuException>()),
      );
      final parsed = ContextMenuRegistry.detached().parseTopLevel({
        'id': 'menu',
        'type': 'submenu',
        'title': 'תפריט',
        'rawDivineNames': true,
        'children': [
          {'id': 'child', 'title': 'ילד'},
          {'id': 'other', 'title': 'אחר', 'rawDivineNames': false},
        ],
      });
      expect(parsed.children.map((c) => c.rawDivineNames), [true, false]);
      expect(parsed.toJson()['rawDivineNames'], isTrue);
    });

    test('עדכון ההורה מחשב מחדש את הירושה בילדים', () {
      final registry = ContextMenuRegistry.forTesting();
      registry.registerPayload('p', {
        'id': 'menu',
        'type': 'submenu',
        'title': 'תפריט',
        'rawDivineNames': true,
        'children': [
          {'id': 'child', 'title': 'ילד'},
          {'id': 'other', 'title': 'אחר', 'rawDivineNames': false},
        ],
      });
      final json = registry.findItem('p', 'menu')!.toJson();
      final children = (json['children'] as List).cast<Map>();
      expect(children.first.containsKey('rawDivineNames'), isFalse);
      expect(children.last['rawDivineNames'], isFalse);

      registry.update('p', 'menu', {'title': 'שם חדש'});
      expect(registry.findItem('p', 'other')!.rawDivineNames, isFalse);
      expect(registry.findItem('p', 'child')!.rawDivineNames, isTrue);

      registry.update('p', 'menu', {'rawDivineNames': false});
      expect(registry.findItem('p', 'child')!.rawDivineNames, isFalse);
      expect(registry.findItem('p', 'other')!.rawDivineNames, isFalse);
    });
  });

  group('הדיספצ\'ר בוחר גרסה לכל מופע', () {
    final d = PluginRuntimeDispatcher.instance;
    const optedIn = 'divine.raw.plugin';
    const plain = 'divine.plain.plugin';
    const topic = 'reader.selection_changed';
    PluginInstanceKey key(String pid) =>
        (pluginId: pid, instanceId: PluginInstanceIds.defaultForeground);

    Map<String, dynamic> payload() => PluginDivineNamesPayload(
      () => const PluginDivineNamesDisplay(
        holyName: HolyNameDisplay.kufKuf,
        otherNames: DivineNamesDisplay.asIs,
      ),
      (payload, names) => {
        ...payload,
        'text': names.filters ? 'יקוק' : 'יהוה',
      },
    ).attachTo({'currentIndex': 3});

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await d.prepareForAppRestart();
      d.registerController('__reset', _Controller());
      d.unregisterController('__reset');
      d.resetVisibilityForTesting();
      d.repositoryForTesting = _Repo();
      d.invalidatePlugin(optedIn);
      d.invalidatePlugin(plain);
    });

    tearDown(() {
      d.unregisterController(optedIn);
      d.unregisterController(plain);
      d.resetVisibilityForTesting();
      d.repositoryForTesting = PluginRegistryRepository();
      debugDefaultTargetPlatformOverride = null;
    });

    bool optInFor(String pid, {String topic = topic}) =>
        d.setEventRawDivineNames(
          pid,
          PluginInstanceIds.defaultForeground,
          topic,
          raw: true,
          generation:
              d.eventOptionsGeneration(
                pid,
                PluginInstanceIds.defaultForeground,
              ) ??
              -1,
        );

    Future<(_Controller, _Controller)> register() async {
      final rawController = _Controller();
      final plainController = _Controller();
      d.registerController(optedIn, rawController);
      d.registerController(plain, plainController);
      d.setVisiblePluginInstances({key(optedIn), key(plain)});
      await d.onForegroundInstanceReady(optedIn);
      await d.onForegroundInstanceReady(plain);
      return (rawController, plainController);
    }

    test('תוסף שביקש raw מקבל את המקור, האחר את המסונן, בלי הנספח', () async {
      final (rawController, plainController) = await register();
      expect(optInFor(optedIn), isTrue);
      await d.dispatchEvent(topic, payload());

      final rawEvent = rawController.delivered.singleWhere(
        (s) => s.contains(topic),
      );
      final plainEvent = plainController.delivered.singleWhere(
        (s) => s.contains(topic),
      );
      expect(rawEvent, contains('יהוה'));
      expect(plainEvent, contains('יקוק'));
      for (final event in [rawEvent, plainEvent]) {
        expect(event, isNot(contains(PluginDivineNamesPayload.key)));
      }

      await d.dispatchEventToPlugin(
        optedIn,
        topic,
        payload(),
        instanceId: PluginInstanceIds.defaultForeground,
      );
      expect(rawController.delivered.last, contains('יהוה'));
    });

    test('מופע מושהה מקבל בחידוש את הגרסה שביקש', () async {
      final (rawController, _) = await register();
      optInFor(optedIn);
      d.setVisiblePluginInstances({key(plain)});
      await pumpEventQueue();
      expect(rawController.paused, isTrue);
      rawController.delivered.clear();

      await d.dispatchEvent(topic, payload());
      d.setVisiblePluginInstances({key(optedIn), key(plain)});
      await pumpEventQueue();

      final flushed = rawController.delivered.singleWhere(
        (s) => s.contains(topic),
      );
      expect(flushed, contains('יהוה'));
      expect(flushed, isNot(contains(PluginDivineNamesPayload.key)));
    });

    test('האפשרות נמחקת בטעינה מחדש, בשחרור ובסגירה', () async {
      await register();
      void optIn() => optInFor(optedIn);

      optIn();
      d.resetEventOptions(optedIn);
      expect(d.rawDivineNamesTopicsOf(optedIn), isEmpty);

      optIn();
      d.markInstanceReleased(
        optedIn,
        reason: PluginRestoreReason.crashed,
      );
      expect(d.rawDivineNamesTopicsOf(optedIn), isEmpty);

      d.registerController(optedIn, _Controller());
      optIn();
      d.registerController(optedIn, _Controller());
      expect(d.rawDivineNamesTopicsOf(optedIn), isEmpty);

      optIn();
      d.unregisterController(optedIn);
      expect(d.rawDivineNamesTopicsOf(optedIn), isEmpty);
      expect(optInFor(optedIn), isFalse);
    });

    test('בקשה של דף קודם אינה חלה על הדף שנטען אחריו', () async {
      await register();
      final previousPage = d.eventOptionsGeneration(
        optedIn,
        PluginInstanceIds.defaultForeground,
      )!;
      d.resetEventOptions(optedIn);
      expect(
        d.setEventRawDivineNames(
          optedIn,
          PluginInstanceIds.defaultForeground,
          topic,
          raw: true,
          generation: previousPage,
        ),
        isFalse,
      );
      expect(d.rawDivineNamesTopicsOf(optedIn), isEmpty);
    });

    test(
      'כשל בנספח: גולמי נופל למסונן; בלי גרסה בטוחה — רק אותו תוסף מדולג',
      () async {
        final (rawController, plainController) = await register();
        optInFor(optedIn);
        var rawCalls = 0;
        Map<String, dynamic> failing({required bool filteredFails}) =>
            PluginDivineNamesPayload(
              () => const PluginDivineNamesDisplay(
                holyName: HolyNameDisplay.kufKuf,
                otherNames: DivineNamesDisplay.asIs,
              ),
              (payload, names) {
                if (!names.filters) {
                  rawCalls++;
                  throw StateError('raw');
                }
                if (filteredFails) throw StateError('filtered');
                return {...payload, 'text': 'יקוק'};
              },
            ).attachTo({'currentIndex': 3});

        await d.dispatchEvent(topic, failing(filteredFails: false));
        expect(
          rawController.delivered.singleWhere((s) => s.contains(topic)),
          contains('יקוק'),
        );
        expect(
          plainController.delivered.singleWhere((s) => s.contains(topic)),
          contains('יקוק'),
        );
        expect(rawCalls, 1);

        rawController.delivered.clear();
        plainController.delivered.clear();
        await d.dispatchEvent(topic, failing(filteredFails: true));
        expect(
          rawController.delivered.where((s) => s.contains(topic)),
          isEmpty,
        );
        expect(
          plainController.delivered.where((s) => s.contains(topic)),
          isEmpty,
        );

        d.markInstanceReleased(optedIn, reason: PluginRestoreReason.crashed);
        await d.dispatchEventToPlugin(
          optedIn,
          topic,
          failing(filteredFails: true),
          instanceId: PluginInstanceIds.defaultForeground,
        );
      },
    );
  });
}
