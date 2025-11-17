import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/pdf_book/pdf_commentators_selector.dart';
import 'package:otzaria/pdf_book/pdf_commentary_content.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

/// מייצג קבוצת קטעי פירוש רצופים מאותו ספר
class CommentaryGroup {
  final String bookTitle;
  final List<Link> links;

  CommentaryGroup({required this.bookTitle, required this.links});
}

/// מקבץ רשימת קישורים לקבוצות לפי שם הספר (רק קטעים רצופים)
List<CommentaryGroup> _groupConsecutiveLinks(List<Link> links) {
  if (links.isEmpty) return [];

  final groups = <CommentaryGroup>[];
  String? currentTitle;
  List<Link> currentGroup = [];

  for (final link in links) {
    final title = utils.getTitleFromPath(link.path2);

    if (currentTitle == null || currentTitle != title) {
      // ספר חדש - שומר את הקבוצה הקודמת ומתחיל קבוצה חדשה
      if (currentGroup.isNotEmpty) {
        groups.add(CommentaryGroup(
          bookTitle: currentTitle!,
          links: List.from(currentGroup),
        ));
      }
      currentTitle = title;
      currentGroup = [link];
    } else {
      // אותו ספר - מוסיף לקבוצה הנוכחית
      currentGroup.add(link);
    }
  }

  // מוסיף את הקבוצה האחרונה
  if (currentGroup.isNotEmpty) {
    groups.add(CommentaryGroup(
      bookTitle: currentTitle!,
      links: List.from(currentGroup),
    ));
  }

  return groups;
}

/// Widget שמציג מפרשים וקישורים עבור PDF
class PdfCommentaryPanel extends StatefulWidget {
  final PdfBookTab tab;
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final VoidCallback? onClose;

  const PdfCommentaryPanel({
    super.key,
    required this.tab,
    required this.openBookCallback,
    required this.fontSize,
    this.onClose,
  });

  @override
  State<PdfCommentaryPanel> createState() => _PdfCommentaryPanelState();
}

