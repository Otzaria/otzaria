import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';

/// חזרת המערכת חלה רק על חלונית ה-PDF הפעילה ושומרת את מסך הקריאה בנוי.
class PdfNavigationBackScope extends StatelessWidget {
  const PdfNavigationBackScope({
    required this.bloc,
    required this.onBack,
    required this.child,
    super.key,
  });

  final PdfBookBloc bloc;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocSelector<TabsBloc, TabsState, bool>(
    selector: (state) => identical(state.activePane, bloc.tab),
    builder: (context, active) => BlocSelector<PdfBookBloc, PdfBookState, bool>(
      bloc: bloc,
      selector: (state) => state is PdfBookLoaded,
      builder: (context, loaded) => ListenableBuilder(
        listenable: bloc.tab.navigationHistory,
        child: child,
        builder: (context, child) {
          final handlesBack =
              active && loaded && bloc.tab.navigationHistory.canGoBack;
          return PopScope(
            canPop: !handlesBack,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && handlesBack) onBack();
            },
            child: child!,
          );
        },
      ),
    ),
  );
}
