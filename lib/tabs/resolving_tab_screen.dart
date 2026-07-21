import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';

/// מסך טעינה של [ResolvingTab]: מציג מחוון בזמן שהיעד הסופי נפתר ברקע,
/// ועם סיום הרזולוציה מחליף את הטאב בו-במקום.
class ResolvingTabScreen extends StatefulWidget {
  final ResolvingTab tab;

  const ResolvingTabScreen({super.key, required this.tab});

  @override
  State<ResolvingTabScreen> createState() => _ResolvingTabScreenState();
}

class _ResolvingTabScreenState extends State<ResolvingTabScreen> {
  @override
  void initState() {
    super.initState();
    final tabsBloc = context.read<TabsBloc>();
    widget.tab.ensureResolved().then((resolved) {
      // ההחלפה נשלחת גם אם המסך כבר לא בעץ — הטאב עדיין ברשימה וממתין לה.
      // ה-resolved ממוזכר (memoized) ולכן אסור לסגור אותו אחרי dispatch קודם.
      if (widget.tab.replaceDispatched) return;
      if (tabsBloc.isClosed) {
        resolved.dispose();
        return;
      }
      widget.tab.replaceDispatched = true;
      tabsBloc.add(ReplaceTab(oldTab: widget.tab, newTab: resolved));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'פותח את ${widget.tab.title}...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
