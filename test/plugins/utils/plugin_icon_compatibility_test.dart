import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';
import 'package:otzaria/plugins/utils/plugin_icon_resolver.dart';
import 'package:otzaria/plugins/utils/plugin_toolbar_actions.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

const _legacyIcons = <String, IconData>{
  'alef_addition_24_regular': OtzariaIcons.alef_add_24_filled,
  'alef_deletion_24_regular': OtzariaIcons.alef_delete_24_filled,
  'alef_half_filled_24_regular': OtzariaIcons.alef_mix_24_regular,
  'alef_with_eraser_24_regular': OtzariaIcons.alef_eraser_24_filled,
  'alef_with_exclamation_24_regular': OtzariaIcons.alef_exclamation_24_filled,
  'alef_with_flavors_24_regular': OtzariaIcons.alef_niqqud_taamim_24_filled,
  'alef_with_information_24_regular': OtzariaIcons.alef_information_24_filled,
  'alef_with_punctuation_24_regular': OtzariaIcons.alef_punctuation_24_filled,
  'alef_with_score_24_regular': OtzariaIcons.alef_niqqud_24_filled,
  'book_md_24_filled': OtzariaIcons.book_24_filled,
  'book_md_24_regular': OtzariaIcons.book_24_regular,
  'book_open_medium_line_24_filled':
      OtzariaIcons.book_open_medium_lines_24_filled,
  'book_open_medium_line_24_regular':
      OtzariaIcons.book_open_medium_lines_24_regular,
  'book_open_small_line_24_filled':
      OtzariaIcons.book_open_small_lines_24_filled,
  'book_open_small_line_24_regular':
      OtzariaIcons.book_open_small_lines_24_regular,
  'book_zim_24_filled': OtzariaIcons.book_24_filled,
  'book_zim_24_regular': OtzariaIcons.book_24_regular,
  'clipboard_text_24_filled': OtzariaIcons.clipboard_text_rtl_24_filled,
  'icon_x_24_regular': OtzariaIcons.cross_24_filled,
  'link_book_empty_24_regular': OtzariaIcons.link_book_24_regular,
  'link_book_exclamation_24_regular': OtzariaIcons.link_exclamation_24_regular,
  'link_deletion_24_regular': OtzariaIcons.link_delete_24_regular,
  'link_with_eraser_24_regular': OtzariaIcons.link_eraser_24_regular,
  'link_with_information_24_regular': OtzariaIcons.link_information_24_regular,
  'otzaria_icon_2_page_line_24_filled':
      OtzariaIcons.otzaria_icon_2_page_lines_24_filled,
  'otzaria_icon_2_page_line_24_regular':
      OtzariaIcons.otzaria_icon_2_page_lines_24_regular,
  'otzaria_icon_line_24_filled': OtzariaIcons.otzaria_icon_lines_24_filled,
  'otzaria_icon_line_24_regular': OtzariaIcons.otzaria_icon_lines_24_regular,
  'search_in_the_book_24_filled': OtzariaIcons.search_in_book_24_filled,
  'search_in_the_book_24_regular': OtzariaIcons.search_in_book_24_regular,
  'search_in_the_document_24_filled': OtzariaIcons.search_in_document_24_filled,
  'search_in_the_document_24_regular':
      OtzariaIcons.search_in_document_24_regular,
  'search_in_the_library_24_filled': OtzariaIcons.search_in_library_24_filled,
  'search_in_the_library_24_regular': OtzariaIcons.search_in_library_24_regular,
  'search_in_the_person_24_filled': OtzariaIcons.search_in_person_24_filled,
  'search_in_the_person_24_regular': OtzariaIcons.search_in_person_24_regular,
  'search_in_the_quote_24_filled': OtzariaIcons.search_in_quote_24_filled,
  'search_in_the_quote_24_regular': OtzariaIcons.search_in_quote_24_regular,
  'search_in_the_settings_24_filled': OtzariaIcons.search_in_settings_24_filled,
  'search_in_the_settings_24_regular':
      OtzariaIcons.search_in_settings_24_regular,
  'search_in_the_text_24_filled': OtzariaIcons.search_in_text_24_filled,
  'search_in_the_text_24_regular': OtzariaIcons.search_in_text_24_regular,
  'stander_24_filled': OtzariaIcons.lectern_24_filled,
  'stander_24_regular': OtzariaIcons.lectern_24_regular,
  'text_continuous_24_filled': OtzariaIcons.text_continuous_rtl_24_filled,
  'text_continuous_24_regular': OtzariaIcons.text_continuous_rtl_24_regular,
  'yoma_deilula_24_regular': OtzariaIcons.calendar_yahrzeit_24_regular,
};

