import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/widgets/otzaria_search_field.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/view/panels/logic/calendar_events_panel_logic.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_date_formatters.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/dialogs.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SettingsCard(
        title: 'אירועים',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                RecommendedActionButton(
                  text: 'צור אירוע',
                  icon: FluentIcons.add_24_regular,
                  onPressed: () => widget.onCreateEvent(),
                ),
                if (widget.state.googleCalendarEnabled) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: widget.state.googleCalendarSyncInProgress
                        ? null
                        : () {
                            final cubit = context.read<CalendarCubit>();
                            if (widget.state.googleCalendarConnected) {
                              cubit.syncGoogleCalendar(interactive: true);
                            } else {
                              cubit.connectGoogleCalendar();
                            }
                          },
                    icon: widget.state.googleCalendarSyncInProgress
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            FluentIcons.arrow_sync_24_regular,
                            size: 16,
                          ),
                    label: Text(
                      widget.state.googleCalendarConnected
                          ? 'סנכרן Google'
                          : 'חבר ל-Google',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                const Spacer(),
                NeutralActionButton(
                  text:
                      widget.state.showAllEvents ? 'הצג יום נוכחי' : 'הצג הכל',
                  icon: widget.state.showAllEvents
                      ? FluentIcons.calendar_month_24_regular
                      : FluentIcons.calendar_day_24_regular,
                  onPressed: () => context
                      .read<CalendarCubit>()
                      .toggleShowAllEvents(!widget.state.showAllEvents),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: OtzariaSearchField(
                    controller: _searchController,
                    hintText: 'חפש אירועים...',
                    onChanged: (query) => context
                        .read<CalendarCubit>()
                        .setEventSearchQuery(query),
                    onClear: () =>
                        context.read<CalendarCubit>().setEventSearchQuery(''),
                  ),
                ),
                IconButton(
                  icon: Icon(widget.state.searchInDescriptions
                      ? FluentIcons.document_text_24_regular
                      : FluentIcons.text_t_24_regular),
                  tooltip: widget.state.searchInDescriptions
                      ? 'חפש רק בכותרת'
                      : 'חפש גם בתיאור',
                  onPressed: () => context
                      .read<CalendarCubit>()
                      .toggleSearchInDescriptions(
                          !widget.state.searchInDescriptions),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: _buildEventsList(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsList(BuildContext context) {
    final cubit = context.read<CalendarCubit>();
    final events = resolveVisibleCalendarEvents(widget.state, cubit);

    if (events.isEmpty) {
      return Center(child: Text(resolveEmptyEventsMessage(widget.state)));
    }

    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppTokens.radiusMD),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (event.googleEventId != null &&
                            event.googleEventId!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              FluentIcons.arrow_sync_24_regular,
                              size: 14,
                              color: scheme.primary,
                            ),
                          ),
                      ],
                    ),
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        truncateDescription(event.description),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: event.eventTime != null
                                ? scheme.primary.withValues(alpha: 0.2)
                                : scheme.secondary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                event.eventTime != null
                                    ? FluentIcons.clock_24_filled
                                    : FluentIcons.calendar_day_24_filled,
                                size: 10,
                                color: event.eventTime != null
                                    ? scheme.primary
                                    : scheme.secondary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                event.eventTime != null
                                    ? '${event.eventTime!.hour.toString().padLeft(2, '0')}:${event.eventTime!.minute.toString().padLeft(2, '0')}'
                                    : 'כל היום',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: event.eventTime != null
                                      ? scheme.primary
                                      : scheme.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            formatEventDate(event.baseGregorianDate),
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (event.recurring) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            FluentIcons.arrow_repeat_all_24_regular,
                            size: 12,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            getRecurrenceLabel(event.recurrenceType),
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(FluentIcons.edit_24_regular, size: 20),
                    tooltip: 'ערוך אירוע',
                    onPressed: () => widget.onCreateEvent(
                      existingEvent: event,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(FluentIcons.delete_24_regular, size: 20),
                    tooltip: 'מחק אירוע',
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
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
