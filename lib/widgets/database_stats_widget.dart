import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';

/// Widget that displays database statistics
class DatabaseStatsWidget extends StatefulWidget {
  const DatabaseStatsWidget({super.key});

  @override
  State<DatabaseStatsWidget> createState() => _DatabaseStatsWidgetState();
}

class _DatabaseStatsWidgetState extends State<DatabaseStatsWidget> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await FileSystemData.instance.getDatabaseStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_stats == null || !_stats!['enabled']) {
      return const SizedBox.shrink();
    }

    final bookCount = _stats!['books'] as int;
    final linkCount = _stats!['links'] as int;

    return Tooltip(
      message: 'מסד נתונים: $bookCount ספרים, $linkCount קישורים',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.database_24_regular,
                size: 14, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              '$bookCount',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
