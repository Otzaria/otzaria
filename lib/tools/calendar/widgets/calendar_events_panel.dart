import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// פאנל האירועים של לוח השנה.
class CalendarEventsPanel extends StatefulWidget {
  final CalendarState state;
  final void Function({CustomEvent? existingEvent, DateTime? specificDate})
  onCreateEvent;

  const CalendarEventsPanel({
    super.key,
    required this.state,
    required this.onCreateEvent,
  });

  @override
  State<CalendarEventsPanel> createState() => _CalendarEventsPanelState();
}

class _CalendarEventsPanelState extends State<CalendarEventsPanel> {
  final TextEditingController _searchController = TextEditingController();

  List<CustomEvent> _resolveVisibleCalendarEvents(
    CalendarState state,
    CalendarCubit cubit,
  ) {
    if (state.eventSearchQuery.isNotEmpty) {
      return cubit.getFilteredEvents(state.eventSearchQuery);
    }

    if (state.showAllEvents) {
      final events = List<CustomEvent>.from(state.events);
      events.sort(compareCalendarEventsChronologically);
      return events;
    }

    return cubit.eventsForDate(state.selectedGregorianDate);
  }

  String _resolveEmptyEventsMessage(CalendarState state) {
    if (state.eventSearchQuery.isNotEmpty) {
      return 'לא נמצאו אירועים מתאימים';
    }
    if (state.showAllEvents) {
      return 'אין אירועים במערכת';
    }
    return 'אין אירועים ביום זה';
  }

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.state.eventSearchQuery;
  }

  @override
  void didUpdateWidget(covariant CalendarEventsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_searchController.text != widget.state.eventSearchQuery) {
      _searchController.text = widget.state.eventSearchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.only(top: 8, bottom: 8, end: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OtzariaSearchField(
                  controller: _searchController,
                  hintText: 'חפש אירועים...',
                  onChanged: (query) =>
                      context.read<CalendarCubit>().setEventSearchQuery(query),
                  onClear: () =>
                      context.read<CalendarCubit>().setEventSearchQuery(''),
                ),
              ),
              const SizedBox(width: 8),
              BarButton.icon(
                tooltip: widget.state.searchInDescriptions
                    ? 'חפש רק בכותרת'
                    : 'חפש גם בתיאור',
                icon: widget.state.searchInDescriptions
                    ? OtzariaIcons.search_in_text_24_regular
                    : OtzariaIcons.search_in_document_24_regular,
                onPressed: () =>
                    context.read<CalendarCubit>().toggleSearchInDescriptions(
                      !widget.state.searchInDescriptions,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ActionButton.recommended(
                text: 'צור אירוע',
                icon: FluentIcons.add_24_regular,
                onPressed: () => widget.onCreateEvent(),
              ),
              if (widget.state.googleCalendarEnabled)
                BarButton.icon(
                  tooltip: widget.state.googleCalendarConnected
                      ? 'סנכרן Google'
                      : 'חבר ל-Google',
                  icon: FluentIcons.arrow_sync_24_regular,
                  selected: widget.state.googleCalendarSyncInProgress,
                  onPressed: widget.state.googleCalendarSyncInProgress
                      ? () {}
                      : () {
                          final cubit = context.read<CalendarCubit>();
                          if (widget.state.googleCalendarConnected) {
                            cubit.syncGoogleCalendar(interactive: true);
                          } else {
                            cubit.connectGoogleCalendar();
                          }
                        },
                ),
              ActionButton.neutral(
                text: widget.state.showAllEvents ? 'הצג יום נוכחי' : 'הצג הכל',
                icon: widget.state.showAllEvents
                    ? FluentIcons.calendar_month_24_regular
                    : FluentIcons.calendar_day_24_regular,
                onPressed: () => context
                    .read<CalendarCubit>()
                    .toggleShowAllEvents(!widget.state.showAllEvents),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildEventsList(context),
        ],
      ),
    );
  }

  Widget _buildEventsList(BuildContext context) {
    final cubit = context.read<CalendarCubit>();
    final events = _resolveVisibleCalendarEvents(widget.state, cubit);

    if (events.isEmpty) {
      return OtzariaEmptyState(
        isCompact: true,
        icon: OtzariaIcons.calendar_24_regular,
        title: _resolveEmptyEventsMessage(widget.state),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final event in events)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                const iconOnlyDeleteBelow = 560.0, splitDateBelow = 360.0;
                final iconOnlyDelete = width < iconOnlyDeleteBelow;
                final splitDate = width < splitDateBelow;
                final eventColor = CalendarEventColors.colorForIndex(
                  event.displayColorIndex,
                  Theme.of(context).brightness,
                );

                final deleteAction = _DeleteEventAction(
                  iconOnly: iconOnlyDelete,
                  onPressed: () async {
                    final confirmed = await showConfirmationDialog(
                      context: context,
                      title: 'אישור מחיקה',
                      content:
                          'האם אתה בטוח שברצונך למחוק את האירוע "${event.title}"?',
                      confirmText: 'מחק',
                      isDangerous: true,
                    );
                    if (confirmed == true && context.mounted) {
                      context.read<CalendarCubit>().deleteEvent(event.id);
                    }
                  },
                );

                final actionButtons = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BarButton.icon(
                      tooltip: 'ערוך אירוע',
                      icon: FluentIcons.edit_24_regular,
                      onPressed: () => widget.onCreateEvent(
                        existingEvent: event,
                      ),
                    ),
                    const SizedBox(width: 6),
                    deleteAction,
                  ],
                );

                final titleRow = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (eventColor != null)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: eventColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          Flexible(
                            child: Tooltip(
                              message: event.title,
                              child: Text(
                                event.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          if (event.googleEventId != null &&
                              event.googleEventId!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                FluentIcons.arrow_sync_24_regular,
                                size: AppTokens.iconXS,
                                color: scheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: AlignmentDirectional.topEnd,
                        child: _eventChip(
                          icon: event.eventTime != null
                              ? FluentIcons.clock_24_filled
                              : FluentIcons.calendar_day_24_filled,
                          text: event.eventTime != null
                              ? '${event.eventTime!.hour.toString().padLeft(2, '0')}:${event.eventTime!.minute.toString().padLeft(2, '0')}'
                              : 'כל היום',
                          tone: event.eventTime != null
                              ? MetaChipTone.primary
                              : MetaChipTone.neutral,
                        ),
                      ),
                    ),
                  ],
                );

                final content = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Tooltip(
                        message: event.description,
                        child: Text(
                          truncateDescription(event.description),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (event.recurring)
                          _eventChip(
                            icon: FluentIcons.arrow_repeat_all_24_regular,
                            text: getRecurrenceLabel(event.recurrenceType),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.bottomStart,
                            child: _eventChip(
                              icon: OtzariaIcons.calendar_24_regular,
                              text: splitDate
                                  ? formatEventDate(
                                      event.baseGregorianDate,
                                    ).replaceFirst(' • ', '\n')
                                  : formatEventDate(event.baseGregorianDate),
                              tooltip: formatEventDate(event.baseGregorianDate),
                              tone: MetaChipTone.primary,
                              maxLines: splitDate ? 2 : 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        actionButtons,
                      ],
                    ),
                  ],
                );

                return AppCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () => cubit.jumpToDate(
                    event.nextOccurrenceFrom(cubit.state.selectedGregorianDate),
                  ),
                  child: content,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _DeleteEventAction extends StatelessWidget {
  final bool iconOnly;
  final VoidCallback onPressed;

  const _DeleteEventAction({
    required this.iconOnly,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (iconOnly) {
      return BarButton.icon(
        tooltip: 'מחק אירוע',
        icon: FluentIcons.delete_24_regular,
        onPressed: onPressed,
      );
    }

    return ActionButton.neutral(
      text: 'מחק',
      onPressed: onPressed,
    );
  }
}

/// תגית מטא של אירוע; הריחוף מציג את הטקסט המלא גם כשהוא נחתך.
Widget _eventChip({
  required IconData icon,
  required String text,
  MetaChipTone tone = MetaChipTone.neutral,
  String? tooltip,
  int maxLines = 1,
}) => MetaChip(
  icon: icon,
  label: text,
  tone: tone,
  tooltip: tooltip ?? text,
  maxLines: maxLines,
);
