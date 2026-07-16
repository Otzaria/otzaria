import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

abstract class HistoryEvent {}

class LoadHistory extends HistoryEvent {}

class SetCurrentWorkspaceName extends HistoryEvent {
  final String? workspaceName;
  SetCurrentWorkspaceName(this.workspaceName);
}

class AddHistory extends HistoryEvent {
  final OpenedTab tab;

  /// scope מפורש לחיפוש, במקום קריאה מ-state של ה-SearchBloc.
  /// נדרש כי SetFacetsWithoutSearch מעבד את ה-state אסינכרונית, אחרי
  /// שהיסטוריית החיפוש כבר נלכדה — ואז ה-scope היה נאבד.
  final List<String>? scopeFacets;

  /// טווח קרבה מפורש, מאותה סיבה: UpdateProximityScopeWithoutSearch מעבד
  /// את ה-state אסינכרונית, ובלי override ההיסטוריה עלולה לצלם טווח ישן.
  final SearchScope? proximityScope;

  AddHistory(this.tab, {this.scopeFacets, this.proximityScope});
}

class CaptureStateForHistory extends HistoryEvent {
  final OpenedTab tab;
  CaptureStateForHistory(this.tab);
}

class FlushHistory extends HistoryEvent {}

class BulkAddHistory extends HistoryEvent {
  final List<Bookmark> snapshots;
  BulkAddHistory(this.snapshots);
}

class RemoveHistory extends HistoryEvent {
  final int index;
  RemoveHistory(this.index);
}

class ClearHistory extends HistoryEvent {}
