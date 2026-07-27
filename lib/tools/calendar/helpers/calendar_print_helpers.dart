import 'package:flutter/services.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
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
  final jewishDate = JewishDate.fromDateTime(date);
  final gregorianYear = date.year;
  final gregorianMonth = date.month;
  final gregorianDay = date.day;
  final hebrewYear = jewishDate.getJewishYear();
  final hebrewMonth = jewishDate.getJewishMonth();
  final hebrewDay = jewishDate.getJewishDayOfMonth();
  final gregorianWeekday = date.weekday;

  return state.events.where((event) {
    if (event.recurrenceType != RecurrenceType.none) {
      if (event.recurringYears != null && event.recurringYears! > 0) {
        final expired = switch (event.recurrenceType) {
          RecurrenceType.annualHebrew || RecurrenceType.monthlyHebrew =>
            hebrewYear >= event.baseJewishYear + event.recurringYears!,
          _ =>
            gregorianYear >=
                event.baseGregorianDate.year + event.recurringYears!,
        };
        if (expired) return false;
      }

      return switch (event.recurrenceType) {
        RecurrenceType.weekly =>
          event.baseGregorianDate.weekday == gregorianWeekday,
        RecurrenceType.monthlyHebrew => event.baseJewishDay == hebrewDay,
        RecurrenceType.monthlyGregorian =>
          event.baseGregorianDate.day == gregorianDay,
        RecurrenceType.annualHebrew =>
          event.baseJewishMonth == hebrewMonth &&
              event.baseJewishDay == hebrewDay,
        RecurrenceType.annualGregorian =>
          event.baseGregorianDate.month == gregorianMonth &&
              event.baseGregorianDate.day == gregorianDay,
        RecurrenceType.none => false,
      };
    }

    // אירוע חד-פעמי — מוצג בכל יום שבטווח [התחלה, סיום]
    final start = DateTime(
      event.baseGregorianDate.year,
      event.baseGregorianDate.month,
      event.baseGregorianDate.day,
    );
    final end = event.endGregorianDate != null
        ? DateTime(
            event.endGregorianDate!.year,
            event.endGregorianDate!.month,
            event.endGregorianDate!.day,
          )
        : start;
    final current = DateTime(gregorianYear, gregorianMonth, gregorianDay);
    return !current.isBefore(start) && !current.isAfter(end);
  }).toList()..sort(compareCalendarEventsByTime);
}

