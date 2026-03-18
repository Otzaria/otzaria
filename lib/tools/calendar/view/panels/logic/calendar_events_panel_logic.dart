import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';

List<CustomEvent> resolveVisibleCalendarEvents(
  CalendarState state,
  CalendarCubit cubit,
) {
  if (state.eventSearchQuery.isNotEmpty) {
    return cubit.getFilteredEvents(state.eventSearchQuery);
  }

  if (state.showAllEvents) {
    final events = List<CustomEvent>.from(state.events);
    events.sort((a, b) => a.baseGregorianDate.compareTo(b.baseGregorianDate));
    return events;
  }

  return cubit.eventsForDate(state.selectedGregorianDate);
}

String resolveEmptyEventsMessage(CalendarState state) {
  if (state.eventSearchQuery.isNotEmpty) {
    return 'לא נמצאו אירועים מתאימים';
  }
  if (state.showAllEvents) {
    return 'אין אירועים במערכת';
  }
  return 'אין אירועים ביום זה';
}
