import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_text_reader_registry.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';

/// מעבר מחלונית תוסף לחלונית ספר מחזיר את המקלדת ל-Flutter ב-macOS (#2945).
void main() {
  final registry = PluginTextReaderRegistry(
    loadSelection: () => null,
    saveSelection: (_) async {},
  );

  test('טאב תוסף מציג תוסף', () {
    expect(
      paneShowsPlugin(ToolTab(toolId: 'demo.plugin', title: 'Demo'), registry),
      isTrue,
    );
  });

  test('כלי מובנה אינו תוסף', () {
    final builtIn = ToolTab(
      toolId: kBuiltInToolsCatalog.first.toolId,
      title: 'כלי',
    );
    expect(paneShowsPlugin(builtIn, registry), isFalse);
  });

  test('אין חלונית פעילה', () {
    expect(paneShowsPlugin(null, registry), isFalse);
  });
}