class _PdfCommentaryPanelState extends State<PdfCommentaryPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showFilterTab = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3, // מפרשים, קישורים, הערות
      vsync: this,
      initialIndex: 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // שורת הכרטיסיות
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // כפתור סינון מפרשים
              IconButton(
                icon: Icon(
                  FluentIcons.filter_24_regular,
                  color: _showFilterTab
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                ),
                tooltip: 'בחירת מפרשים',
                onPressed: () {
                  setState(() {
                    _showFilterTab = !_showFilterTab;
                  });
                },
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // חישוב גודל הטקסט לפי רוחב זמין
                    final availableWidth = constraints.maxWidth;
                    final fontSize = availableWidth < 200
                        ? 11.0
                        : (availableWidth < 300 ? 13.0 : 14.0);

                    return TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      padding: EdgeInsets.zero,
                      labelPadding: EdgeInsets.symmetric(
                          horizontal: availableWidth < 250 ? 8 : 16),
                      tabs: [
                        Tab(
                          child: Text(
                            'מפרשים',
                            style: TextStyle(fontSize: fontSize),
                          ),
                        ),
                        Tab(
                          child: Text(
                            'קישורים',
                            style: TextStyle(fontSize: fontSize),
                          ),
                        ),
                        Tab(
                          child: Text(
                            'הערות אישיות',
                            style: TextStyle(fontSize: fontSize),
                          ),
                        ),
                      ],
                      labelColor: Theme.of(context).colorScheme.primary,
                      unselectedLabelColor: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                      indicatorColor: Theme.of(context).colorScheme.primary,
                      dividerColor: Colors.transparent,
                      onTap: (index) {
                        // אם לוחצים על טאב מפרשים (0) ואנחנו בכפתור סינון, סוגרים אותו
                        if (index == 0 && _showFilterTab) {
                          setState(() {
                            _showFilterTab = false;
                          });
                        }
                      },
                    );
                  },
                ),
              ),
              // לחצן סגירה
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                margin: const EdgeInsets.all(8.0),
                child: IconButton(
                  iconSize: 18,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  onPressed: widget.onClose ?? () {},
                ),
              ),
            ],
          ),
        ),
        // תוכן הכרטיסיות
        Expanded(
          child: _showFilterTab
              ? _buildCommentatorsFilter()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCommentariesView(),
                    _buildLinksView(),
                    _buildNotesView(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCommentatorsFilter() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: PdfCommentatorsSelector(
        tab: widget.tab,
        onChanged: () {
          setState(() {
            // עדכון התצוגה כשמשנים מפרשים
          });
        },
      ),
    );
  }

  Widget _buildCommentariesView() {
    debugPrint('=== PDF Commentary Debug ===');
    debugPrint('currentTextLineNumber: ${widget.tab.currentTextLineNumber}');
    debugPrint('total links: ${widget.tab.links.length}');
    debugPrint('activeCommentators: ${widget.tab.activeCommentators}');
    
    // בדיקה אם יש מספר שורה נוכחי
    if (widget.tab.currentTextLineNumber == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'לא נמצאו מפרשים לדף זה',
                style: TextStyle(
                  fontSize: widget.fontSize * 0.9,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Debug: currentTextLineNumber is null',
                style: TextStyle(
                  fontSize: widget.fontSize * 0.7,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // סינון מפרשים לפי השורה הנוכחית
    final currentLine = widget.tab.currentTextLineNumber!;
    debugPrint('Looking for links at line: ${currentLine + 1}');
    
    final relevantLinks = widget.tab.links
        .where((link) =>
            link.index1 == currentLine + 1 &&
            (link.connectionType == "commentary" ||
                link.connectionType == "targum") &&
            widget.tab.activeCommentators
                .contains(utils.getTitleFromPath(link.path2)))
        .toList();

    debugPrint('Found ${relevantLinks.length} relevant links');
    
    if (relevantLinks.isEmpty) {
      // בדיקה מפורטת למה אין קישורים
      final allLinksForLine = widget.tab.links
          .where((link) => link.index1 == currentLine + 1)
          .toList();
      
      debugPrint('Total links for line ${currentLine + 1}: ${allLinksForLine.length}');
      if (allLinksForLine.isNotEmpty) {
        debugPrint('Available commentators in links:');
        for (final link in allLinksForLine.take(5)) {
          debugPrint('  - ${utils.getTitleFromPath(link.path2)} (${link.connectionType})');
        }
      }
      
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'לא נמצאו מפרשים לדף זה',
                style: TextStyle(
                  fontSize: widget.fontSize * 0.9,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Debug: Line ${currentLine + 1}, ${allLinksForLine.length} links found, ${widget.tab.activeCommentators.length} active commentators',
                style: TextStyle(
                  fontSize: widget.fontSize * 0.7,
                  color: Colors.red,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // קיבוץ המפרשים לפי ספר
    final groups = _groupConsecutiveLinks(relevantLinks);

    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return _buildCommentaryGroupTile(group);
      },
    );
  }

  Widget _buildCommentaryGroupTile(CommentaryGroup group) {
    return ExpansionTile(
      key: PageStorageKey('${group.bookTitle}_${widget.tab.currentTextLineNumber}'),
      maintainState: true,
      initiallyExpanded: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      collapsedBackgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(
        group.bookTitle,
        style: TextStyle(
          fontSize: widget.fontSize * 0.85,
          fontWeight: FontWeight.bold,
          fontFamily: 'FrankRuhlCLM',
        ),
      ),
      children: group.links.map((link) {
        return ListTile(
          contentPadding: const EdgeInsets.only(right: 32.0, left: 16.0),
          title: Text(
            link.heRef,
            style: TextStyle(
              fontSize: widget.fontSize * 0.75,
              fontWeight: FontWeight.normal,
              fontFamily: 'FrankRuhlCLM',
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
          ),
          subtitle: PdfCommentaryContent(
            key: ValueKey('${link.path2}_${link.index2}_${widget.tab.currentTextLineNumber}'),
            link: link,
            fontSize: widget.fontSize,
            openBookCallback: widget.openBookCallback,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLinksView() {
    if (widget.tab.currentTextLineNumber == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'לא נמצאו קישורים לדף זה',
            style: TextStyle(
              fontSize: widget.fontSize * 0.9,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    // סינון קישורים (לא מפרשים)
    final currentLine = widget.tab.currentTextLineNumber!;
    final relevantLinks = widget.tab.links
        .where((link) =>
            link.index1 == currentLine + 1 &&
            link.connectionType != "commentary" &&
            link.connectionType != "targum" &&
            link.start == null &&
            link.end == null)
        .toList();

    if (relevantLinks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'לא נמצאו קישורים לדף זה',
            style: TextStyle(
              fontSize: widget.fontSize * 0.9,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: relevantLinks.length,
      itemBuilder: (context, index) {
        final link = relevantLinks[index];
        return _buildLinkTile(link);
      },
    );
  }

  Widget _buildLinkTile(Link link) {
    return ExpansionTile(
      title: Text(
        link.heRef,
        style: TextStyle(
          fontSize: widget.fontSize * 0.75,
          fontWeight: FontWeight.w600,
          fontFamily: 'FrankRuhlCLM',
        ),
      ),
      subtitle: Text(
        utils.getTitleFromPath(link.path2),
        style: TextStyle(
          fontSize: widget.fontSize * 0.65,
          fontFamily: 'FrankRuhlCLM',
          color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
        ),
      ),
      children: [
        GestureDetector(
          onTap: () {
            // פתיחת הספר בלחיצה על הקישור
            widget.openBookCallback(
              TextBookTab(
                book: TextBook(
                  title: utils.getTitleFromPath(link.path2),
                ),
                index: link.index2 - 1,
                openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ??
                        false) ||
                    (Settings.getValue<bool>('key-default-sidebar-open') ??
                        false),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: FutureBuilder<String>(
              future: link.content,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text('שגיאה: ${snapshot.error}');
                }
                return Text(
                  utils.stripHtmlIfNeeded(snapshot.data ?? ''),
                  style: TextStyle(
                    fontSize: widget.fontSize * 0.75,
                    fontFamily: 'FrankRuhlCLM',
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          'הערות אישיות - בקרוב',
          style: TextStyle(
            fontSize: widget.fontSize * 0.9,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}
