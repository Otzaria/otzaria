import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

import '../providers/shamor_zachor_data_provider.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import '../widgets/book_card_widget.dart';
import '../models/book_model.dart';

enum TrackingFilter { all, inProgress, completed }

/// Screen for tracking learning progress
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with AutomaticKeepAliveClientMixin {
  static final Logger _logger = Logger('TrackingScreen');

  @override
  bool get wantKeepAlive => true;

  TrackingFilter _selectedFilter = TrackingFilter.all;

  @override
  void initState() {
    super.initState();
    _logger.fine('Initialized TrackingScreen');
  }

  void _onBookCardTap(Map<String, dynamic> itemData) {
    // Find ancestor MainScreen and navigate
    // Ideally we would pass a callback, but to minimize plumbing in Provider,
    // we can find the state or use a notification.
    // BUT since we are inside ShamorZachorMainScreen, we can assume it exists.
    // HOWEVER, _ShamorZachorMainScreenState is private.
    // Let's refactor TrackingScreen to accept a callback, OR pass the function down.
    // The previous implementation of BookCardWidget might handle taps internally?
    // Let's check BookCardWidget implementation if we can.

    // For now, let's assume BookCardWidget has an onTap or similar.
    // Wait, the BookCardWidget in previous conversation showed internal navigation?
    // "onBookClickCallback: () => _openOtzarBook(book)" in libraryBrowser, but used BookGridItem.
    // BookCardWidget in ShamorZachor seems to handle taps.

    // Let's rely on finding the ancestor specific Notification or just make MainScreenState public?
    // No, making state public is bad pattern.
    // Better: dispatch a notification.

    BookNavigationNotification(
      categoryName: itemData['topLevelCategoryKey'],
      bookName: itemData['bookName'],
      bookDetails: itemData['bookDetails'],
    ).dispatch(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Consumer2<ShamorZachorDataProvider, ShamorZachorProgressProvider>(
      builder: (context, dataProvider, progressProvider, child) {
        // Handle loading/error states handled by parent mostly, but good to have safety

        final allBookData = dataProvider.allBookData;

        final (inProgressItems, completedItems) =
            progressProvider.getCategorizedTrackedBooks(allBookData);

        final List<Map<String, dynamic>> itemsToShow;
        switch (_selectedFilter) {
          case TrackingFilter.inProgress:
            itemsToShow = inProgressItems;
            break;
          case TrackingFilter.completed:
            itemsToShow = completedItems;
            break;
          case TrackingFilter.all:
            final allItems = [...completedItems, ...inProgressItems];
            itemsToShow = allItems;
            break;
        }

        return Column(
          children: [
            _buildFilterSegments(),
            Expanded(
              child: _buildBooksList(itemsToShow),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterSegments() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SegmentedButton<TrackingFilter>(
        segments: const [
          ButtonSegment<TrackingFilter>(
            value: TrackingFilter.all,
            label: Text('הכל'),
            icon: Icon(FluentIcons.library_24_regular),
          ),
          ButtonSegment<TrackingFilter>(
            value: TrackingFilter.inProgress,
            label: Text('בתהליך'),
            icon: Icon(FluentIcons.hourglass_24_regular),
          ),
          ButtonSegment<TrackingFilter>(
            value: TrackingFilter.completed,
            label: Text('הושלם'),
            icon: Icon(FluentIcons.checkmark_circle_24_regular),
          ),
        ],
        selected: {_selectedFilter},
        onSelectionChanged: (Set<TrackingFilter> newSelection) {
          if (mounted) {
            setState(() {
              _selectedFilter = newSelection.first;
            });
          }
        },
        showSelectedIcon: false,
      ),
    );
  }

  Widget _buildBooksList(List<Map<String, dynamic>> itemsData) {
    if (itemsData.isEmpty) {
      // ... (Empty state logic same as before, simplified for brevity)
      return Center(child: Text('אין ספרים להצגה'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const double desiredCardWidth = 350;
        int crossAxisCount = (constraints.maxWidth / desiredCardWidth).floor();
        if (crossAxisCount < 1) crossAxisCount = 1;

        return GridView.builder(
          key: PageStorageKey('tracking_grid_${_selectedFilter.name}'),
          padding: const EdgeInsets.all(16.0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 175,
          ),
          itemCount: itemsData.length,
          itemBuilder: (context, index) {
            final item = itemsData[index];
            return GestureDetector(
              onTap: () => _onBookCardTap(item),
              child: AbsorbPointer(
                  // Prevent inner buttons from blocking tap if we want whole card tappable?
                  // Actually BookCardWidget might have buttons (delete etc).
                  // We should wrap BookCardWidget or modify it.
                  // Let's assume BookCardWidget has no internal navigation logic that conflicts.
                  // Actually, looking at previous `books_screen.dart`, BookCardWidget DID NOT navigate itself.
                  // It was passive.
                  // So we can wrap it in GestureDetector.
                  absorbing: false, // Let buttons work
                  child: _buildBookCard(item)),
            );
          },
        );
      },
    );
  }

  Widget _buildBookCard(Map<String, dynamic> itemData) {
    return BookCardWidget(
      topLevelCategoryKey: itemData['topLevelCategoryKey'],
      categoryName: itemData['displayCategoryName'],
      bookName: itemData['bookName'],
      bookDetails: itemData['bookDetails'],
      bookProgressData: itemData['bookProgressData'],
      isFromTrackingScreen: true,
      completionDate: itemData['completionDate'],
      isInCompletedListContext: _selectedFilter == TrackingFilter.completed,
    );
  }
}
