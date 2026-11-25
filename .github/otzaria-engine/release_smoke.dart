import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

void main() {
  try {
    final output = Platform.environment['ENGINE_SMOKE_OUTPUT'];
    if (output == null || output.isEmpty) {
      throw StateError('ENGINE_SMOKE_OUTPUT must name the report file.');
    }
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textDirection: ui.TextDirection.rtl,
              fontSize: 18,
            ),
          )
          ..pushStyle(ui.TextStyle(letterSpacing: 0.25))
          ..addText('בדיקת מנוע טקסט בעברית ')
          ..pushStyle(
            ui.TextStyle(fontWeight: ui.FontWeight.bold, wordSpacing: 0.75),
          )
          ..addText('Flutter 123')
          ..pop()
          ..pop();
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 280));
    final lines = paragraph.computeLineMetrics();
    final boxes = paragraph.getBoxesForRange(0, 10);
    if (!paragraph.height.isFinite ||
        paragraph.height <= 0 ||
        lines.isEmpty ||
        boxes.isEmpty) {
      throw StateError('The release engine did not lay out the paragraph.');
    }
    File(output).writeAsStringSync(
      jsonEncode({
        'height': paragraph.height,
        'width': paragraph.width,
        'lines': lines.length,
        'selectionBoxes': boxes.length,
        'dartVersion': Platform.version,
      }),
    );
    paragraph.dispose();
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
