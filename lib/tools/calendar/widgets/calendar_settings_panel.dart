import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';

/// קישור תוכן פאנל ההגדרות.
class CalendarSettingsPanel extends StatelessWidget {
  const CalendarSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: context.read<CalendarCubit>(),
      child: const SingleChildScrollView(
        child: CalendarSettingsTab(),
      ),
    );
  }
}
