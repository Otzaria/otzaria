import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

import '../providers/shamor_zachor_data_provider.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import '../widgets/book_card_widget.dart';

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

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Consumer2<ShamorZachorDataProvider, ShamorZachorProgressProvider>(
      builder: (context, dataProvider, progressProvider, child) {
        // Handle loading state
        if (dataProvider.isLoading || progressProvider.isLoading) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('טוען נתוני מעקב...'),
              ],
            ),
          );
        }

        // Handle error state
        if (dataProvider.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  'שגיאה בטעינת נתונים',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  dataProvider.error!.userFriendlyMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => dataProvider.retry(),
                  child: const Text('נסה שוב'),
                ),
              ],
            ),
          );
        }

        final allBookData = dataProvider.allBookData;
        _logger.info('TrackingScreen - Categories in allBookData: ${allBookData.keys.toList()}');
        _logger.info('TrackingScreen - Total categories: ${allBookData.length}');

        final (inProgressItems, completedItems) =
            progressProvider.getCategorizedTrackedBooks(allBookData);

        _logger.info('TrackingScreen - In progress: ${inProgressItems.length}, Completed: ${completedItems.length}');

        final List<Map<String, dynamic>> itemsToShow;
        switch (_selectedFilter) {
          case TrackingFilter.inProgress:
            itemsToShow = inProgressItems;
            break;
          case TrackingFilter.completed:
            itemsToShow = completedItems;
            break;
          case TrackingFilter.all:
            // Combine in progress and completed, sort by completion date (newest first) for completed, then in progress by progress
            final allItems = [...completedItems, ...inProgressItems];
            // Already sorted individually, no need to re-sort combined
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

  /// Build the filter segments (In Progress / Completed)
  Widget _buildFilterSegments() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SegmentedButton<TrackingFilter>(
        segments: const [
          ButtonSegment<TrackingFilter>(
            value: TrackingFilter.all,
            label: Text('הכל'),
            icon: Icon(Icons.library_books),
          ),
          ButtonSegment<TrackingFilter>(
            value: TrackingFilter.inProgress,
            label: Text('בתהליך'),
            icon: Icon(Icons.hourglass_empty_outlined),
          ),
          ButtonSegment<TrackingFilter>(
            value: TrackingFilter.completed,
            label: Text('הושלם'),
            icon: Icon(Icons.check_circle_outline),
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

  /// Build the books list based on current filter
  Widget _buildBooksList(List<Map<String, dynamic>> itemsData) {
    if (itemsData.isEmpty) {
      IconData icon;
      String title;
      String subtitle;

      switch (_selectedFilter) {
        case TrackingFilter.inProgress:
          icon = Icons.hourglass_empty;
          title = 'אין ספרים בתהליך כעת';
          subtitle = 'התחל ללמוד ספר כדי לראות אותו כאן';
          break;
        case TrackingFilter.completed:
          icon = Icons.check_circle_outline;
          title = 'עדיין לא סיימת ספרים';
          subtitle = 'סיים ספר כדי לראות אותו כאן';
          break;
        case TrackingFilter.all:
          icon = Icons.library_books;
          title = 'אין ספרים במעקב';
          subtitle = 'התחל ללמוד ספר כדי לראות אותו כאן';
          break;
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const double desiredCardWidth = 350;

        int crossAxisCount = (constraints.maxWidth / desiredCardWidth).floor();
        if (crossAxisCount < 1) crossAxisCount = 1;

        // Use list view for narrow screens
        if (constraints.maxWidth < 500 || crossAxisCount == 1) {
          return ListView.builder(
            key: PageStorageKey('tracking_list_${_selectedFilter.name}'),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            itemCount: itemsData.length,
            itemBuilder: (context, index) {
              return _buildBookCard(itemsData[index]);
            },
          );
        }

        // Use grid view for wider screens

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
            return _buildBookCard(itemsData[index]);
          },
        );
      },
    );
  }

  /// Build a single book card
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
