import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:collection/collection.dart' show mergeSort;
import 'package:flutter/services.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/printing/shaped_text/pdf_shaped_font.dart';
import 'package:otzaria/printing/shaped_text/shaped_text_layout.dart';
import 'package:otzaria/printing/shaped_text/shaped_text_widget.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';

enum CalendarPrintLayout { month, week, day }

CalendarPrintLayout resolveCalendarPrintLayout(CalendarView view) {
  return switch (view) {
    CalendarView.month => CalendarPrintLayout.month,
    CalendarView.week => CalendarPrintLayout.week,
    CalendarView.day => CalendarPrintLayout.day,
  };
}

List<String> _jewishEventsForDate(DateTime date, bool inIsrael) {
  final jc = JewishCalendar.fromDateTime(date)..inIsrael = inIsrael;
  final hdf = HebrewDateFormatter()..hebrewFormat = true;
  final List<String> result = [];

  final yomTov = hdf.formatYomTov(jc);
  if (yomTov.isNotEmpty) result.addAll(yomTov.split(',').map((e) => e.trim()));

  if (jc.isRoshChodesh() && !result.contains('ראש חודש')) result.add('ר"ח');

  if (jc.getDayOfWeek() == 7) {
    final parsha = hdf.formatParsha(jc);
    if (parsha.isNotEmpty) result.add(parsha);
  }

  return result;
}

List<CustomEvent> _eventsForDate(DateTime date, CalendarState state) {
  return state.events.where((event) => event.occursOn(date)).toList()
    ..sort(compareCalendarEventsByTime);
}

/// יוצר PDF של לוח השנה עם האירועים
Future<Uint8List> createCalendarPdf(
  CalendarState state,
  PdfPageFormat format, {
  int count = 1,
}) async {
  final primaryBytes = await _loadFont(
    'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf',
  );
  final fallbackBytes = await _loadFont('fonts/Tinos-Regular.ttf');
  final primaryShaper = ShaperFont.register(primaryBytes);
  final fallbackShaper = ShaperFont.register(fallbackBytes);
  try {
    final pdf = pw.Document();
    final font = _CalendarText([
      PdfShapedFont(
        pdf.document,
        shaper: primaryShaper,
        fontBytes: primaryBytes,
      ),
      PdfShapedFont(
        pdf.document,
        shaper: fallbackShaper,
        fontBytes: fallbackBytes,
      ),
    ]);

    switch (resolveCalendarPrintLayout(state.calendarView)) {
      case CalendarPrintLayout.month:
        await _addMonthPages(pdf, state, font, format, count);
      case CalendarPrintLayout.week:
        await _addWeekPages(pdf, state, font, format, count);
      case CalendarPrintLayout.day:
        await _addDayPages(pdf, state, font, format, count);
    }

    return await pdf.save();
  } finally {
    primaryShaper.dispose();
    fallbackShaper.dispose();
  }
}

Future<Uint8List> _loadFont(String path) async =>
    (await rootBundle.load(path)).buffer.asUint8List();

/// טקסט מעוצב (OpenType) — ניקוד, גרשיים וספרות יוצאים במקומם ובטקסט וקטורי.
class _CalendarText {
  _CalendarText(this.fonts);

  final List<PdfShapedFont> fonts;

  /// [singleLine] חותך לשורה אחת, כמו `maxLines: 1` בתאים הצרים.
  pw.Widget call(
    String text,
    double fontSize, {
    PdfColor color = PdfColors.black,
    ShapedTextAlign align = ShapedTextAlign.start,
    bool singleLine = false,
  }) {
    final widget = ShapedText(
      text,
      fonts: fonts,
      fontSize: fontSize,
      color: color,
      align: align,
    );
    if (!singleLine) return widget;
    final lineHeight = ShapedTextLayout(
      fonts: [for (final font in fonts) font.shaper],
      fontSize: fontSize,
    ).lineHeight;
    return pw.ConstrainedBox(
      constraints: pw.BoxConstraints(maxHeight: lineHeight),
      child: widget,
    );
  }
}

pw.Page _rtlPage(PdfPageFormat format, pw.Widget Function(pw.Context) build) =>
    pw.Page(
      pageFormat: format,
      textDirection: pw.TextDirection.rtl,
      build: build,
    );

Future<void> _addMonthPages(
  pw.Document pdf,
  CalendarState state,
  _CalendarText font,
  PdfPageFormat format,
  int count,
) async {
  for (int i = 0; i < count; i++) {
    final monthState = _getStateForMonthOffset(state, i);
    pdf.addPage(
      _rtlPage(
        format,
        (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 16),
              child: font(
                _getMonthYearText(monthState),
                24,
                align: ShapedTextAlign.center,
              ),
            ),
            pw.Expanded(child: _buildCalendarGrid(monthState, font)),
          ],
        ),
      ),
    );
  }
}

