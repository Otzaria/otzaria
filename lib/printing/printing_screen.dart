import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/constants/fonts.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/pdf_book/pdf_page_number_dispaly.dart';
import 'package:otzaria/pdf_book/pdf_thumbnails_screen.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:otzaria/models/books.dart';

class PrintingScreen extends StatefulWidget {
  final Future<String> data;
  final Future<Uint8List> Function(PdfPageFormat format)? createPdfOverride;
  final String bookId;
  final List<Link> links;
  final List<String> activeCommentators;
  final bool removeNikud;
  final bool removeTaamim;
  final int startLine;
  final List<TocEntry> tableOfContents;
  const PrintingScreen({
    super.key,
    required this.data,
    this.createPdfOverride,
    required this.bookId,
    this.links = const [],
    this.activeCommentators = const [],
    this.startLine = 0,
    this.removeNikud = false,
    this.removeTaamim = false,
    this.tableOfContents = const [],
  });
  @override
  State<PrintingScreen> createState() => _PrintingScreenState();
}

class _PrintingScreenState extends State<PrintingScreen> {
  double fontSize = 15.0;
  String fontName =
      AppFonts.fontPaths.keys.first; // ברירת מחדל - הגופן הראשון ברשימה
  late int startLine;
  late int endLine;
  late Future<Uint8List> pdf;
  pw.PageOrientation orientation = pw.PageOrientation.portrait;
  PdfPageFormat format = PdfPageFormat.a4;
  double pageMargin = 20.0;

  final PdfViewerController _pdfViewerController = PdfViewerController();
  final ValueNotifier<PdfDocumentRef?> _documentRef =
      ValueNotifier<PdfDocumentRef?>(null);

  bool _showThumbnails = false;
  int _pagesPerSheet = 1;

  bool _includeCommentaries = false;
  bool _includePersonalNotes = false;

  final Map<String, String> _commentaryContentCache = {};
  List<PersonalNote>? _personalNotesCache;
  bool _isLoadingNotes = false;

  // מצב בחירה: שורות או כותרות
  bool _isHeaderMode = true; // ברירת מחדל: כותרות
  int? _startHeaderIndex;
  int? _endHeaderIndex;
  List<TocEntry> _flatHeaders = [];

  // הגדרות ניקוד וטעמים - ברירת מחדל לפי תצוגת הספר
  late bool _removeNikud;
  late bool _removeTaamim;

  @override
  void initState() {
    super.initState();
    startLine = widget.startLine;
    endLine = startLine;

    // במצב "צורת הדף" (PDF חיצוני), ברירת המחדל היא לרוחב
    if (widget.createPdfOverride != null) {
      orientation = pw.PageOrientation.landscape;
    }

    // אתחול הגדרות ניקוד וטעמים לפי תצוגת הספר
    _removeNikud = widget.removeNikud;
    _removeTaamim = widget.removeTaamim;

    // במצב PDF חיצוני (כמו "צורת הדף") אין טווח שורות/כותרות.
    if (widget.createPdfOverride != null) {
      _isHeaderMode = false;
      _flatHeaders = const [];
      pdf = _createOutputPdf(format);
      return;
    }

    // יצירת רשימה שטוחה של כל הכותרות
    _flatHeaders = _flattenHeaders(widget.tableOfContents);

    // אם יש כותרות, אתחל את מצב הכותרות
    if (_flatHeaders.isNotEmpty) {
      _startHeaderIndex = 0;
      _endHeaderIndex = min(2, _flatHeaders.length - 1);
      _updateRangeByHeaders();
    } else {
      // אם אין כותרות, עבור למצב שורות
      _isHeaderMode = false;
      () async {
        endLine = min(startLine + 3, (await widget.data).split('\n').length);
        setState(() {});
      }();
    }

    pdf = _createOutputPdf(format);
  }

  @override
  void dispose() {
    _documentRef.dispose();
    super.dispose();
  }

  // פונקציה ליצירת רשימה שטוחה של כל הכותרות
  List<TocEntry> _flattenHeaders(List<TocEntry> headers) {
    List<TocEntry> result = [];
    for (var header in headers) {
      // דילוג על רמה 1 (כותרת ראשית של הספר)
      if (header.level > 1) {
        result.add(header);
      }
      if (header.children.isNotEmpty) {
        result.addAll(_flattenHeaders(header.children));
      }
    }
    return result;
  }

