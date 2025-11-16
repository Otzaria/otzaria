import 'package:flutter/material.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:search_engine/search_engine.dart';

class RawIndexViewerDialog extends StatefulWidget {
  final String query;

  const RawIndexViewerDialog({super.key, required this.query});

  @override
  State<RawIndexViewerDialog> createState() => _RawIndexViewerDialogState();
}

class _RawIndexViewerDialogState extends State<RawIndexViewerDialog> {
  List<ReferenceSearchResult>? results;
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    try {
      final data = await TantivyDataProvider.instance
          .searchRefs(widget.query, 1000, false);
      setState(() {
        results = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('תוצאות גולמיות מהאינדקס: "${widget.query}"'),
      content: SizedBox(
        width: 700,
        height: 600,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Text('שגיאה: $error'))
                : Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.blue.shade50,
                        child: Text(
                          'סה"כ ${results!.length} תוצאות מהאינדקס (ללא סינון)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: results!.length,
                          itemBuilder: (context, index) {
                            final result = results![index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(
                                  result.reference,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('ספר: ${result.title}'),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('סגור'),
        ),
      ],
    );
  }
}
