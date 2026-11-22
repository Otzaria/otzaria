import 'package:flutter/widgets.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';

/// קישור otzaria://detection: ממלא את שדה האיתור ומריץ, או מנקה כשהשאילתה
/// ריקה. דיאלוג שכבר פתוח נשאר פתוח ומציג את השאילתה החדשה.
void runDetectionDeepLink(
  String query, {
  required TextEditingController controller,
  required FindRefBloc bloc,
  void Function({required bool closeIfOpen})? openDialog,
}) {
  controller.text = query;
  controller.selection = TextSelection.collapsed(offset: query.length);
  if (query.isEmpty) {
    // קודם מבטלים חיפוש שעדיין רץ, ורק אז מחזירים ל-Initial.
    bloc.add(const SearchRefRequested(''));
    bloc.add(ClearSearchRequested());
  } else {
    bloc.add(SearchRefRequested(query));
  }
  openDialog?.call(closeIfOpen: false);
}
