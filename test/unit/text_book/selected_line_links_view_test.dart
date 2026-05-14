import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/view/selected_line_links_view.dart';

void main() {
  group('buildSelectedLinkRenderSettings', () {
    test('passes removeNikud through to link content rendering', () {
      final settings = SettingsState.initial();

      final renderSettings = buildSelectedLinkRenderSettings(
        settingsState: settings,
        removeNikud: true,
        searchText: '',
      );

      expect(renderSettings.removeNikud, isTrue);
    });

    test('follows teamim visibility setting for link content rendering', () {
      final settings = SettingsState.initial().copyWith(showTeamim: false);

      final renderSettings = buildSelectedLinkRenderSettings(
        settingsState: settings,
        removeNikud: false,
        searchText: 'שלום',
      );

      expect(renderSettings.removeTeamim, isTrue);
      expect(renderSettings.searchText, 'שלום');
    });

    test('justifies link content rendering', () {
      final settings = SettingsState.initial();

      final renderSettings = buildSelectedLinkRenderSettings(
        settingsState: settings,
        removeNikud: false,
        searchText: '',
      );

      expect(renderSettings.justifyText, isTrue);
    });
  });

  group('normalizeSelectedLinkText', () {
    test('collapses tabs into a single space', () {
      expect(
        normalizeSelectedLinkText('ודר\t\t\tשאל'),
        'ודר שאל',
      );
    });

    test('collapses nbsp and repeated spaces', () {
      expect(
        normalizeSelectedLinkText('ודר&nbsp;  שאל'),
        'ודר שאל',
      );
    });
  });

  group('buildSelectedLinksSearchKey', () {
    test('changes when the links change even if the list length stays the same',
        () {
      final firstLinks = [
        Link(
          heRef: 'א',
          index1: 1,
          path2: '/books/alpha.txt',
          index2: 1,
          connectionType: 'reference',
        ),
      ];
      final secondLinks = [
        Link(
          heRef: 'ב',
          index1: 1,
          path2: '/books/beta.txt',
          index2: 1,
          connectionType: 'reference',
        ),
      ];

      final firstKey = buildSelectedLinksSearchKey(
        searchQuery: 'חיפוש',
        searchInContent: false,
        links: firstLinks,
      );
      final secondKey = buildSelectedLinksSearchKey(
        searchQuery: 'חיפוש',
        searchInContent: false,
        links: secondLinks,
      );

      expect(firstKey, isNot(secondKey));
    });

    test('changes for the same target when source line changes', () {
      final firstLinks = [
        Link(
          heRef: 'אותו יעד',
          index1: 1,
          path2: '/books/alpha.txt',
          index2: 372,
          connectionType: 'reference',
        ),
      ];
      final secondLinks = [
        Link(
          heRef: 'אותו יעד',
          index1: 2,
          path2: '/books/alpha.txt',
          index2: 372,
          connectionType: 'reference',
        ),
      ];

      final firstKey = buildSelectedLinksSearchKey(
        searchQuery: 'חיפוש',
        searchInContent: false,
        links: firstLinks,
      );
      final secondKey = buildSelectedLinksSearchKey(
        searchQuery: 'חיפוש',
        searchInContent: false,
        links: secondLinks,
      );

      expect(firstKey, isNot(secondKey));
    });
  });

  group('buildSelectedLinkInstanceKey', () {
    test('differs for repeated target links from different source lines', () {
      final firstLink = Link(
        heRef: 'אותו יעד',
        index1: 1,
        path2: '/books/alpha.txt',
        index2: 372,
        connectionType: 'reference',
      );
      final secondLink = Link(
        heRef: 'אותו יעד',
        index1: 2,
        path2: '/books/alpha.txt',
        index2: 372,
        connectionType: 'reference',
      );

      expect(
        buildSelectedLinkInstanceKey(firstLink),
        isNot(buildSelectedLinkInstanceKey(secondLink)),
      );
      expect(
        buildSelectedLinkContentKey(firstLink),
        buildSelectedLinkContentKey(secondLink),
      );
    });
  });
}