  // עדכון טווח השורות לפי כותרות נבחרות
  void _updateRangeByHeaders() async {
    if (_startHeaderIndex != null && _endHeaderIndex != null) {
      final startHeader = _flatHeaders[_startHeaderIndex!];
      final totalLines = (await widget.data).split('\n').length;

      startLine = startHeader.index;

      // מציאת סוף הכותרת האחרונה
      if (_endHeaderIndex! < _flatHeaders.length - 1) {
        // אם יש כותרת נוספת, נעצור לפניה
        endLine = _flatHeaders[_endHeaderIndex! + 1].index;
      } else {
        // אם זו הכותרת האחרונה, נלך עד סוף הספר
        endLine = totalLines;
      }

      setState(() {});
    }
  }

  @override
  void setState(VoidCallback fn) {
    pdf = _createOutputPdf(format);
    if (mounted) {
      super.setState(fn);
    }
  }

  void printPdf() {
    Printing.layoutPdf(onLayout: createPdf);
  }

  Future<Uint8List> _createOutputPdf(PdfPageFormat format) async {
    final base = await _createBasePdf(format);
    if (_pagesPerSheet <= 1) return base;

    try {
      return await _createNUpPdfFromRaster(
        base,
        sheetFormat: format,
        pagesPerSheet: _pagesPerSheet,
      );
    } catch (_) {
      // fallback: always return original PDF if raster/imposition fails
      return base;
    }
  }

  Future<Uint8List> _createBasePdf(PdfPageFormat format) async {
    final override = widget.createPdfOverride;
    if (override != null) {
      final effectiveFormat =
          orientation == pw.PageOrientation.landscape ? format.landscape : format;
      return override(effectiveFormat);
    }
    return createPdf(format);
  }

  Future<Uint8List> _createNUpPdfFromRaster(
    Uint8List sourcePdf, {
    required PdfPageFormat sheetFormat,
    required int pagesPerSheet,
  }) async {
    final (rows, cols) = switch (pagesPerSheet) {
      2 => (1, 2),
      4 => (2, 2),
      _ => (1, 1),
    };
    if (rows == 1 && cols == 1) return sourcePdf;

    const dpi = 120.0;
    final rasterPages = <Uint8List>[];

    await for (final raster in Printing.raster(sourcePdf, dpi: dpi)) {
      final image = await raster.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) continue;
      rasterPages.add(data.buffer.asUint8List());
    }

    if (rasterPages.isEmpty) return sourcePdf;

    final output = pw.Document(compress: false);
    final cells = rows * cols;
    final cellHeight = sheetFormat.height / rows;

