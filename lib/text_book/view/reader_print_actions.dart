import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/printing/page_shape_print_policy.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:otzaria/text_book/view/reader_export_actions.dart';

/// פותח את [screen] כדיאלוג שלא נסגר בלחיצה בחוץ. כל פתיחה של מסך ההדפסה
/// בקורא הטקסט ובחלונית המפרשים שלו עוברת כאן.
Future<void> showPrintingScreen(BuildContext context, PrintingScreen screen) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => screen,
    );

/// הדפסת הספר המלא מ-[startLine], עם המפרשים [activeCommentators] (ברירת
/// המחדל: הפעילים).
void showBookPrintingScreen(
  BuildContext context,
  TextBookLoaded state, {
  required int startLine,
  List<String>? activeCommentators,
  bool initialIncludeCommentaries = false,
}) {
  // תוכן מלא מה-repository — state.content יכול להיות חלקי (חימום/שחרור).
  // חובה לקרוא כאן: בתוך ה-builder ה-context הוא של הדיאלוג וחסר לו provider ל-TextBookBloc.
  final contentData = context.read<TextBookBloc>().repository.getBookContent(
    state.book,
  );
  showPrintingScreen(
    context,
    PrintingScreen(
      data: contentData,
      bookId: state.book.title,
      book: state.book,
      protection: state.protection,
      links: state.links,
      activeCommentators: activeCommentators ?? state.activeCommentators,
      initialIncludeCommentaries: initialIncludeCommentaries,
      startLine: startLine,
      displayProfile: readerExportProfile(state),
      commentaryDisplayProfile: state.displayProfile(
        target: TextTarget.commentary,
        channel: TextChannel.export,
      ),
      tableOfContents: state.tableOfContents,
    ),
  );
}

/// הדפסת הספר מהקורא, לפי מדיניות ההדפסה של תצוגת צורת הדף.
mixin ReaderPrintActions<T extends StatefulWidget> on State<T> {
  TextBookTab get readerTab;

  /// צילום תצוגת צורת הדף להדפסה; null כשאין מה לצלם.
  Future<Uint8List?> capturePageShapeViewPng();

  Future<void> handlePrintPress(TextBookLoaded state) async {
    context.read<TourCubit>().recordInteraction(
      TourInteraction(type: TourInteractionType.printUsed),
    );
    var commentators = state.activeCommentators;
    var protection = state.protection;
    var useScreenshot = state.showPageShapeView;
    if (state.showPageShapeView) {
      final policy = await resolvePageShapePrintPolicy(
        mainProtection: state.protection,
        layout: readerTab.pageShapePluginController.layout,
        availableCommentators: state.availableCommentators,
        links: state.links,
      );
      commentators = policy.commentators;
      protection = policy.protection;
      useScreenshot = policy.useScreenshot;
    }
    if (!mounted) return;
    if (useScreenshot) {
      final png = await capturePageShapeViewPng();
      if (!mounted) return;
      if (png == null || png.isEmpty) {
        UiSnack.showError(TextBookMessages.cannotCapturePageShapeForPrint);
        return;
      }
      if (!mounted) return;

      showPrintingScreen(
        context,
        PrintingScreen(
          // במצב זה ה-PDF נוצר מצילום המסך, ולכן אין צורך בנתוני הטקסט
          data: Future.value(''),
          bookId: state.book.title,
          protection: protection,
          displayProfile: readerExportProfile(state),
          createPdfOverride: (PdfPageFormat format) async {
            final doc = pw.Document(compress: false);
            final img = pw.MemoryImage(png);
            doc.addPage(
              pw.Page(
                pageFormat: format,
                margin: pw.EdgeInsets.zero,
                build: (context) =>
                    pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
              ),
            );
            return doc.save();
          },
        ),
      );
      return;
    }

    showBookPrintingScreen(
      context,
      state,
      startLine: readerTab.index,
      activeCommentators: commentators,
      initialIncludeCommentaries: state.showPageShapeView,
    );
  }
}
