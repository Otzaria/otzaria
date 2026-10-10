import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// הממשק של מסייע ההורדה ל-Linux: בהיר בלבד, מקלדת ונגישות כמו ב-Windows,
/// כותרת חלון בגופן רגיל בקצה הקריאה, והעיצוב מוטמע מהנעיצה ולא מהמאגר.
void main() {
  const dir = 'tool/download_assistant/linux';
  String read(String name) => File('$dir/$name').readAsStringSync();

  String routine(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, isNonNegative, reason: signature);
    return source.substring(start, source.indexOf('\n}\n', start));
  }

  final ui = read('ui.c');
  final widgets = read('widgets.c');
  final main = read('main.c');

  test('בהיר בלבד, גם כשהמערכת כהה', () {
    expect(main, contains('g_unsetenv("GTK_THEME");'));
    final theme = routine(widgets, 'void otz_theme_install(void)');
    expect(theme, contains('"gtk-theme-name", "Adwaita"'));
    expect(theme, contains('"gtk-application-prefer-dark-theme", FALSE'));
    expect(theme, contains('GTK_STYLE_PROVIDER_PRIORITY_USER + 1'));
    expect(widgets, contains(r'"window.otz * { all: unset; }\n"'));
  });

  test('כותרת החלון: תווית רגילה בקצה הקריאה, בלי הכותרת המרוכזת', () {
    final window = routine(ui, 'static void build_window(Ui *ui)');
    final title = window.indexOf('gtk_window_set_title(');
    final bar = window.indexOf('gtk_window_set_titlebar(');
    expect(title, isNonNegative);
    expect(
      bar,
      greaterThan(title),
      reason: 'אחרת GTK מעתיק את השם לכותרת מרוכזת ומודגשת',
    );
    expect(
      window,
      contains('gtk_header_bar_pack_start(GTK_HEADER_BAR(bar), title);'),
    );
    expect(window, contains('gtk_header_bar_set_show_close_button('));
    expect(
      widgets,
      contains('.t-wintitle { font-size: 13px; color: #201B13; }'),
    );
    expect(
      routine(ui, 'int otz_ui_run(const OtzUiOptions *options)'),
      contains('GTK_TEXT_DIR_RTL'),
    );
  });

  test(
    'מקלדת: Return לפעולה הראשית, Esc לחזרה ולדו-שיח, חיצים בכרטיסי רדיו',
    () {
      final keys = routine(ui, 'static gboolean on_key(');
      expect(keys, contains('GDK_KEY_Escape'));
      expect(
        keys,
        contains('ui->dialog_open ? ui->dialog_cancel : ui->escape'),
      );
      expect(keys, contains('GDK_KEY_Return'));
      expect(keys, contains('GDK_KEY_KP_Enter'));
      // כפתור במוקד מופעל בעצמו; כרטיס (toggle) במוקד — הפעולה הראשית.
      expect(
        keys,
        contains('GTK_IS_BUTTON(focus) && !GTK_IS_TOGGLE_BUTTON(focus)'),
      );
      expect(
        keys,
        contains('ui->dialog_open ? ui->dialog_default : ui->primary'),
      );
      final card = routine(widgets, 'GtkWidget *otz_card(');
      expect(card, contains('gtk_radio_button_new('));
      expect(card, contains('gtk_check_button_new()'));
      expect(card, contains('otz_accessible(card, spec->title, description);'));
      // "אין בחירה" ברשימת היעדים: רדיו נסתר, כדי ש-GTK לא יסמן את הראשון.
      expect(
        routine(ui, 'static GtkWidget *other_page('),
        contains('unselected_group('),
      );
    },
  );

  test('טבעת מוקד גלויה בכל פקד, בתוך השוליים שלו', () {
    for (final name in ['draw_button', 'draw_field', 'draw_card']) {
      final draw = routine(widgets, 'static gboolean $name(');
      expect(
        draw,
        contains('gtk_widget_has_visible_focus(widget)'),
        reason: name,
      );
      expect(draw, contains('focus_ring('), reason: name);
    }
    expect(read('widgets.h'), contains('#define OTZ_RING 4'));
  });

  test('דו-שיח בתוך החלון: יציאה בזמן הורדה, עצירה, מקום, אין בחירה', () {
    final delete = routine(ui, 'static gboolean on_delete(');
    expect(delete, contains('PAGE_WORKING'));
    expect(delete, contains('S_EXIT_TITLE'));
    expect(delete, contains('TRUE, exit_now'));
    expect(ui, contains('otz_tr(S_STOP_TITLE)'));
    expect(ui, contains('otz_tr(S_SPACE_TITLE)'));
    expect(ui, contains('otz_tr(S_NO_TARGET_TITLE)'));
    expect(ui, contains('otz_tr(S_NOTHING_TITLE)'));
    expect(ui, isNot(contains('gtk_message_dialog_new')));
    expect(main, isNot(contains('gtk_message_dialog_new')));
  });

  test('העיצוב מהנעיצה, נבדק ב-SHA-256 ומוטמע; אין PNG במאגר', () {
    final fetch = read('fetch_art.sh');
    expect(fetch, contains('installer/assistant_art.pin.json'));
    expect(fetch, contains('sha256sum'));
    expect(fetch, contains('https://github.com/Otzaria/*'));
    expect(fetch, contains('AA_ART_VERSION'));
    expect(fetch, contains('.pinned-sha256'));
    final makefile = read('Makefile');
    expect(makefile, contains('sh fetch_art.sh \$(ART)'));
    expect(makefile, contains('--generate-source'));
    expect(makefile, contains('\$(BUILD)/app/art_resources.o'));
    final pngs = Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.png') && !f.path.contains('build'));
    expect(pngs, isEmpty);
  });

  test('צילומי המסך: workflow ידני, שתי שפות, ונכשל על אזהרת GTK', () {
    final workflow = File(
      '.github/workflows/linux-assistant-screenshots.yml',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(workflow, contains('on:\n  workflow_dispatch:\n\n'));
    expect(workflow, contains('--dev-screenshot'));
    expect(workflow, contains('GDK_SCALE: "2"'));
    expect(workflow, contains('Gtk-(WARNING|CRITICAL)'));
    expect(workflow, contains('make check-needed'));
    expect(workflow, contains('image: debian:bookworm-slim'));
    expect(ui, contains('for (int language = 0; language < 2; language++)'));
  });
}