Future<void> _addWeekPages(
  pw.Document pdf,
  CalendarState state,
  _CalendarText font,
  PdfPageFormat format,
  int count,
) async {
  for (int i = 0; i < count; i++) {
    final weekState = _getStateForWeekOffset(state, i);
    pdf.addPage(
      _rtlPage(
        format,
        (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 16),
              child: font(
                _getWeekRangeText(weekState),
                18,
                align: ShapedTextAlign.center,
              ),
            ),
            _buildWeekGrid(weekState, font),
          ],
        ),
      ),
    );
  }
}

Future<void> _addDayPages(
  pw.Document pdf,
  CalendarState state,
  _CalendarText font,
  PdfPageFormat format,
  int count,
) async {
  for (int i = 0; i < count; i++) {
    final dayState = _getStateForDayOffset(state, i);
    final date = dayState.selectedGregorianDate;
    final jewishDate = JewishDate.fromDateTime(date);
    final events = _eventsForDate(date, dayState);

    // MultiPage: רשימת זמנים ארוכה ממשיכה לעמוד הבא; ב-Page היא חרגה והעמוד יצא ריק.
    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 16),
            child: font(
              _getDayText(date, jewishDate),
              20,
              align: ShapedTextAlign.center,
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 16),
            child: font(
              'עיר: ${dayState.selectedCity}',
              12,
              align: ShapedTextAlign.center,
            ),
          ),
          pw.Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (name, time) in calendarPrintedZmanim(dayState))
                pw.Container(
                  width: 150,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    children: [font(name, 9), font(time, 10)],
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 20),
          font('אירועים', 14),
          pw.SizedBox(height: 8),
          if (events.isEmpty)
            font('אין אירועים ליום זה', 11, color: PdfColors.grey700)
          else
            ...events.map(
              (event) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: font('• ${event.title}', 11),
              ),
            ),
        ],
      ),
    );
  }
}

/// הזמנים שהמסך מציג ליום — שהמשתמש הפעיל ושרלוונטיים לו — בשמם העברי.
@visibleForTesting
List<(String, String)> calendarPrintedZmanim(CalendarState state) {
  final jewishCalendar = JewishCalendar.fromDateTime(
    state.selectedGregorianDate,
  )..inIsrael = state.inIsrael;
  final zmanim = [
    for (final def in kZmanimRegistry)
      if (state.enabledZmanim.contains(def.id) &&
          (def.isRelevant?.call(jewishCalendar) ?? true))
        if (state.dailyTimes[def.id] case final time? when time.isNotEmpty)
          (id: def.id, name: def.fullName, time: time),
  ];
  // כמו במסך: שעות לפי הסדר הכרונולוגי, זמני תאריך אחריהן, וחצות לילה בסוף.
  int rank(({String id, String name, String time}) z) =>
      z.id == 'chatzosLayla' ? 2 : (isClockTime(z.time) ? 0 : 1);
  mergeSort(
    zmanim,
    compare: (a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0 || rank(a) != 0) return byRank;
      return a.time.compareTo(b.time);
    },
  );
  return [for (final z in zmanim) (z.name, z.time)];
}

CalendarState _getStateForDayOffset(CalendarState state, int offset) {
  if (offset == 0) return state;

  final newDate = addCalendarDays(state.selectedGregorianDate, offset);
  final newJewishDate = JewishDate.fromDateTime(newDate);
  return state.copyWith(
    selectedGregorianDate: newDate,
    selectedJewishDate: newJewishDate,
    currentGregorianDate: newDate,
    currentJewishDate: newJewishDate,
    dailyTimes: calculateDailyTimes(newDate, state.selectedCity),
  );
}

String _getDayText(DateTime date, JewishDate jewishDate) {
  return '${kHebrewDays[date.weekday % 7]} • '
      '${formatHebrewDay(jewishDate.getJewishDayOfMonth())} '
      '${getHebrewMonthNameFor(jewishDate)} '
      '${formatHebrewYear(jewishDate.getJewishYear())}\n'
      '${date.day}/${date.month}/${date.year}';
}

// ─── State helpers ─────────────────────────────────────────────────────────

