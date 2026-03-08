/* represents links between two books in the library*/

import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

/// Represents a link between two books in the library.
class Link {
  /// The Hebrew reference of the link.
  final String heRef;

  /// The index of the first book in the link.
  final int index1;

  /// The path of the second book in the link.
  final String path2;

  /// The index of the second book in the link.
  final int index2;

  /// The type of the connection in the link.
  final String connectionType;

  /// The start character position of the link in the text (optional, for character-based links).
  final int? start;

  /// The end character position of the link in the text (optional, for character-based links).
  final int? end;

  /// Creates a new instance of [Link] with the provided parameters.
  Link({
    required this.heRef,
    required this.index1,
    required this.path2,
    required this.index2,
    required this.connectionType,
    this.start,
    this.end,
  });

  /// Returns the content of the link as a [Future] of [String].
  Future<String> get content =>
      LibraryProviderManager.instance.getLinkContent(this);

  /// Constructs a [Link] object from a JSON object.
  ///
  /// The JSON object should have the following keys:
  /// - 'heRef_2': The Hebrew reference of the link.
  /// - 'line_index_1': The index of the first book in the link.
  /// - 'path_2': The path of the second book in the link.
  /// - 'line_index_2': The index of the second book in the link.
  /// - 'Conection Type': The type of the connection in the link.
  /// - 'start': (optional) The start character position of the link.
  /// - 'end': (optional) The end character position of the link.
  Link.fromJson(Map<String, dynamic> json)
      : heRef = json['heRef_2'].toString(),
        index1 = int.parse(json['line_index_1'].toString().split('.').first),
        path2 = json['path_2'].toString(),
        index2 = int.parse(json['line_index_2'].toString().split('.').first),
        connectionType = json['Conection Type'].toString().isEmpty
            ? 'reference'
            : json['Conection Type'].toString(),
        start = json['start'] != null
            ? int.tryParse(json['start'].toString())
            : null,
        end = json['end'] != null ? int.tryParse(json['end'].toString()) : null;
}

/// Retrieves a list of [Link] objects for the given list of [indexes] and the [links] to be processed.
///
/// The [indexes] parameter is a required list of integers representing the indexes of the links to retrieve.
/// The [links] parameter is a required [Future] of a list of [Link] objects representing the links to be processed.
/// The [commentatorsToShow] parameter is a required list of [Book] objects representing the commentators to show.
///
/// Returns a [Future] of a list of [Link] objects representing the retrieved links.
///
/// The function retrieves the list of links by first awaiting the completion of the [links] future.
/// It then iterates over each index in the [indexes] list and filters the retrieved links based on the following criteria:
/// - The index of the link should be equal to the current index plus one.
/// - The connection type of the link should be either "commentary" or "targum".
/// - The title of the second book in the link should be present in the list of commentators to show.
/// The filtered links are added to the [allLinks] list.
/// After iterating over all the indexes, the [allLinks] list is sorted based on the order of the commentators to show.
/// The sorted list of links is then returned as a [Future] of a list of [Link] objects.
Future<List<Link>> getLinksforIndexs(
    {required List<int> indexes,
    required List<Link> links,
    required List<String> commentatorsToShow}) async {
  // אם אין מפרשים להצגה, מחזיר רשימה ריקה מיד
  if (commentatorsToShow.isEmpty) {
    return [];
  }

  // אם אין אינדקסים, מחזיר רשימה ריקה מיד
  if (indexes.isEmpty) {
    return [];
  }

  // יצירת Set לחיפוש מהיר יותר
  final indexSet = indexes.map((i) => i + 1).toSet();
  final commentatorsSet = commentatorsToShow.toSet();

  // סינון אחד במקום לולאה עם סינונים מרובים
  final allLinks = links.where((link) {
    // בדיקות מהירות קודם
    if (!indexSet.contains(link.index1)) return false;
    final type = link.connectionType.toUpperCase();
    if (type != "COMMENTARY" && type != "TARGUM") return false;
    if (link.path2.isEmpty || link.index2 <= 0) return false;

    // בדיקה איטית יותר בסוף
    return commentatorsSet.contains(utils.getTitleFromPath(link.path2));
  }).toList();

  // מסיר כפילויות לפי שורת היעד בפירוש, כי ה-UI מרנדר פריט אחד לכל path2/index2.
  final seenLinkKeys = <String>{};
  allLinks.retainWhere((link) {
    final key = '${link.path2}|${link.index2}';
    return seenLinkKeys.add(key);
  });

  // אם אין קישורים, מחזיר רשימה ריקה מיד
  if (allLinks.isEmpty) {
    return [];
  }

  // מיון אחד משולב במקום שני מיונים נפרדים
  allLinks.sort((a, b) {
    // קודם לפי סדר המפרשים
    final commentatorComparison = commentatorsToShow
        .indexOf(utils.getTitleFromPath(a.path2))
        .compareTo(commentatorsToShow.indexOf(utils.getTitleFromPath(b.path2)));

    if (commentatorComparison != 0) {
      return commentatorComparison;
    }

    // אם אותו מפרש, מיון לפי heRef
    return a.heRef
        .replaceAll(' טו,', ' ,יה')
        .replaceAll(' טז,', ' יו,')
        .compareTo(
            b.heRef.replaceAll(' טו,', ' ,יה').replaceAll(' טז,', ' יו,'));
  });

  return allLinks;
}
