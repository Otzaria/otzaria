import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_data_folder_unwritable_view.dart';
import 'package:otzaria/plugins/view/plugin_webview2_missing_view.dart';
import 'package:otzaria/plugins/view/plugin_webview_failed_view.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';

/// UI-066: מסכי השגיאה של התוספים על מצב השגיאה המשותף.
void main() {
  final views = <String, Widget>{
    'WebView2 חסר': PluginWebView2MissingView(onRetry: () {}),
    'WebView נכשל': PluginWebViewFailedView(onRetry: () {}),
    'תיקייה חסומה': PluginDataFolderUnwritableView(
      folderPath: r'C:\x',
      onRetry: () {},
    ),
  };
  for (final entry in views.entries) {
    testWidgets('${entry.key}: OtzariaErrorState', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: entry.value)),
      );
      expect(find.byType(OtzariaErrorState), findsOneWidget);
      expect(find.text('מה אפשר לעשות:'), findsOneWidget);
    });
  }
}