CalendarState _getStateForMonthOffset(CalendarState state, int offset) {
  if (state.calendarType == CalendarType.gregorian) {
    final current = state.currentGregorianDate;
    final newDate = DateTime(current.year, current.month + offset, 1);
    return state.copyWith(
      currentGregorianDate: newDate,
      selectedGregorianDate: newDate,
      selectedJewishDate: JewishDate.fromDateTime(newDate),
      currentJewishDate: JewishDate.fromDateTime(newDate),
    );
  } else {
    JewishDate jewishDate = JewishDate();
    jewishDate.setJewishDate(
      state.currentJewishDate.getJewishYear(),
      state.currentJewishDate.getJewishMonth(),
      1,
    );
    for (int i = 0; i < offset; i++) {
      final daysInMonth = jewishDate.getDaysInJewishMonth();
      jewishDate.setJewishDate(
        jewishDate.getJewishYear(),
        jewishDate.getJewishMonth(),
        daysInMonth,
      );
      jewishDate.forward();
    }
    final gregorian = jewishDate.getGregorianCalendar();
    return state.copyWith(
      currentJewishDate: jewishDate,
      currentGregorianDate: gregorian,
      selectedGregorianDate: gregorian,
      selectedJewishDate: jewishDate,
    );
  }
}

CalendarState _getStateForWeekOffset(CalendarState state, int offset) {
  final weekStart = addCalendarDays(
    state.selectedGregorianDate,
    -(state.selectedGregorianDate.weekday % 7),
  );
  final newDate = addCalendarDays(weekStart, offset * 7);
  final newJewishDate = JewishDate.fromDateTime(newDate);
  return state.copyWith(
    selectedGregorianDate: newDate,
    selectedJewishDate: newJewishDate,
    currentGregorianDate: newDate,
    currentJewishDate: newJewishDate,
  );
}

// ─── Text helpers ──────────────────────────────────────────────────────────

String _getMonthYearText(CalendarState state) {
  if (state.calendarType == CalendarType.gregorian) {
    return '${getGregorianMonthName(state.currentGregorianDate.month)} ${state.currentGregorianDate.year}';
  }
  final monthName = getHebrewMonthNameFor(state.currentJewishDate);
  final yearStr = formatHebrewYear(state.currentJewishDate.getJewishYear());
  return '$monthName $yearStr';
}

String _getWeekRangeText(CalendarState state) {
  final startDate = addCalendarDays(
    state.selectedGregorianDate,
    -(state.selectedGregorianDate.weekday % 7),
  );
  final endDate = addCalendarDays(startDate, 6);
  final startJewish = JewishDate.fromDateTime(startDate);
  final endJewish = JewishDate.fromDateTime(endDate);

  final sameHebrewMonth =
      startJewish.getJewishMonth() == endJewish.getJewishMonth() &&
      startJewish.getJewishYear() == endJewish.getJewishYear();

  final hebrewRange = sameHebrewMonth
      ? '${formatHebrewDay(startJewish.getJewishDayOfMonth())}-${formatHebrewDay(endJewish.getJewishDayOfMonth())} '
            '${getHebrewMonthNameFor(startJewish)} '
            '${formatHebrewYear(startJewish.getJewishYear())}'
      : '${formatHebrewDay(startJewish.getJewishDayOfMonth())} ${getHebrewMonthNameFor(startJewish)} '
            '${formatHebrewYear(startJewish.getJewishYear())}'
            ' - '
            '${formatHebrewDay(endJewish.getJewishDayOfMonth())} ${getHebrewMonthNameFor(endJewish)} '
            '${formatHebrewYear(endJewish.getJewishYear())}';

  final gregorianRange =
      '${startDate.day}/${startDate.month}/${startDate.year} - ${endDate.day}/${endDate.month}/${endDate.year}';

  return '$hebrewRange • $gregorianRange';
}

// ─── Grid builders ─────────────────────────────────────────────────────────

pw.Widget _buildCalendarGrid(CalendarState state, _CalendarText font) {
  final days = kHebrewDays;

  if (state.calendarType == CalendarType.gregorian) {
    return _buildGregorianCalendarGrid(state, font, days);
  } else {
    return _buildHebrewCalendarGrid(state, font, days);
  }
}

pw.Widget _buildGregorianCalendarGrid(
  CalendarState state,
  _CalendarText font,
  List<String> days,
) {
  final current = state.currentGregorianDate;
  final firstDay = DateTime(current.year, current.month, 1);
  final daysInMonth = DateTime(current.year, current.month + 1, 0).day;
  final startingWeekday = firstDay.weekday % 7;

  List<pw.Widget> cells = [];
  for (int i = 0; i < startingWeekday; i++) {
    cells.add(pw.Container());
  }
  for (int day = 1; day <= daysInMonth; day++) {
    final date = DateTime(current.year, current.month, day);
    final jd = JewishDate.fromDateTime(date);
    final events = _eventsForDate(date, state);
    final jewishEvents = _jewishEventsForDate(date, state.inIsrael);
    cells.add(
      _buildDayCellPdf(
        '$day',
        formatHebrewDay(jd.getJewishDayOfMonth()),
        events,
        font,
        jewishEvents: jewishEvents,
      ),
    );
  }

  return _buildGridFromCells(cells, days, font);
}

