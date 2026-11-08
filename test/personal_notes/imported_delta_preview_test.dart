import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:otzaria/personal_notes/widgets/note_delta_preview.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';

void main() {
  final cases = <String, List<Map<String, dynamic>>>{
    'plain Hebrew': [
      {'insert': 'שלום וברכה\n'},
    ],
    'large paragraph': [
      {
        'insert': 'שלום עולם',
        'attributes': {'size': 32},
      },
      {'insert': '\n'},
    ],
    'script after truncation': [
      {'insert': 'אבג ' * 100},
      {
        'insert': 'עילי',
        'attributes': {'script': 'super'},
      },
      {'insert': '\n'},
    ],
    'line height': [
      {'insert': 'שלום עולם'},
      {
        'insert': '\n',
        'attributes': {'line-height': 2},
      },
    ],
    'named colors': [
      {
        'insert': 'שלום עולם',
        'attributes': {'color': 'red', 'background': 'yellow'},
      },
      {'insert': '\n'},
    ],
    'rgba colors': [
      {
        'insert': 'שלום עולם',
        'attributes': {'color': 'rgba(255, 0, 0, 1)'},
      },
      {'insert': '\n'},
    ],
    'script': [
      {'insert': 'x'},
      {
        'insert': '2',
        'attributes': {'script': 'super'},
      },
      {'insert': '\n'},
    ],
    'subscript': [
      {'insert': 'בסיס'},
      {
        'insert': 'תחתון',
        'attributes': {'script': 'sub'},
      },
      {'insert': '\n'},
    ],
    'inline code': [
      {
        'insert': 'קוד',
        'attributes': {'code': true},
      },
      {'insert': '\n'},
    ],
    'list 12': [
      {
        'insert': 'שלום עולם',
        'attributes': {'size': 12},
      },
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'},
      },
    ],
    'list 32': [
      {
        'insert': 'שלום עולם',
        'attributes': {'size': 32},
      },
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'},
      },
    ],
    'checklist': [
      {'insert': 'שלום עולם'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
    ],
    'header in list': [
      {'insert': 'שלום עולם'},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered', 'header': 2},
      },
    ],
    'mixed RTL direction': [
      {'insert': 'שלום עולם'},
      {
        'insert': '\n',
        'attributes': {'direction': 'rtl', 'blockquote': true},
      },
    ],
    'indent code': [
      {'insert': 'hello'},
      {
        'insert': '\n',
        'attributes': {'code-block': true, 'indent': 2},
      },
      {'insert': 'world'},
      {
        'insert': '\n',
        'attributes': {'code-block': true, 'indent': 2},
      },
    ],
  };

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.5]) {
      for (final entry in cases.entries) {
        testWidgets('${entry.key} $brightness ×$scale', (tester) async {
          // שורה 1.5 בהערות (#2531): 280 תווים בהגדלה ×1.5 גבוהים מ-600.
          tester.view.physicalSize = const Size(800, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          const fallbackCases = {
            'line height',
            'named colors',
            'rgba colors',
            'script',
            'subscript',
            'inline code',
            'mixed RTL direction',
            'indent code',
            'list 32',
            'list 12',
            'checklist',
            'header in list',
          };
          Future<({Size size, Map<String, TextStyle> runs})> render(
            bool interactive,
          ) async {
            final key = GlobalKey();
            final note = PersonalNote(
              id: 'p',
              bookId: 'T',
              lineNumber: 1,
              displayTitle: 't',
              lastKnownLineNumber: null,
              status: PersonalNoteStatus.located,
              content: jsonEncode(entry.value),
              contentPlain: '',
              contentFormat: PersonalNoteContentFormat.quillDelta,
              createdAt: DateTime(2025),
              updatedAt: DateTime(2025),
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(brightness: brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          key: key,
                          width: 400,
                          child: PersonalNoteContentView(
                            note: note,
                            interactive: interactive,
                            maxPreviewChars: 280,
                            textStyle: const TextStyle(
                              fontSize: 12,
                              color: Color(0xff444444),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            final usesQuill = interactive || fallbackCases.contains(entry.key);
            expect(
              find.byType(quill.QuillEditor),
              usesQuill ? findsOneWidget : findsNothing,
            );
            expect(
              find.byType(NoteDeltaPreview),
              usesQuill ? findsNothing : findsOneWidget,
            );
            if (!interactive && usesQuill) {
              final editor = tester.widget<quill.QuillEditor>(
                find.byType(quill.QuillEditor),
              );
              expect(editor.controller.readOnly, isTrue);
              expect(editor.config.enableInteractiveSelection, isFalse);
              expect(
                find.ancestor(
                  of: find.byType(quill.QuillEditor),
                  matching: find.byType(ExcludeFocus),
                ),
                findsWidgets,
              );
            }
            expect(tester.takeException(), isNull);
            final runs = <String, TextStyle>{};
            void visit(InlineSpan span, TextStyle inherited) {
              final style = inherited.merge(span.style);
              if (span is TextSpan) {
                if (span.text?.trim().isNotEmpty ?? false) {
                  runs[span.text!] = style;
                }
                for (final child in span.children ?? <InlineSpan>[]) {
                  visit(child, style);
                }
              }
            }

            for (final element in find.byType(RichText).evaluate()) {
              visit((element.widget as RichText).text, const TextStyle());
            }
            return (size: tester.getSize(find.byKey(key)), runs: runs);
          }

          final original = await render(true);
          final light = await render(false);
          expect(light.runs, original.runs, reason: '${entry.key} styles');
          expect(
            light.size.height,
            moreOrLessEquals(original.size.height, epsilon: 1),
            reason: '${entry.key} height',
          );
        });
      }
    }
  }
}
