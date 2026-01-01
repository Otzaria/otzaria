import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/resizable_drag_handle.dart';

/// Widget שמאפשר שינוי גודל של אזור סינון התוצאות
/// ושומר את הגודל בהגדרות המשתמש
class ResizableFacetFiltering extends StatefulWidget {
  final SearchingTab tab;
  final double minWidth;
  final double maxWidth;

  const ResizableFacetFiltering({
    super.key,
    required this.tab,
    this.minWidth = 150,
    this.maxWidth = 500,
  });

  @override
  State<ResizableFacetFiltering> createState() =>
      _ResizableFacetFilteringState();
}

class _ResizableFacetFilteringState extends State<ResizableFacetFiltering> {
  late double _currentWidth;

  @override
  void initState() {
    super.initState();
    // טעינת הרוחב מההגדרות
    final settingsState = context.read<SettingsBloc>().state;
    _currentWidth = settingsState.facetFilteringWidth;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      listener: (context, state) {
        // עדכון הרוחב כאשר ההגדרות משתנות מבחוץ
        if (state.facetFilteringWidth != _currentWidth) {
          setState(() {
            _currentWidth = state.facetFilteringWidth;
          });
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // אזור הסינון עצמו
          SizedBox(
            width: _currentWidth,
            child: SearchFacetFiltering(tab: widget.tab),
          ),
          // הידית לשינוי גודל
          ResizableDragHandle(
            isVertical: true,
            cursor: SystemMouseCursors.resizeLeftRight,
            onDragStart: null,
            onDragDelta: (delta) {
              setState(() {
                // עדכון הרוחב בהתאם לתנועת העכבר
                // delta חיובי = ימינה, שלילי = שמאלה
                _currentWidth = (_currentWidth - delta)
                    .clamp(widget.minWidth, widget.maxWidth);
              });
            },
            onDragEnd: () {
              context
                  .read<SettingsBloc>()
                  .add(UpdateFacetFilteringWidth(_currentWidth));
            },
          ),
        ],
      ),
    );
  }
}