pw.Widget _buildHebrewCalendarGrid(
  CalendarState state,
  _CalendarText font,
  List<String> days,
) {
  final currentJd = state.currentJewishDate;
  final daysInMonth = currentJd.getDaysInJewishMonth();
  final firstDay = JewishDate()
    ..setJewishDate(currentJd.getJewishYear(), currentJd.getJewishMonth(), 1);
  final startingWeekday = firstDay.getGregorianCalendar().weekday % 7;

  List<pw.Widget> cells = [];
  for (int i = 0; i < startingWeekday; i++) {
    cells.add(pw.Container());
  }
  for (int day = 1; day <= daysInMonth; day++) {
    final jd = JewishDate()
      ..setJewishDate(
        currentJd.getJewishYear(),
        currentJd.getJewishMonth(),
        day,
      );
    final date = jd.getGregorianCalendar();
    final events = _eventsForDate(date, state);
    final jewishEvents = _jewishEventsForDate(date, state.inIsrael);
    cells.add(
      _buildDayCellPdf(
        formatHebrewDay(day),
        '${date.day}',
        events,
        font,
        jewishEvents: jewishEvents,
      ),
    );
  }

  return _buildGridFromCells(cells, days, font);
}

pw.Widget _buildGridFromCells(
  List<pw.Widget> cells,
  List<String> days,
  _CalendarText font,
) {
  final totalCells = ((cells.length / 7).ceil()) * 7;
  while (cells.length < totalCells) {
    cells.add(pw.Container());
  }

  return pw.Column(
    children: [
      pw.Row(
        children: days
            .map(
              (day) => pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  alignment: pw.Alignment.center,
                  child: font(day, 10, align: ShapedTextAlign.center),
                ),
              ),
            )
            .toList(),
      ),
      pw.Divider(),
      // שורות בגובה קבוע גלשו מהעמוד לרוחב, ו-Column של pdf מוחק ילד שגלש.
      for (int i = 0; i < cells.length; i += 7)
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: cells
                .sublist(i, i + 7)
                .map((cell) => pw.Expanded(child: cell))
                .toList(),
          ),
        ),
    ],
  );
}

pw.Widget _buildDayCellPdf(
  String primaryLabel,
  String secondaryLabel,
  List<CustomEvent> events,
  _CalendarText font, {
  List<String> jewishEvents = const [],
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(4),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: font(secondaryLabel, 8, color: PdfColors.grey600),
            ),
            pw.Expanded(
              child: font(primaryLabel, 11, align: ShapedTextAlign.end),
            ),
          ],
        ),
        for (final je in jewishEvents) font(je, 7, singleLine: true),
        for (final event in events.take(2))
          font('• ${event.title}', 7, singleLine: true),
      ],
    ),
  );
}

pw.Widget _buildWeekGrid(CalendarState state, _CalendarText font) {
  final startDate = addCalendarDays(
    state.selectedGregorianDate,
    -(state.selectedGregorianDate.weekday % 7),
  );
  final days = List.generate(7, (i) => addCalendarDays(startDate, i));

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: days.map((date) {
      final jd = JewishDate.fromDateTime(date);
      final dailyTimes = calculateDailyTimes(date, state.selectedCity);
      final events = _eventsForDate(date, state);
      final jewishEvents = _jewishEventsForDate(date, state.inIsrael);
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              font(kHebrewDays[date.weekday % 7], 9),
              font(formatHebrewDay(jd.getJewishDayOfMonth()), 11),
              font('${date.day}/${date.month}', 8, color: PdfColors.grey600),
              pw.SizedBox(height: 4),
              for (final je in jewishEvents) font(je, 7, singleLine: true),
              if (jewishEvents.isNotEmpty) pw.SizedBox(height: 2),
              if (dailyTimes['sunrise'] case final sunrise?)
                font('זריחה $sunrise', 7, color: PdfColors.blue800),
              if (dailyTimes['sunset'] case final sunset?)
                font('שקיעה $sunset', 7, color: PdfColors.blue800),
              if (dailyTimes['sunrise'] != null || dailyTimes['sunset'] != null)
                pw.SizedBox(height: 4),
              for (final event in events.take(3))
                font('• ${event.title}', 7, singleLine: true),
            ],
          ),
        ),
      );
    }).toList(),
  );
}