    for (var i = 0; i < rasterPages.length; i += cells) {
      final chunk = rasterPages.sublist(
        i,
        min(i + cells, rasterPages.length),
      );

      output.addPage(
        pw.Page(
          pageFormat: sheetFormat,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                children: List.generate(rows, (row) {
                  return pw.SizedBox(
                    height: cellHeight,
                    child: pw.Row(
                      children: List.generate(cols, (col) {
                        final indexInChunk = row * cols + col;
                        if (indexInChunk >= chunk.length) {
                          return pw.Expanded(child: pw.SizedBox());
                        }
                        final image = pw.MemoryImage(chunk[indexInChunk]);
                        return pw.Expanded(
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Image(
                              image,
                              fit: pw.BoxFit.contain,
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            );
          },
        ),
      );
    }

    return output.save();
  }

  Future<Uint8List> createPdf(PdfPageFormat format) async {
    final font = pw.Font.ttf(await rootBundle.load(fonts[fontName]!));
    final fullBackFont = pw.Font.ttf(await rootBundle
        .load('fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf'));
    String dataString = await widget.data;
    if (orientation == pw.PageOrientation.landscape) {
      format = format.landscape;
    }

    // הסרת ניקוד וטעמים לפי הגדרות המשתמש
    // טעמים: U+0591-U+05AF
    // ניקוד: U+05B0-U+05C7
    if (_removeNikud && _removeTaamim) {
      // הסרת ניקוד וטעמים (U+0591-U+05C7)
      dataString = removeVolwels(dataString);
    } else if (_removeNikud && !_removeTaamim) {
      // הסרת ניקוד בלבד, שמירת טעמים (U+05B0-U+05C7)
      dataString = dataString
          .replaceAll('־', ' ')
          .replaceAll('׀', ' ')
          .replaceAll('|', ' ')
          .replaceAll(RegExp(r'[\u05B0-\u05C7]'), '');
    } else if (!_removeNikud && _removeTaamim) {
      // הסרת טעמים בלבד, שמירת ניקוד
      dataString = removeTeamim(dataString);
    }
    // אם שניהם false - לא מסירים כלום

    final shouldReplaceHolyNames =
        Settings.getValue<bool>('key-replace-holy-names') ?? true;
    if (shouldReplaceHolyNames) {
      dataString = replaceHolyNames(dataString);
    }

    List<String> data = stripHtmlIfNeeded(dataString).split('\n').toList();
    final pageMargin = this.pageMargin;
    final fontSize = this.fontSize;

    String bookName = data[0];
    if (shouldReplaceHolyNames) {
      bookName = replaceHolyNames(bookName);
    }
    final allLines = data;
    final selectedStart = startLine.clamp(0, allLines.length);
    final selectedEnd = endLine.clamp(selectedStart, allLines.length);

    final personalNotes = _includePersonalNotes
        ? await _getPersonalNotesForBook(widget.bookId)
        : const <PersonalNote>[];

    final blocks = await _buildPrintBlocks(
      allLines: allLines,
      selectedStart: selectedStart,
      selectedEnd: selectedEnd,
      shouldReplaceHolyNames: shouldReplaceHolyNames,
      personalNotes: personalNotes,
    );

    final result = await Isolate.run(() async {
      final pdfData =
          pw.Document(compress: false, pageMode: PdfPageMode.outlines);
      pdfData.addPage(pw.MultiPage(
          theme:
              pw.ThemeData.withFont(base: font, fontFallback: [fullBackFont]),
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          textDirection: pw.TextDirection.rtl,
          maxPages: 1000000,
          margin: pw.EdgeInsets.all(pageMargin),
          pageFormat: format,
          header: (pw.Context context) {
            return pw.Container(
                alignment: pw.Alignment.topCenter,
                margin: const pw.EdgeInsets.only(top: 1.0 * PdfPageFormat.cm),
                child: pw.Text(bookName,
                    style: pw.Theme.of(context)
                        .defaultTextStyle
                        .copyWith(color: PdfColors.grey)));
          },
          footer: (pw.Context context) {
            return pw.Container(
                alignment: pw.Alignment.bottomCenter,
                margin: const pw.EdgeInsets.only(top: 1.0 * PdfPageFormat.cm),
                child: pw.Text(
                    'עמוד ${context.pageNumber} מתוך ${context.pagesCount} - הודפס מתוכנת אוצריא',
                    style: pw.Theme.of(context)
                        .defaultTextStyle
                        .copyWith(color: PdfColors.grey)));
          },
          build: (pw.Context context) {
            return blocks
                .map((b) {
                  final kind = b['kind'];
                  final title = b['title'];
                  final text = (b['text'] ?? '').replaceAll('\n', '');

                  if (kind == 'commentaryTitle') {
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(
                        top: 6,
                        right: 8,
                        left: 8,
                      ),
                      child: pw.Text(
                        title ?? 'מפרשים',
                        style: pw.TextStyle(
                          fontSize: max(10.0, fontSize * 0.9),
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800,
                        ),
                      ),
                    );
                  }

                  if (kind == 'commentaryGroupTitle') {
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(
                        top: 4,
                        right: 12,
                        left: 8,
                      ),
                      child: pw.Text(
                        title ?? '',
                        style: pw.TextStyle(
                          fontSize: max(10.0, fontSize * 0.9),
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey900,
                        ),
                      ),
                    );
                  }

                  if (kind == 'noteTitle') {
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(
                        top: 6,
                        right: 8,
                        left: 8,
                      ),
                      child: pw.Text(
                        title ?? 'הערות אישיות',
                        style: pw.TextStyle(
                          fontSize: max(10.0, fontSize * 0.9),
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800,
                        ),
                      ),
                    );
                  }

                  final effectiveFontSize = switch (kind) {
                    'commentary' || 'note' => max(10.0, fontSize * 0.9),
                    _ => fontSize,
                  };

                  final padding = switch (kind) {
                    'commentary' || 'note' => const pw.EdgeInsets.only(
                        top: 2,
                        bottom: 2,
                        right: 18,
                        left: 8,
                      ),
                    'commentaryGroupTitle' => const pw.EdgeInsets.only(
                        top: 4,
                        bottom: 2,
                        right: 12,
                        left: 8,
                      ),
                    _ => const pw.EdgeInsets.all(8.0),
                  };

                  return pw.Padding(
                    padding: padding,
                    child: pw.Paragraph(
                      text: text,
                      textAlign: pw.TextAlign.justify,
                      style: pw.TextStyle(
                        fontSize: effectiveFontSize,
                        font: font,
                      ),
                    ),
                  );
                })
                .toList();
          }));

      return await pdfData.save();
    });

    return result;
  }

  Future<List<Map<String, String>>> _buildPrintBlocks({
    required List<String> allLines,
    required int selectedStart,
    required int selectedEnd,
    required bool shouldReplaceHolyNames,
    required List<PersonalNote> personalNotes,
  }) async {
    final blocks = <Map<String, String>>[];

    Map<int, List<PersonalNote>> notesByLine = const {};
    if (_includePersonalNotes && personalNotes.isNotEmpty) {
      final map = <int, List<PersonalNote>>{};
      for (final note in personalNotes) {
        final ln = note.lineNumber;
        if (ln == null) continue;
        (map[ln] ??= []).add(note);
      }
      notesByLine = map;
    }

    for (var i = selectedStart; i < selectedEnd; i++) {
      var lineText = allLines[i];
      if (shouldReplaceHolyNames) {
        lineText = replaceHolyNames(lineText);
      }
      blocks.add({'kind': 'text', 'text': lineText});

      final lineNumber1Based = i + 1;

      if (_includeCommentaries) {
        final linksForLine = await getLinksforIndexs(
          indexes: [i],
          links: widget.links,
          commentatorsToShow: widget.activeCommentators,
        );

        if (linksForLine.isNotEmpty) {
          blocks.add({'kind': 'commentaryTitle', 'title': 'מפרשים'});

          // קיבוץ לפי מפרש (כמו בתצוגת PDF): כותרת לכל מפרש, ומתחתיה כל הקטעים שלו
          String? currentGroupTitle;
          for (final link in linksForLine) {
            final commentatorTitle = getTitleFromPath(link.path2);
            if (currentGroupTitle != commentatorTitle) {
              currentGroupTitle = commentatorTitle;
              blocks.add({
                'kind': 'commentaryGroupTitle',
                'title': commentatorTitle,
              });
            }

            final content = await _getCommentaryContent(
              link,
              shouldReplaceHolyNames: shouldReplaceHolyNames,
            );
            if (content.trim().isEmpty) continue;
            blocks.add({
              'kind': 'commentary',
              'text': content,
            });
          }
        }
      }

      if (_includePersonalNotes) {
        final notes = notesByLine[lineNumber1Based] ?? const <PersonalNote>[];
        if (notes.isNotEmpty) {
          blocks.add({'kind': 'noteTitle', 'title': 'הערות אישיות'});
          for (final note in notes) {
            var noteText = note.content;
            if (shouldReplaceHolyNames) {
              noteText = replaceHolyNames(noteText);
            }
            blocks.add({'kind': 'note', 'text': noteText});
          }
        }
      }
    }

    return blocks;
  }

  Future<String> _getCommentaryContent(
    Link link, {
    required bool shouldReplaceHolyNames,
  }) async {
    final key = '${link.path2}::${link.index2}::${link.heRef}';
    final cached = _commentaryContentCache[key];
    if (cached != null) return cached;

    var text = await link.content;
    text = stripHtmlIfNeeded(text);
    if (_removeNikud && _removeTaamim) {
      text = removeVolwels(text);
    } else if (_removeNikud && !_removeTaamim) {
      text = text
          .replaceAll('־', ' ')
          .replaceAll('׀', ' ')
          .replaceAll('|', ' ')
          .replaceAll(RegExp(r'[\u05B0-\u05C7]'), '');
    } else if (!_removeNikud && _removeTaamim) {
      text = removeTeamim(text);
    }
    if (shouldReplaceHolyNames) {
      text = replaceHolyNames(text);
    }

    _commentaryContentCache[key] = text;
    return text;
  }

  Future<List<PersonalNote>> _getPersonalNotesForBook(String bookId) async {
    if (_personalNotesCache != null) return _personalNotesCache!;
    if (_isLoadingNotes) return const <PersonalNote>[];
    _isLoadingNotes = true;

    try {
      final repo = PersonalNotesRepository();
      final all = await repo.loadNotes(bookId);
      final located = all.where((n) => n.hasLocation).toList();
      _personalNotesCache = located;
      return located;
    } catch (_) {
      _personalNotesCache = const <PersonalNote>[];
      return const <PersonalNote>[];
    } finally {
      _isLoadingNotes = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCustomPdfMode = widget.createPdfOverride != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('הדפסה'),
        centerTitle: true,
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              final path = await FilePicker.platform.saveFile(
                  dialogTitle: "שמירת קובץ PDF", allowedExtensions: ['pdf']);
              if (path != null) {
                final file = File('$path.pdf');
                await file.writeAsBytes(await pdf);
              }
            },
            icon: const Icon(FluentIcons.save_24_regular),
            label: const Text('שמירה'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () async {
              await Printing.layoutPdf(
                usePrinterSettings: true,
                onLayout: (PdfPageFormat format) async => pdf,
                format: format,
              );
            },
            icon: const Icon(FluentIcons.print_24_regular),
            label: const Text('הדפסה'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: FutureBuilder(
        future: widget.data,
        builder: (context, snapshot) {
          if (isCustomPdfMode) {
            return Row(
              children: [
                // פאנל הגדרות בצד
                Container(
                  width: 320,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                      left: BorderSide(
                        color: colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSectionCard(
                          context: context,
                          title: 'תצוגה מקדימה',
                          icon: FluentIcons.eye_24_regular,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDropdownRow(
                                context: context,
                                label: 'מעבר לדף',
                                child: SizedBox(
                                  height: 40,
                                  child: PageNumberDisplay(
                                      controller: _pdfViewerController),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                title: const Text('תצוגה מוקטנת של כל הדפים'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: _showThumbnails,
                                onChanged: (value) {
                                  setState(() {
                                    _showThumbnails = value;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildSectionCard(
                          context: context,
                          title: 'הגדרות דף',
                          icon: FluentIcons.options_24_regular,
                          child: Column(
                            children: [
                              _buildDropdownRow(
                                context: context,
                                label: 'גודל דף',
                                child: DropdownButton<PdfPageFormat>(
                                  value: format,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  borderRadius: BorderRadius.circular(8),
                                  onChanged: (PdfPageFormat? value) {
                                    if (value == null) return;
                                    setState(() {
                                      format = value;
                                    });
                                  },
                                  items: const {
                                    'A4': PdfPageFormat.a4,
                                    'Letter': PdfPageFormat.letter,
                                  }.entries.map((entry) {
                                    return DropdownMenuItem(
                                      value: entry.value,
                                      child: Text(entry.key),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildDropdownRow(
                                context: context,
                                label: 'כיוון',
                                child: DropdownButton<pw.PageOrientation>(
                                  value: orientation,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  borderRadius: BorderRadius.circular(8),
                                  onChanged: (pw.PageOrientation? value) {
                                    if (value == null) return;
                                    orientation = value;
                                    setState(() {});
                                  },
                                  items: const [
                                    DropdownMenuItem(
                                      value: pw.PageOrientation.portrait,
                                      child: Text('לאורך'),
                                    ),
                                    DropdownMenuItem(
                                      value: pw.PageOrientation.landscape,
                                      child: Text('לרוחב'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildDropdownRow(
                                context: context,
                                label: 'עמודים בגליון',
                                child: DropdownButton<int>(
                                  value: _pagesPerSheet,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  borderRadius: BorderRadius.circular(8),
                                  onChanged: (int? value) {
                                    if (value == null) return;
                                    setState(() {
                                      _pagesPerSheet = value;
                                    });
                                  },
                                  items: const [
                                    DropdownMenuItem(
                                      value: 1,
                                      child: Text('1 (רגיל)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 2,
                                      child: Text('2 (יישור לימין)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 4,
                                      child: Text('4 (יישור לימין)'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // תצוגה מקדימה של ה-PDF
                Expanded(
                  child: Container(
                    color: colorScheme.surfaceContainerLow,
                    child: Row(
                      children: [
                        Expanded(
                          child: FutureBuilder(
                            future: pdf,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                      ConnectionState.done &&
                                  snapshot.hasData) {
                                return PdfViewer.data(
                                  snapshot.data!,
                                  sourceName: 'printing',
                                  controller: _pdfViewerController,
                                  params: PdfViewerParams(
                                    viewerOverlayBuilder:
                                        (context, size, handleLinkTap) => [
                                      PdfViewerScrollThumb(
                                        controller: _pdfViewerController,
                                        orientation:
                                            ScrollbarOrientation.right,
                                        thumbSize: const Size(40, 25),
                                        thumbBuilder: (context, thumbSize,
                                                pageNumber, controller) =>
                                            Container(
                                          color: Colors.black,
                                          child: Center(
                                            child: Text(
                                              pageNumber.toString(),
                                              style: const TextStyle(
                                                  color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    onDocumentChanged: (document) {
                                      if (document == null) {
                                        _documentRef.value = null;
                                      }
                                    },
                                    onViewerReady: (document, controller) {
                                      _documentRef.value =
                                          controller.documentRef;
                                    },
                                  ),
                                );
                              }
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'מכין תצוגה מקדימה...',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        if (_showThumbnails) ...[
                          VerticalDivider(
                            width: 1,
                            color: colorScheme.outlineVariant,
                          ),
                          SizedBox(
                            width: 260,
                            child: ValueListenableBuilder<PdfDocumentRef?>(
                              valueListenable: _documentRef,
                              builder: (context, documentRef, _) {
                                return ThumbnailsView(
                                  documentRef: documentRef,
                                  controller: _pdfViewerController,
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          if (snapshot.connectionState == ConnectionState.done) {
            final totalLines = snapshot.data!.split('\n').length;
            return Row(
              children: [
                // פאנל הגדרות בצד
                Container(
                  width: 320,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                      left: BorderSide(
                        color: colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ניווט ותצוגה מקדימה
                        _buildSectionCard(
                          context: context,
                          title: 'תצוגה מקדימה',
                          icon: FluentIcons.eye_24_regular,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDropdownRow(
                                context: context,
                                label: 'מעבר לדף',
                                child: SizedBox(
                                  height: 40,
                                  child: PageNumberDisplay(
                                      controller: _pdfViewerController),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                title: const Text('תצוגה מוקטנת של כל הדפים'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: _showThumbnails,
                                onChanged: (value) {
                                  setState(() {
                                    _showThumbnails = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              if (!isCustomPdfMode) ...[
                                SwitchListTile(
                                  title: const Text('כלול מפרשים'),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: _includeCommentaries,
                                  onChanged: (value) {
                                    setState(() {
                                      _includeCommentaries = value;
                                    });
                                  },
                                ),
                                SwitchListTile(
                                  title: const Text('כלול הערות אישיות'),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: _includePersonalNotes,
                                  onChanged: (value) {
                                    setState(() {
                                      _includePersonalNotes = value;
                                      if (!value) {
                                        _personalNotesCache = null;
                                      }
                                    });
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // כותרת טווח הדפסה
                        _buildSectionCard(
                          context: context,
                          title: 'טווח הדפסה',
                          icon: FluentIcons.document_page_number_24_regular,
                          child: Column(
                            children: [
                              // תפריט בחירה: שורות/כותרות
                              if (_flatHeaders.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: SegmentedButton<bool>(
                                          segments: const [
                                            ButtonSegment<bool>(
                                              value: true,
                                              label: Text('כותרות'),
                                              icon: Icon(
                                                  FluentIcons
                                                      .text_bullet_list_24_regular,
                                                  size: 16),
                                            ),
                                            ButtonSegment<bool>(
                                              value: false,
                                              label: Text('שורות'),
                                              icon: Icon(
                                                  FluentIcons
                                                      .text_number_list_ltr_24_regular,
                                                  size: 16),
                                            ),
                                          ],
                                          selected: {_isHeaderMode},
                                          onSelectionChanged:
                                              (Set<bool> newSelection) {
                                            setState(() {
                                              _isHeaderMode =
                                                  newSelection.first;
                                              if (_isHeaderMode &&
                                                  _flatHeaders.isNotEmpty) {
                                                // אתחול ברירת מחדל לכותרת ראשונה
                                                _startHeaderIndex = 0;
                                                _endHeaderIndex = min(
                                                    2, _flatHeaders.length - 1);
                                                _updateRangeByHeaders();
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              // בחירת טווח לפי שורות
                              if (!_isHeaderMode) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'שורה ${startLine + 1}',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      'שורה ${endLine + 1}',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                RangeSlider(
                                  min: 0.0,
                                  max: totalLines.toDouble(),
                                  values: RangeValues(
                                      startLine.toDouble(), endLine.toDouble()),
                                  onChanged: (value) {
                                    startLine = value.start.toInt();
                                    endLine = value.end.toInt();
                                    setState(() {});
                                  },
                                ),
                                Text(
                                  '${endLine - startLine} שורות נבחרו מתוך $totalLines',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],

                              // בחירת טווח לפי כותרות
                              if (_isHeaderMode && _flatHeaders.isNotEmpty) ...[
                                _buildDropdownRow(
                                  context: context,
                                  label: 'מ-',
                                  child: DropdownButton<int>(
                                    value: _startHeaderIndex,
                                    isExpanded: true,
                                    underline: const SizedBox(),
                                    borderRadius: BorderRadius.circular(8),
                                    onChanged: (int? value) {
                                      setState(() {
                                        _startHeaderIndex = value;
                                        if (_endHeaderIndex != null &&
                                            value != null &&
                                            value > _endHeaderIndex!) {
                                          _endHeaderIndex = value;
                                        }
                                        _updateRangeByHeaders();
                                      });
                                    },
                                    items: _flatHeaders
                                        .asMap()
                                        .entries
                                        .map((entry) {
                                      return DropdownMenuItem<int>(
                                        value: entry.key,
                                        child: Text(
                                          entry.value.fullText,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildDropdownRow(
                                  context: context,
                                  label: 'עד-',
                                  child: DropdownButton<int>(
                                    value: _endHeaderIndex,
                                    isExpanded: true,
                                    underline: const SizedBox(),
                                    borderRadius: BorderRadius.circular(8),
                                    onChanged: (int? value) {
                                      setState(() {
                                        _endHeaderIndex = value;
                                        if (_startHeaderIndex != null &&
                                            value != null &&
                                            value < _startHeaderIndex!) {
                                          _startHeaderIndex = value;
                                        }
                                        _updateRangeByHeaders();
                                      });
                                    },
                                    items: _flatHeaders
                                        .asMap()
                                        .entries
                                        .map((entry) {
                                      return DropdownMenuItem<int>(
                                        value: entry.key,
                                        child: Text(
                                          entry.value.fullText,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${(_endHeaderIndex ?? 0) - (_startHeaderIndex ?? 0) + 1} כותרות נבחרו',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // הגדרות טקסט
                        _buildSectionCard(
                          context: context,
                          title: 'הגדרות טקסט',
                          icon: FluentIcons.text_font_24_regular,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSliderRow(
                                context: context,
                                label: 'גודל גופן',
                                value: fontSize,
                                min: 10,
                                max: 50,
                                displayValue: fontSize.toInt().toString(),
                                onChanged: (value) {
                                  setState(() {
                                    fontSize = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              _buildDropdownRow(
                                context: context,
                                label: 'גופן',
                                child: DropdownButton<String>(
                                  value: fontName,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  borderRadius: BorderRadius.circular(8),
                                  onChanged: (String? value) {
                                    fontName = value!;
                                    setState(() {});
                                  },
                                  items: fontNames.entries
                                      .map<DropdownMenuItem<String>>((entry) {
                                    return DropdownMenuItem<String>(
                                      value: entry.key,
                                      child: Text(
                                        entry.value,
                                        style: TextStyle(
                                          fontFamily: entry.key,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // הגדרות ניקוד וטעמים
                              SwitchListTile(
                                title: const Text('הדפסה עם ניקוד'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: !_removeNikud,
                                onChanged: (value) {
                                  setState(() {
                                    _removeNikud = !value;
                                  });
                                },
                              ),
                              SwitchListTile(
                                title: const Text('הדפסה עם טעמים'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: !_removeTaamim,
                                onChanged: (value) {
                                  setState(() {
                                    _removeTaamim = !value;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // הגדרות עמוד
                        _buildSectionCard(
                          context: context,
                          title: 'הגדרות עמוד',
                          icon: FluentIcons.document_24_regular,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSliderRow(
                                context: context,
                                label: 'שוליים',
                                value: pageMargin,
                                min: 10,
                                max: 100,
                                displayValue: '${pageMargin.toInt()} px',
                                onChanged: (value) {
                                  setState(() {
                                    pageMargin = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              _buildDropdownRow(
                                context: context,
                                label: 'גודל עמוד',
                                child: DropdownButton<PdfPageFormat>(
                                  value: format,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  borderRadius: BorderRadius.circular(8),
                                  onChanged: (PdfPageFormat? value) {
                                    format = value!;
                                    setState(() {});
                                  },
                                  items: formats.entries
                                      .map<DropdownMenuItem<PdfPageFormat>>(
                                          (entry) {
                                    return DropdownMenuItem<PdfPageFormat>(
                                      value: entry.key,
                                      child: Text(entry.value),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildDropdownRow(
                                context: context,
                                label: 'כיוון',
                                child: DropdownButton<pw.PageOrientation>(
                                  value: orientation,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  borderRadius: BorderRadius.circular(8),
                                  onChanged: (pw.PageOrientation? value) {
                                    orientation = value!;
                                    setState(() {});
                                  },
                                  items: const [
                                    DropdownMenuItem(
                                      value: pw.PageOrientation.portrait,
                                      child: Text('לאורך'),
                                    ),
                                    DropdownMenuItem(
                                      value: pw.PageOrientation.landscape,
                                      child: Text('לרוחב'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildDropdownRow(
                                context: context,
                                label: 'עמודים בגליון',
                                child: DropdownButton<int>(
                                  value: _pagesPerSheet,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  borderRadius: BorderRadius.circular(8),
                                  onChanged: (int? value) {
                                    if (value == null) return;
                                    setState(() {
                                      _pagesPerSheet = value;
                                    });
                                  },
                                  items: const [
                                    DropdownMenuItem(
                                      value: 1,
                                      child: Text('1 (רגיל)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 2,
                                      child: Text('2 (יישור לימין)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 4,
                                      child: Text('4 (יישור לימין)'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // תצוגה מקדימה של ה-PDF
                Expanded(
                  child: Container(
                    color: colorScheme.surfaceContainerLow,
                    child: Row(
                      children: [
                        Expanded(
                          child: FutureBuilder(
                            future: pdf,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                      ConnectionState.done &&
                                  snapshot.hasData) {
                                return PdfViewer.data(
                                  snapshot.data!,
                                  sourceName: 'printing',
                                  controller: _pdfViewerController,
                                  params: PdfViewerParams(
                                    viewerOverlayBuilder:
                                        (context, size, handleLinkTap) => [
                                      PdfViewerScrollThumb(
                                        controller: _pdfViewerController,
                                        orientation:
                                            ScrollbarOrientation.right,
                                        thumbSize: const Size(40, 25),
                                        thumbBuilder: (context, thumbSize,
                                                pageNumber, controller) =>
                                            Container(
                                          color: Colors.black,
                                          child: Center(
                                            child: Text(
                                              pageNumber.toString(),
                                              style: const TextStyle(
                                                  color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    onDocumentChanged: (document) {
                                      if (document == null) {
                                        _documentRef.value = null;
                                      }
                                    },
                                    onViewerReady: (document, controller) {
                                      _documentRef.value = controller.documentRef;
                                    },
                                  ),
                                );
                              }
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'מכין תצוגה מקדימה...',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        if (_showThumbnails) ...[
                          VerticalDivider(
                            width: 1,
                            color: colorScheme.outlineVariant,
                          ),
                          SizedBox(
                            width: 260,
                            child: ValueListenableBuilder<PdfDocumentRef?>(
                              valueListenable: _documentRef,
                              builder: (context, documentRef, _) {
                                return ThumbnailsView(
                                  documentRef: documentRef,
                                  controller: _pdfViewerController,
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'טוען נתונים...',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required BuildContext context,
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                displayValue,
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownRow({
    required BuildContext context,
    required String label,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outlineVariant,
              ),
            ),
            child: child,
          ),
        ),
      ],
    );
  }

  // שימוש בקבועים מ-AppFonts
  Map<String, String> get fonts => AppFonts.fontPaths;
  Map<String, String> get fontNames => AppFonts.fontLabels;

  final Map<PdfPageFormat, String> formats = {
    PdfPageFormat.a4: 'A4',
    PdfPageFormat.letter: 'Letter',
    PdfPageFormat.legal: 'Legal',
    PdfPageFormat.a5: 'A5',
    PdfPageFormat.a3: 'A3',
  };
}
