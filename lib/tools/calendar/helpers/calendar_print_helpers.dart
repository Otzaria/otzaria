import 'package:flutter/services.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:otzaria/tools/calendar/bloc/calendar_state.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';

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

  switch (state.calendarView) {
    case CalendarView.month:
      await _addMonthPages(pdf, state, font, format, count);
    case CalendarView.week:
      await _addWeekPages(pdf, state, font, format, count);
    case CalendarView.day:
      await _addDayPages(pdf, state, font, format, count);
  }

  return pdf.save();
}

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
      pw.Page(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 16),
              child: pw.Text(
                _getMonthYearText(monthState),
                style: pw.TextStyle(
                    font: font, fontSize: 24, fontWeight: pw.FontWeight.bold),
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
      pw.Page(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 16),
              child: pw.Text(
                _getWeekRangeText(weekState),
                style: pw.TextStyle(
                    font: font, fontSize: 18, fontWeight: pw.FontWeight.bold),
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
    final dayDate = state.selectedGregorianDate.add(Duration(days: i));
    final dayState = _stateWithDate(state, dayDate);
    final times = calculateDailyTimes(dayDate, state.selectedCity);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              _getDayText(dayState),
              style: pw.TextStyle(
                  font: font, fontSize: 20, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 16),
            _buildTimesTable(times, font),
            pw.SizedBox(height: 16),
            _buildEventsList(dayState, font),
          ],
        ),
      ),
    );
  }
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
    jewishDate.setJewishDate(state.currentJewishDate.getJewishYear(),
        state.currentJewishDate.getJewishMonth(), 1);
    for (int i = 0; i < offset; i++) {
      final daysInMonth = jewishDate.getDaysInJewishMonth();
      jewishDate.setJewishDate(
          jewishDate.getJewishYear(), jewishDate.getJewishMonth(), daysInMonth);
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
  final newDate = state.selectedGregorianDate.add(Duration(days: offset * 7));
  return state.copyWith(
    selectedGregorianDate: newDate,
    selectedJewishDate: JewishDate.fromDateTime(newDate),
  );
}

CalendarState _stateWithDate(CalendarState state, DateTime date) {
  return state.copyWith(
    selectedGregorianDate: date,
    selectedJewishDate: JewishDate.fromDateTime(date),
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
  final startDate = state.selectedGregorianDate;
  final endDate = startDate.add(const Duration(days: 6));
  return '${startDate.day}/${startDate.month}/${startDate.year} - ${endDate.day}/${endDate.month}/${endDate.year}';
}

String _getDayText(CalendarState state) {
  final jd = state.selectedJewishDate;
  return '${kHebrewDays[state.selectedGregorianDate.weekday % 7]} ${formatHebrewDay(jd.getJewishDayOfMonth())} ${getHebrewMonthNameFor(jd)} ${formatHebrewYear(jd.getJewishYear())}';
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
    CalendarState state, pw.Font font, List<String> days, double cellHeight) {
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
    final events = state.events
        .where((e) =>
            e.baseGregorianDate.year == date.year &&
            e.baseGregorianDate.month == date.month &&
            e.baseGregorianDate.day == date.day)
        .toList();
    cells.add(_buildDayCellPdf(
        '$day', formatHebrewDay(jd.getJewishDayOfMonth()), events, font,
        height: cellHeight));
  }

  return _buildGridFromCells(cells, days, font);
}

pw.Widget _buildHebrewCalendarGrid(
    CalendarState state, pw.Font font, List<String> days, double cellHeight) {
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
          currentJd.getJewishYear(), currentJd.getJewishMonth(), day);
    final date = jd.getGregorianCalendar();
    final events = state.events
        .where((e) =>
            e.baseGregorianDate.year == date.year &&
            e.baseGregorianDate.month == date.month &&
            e.baseGregorianDate.day == date.day)
        .toList();
    cells.add(_buildDayCellPdf(
        formatHebrewDay(day), '${date.day}', events, font,
        height: cellHeight));
  }

  return _buildGridFromCells(cells, days, font);
}

pw.Widget _buildGridFromCells(
    List<pw.Widget> cells, List<String> days, pw.Font font) {
  final totalCells = ((cells.length / 7).ceil()) * 7;
  while (cells.length < totalCells) {
    cells.add(pw.Container());
  }

  return pw.Column(
    children: [
      pw.Row(
        children: days
            .map((day) => pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    alignment: pw.Alignment.center,
                    child: pw.Text(day,
                        style: pw.TextStyle(font: font, fontSize: 10)),
                  ),
                ))
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

pw.Widget _buildDayCellPdf(String primaryLabel, String secondaryLabel,
    List<CustomEvent> events, pw.Font font,
    {double height = 80}) {
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
            pw.Text(secondaryLabel,
                style: pw.TextStyle(
                    font: font, fontSize: 8, color: PdfColors.grey600)),
            pw.Text(primaryLabel,
                style: pw.TextStyle(
                    font: font, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        for (final event in events.take(2))
          pw.Text('• ${event.title}',
              style: pw.TextStyle(font: font, fontSize: 7),
              maxLines: 1,
              overflow: pw.TextOverflow.clip),
      ],
    ),
  );
}

pw.Widget _buildWeekGrid(CalendarState state, pw.Font font) {
  final startDate = state.selectedGregorianDate;
  final days = List.generate(7, (i) => startDate.add(Duration(days: i)));

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: days.map((date) {
      final jd = JewishDate.fromDateTime(date);
      final events = state.events
          .where((e) =>
              e.baseGregorianDate.year == date.year &&
              e.baseGregorianDate.month == date.month &&
              e.baseGregorianDate.day == date.day)
          .toList();
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(kHebrewDays[date.weekday % 7],
                  style: pw.TextStyle(
                      font: font, fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text(formatHebrewDay(jd.getJewishDayOfMonth()),
                  style: pw.TextStyle(font: font, fontSize: 11)),
              pw.Text('${date.day}/${date.month}',
                  style: pw.TextStyle(
                      font: font, fontSize: 8, color: PdfColors.grey600)),
              pw.SizedBox(height: 4),
              for (final event in events.take(3))
                pw.Text('• ${event.title}',
                    style: pw.TextStyle(font: font, fontSize: 7),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip),
            ],
          ),
        ),
      );
    }).toList(),
  );
}

pw.Widget _buildTimesTable(Map<String, String> times, pw.Font font) {
  final timeEntries = times.entries.toList();
  return pw.GridView(
    crossAxisCount: 2,
    childAspectRatio: 3,
    children: timeEntries.map((entry) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey200, width: 0.5),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(entry.value,
                style: pw.TextStyle(
                    font: font, fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.Text(entry.key, style: pw.TextStyle(font: font, fontSize: 8)),
          ],
        ),
      );
    }).toList(),
  );
}

pw.Widget _buildEventsList(CalendarState state, pw.Font font) {
  final date = state.selectedGregorianDate;
  final events = state.events
      .where((e) =>
          e.baseGregorianDate.year == date.year &&
          e.baseGregorianDate.month == date.month &&
          e.baseGregorianDate.day == date.day)
      .toList();
  if (events.isEmpty) return pw.SizedBox();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Text('אירועים:',
          style: pw.TextStyle(
              font: font, fontSize: 12, fontWeight: pw.FontWeight.bold)),
      for (final event in events)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Text('• ${event.title}',
              style: pw.TextStyle(font: font, fontSize: 10)),
        ),
    ],
  );
}