/// יוצר PDF של לוח השנה עם האירועים
Future<Uint8List> createCalendarPdf(
  CalendarState state,
  PdfPageFormat format, {
  int count = 1,
}) async {
  final font = pw.Font.ttf(
    await rootBundle.load('fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf'),
  );
  final pdf = pw.Document();

  switch (resolveCalendarPrintLayout(state.calendarView)) {
    case CalendarPrintLayout.month:
      await _addMonthPages(pdf, state, font, format, count);
    case CalendarPrintLayout.week:
      await _addWeekPages(pdf, state, font, format, count);
    case CalendarPrintLayout.day:
      await _addDayPages(pdf, state, font, format, count);
  }

  return pdf.save();
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
  pw.Font font,
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
              child: pw.Text(
                _getMonthYearText(monthState),
                style: pw.TextStyle(
                  font: font,
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
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
  pw.Font font,
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
              child: pw.Text(
                _getWeekRangeText(weekState),
                style: pw.TextStyle(
                  font: font,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
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
  pw.Font font,
  PdfPageFormat format,
  int count,
) async {
  for (int i = 0; i < count; i++) {
    final dayState = _getStateForDayOffset(state, i);
    final date = dayState.selectedGregorianDate;
    final jewishDate = JewishDate.fromDateTime(date);
    final events = _eventsForDate(date, dayState);

    pdf.addPage(
      _rtlPage(
        format,
        (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 16),
              child: pw.Text(
                _getDayText(date, jewishDate),
                style: pw.TextStyle(
                  font: font,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 16),
              child: pw.Text(
                'עיר: ${dayState.selectedCity}',
                style: pw.TextStyle(font: font, fontSize: 12),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in dayState.dailyTimes.entries)
                  pw.Container(
                    width: 150,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.5,
                      ),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          entry.value,
                          style: pw.TextStyle(
                            font: font,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: pw.Text(
                            entry.key,
                            style: pw.TextStyle(font: font, fontSize: 9),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'אירועים',
              style: pw.TextStyle(
                font: font,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.right,
            ),
            pw.SizedBox(height: 8),
            if (events.isEmpty)
              pw.Text(
                'אין אירועים ליום זה',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 11,
                  color: PdfColors.grey700,
                ),
                textAlign: pw.TextAlign.right,
              )
            else
              ...events.map(
                (event) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Text(
                    '• ${event.title}',
                    style: pw.TextStyle(font: font, fontSize: 11),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

CalendarState _getStateForDayOffset(CalendarState state, int offset) {
  if (offset == 0) return state;

  final newDate = state.selectedGregorianDate.add(Duration(days: offset));
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
  final weekStart = state.selectedGregorianDate.subtract(
    Duration(days: state.selectedGregorianDate.weekday % 7),
  );
  final newDate = weekStart.add(Duration(days: offset * 7));
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
  final startDate = state.selectedGregorianDate.subtract(
    Duration(days: state.selectedGregorianDate.weekday % 7),
  );
  final endDate = startDate.add(const Duration(days: 6));
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

pw.Widget _buildCalendarGrid(CalendarState state, pw.Font font) {
  final days = kHebrewDays;
  const cellHeight = 80.0;

  if (state.calendarType == CalendarType.gregorian) {
    return _buildGregorianCalendarGrid(state, font, days, cellHeight);
  } else {
    return _buildHebrewCalendarGrid(state, font, days, cellHeight);
  }
}

pw.Widget _buildGregorianCalendarGrid(
  CalendarState state,
  pw.Font font,
  List<String> days,
  double cellHeight,
) {
  final current = state.currentGregorianDate;
  final firstDay = DateTime(current.year, current.month, 1);
  final daysInMonth = DateTime(current.year, current.month + 1, 0).day;
  final startingWeekday = firstDay.weekday % 7;

  List<pw.Widget> cells = [];
  for (int i = 0; i < startingWeekday; i++) {
    cells.add(pw.Container(height: cellHeight));
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
        height: cellHeight,
        jewishEvents: jewishEvents,
      ),
    );
  }

  return _buildGridFromCells(cells, days, font);
}

pw.Widget _buildHebrewCalendarGrid(
  CalendarState state,
  pw.Font font,
  List<String> days,
  double cellHeight,
) {
  final currentJd = state.currentJewishDate;
  final daysInMonth = currentJd.getDaysInJewishMonth();
  final firstDay = JewishDate()
    ..setJewishDate(currentJd.getJewishYear(), currentJd.getJewishMonth(), 1);
  final startingWeekday = firstDay.getGregorianCalendar().weekday % 7;

  List<pw.Widget> cells = [];
  for (int i = 0; i < startingWeekday; i++) {
    cells.add(pw.Container(height: cellHeight));
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
        height: cellHeight,
        jewishEvents: jewishEvents,
      ),
    );
  }

  return _buildGridFromCells(cells, days, font);
}

pw.Widget _buildGridFromCells(
  List<pw.Widget> cells,
  List<String> days,
  pw.Font font,
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
                  child: pw.Text(
                    day,
                    style: pw.TextStyle(font: font, fontSize: 10),
                  ),
                ),
              ),
            )
            .toList(),
      ),
      pw.Divider(),
      for (int i = 0; i < cells.length; i += 7)
        pw.Row(
          children: cells
              .sublist(i, i + 7)
              .map((cell) => pw.Expanded(child: cell))
              .toList(),
        ),
    ],
  );
}

pw.Widget _buildDayCellPdf(
  String primaryLabel,
  String secondaryLabel,
  List<CustomEvent> events,
  pw.Font font, {
  double height = 80,
  List<String> jewishEvents = const [],
}) {
  return pw.Container(
    height: height,
    padding: const pw.EdgeInsets.all(4),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              secondaryLabel,
              style: pw.TextStyle(
                font: font,
                fontSize: 8,
                color: PdfColors.grey600,
              ),
            ),
            pw.Text(
              primaryLabel,
              style: pw.TextStyle(
                font: font,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        for (final je in jewishEvents)
          pw.Text(
            je,
            style: pw.TextStyle(font: font, fontSize: 7),
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            textAlign: pw.TextAlign.right,
          ),
        for (final event in events.take(2))
          pw.Text(
            '• ${event.title}',
            style: pw.TextStyle(font: font, fontSize: 7),
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
      ],
    ),
  );
}

pw.Widget _buildWeekGrid(CalendarState state, pw.Font font) {
  final startDate = state.selectedGregorianDate.subtract(
    Duration(days: state.selectedGregorianDate.weekday % 7),
  );
  final days = List.generate(7, (i) => startDate.add(Duration(days: i)));

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
              pw.Text(
                kHebrewDays[date.weekday % 7],
                style: pw.TextStyle(
                  font: font,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                formatHebrewDay(jd.getJewishDayOfMonth()),
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
              pw.Text(
                '${date.day}/${date.month}',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
              pw.SizedBox(height: 4),
              for (final je in jewishEvents)
                pw.Text(
                  je,
                  style: pw.TextStyle(font: font, fontSize: 7),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  textAlign: pw.TextAlign.right,
                ),
              if (jewishEvents.isNotEmpty) pw.SizedBox(height: 2),
              if (dailyTimes['sunrise'] case final sunrise?)
                pw.Text(
                  'זריחה $sunrise',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 7,
                    color: PdfColors.blue800,
                  ),
                ),
              if (dailyTimes['sunset'] case final sunset?)
                pw.Text(
                  'שקיעה $sunset',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 7,
                    color: PdfColors.blue800,
                  ),
                ),
              if (dailyTimes['sunrise'] != null || dailyTimes['sunset'] != null)
                pw.SizedBox(height: 4),
              for (final event in events.take(3))
                pw.Text(
                  '• ${event.title}',
                  style: pw.TextStyle(font: font, fontSize: 7),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
            ],
          ),
        ),
      );
    }).toList(),
  );
}
