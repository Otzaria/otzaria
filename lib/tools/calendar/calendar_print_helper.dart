import 'package:flutter/services.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'calendar_cubit.dart';

/// יוצר PDF של לוח השנה עם האירועים
/// תומך בהדפסת מספר חודשים/שבועות/ימים
Future<Uint8List> createCalendarPdf(
  CalendarState state,
  PdfPageFormat format, {
  int count = 1, // מספר התקופות להדפסה
}) async {
  final font = pw.Font.ttf(
    await rootBundle.load('fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf'),
  );

  final pdf = pw.Document();

  // יצירת עמודים לפי סוג התצוגה
  switch (state.calendarView) {
    case CalendarView.month:
      await _addMonthPages(pdf, state, font, format, count);
      break;
    case CalendarView.week:
      await _addWeekPages(pdf, state, font, format, count);
      break;
    case CalendarView.day:
      await _addDayPages(pdf, state, font, format, count);
      break;
  }

  return pdf.save();
}

/// מוסיף עמודי חודשים
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
        build: (context) {
          return pw.Column(
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
              pw.Expanded(
                child: _buildCalendarGrid(monthState, font),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// מוסיף עמודי שבועות
Future<void> _addWeekPages(
  pw.Document pdf,
  CalendarState state,
  pw.Font font,
  PdfPageFormat format,
  int count,
) async {
  for (int i = 0; i < count; i++) {
    final weekState = _getStateForWeekOffset(state, i);
    final weekDates = _getWeekDates(weekState);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 16),
                child: pw.Text(
                  _getWeekRangeText(weekDates),
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Expanded(
                child: _buildWeekGrid(weekDates, weekState, font),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// מוסיף עמודי ימים
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

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                child: pw.Text(
                  _getDayText(date, jewishDate),
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Expanded(
                child: _buildDayContent(date, dayState, font),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// בונה את רשת לוח השנה
pw.Widget _buildCalendarGrid(CalendarState state, pw.Font font) {
  final hebrewDays = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];

  final dayHeaders = pw.Row(
    children: hebrewDays.asMap().entries.map((entry) {
      final index = entry.key;
      final day = entry.value;
      final isShabbat = index == 6; // שבת

      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: pw.BoxDecoration(
            color: isShabbat ? PdfColors.blue50 : PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Text(
            day,
            style: pw.TextStyle(
              font: font,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: isShabbat ? PdfColors.blue800 : PdfColors.grey800,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
      );
    }).toList(),
  );

  final daysCells = _buildDaysCells(state, font);

  return pw.Column(
    children: [
      dayHeaders,
      pw.Expanded(
        child: pw.Column(
          children: daysCells,
        ),
      ),
    ],
  );
}

/// בונה רשת שבועית
pw.Widget _buildWeekGrid(
  List<DateTime> weekDates,
  CalendarState state,
  pw.Font font,
) {
  final hebrewDays = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];

  return pw.Column(
    children: [
      // כותרות ימים
      pw.Row(
        children: hebrewDays.asMap().entries.map((entry) {
          final index = entry.key;
          final day = entry.value;
          final isShabbat = index == 6;

          return pw.Expanded(
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: pw.BoxDecoration(
                color: isShabbat ? PdfColors.blue50 : PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              ),
              child: pw.Text(
                day,
                style: pw.TextStyle(
                  font: font,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: isShabbat ? PdfColors.blue800 : PdfColors.grey800,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
          );
        }).toList(),
      ),
      // תאי ימים
      pw.Expanded(
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: weekDates.map((date) {
            return pw.Expanded(
              child: _buildDayCell(date, state, font),
            );
          }).toList(),
        ),
      ),
    ],
  );
}

/// בונה תוכן יום בודד (לתצוגה יומית)
pw.Widget _buildDayContent(
  DateTime date,
  CalendarState state,
  pw.Font font,
) {
  final jewishCalendar = JewishCalendar.fromDateTime(date)
    ..inIsrael = state.inIsrael;
  final events = _getEventsForDate(date, state);
  final holidays = _getHolidaysForDate(jewishCalendar);

  return pw.Container(
    padding: const pw.EdgeInsets.all(16),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (holidays.isNotEmpty) ...[
          pw.Text(
            'מועדים וחגים:',
            style: pw.TextStyle(
              font: font,
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          ...holidays.map((holiday) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                '• $holiday',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 14,
                  color: PdfColors.red800,
                ),
              ),
            );
          }),
          pw.SizedBox(height: 16),
        ],
        if (events.isNotEmpty) ...[
          pw.Text(
            'אירועים:',
            style: pw.TextStyle(
              font: font,
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          ...events.map((event) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '• ${event.title}',
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                  if (event.description.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 12, top: 2),
                      child: pw.Text(
                        event.description,
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 12,
                          color: PdfColors.grey800,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
        if (holidays.isEmpty && events.isEmpty)
          pw.Center(
            child: pw.Text(
              'אין אירועים או מועדים ליום זה',
              style: pw.TextStyle(
                font: font,
                fontSize: 14,
                color: PdfColors.grey600,
              ),
            ),
          ),
      ],
    ),
  );
}

/// בונה את תאי הימים
List<pw.Widget> _buildDaysCells(CalendarState state, pw.Font font) {
  final List<pw.Widget> rows = [];
  final List<DateTime> dates = _getDatesForMonth(state);

  for (int i = 0; i < dates.length; i += 7) {
    final weekDates = dates.sublist(
      i,
      i + 7 > dates.length ? dates.length : i + 7,
    );

    rows.add(
      pw.Expanded(
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: weekDates.map((date) {
            return pw.Expanded(
              child: _buildDayCell(date, state, font),
            );
          }).toList(),
        ),
      ),
    );
  }

  return rows;
}

/// בונה תא יום בודד - עם עיצוב דומה לתוכנה
pw.Widget _buildDayCell(DateTime date, CalendarState state, pw.Font font) {
  final jewishDate = JewishDate.fromDateTime(date);
  final jewishCalendar = JewishCalendar.fromDateTime(date)
    ..inIsrael = state.inIsrael;

  final isCurrentMonth = date.month == state.currentGregorianDate.month;
  final isToday = date.day == DateTime.now().day &&
      date.month == DateTime.now().month &&
      date.year == DateTime.now().year;

  final events = _getEventsForDate(date, state);
  final holidays = _getHolidaysForDate(jewishCalendar);

  // צבעי רקע דומים לתוכנה
  final bgColor = isToday
      ? PdfColors.blue100
      : (jewishCalendar.getDayOfWeek() == 7 ||
              jewishCalendar.isYomTov() ||
              jewishCalendar.isRoshChodesh())
          ? PdfColors.grey50
          : PdfColors.white;

  // צבע גבול
  final borderColor = isToday
      ? PdfColors.blue600
      : (jewishCalendar.getDayOfWeek() == 7 ||
              jewishCalendar.isYomTov() ||
              jewishCalendar.isRoshChodesh())
          ? PdfColors.grey300
          : PdfColors.grey200;

  return pw.Container(
    margin: const pw.EdgeInsets.all(1), // מרווח קטן בין התאים
    decoration: pw.BoxDecoration(
      color: bgColor,
      borderRadius: pw.BorderRadius.circular(6), // פינות מעוגלות כמו בתוכנה
      border: pw.Border.all(
        color: borderColor,
        width: isToday ? 2 : 1,
      ),
    ),
    padding: const pw.EdgeInsets.all(6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // תאריכים - מיקום דומה לתוכנה
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // תאריך עברי (צד ימין)
            if (state.calendarType == CalendarType.hebrew ||
                state.calendarType == CalendarType.combined)
              pw.Text(
                _formatHebrewDay(jewishDate.getJewishDayOfMonth()),
                style: pw.TextStyle(
                  font: font,
                  fontSize:
                      state.calendarType == CalendarType.combined ? 11 : 13,
                  fontWeight: pw.FontWeight.bold,
                  color: isCurrentMonth
                      ? (isToday ? PdfColors.blue800 : PdfColors.black)
                      : PdfColors.grey500,
                ),
              ),
            // תאריך לועזי (צד שמאל או יחיד)
            if (state.calendarType == CalendarType.gregorian ||
                (state.calendarType == CalendarType.combined))
              pw.Text(
                '${date.day}',
                style: pw.TextStyle(
                  font: font,
                  fontSize:
                      state.calendarType == CalendarType.combined ? 9 : 13,
                  fontWeight: state.calendarType == CalendarType.combined
                      ? pw.FontWeight.normal
                      : pw.FontWeight.bold,
                  color: isCurrentMonth
                      ? (state.calendarType == CalendarType.combined
                          ? PdfColors.grey600
                          : (isToday ? PdfColors.blue800 : PdfColors.black))
                      : PdfColors.grey400,
                ),
              ),
          ],
        ),

        pw.SizedBox(height: 4),

        // מועדים - עם עיצוב משופר
        ...holidays.map((holiday) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 2),
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: pw.BoxDecoration(
              color: PdfColors.red50,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              holiday,
              style: pw.TextStyle(
                font: font,
                fontSize: 6,
                color: PdfColors.red700,
                fontWeight: pw.FontWeight.bold,
              ),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
          );
        }),

        // אירועים - עם עיצוב משופר
        ...events.map((event) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 2),
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              event.title,
              style: pw.TextStyle(
                font: font,
                fontSize: 6,
                color: PdfColors.blue700,
                fontWeight: pw.FontWeight.bold,
              ),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
          );
        }),
      ],
    ),
  );
}

// ===== פונקציות עזר לחישוב תאריכים =====

/// מחזיר state עבור חודש עם offset
CalendarState _getStateForMonthOffset(CalendarState state, int offset) {
  if (offset == 0) return state;

  if (state.calendarType == CalendarType.gregorian ||
      state.calendarType == CalendarType.combined) {
    final currentDate = state.currentGregorianDate;
    final newDate = DateTime(
      currentDate.year,
      currentDate.month + offset,
      1,
    );
    final newJewishDate = JewishDate.fromDateTime(newDate);

    return state.copyWith(
      currentGregorianDate: newDate,
      currentJewishDate: newJewishDate,
    );
  } else {
    final currentJewishDate = state.currentJewishDate;
    final newJewishDate = JewishDate();
    newJewishDate.setJewishDate(
      currentJewishDate.getJewishYear(),
      currentJewishDate.getJewishMonth(),
      1,
    );

    for (int i = 0; i < offset; i++) {
      newJewishDate.forward();
      final daysInMonth = newJewishDate.getDaysInJewishMonth();
      for (int j = 1; j < daysInMonth; j++) {
        newJewishDate.forward();
      }
    }

    return state.copyWith(
      currentJewishDate: newJewishDate,
      currentGregorianDate: newJewishDate.getGregorianCalendar(),
    );
  }
}

/// מחזיר state עבור שבוע עם offset
CalendarState _getStateForWeekOffset(CalendarState state, int offset) {
  if (offset == 0) return state;

  final currentDate = state.selectedGregorianDate;
  final newDate = currentDate.add(Duration(days: 7 * offset));
  final newJewishDate = JewishDate.fromDateTime(newDate);

  return state.copyWith(
    selectedGregorianDate: newDate,
    selectedJewishDate: newJewishDate,
  );
}

/// מחזיר state עבור יום עם offset
CalendarState _getStateForDayOffset(CalendarState state, int offset) {
  if (offset == 0) return state;

  final currentDate = state.selectedGregorianDate;
  final newDate = currentDate.add(Duration(days: offset));
  final newJewishDate = JewishDate.fromDateTime(newDate);

  return state.copyWith(
    selectedGregorianDate: newDate,
    selectedJewishDate: newJewishDate,
  );
}

/// מחזיר רשימת תאריכים לשבוע
List<DateTime> _getWeekDates(CalendarState state) {
  final selectedDate = state.selectedGregorianDate;
  final startOfWeek =
      selectedDate.subtract(Duration(days: selectedDate.weekday % 7));

  return List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
}

/// מחזיר אירועים לתאריך מסוים
List<CustomEvent> _getEventsForDate(DateTime date, CalendarState state) {
  final jd = JewishDate.fromDateTime(date);
  final gY = date.year, gM = date.month, gD = date.day;
  final hY = jd.getJewishYear(),
      hM = jd.getJewishMonth(),
      hD = jd.getJewishDayOfMonth();
  final gWeekday = date.weekday;

  return state.events.where((e) {
    if (e.recurrenceType != RecurrenceType.none) {
      if (e.recurringYears != null && e.recurringYears! > 0) {
        bool expired = false;
        if (e.recurrenceType == RecurrenceType.annualHebrew ||
            e.recurrenceType == RecurrenceType.monthlyHebrew) {
          if (hY >= e.baseJewishYear + e.recurringYears!) {
            expired = true;
          }
        } else {
          if (gY >= e.baseGregorianDate.year + e.recurringYears!) {
            expired = true;
          }
        }
        if (expired) return false;
      }

      switch (e.recurrenceType) {
        case RecurrenceType.weekly:
          return e.baseGregorianDate.weekday == gWeekday;
        case RecurrenceType.monthlyHebrew:
          return e.baseJewishDay == hD;
        case RecurrenceType.monthlyGregorian:
          return e.baseGregorianDate.day == gD;
        case RecurrenceType.annualHebrew:
          return e.baseJewishMonth == hM && e.baseJewishDay == hD;
        case RecurrenceType.annualGregorian:
          return e.baseGregorianDate.month == gM &&
              e.baseGregorianDate.day == gD;
        case RecurrenceType.none:
          return false;
      }
    } else {
      return e.baseGregorianDate.year == gY &&
          e.baseGregorianDate.month == gM &&
          e.baseGregorianDate.day == gD;
    }
  }).toList()
    ..sort((a, b) => a.title.compareTo(b.title));
}

/// מחזיר רשימת תאריכים לחודש
List<DateTime> _getDatesForMonth(CalendarState state) {
  final List<DateTime> dates = [];

  if (state.calendarType == CalendarType.gregorian ||
      state.calendarType == CalendarType.combined) {
    final currentDate = state.currentGregorianDate;
    final firstDayOfMonth = DateTime(currentDate.year, currentDate.month, 1);
    final lastDayOfMonth = DateTime(currentDate.year, currentDate.month + 1, 0);
    final startingWeekday = firstDayOfMonth.weekday % 7;

    if (startingWeekday > 0) {
      final previousMonthLastDay =
          DateTime(currentDate.year, currentDate.month, 0);
      for (int i = startingWeekday - 1; i >= 0; i--) {
        dates.add(previousMonthLastDay.subtract(Duration(days: i)));
      }
    }

    for (int day = 1; day <= lastDayOfMonth.day; day++) {
      dates.add(DateTime(currentDate.year, currentDate.month, day));
    }

    final totalCells = ((dates.length / 7).ceil()) * 7;
    final remainingCells = totalCells - dates.length;
    for (int day = 1; day <= remainingCells; day++) {
      dates.add(DateTime(currentDate.year, currentDate.month + 1, day));
    }
  } else {
    final currentJewishDate = state.currentJewishDate;
    final daysInMonth = currentJewishDate.getDaysInJewishMonth();
    final firstDayOfMonth = JewishDate();
    firstDayOfMonth.setJewishDate(
      currentJewishDate.getJewishYear(),
      currentJewishDate.getJewishMonth(),
      1,
    );
    final startingWeekday = firstDayOfMonth.getGregorianCalendar().weekday % 7;

    if (startingWeekday > 0) {
      final previousMonth = JewishDate();
      previousMonth.setJewishDate(
        currentJewishDate.getJewishYear(),
        currentJewishDate.getJewishMonth(),
        1,
      );
      previousMonth.back();
      final daysInPreviousMonth = previousMonth.getDaysInJewishMonth();

      for (int i = startingWeekday - 1; i >= 0; i--) {
        final day = daysInPreviousMonth - i;
        final jewishDate = JewishDate();
        jewishDate.setJewishDate(
          previousMonth.getJewishYear(),
          previousMonth.getJewishMonth(),
          day,
        );
        dates.add(jewishDate.getGregorianCalendar());
      }
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final jewishDate = JewishDate();
      jewishDate.setJewishDate(
        currentJewishDate.getJewishYear(),
        currentJewishDate.getJewishMonth(),
        day,
      );
      dates.add(jewishDate.getGregorianCalendar());
    }

    final totalCells = ((dates.length / 7).ceil()) * 7;
    final remainingCells = totalCells - dates.length;
    for (int day = 1; day <= remainingCells; day++) {
      final nextMonth = JewishDate();
      nextMonth.setJewishDate(
        currentJewishDate.getJewishYear(),
        currentJewishDate.getJewishMonth(),
        1,
      );
      nextMonth.forward();
      final jewishDate = JewishDate();
      jewishDate.setJewishDate(
        nextMonth.getJewishYear(),
        nextMonth.getJewishMonth(),
        day,
      );
      dates.add(jewishDate.getGregorianCalendar());
    }
  }

  return dates;
}

/// מחזיר רשימת מועדים לתאריך
List<String> _getHolidaysForDate(JewishCalendar jewishCalendar) {
  final List<String> holidays = [];

  if (jewishCalendar.isRoshChodesh()) {
    holidays.add('ראש חודש');
  }

  final yomTovIndex = jewishCalendar.getYomTovIndex();
  if (yomTovIndex != -1) {
    final holidayName = _getHolidayName(yomTovIndex);
    if (holidayName.isNotEmpty) {
      holidays.add(holidayName);
    }
  }

  if (jewishCalendar.isTaanis() && yomTovIndex != JewishCalendar.YOM_KIPPUR) {
    if (!holidays.any((h) => h.contains('תענית'))) {
      holidays.add('תענית');
    }
  }

  return holidays;
}

/// מחזיר שם חג
String _getHolidayName(int yomTovIndex) {
  switch (yomTovIndex) {
    case JewishCalendar.EREV_PESACH:
      return 'ערב פסח';
    case JewishCalendar.PESACH:
      return 'פסח';
    case JewishCalendar.CHOL_HAMOED_PESACH:
      return 'חול המועד פסח';
    case JewishCalendar.PESACH_SHENI:
      return 'פסח שני';
    case JewishCalendar.EREV_SHAVUOS:
      return 'ערב שבועות';
    case JewishCalendar.SHAVUOS:
      return 'שבועות';
    case JewishCalendar.SEVENTEEN_OF_TAMMUZ:
      return 'י"ז בתמוז';
    case JewishCalendar.TISHA_BEAV:
      return 'תשעה באב';
    case JewishCalendar.TU_BEAV:
      return 'ט"ו באב';
    case JewishCalendar.EREV_ROSH_HASHANA:
      return 'ערב ראש השנה';
    case JewishCalendar.ROSH_HASHANA:
      return 'ראש השנה';
    case JewishCalendar.FAST_OF_GEDALYAH:
      return 'צום גדליה';
    case JewishCalendar.EREV_YOM_KIPPUR:
      return 'ערב יום כיפור';
    case JewishCalendar.YOM_KIPPUR:
      return 'יום כיפור';
    case JewishCalendar.EREV_SUCCOS:
      return 'ערב סוכות';
    case JewishCalendar.SUCCOS:
      return 'סוכות';
    case JewishCalendar.CHOL_HAMOED_SUCCOS:
      return 'חול המועד סוכות';
    case JewishCalendar.HOSHANA_RABBA:
      return 'הושענא רבה';
    case JewishCalendar.SHEMINI_ATZERES:
      return 'שמיני עצרת';
    case JewishCalendar.SIMCHAS_TORAH:
      return 'שמחת תורה';
    case JewishCalendar.CHANUKAH:
      return 'חנוכה';
    case JewishCalendar.TENTH_OF_TEVES:
      return 'עשרה בטבת';
    case JewishCalendar.TU_BESHVAT:
      return 'ט"ו בשבט';
    case JewishCalendar.FAST_OF_ESTHER:
      return 'תענית אסתר';
    case JewishCalendar.PURIM:
      return 'פורים';
    case JewishCalendar.SHUSHAN_PURIM:
      return 'שושן פורים';
    case JewishCalendar.PURIM_KATAN:
      return 'פורים קטן';
    case JewishCalendar.ROSH_CHODESH:
      return 'ראש חודש';
    case JewishCalendar.YOM_HASHOAH:
      return 'יום השואה';
    case JewishCalendar.YOM_HAZIKARON:
      return 'יום הזיכרון';
    case JewishCalendar.YOM_HAATZMAUT:
      return 'יום העצמאות';
    case JewishCalendar.YOM_YERUSHALAYIM:
      return 'יום ירושלים';
    default:
      return '';
  }
}

// ===== פונקציות עיצוב טקסט =====

String _formatHebrewDay(int day) {
  return _numberToHebrewWithoutQuotes(day);
}

String _numberToHebrewWithoutQuotes(int number) {
  if (number <= 0) return '';
  String result = '';
  int num = number;
  if (num >= 100) {
    int hundreds = (num ~/ 100) * 100;
    if (hundreds == 900) {
      result += 'תתק';
    } else if (hundreds == 800) {
      result += 'תת';
    } else if (hundreds == 700) {
      result += 'תש';
    } else if (hundreds == 600) {
      result += 'תר';
    } else if (hundreds == 500) {
      result += 'תק';
    } else if (hundreds == 400) {
      result += 'ת';
    } else if (hundreds == 300) {
      result += 'ש';
    } else if (hundreds == 200) {
      result += 'ר';
    } else if (hundreds == 100) {
      result += 'ק';
    }
    num %= 100;
  }
  const ones = ['', 'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט'];
  const tens = ['', 'י', 'כ', 'ל', 'מ', 'נ', 'ס', 'ע', 'פ', 'צ'];
  if (num == 15) {
    result += 'טו';
  } else if (num == 16) {
    result += 'טז';
  } else {
    if (num >= 10) {
      result += tens[num ~/ 10];
      num %= 10;
    }
    if (num > 0) {
      result += ones[num];
    }
  }
  return result;
}

String _getMonthYearText(CalendarState state) {
  final hebrewMonths = [
    'ניסן',
    'אייר',
    'סיון',
    'תמוז',
    'אב',
    'אלול',
    'תשרי',
    'חשון',
    'כסלו',
    'טבת',
    'שבט',
    'אדר'
  ];

  final gregorianMonths = [
    'ינואר',
    'פברואר',
    'מרץ',
    'אפריל',
    'מאי',
    'יוני',
    'יולי',
    'אוגוסט',
    'ספטמבר',
    'אוקטובר',
    'נובמבר',
    'דצמבר'
  ];

  final jewishDate = state.currentJewishDate;
  final gregorianDate = state.currentGregorianDate;

  final hebMonth = _getHebrewMonthName(jewishDate, hebrewMonths);
  final hebYear = _formatHebrewYear(jewishDate.getJewishYear());
  final gregMonth = gregorianMonths[gregorianDate.month - 1];
  final gregYear = gregorianDate.year;

  return '$hebMonth $hebYear • $gregMonth $gregYear';
}

String _getWeekRangeText(List<DateTime> weekDates) {
  if (weekDates.isEmpty) return '';

  final firstDate = weekDates.first;
  final lastDate = weekDates.last;
  final firstJewish = JewishDate.fromDateTime(firstDate);
  final lastJewish = JewishDate.fromDateTime(lastDate);

  final hebrewMonths = [
    'ניסן',
    'אייר',
    'סיון',
    'תמוז',
    'אב',
    'אלול',
    'תשרי',
    'חשון',
    'כסלו',
    'טבת',
    'שבט',
    'אדר'
  ];

  final firstHebMonth = _getHebrewMonthName(firstJewish, hebrewMonths);
  final lastHebMonth = _getHebrewMonthName(lastJewish, hebrewMonths);

  return '${_formatHebrewDay(firstJewish.getJewishDayOfMonth())} $firstHebMonth - '
      '${_formatHebrewDay(lastJewish.getJewishDayOfMonth())} $lastHebMonth '
      '${_formatHebrewYear(lastJewish.getJewishYear())} • '
      '${firstDate.day}/${firstDate.month} - ${lastDate.day}/${lastDate.month}/${lastDate.year}';
}

String _getDayText(DateTime date, JewishDate jewishDate) {
  final hebrewDays = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
  final hebrewMonths = [
    'ניסן',
    'אייר',
    'סיון',
    'תמוז',
    'אב',
    'אלול',
    'תשרי',
    'חשון',
    'כסלו',
    'טבת',
    'שבט',
    'אדר'
  ];
  final gregorianMonths = [
    'ינואר',
    'פברואר',
    'מרץ',
    'אפריל',
    'מאי',
    'יוני',
    'יולי',
    'אוגוסט',
    'ספטמבר',
    'אוקטובר',
    'נובמבר',
    'דצמבר'
  ];

  final dayOfWeek = hebrewDays[date.weekday % 7];
  final hebMonth = _getHebrewMonthName(jewishDate, hebrewMonths);
  final hebYear = _formatHebrewYear(jewishDate.getJewishYear());
  final gregMonth = gregorianMonths[date.month - 1];

  return '$dayOfWeek, ${_formatHebrewDay(jewishDate.getJewishDayOfMonth())} $hebMonth $hebYear\n'
      '${date.day} $gregMonth ${date.year}';
}

String _getHebrewMonthName(JewishDate jewishDate, List<String> hebrewMonths) {
  final int m = jewishDate.getJewishMonth();
  final bool leap = jewishDate.isJewishLeapYear();
  if (leap && m == 12) return 'אדר א׳';
  if (leap && m == 13) return 'אדר ב׳';
  final int idx = (m - 1).clamp(0, hebrewMonths.length - 1);
  return hebrewMonths[idx];
}

String _formatHebrewYear(int year) {
  final thousands = year ~/ 1000;
  final remainder = year % 1000;

  String remainderStr = _numberToHebrewWithoutQuotes(remainder);

  String formattedRemainder;
  if (remainderStr.length > 1) {
    formattedRemainder =
        '${remainderStr.substring(0, remainderStr.length - 1)}״${remainderStr.substring(remainderStr.length - 1)}';
  } else if (remainderStr.length == 1) {
    formattedRemainder = '$remainderStr׳';
  } else {
    formattedRemainder = remainderStr;
  }

  if (thousands == 5) {
    return 'ה׳$formattedRemainder';
  }

  return formattedRemainder;
}
