import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

import '../providers/shamor_zachor_data_provider.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import '../widgets/error_boundary.dart';
import '../shamor_zachor_widget.dart';
import 'tracking_screen.dart';
import 'books_screen.dart';

/// Main screen for Shamor Zachor with bottom navigation
class ShamorZachorMainScreen extends StatefulWidget {
  const ShamorZachorMainScreen({super.key});

  @override
  State<ShamorZachorMainScreen> createState() => _ShamorZachorMainScreenState();
}

class _ShamorZachorMainScreenState extends State<ShamorZachorMainScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  static final Logger _logger = Logger('ShamorZachorMainScreen');

  @override
  bool get wantKeepAlive => true;

  int _selectedIndex = 0;
  late final PageController _pageController;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _screens = [
      const TrackingScreen(),
      const BooksScreen(),
    ];
    _logger.info('Initialized ShamorZachorMainScreen');

    // Notify initial title state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _notifyTitleChange(_selectedIndex);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index != _selectedIndex && mounted) {
      setState(() {
        _selectedIndex = index;
      });
      // Only animate if PageController is attached
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      // Notify parent about title change
      _notifyTitleChange(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Scaffold(
      body: ErrorBoundary(
        child: Column(
          children: [
            Expanded(
              child: Consumer2<ShamorZachorDataProvider,
                  ShamorZachorProgressProvider>(
                builder: (context, dataProvider, progressProvider, child) {
                  // Show loading state
                  if (dataProvider.isLoading || progressProvider.isLoading) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('טוען נתונים...'),
                        ],
                      ),
                    );
                  }

                  if (progressProvider.error != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            FluentIcons.database_24_regular,
                            size: 64,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'שגיאה בטעינת נתוני התקדמות',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            progressProvider.error!.userFriendlyMessage,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              // נסה לטעון מחדש את שני הספקים
                              dataProvider.loadAllData();
                              // צריך להוסיף מתודה לטעינה מחדש ב-progressProvider
                              // בינתיים, זו התחלה טובה
                            },
                            child: const Text('נסה שוב'),
                          ),
                        ],
                      ),
                    );
                  }

                  // Show main content
                  return PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      if (mounted) {
                        setState(() {
                          _selectedIndex = index;
                        });
                        // Notify parent about title change when swiping
                        _notifyTitleChange(index);
                      }
                    },
                    children: _screens,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        height: 60,
        destinations: const [
          NavigationDestination(
            icon: Icon(FluentIcons.timeline_24_regular),
            selectedIcon: Icon(FluentIcons.timeline_24_filled),
            label: 'מעקב',
          ),
          NavigationDestination(
            icon: Icon(FluentIcons.book_24_regular),
            selectedIcon: Icon(FluentIcons.book_24_filled),
            label: 'ספרים',
          ),
        ],
      ),
    );
  }

  String _getTitle(int index) {
    switch (index) {
      case 0:
        return 'מעקב לימוד';
      case 1:
        return 'ספרים';
      default:
        return 'שמור וזכור';
    }
  }

  /// Notify parent about title change
  void _notifyTitleChange(int index) {
    // Use post-frame callback to find ancestor widget
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final newTitle = _getTitle(index);
        final fullTitle = 'זכור ושמור - $newTitle';

        // Find the ShamorZachorWidget ancestor
        final ancestorWidget =
            context.findAncestorWidgetOfExactType<ShamorZachorWidget>();
        if (ancestorWidget != null && ancestorWidget.onTitleChanged != null) {
          ancestorWidget.onTitleChanged!(fullTitle);
        }
      }
    });
  }
}
