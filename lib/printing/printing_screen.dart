import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/constants/fonts.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PrintingScreen extends StatefulWidget {
  final Future<String> data;
  final bool removeNikud;
  final int startLine;
  const PrintingScreen({
    super.key,
    required this.data,
    this.startLine = 0,
    this.removeNikud = false,
  });
  @override
  State<PrintingScreen> createState() => _PrintingScreenState();
}

class _PrintingScreenState extends State<PrintingScreen> {
  double fontSize = 15.0;
  String fontName = AppFonts.fontPaths.keys.first; // ברירת מחדל - הגופן הראשון ברשימה
  late int startLine;
  late int endLine;
  late Future<Uint8List> pdf;
  pw.PageOrientation orientation = pw.PageOrientation.portrait;
  PdfPageFormat format = PdfPageFormat.a4;
  double pageMargin = 20.0;

  @override
  void initState() {
    super.initState();
    startLine = widget.startLine;
    endLine = startLine;
    () async {
      endLine = min(startLine + 3, (await widget.data).split('\n').length);
      setState(() {});
    }();

    pdf = createPdf(format);
  }

  @override
  void setState(VoidCallback fn) {
    pdf = createPdf(format);
    if (mounted) {
      super.setState(fn);
    }
  }

  void printPdf() {
    Printing.layoutPdf(onLayout: createPdf);
  }

  Future<Uint8List> createPdf(PdfPageFormat format) async {
    final font = pw.Font.ttf(await rootBundle.load(fonts[fontName]!));
    final fullBackFont = pw.Font.ttf(await rootBundle
        .load('fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf'));
    String dataString = await widget.data;
    if (orientation == pw.PageOrientation.landscape) {
      format = format.landscape;
    }
    if (widget.removeNikud) {
      dataString = removeVolwels(dataString);
    }

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
    data = data.getRange(startLine, endLine).toList();

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
          build: (pw.Context context) => data
              .map(
                (i) => pw.Padding(
                  padding: const pw.EdgeInsets.all(8.0),
                  child: pw.Paragraph(
                      text: i.replaceAll('\n', ''),
                      textAlign: pw.TextAlign.justify,
                      style: pw.TextStyle(fontSize: fontSize, font: font)),
                ),
              )
              .toList()));

      return await pdfData.save();
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                        // כותרת טווח הדפסה
                        _buildSectionCard(
                          context: context,
                          title: 'טווח הדפסה',
                          icon: FluentIcons.document_page_number_24_regular,
                          child: Column(
                            children: [
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
                    child: FutureBuilder(
                      future: pdf,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done &&
                            snapshot.hasData) {
                          return PdfViewer.data(
                            snapshot.data!,
                            sourceName: 'printing',
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