void main() {
  group('תאימות שמות אוצריא מגרסה 0.5.0', () {
    for (final entry in _legacyIcons.entries) {
      test(entry.key, () {
        for (final prefix in ['', kOtzariaIconPrefix]) {
          expect(pluginIconFromName('$prefix${entry.key}'), entry.value);
        }
      });
    }

    test('שמות נוכחיים נשמרים עם התחילית ובלעדיה', () {
      for (final entry in OtzariaIcons.allIcons.entries) {
        for (final prefix in ['', kOtzariaIconPrefix]) {
          expect(pluginIconFromName('$prefix${entry.key}'), entry.value);
        }
      }
    });

    test('תחילית Fluent עוקפת את כינויי אוצריא', () {
      expect(
        pluginIconFromName('fluent:text_continuous_24_regular'),
        FluentIcons.text_continuous_24_regular,
      );
      expect(
        pluginIconFromName('fluent:text_continuous_24_filled'),
        FluentIcons.text_continuous_24_filled,
      );
      expect(pluginIconFromName('fluent:alef_with_score_24_regular'), isNull);
    });

    test('שם לא מוכר אינו מקבל כינוי', () {
      for (final prefix in ['', kOtzariaIconPrefix, kFluentIconPrefix]) {
        expect(pluginIconFromName('${prefix}unknown_24_regular'), isNull);
      }
    });
  });

  for (final prefix in ['', kOtzariaIconPrefix]) {
    test('מניפסט תקין שומר אייקון ישן בכלי, בסרגל ובתפריט: $prefix', () async {
      final name = '${prefix}alef_with_score_24_regular';
      final manifest = PluginManifest.fromJson({
        'id': 'test.legacy_icons',
        'name': 'תוסף ניקוד',
        'version': '1.0.0',
        'entrypoint': 'index.html',
        'contributes': {
          'toolTab': {'iconName': name},
        },
      });
      await PluginManifestValidator.validateManifest(
        manifest: manifest,
        directoryPath: '.',
        skipAppVersionValidation: true,
        skipFileValidation: true,
      );
      final plugin = InstalledPlugin(
        pluginId: manifest.id,
        name: manifest.name,
        version: manifest.version,
        installPath: '.',
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: manifest,
        installedAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final toolbar = buildPluginToolbarActions(
        records: [
          (
            manifest.id,
            PluginToolbarItem(
              id: 'niqqud',
              title: 'ניקוד',
              icon: manifest.toolTabIconName,
              type: 'menu',
              children: [
                PluginToolbarItem(
                  id: 'continuous',
                  title: 'רציף',
                  icon: '${prefix}text_continuous_24_regular',
                ),
              ],
            ),
          ),
        ],
        context: 'reader-text',
        compact: false,
        locationPayload: () async => {},
      ).single;
      final menu = buildPluginContextMenuEntries(
        records: [
          (
            manifest.id,
            PluginContextMenuItem(
              id: 'niqqud',
              label: 'ניקוד',
              icon: manifest.toolTabIconName,
            ),
          ),
        ],
        selection: const {'text': 'טקסט עברי'},
      ).single;
      expect(
        [
          ToolCatalogEntry.fromPlugin(plugin).icon,
          toolbar.icon,
          menu.icon,
          toolbar.submenuItems!.single.icon,
        ],
        [
          OtzariaIcons.alef_niqqud_24_filled,
          OtzariaIcons.alef_niqqud_24_filled,
          OtzariaIcons.alef_niqqud_24_filled,
          OtzariaIcons.text_continuous_rtl_24_regular,
        ],
      );
    });
  }
}
