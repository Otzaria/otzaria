import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';
import '../migration/generator/generator.dart';
import '../migration/core/models/generation_progress.dart';
import '../migration/dao/daos/database.dart';
import '../migration/dao/repository/seforim_repository.dart';
import '../data/constants/database_constants.dart';
import '../core/app_paths.dart';

enum DuplicateBookStrategy {
  skip,
  replace,
  ask,
}

/// Represents the current generation step
enum GenerationStep {
  idle,
  books,
  links,
  complete,
  error,
}

class DatabaseGenerationScreen extends StatefulWidget {
  const DatabaseGenerationScreen({super.key});

  @override
  State<DatabaseGenerationScreen> createState() =>
      _DatabaseGenerationScreenState();
}

class _DatabaseGenerationScreenState extends State<DatabaseGenerationScreen> {
  final _logger = Logger('DatabaseGenerationScreen');
  GenerationProgress _progress = GenerationProgress.initial();
  StreamSubscription<GenerationProgress>? _progressSubscription;
  DateTime? _startTime;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  String? _selectedLibraryPath;
  String? _selectedDbPath;
  final DuplicateBookStrategy _duplicateStrategy =
      DuplicateBookStrategy.replace;

  // Step tracking
  GenerationStep _currentStep = GenerationStep.idle;
  double _booksProgress = 0.0;
  double _linksProgress = 0.0;
  int _processedBooks = 0;
  int _totalBooks = 0;
  int _processedLinks = 0;
  int _totalLinks = 0;
  String _currentMessage = '';

  // File validation status
  bool _dbFileExists = false;
  bool _otzariaFolderExists = false;
  bool _priorityFileExists = false;
  bool _acronymFileExists = false;
  bool _linksDirectoryExists = false;
  final List<Map<String, String>> _duplicateBooks = [];
  final Map<String, String> _duplicateReasons = {};

  @override
  void initState() {
    super.initState();
    _loadDefaultLibraryPath();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadDefaultLibraryPath() async {
    try {
      final libraryPath = await AppPaths.getLibraryPath();
      final dbPath = DatabaseConstants.getDatabasePathForLibrary(libraryPath);

      setState(() {
        _selectedLibraryPath = libraryPath;
        _selectedDbPath = dbPath;
      });

      await _checkFileStatus();
      _logger.info('Auto-loaded library path: $libraryPath');
    } catch (e, stackTrace) {
      _logger.warning('Error loading default library path', e, stackTrace);
      await _checkFileStatus();
    }
  }

  void _resetToInitialState() {
    setState(() {
      _progress = GenerationProgress.initial();
      _progressSubscription?.cancel();
      _progressSubscription = null;
      _timer?.cancel();
      _timer = null;
      _startTime = null;
      _elapsed = Duration.zero;
      _currentStep = GenerationStep.idle;
      _booksProgress = 0.0;
      _linksProgress = 0.0;
      _processedBooks = 0;
      _totalBooks = 0;
      _processedLinks = 0;
      _totalLinks = 0;
      _currentMessage = '';
    });
  }

  Future<void> _selectLibraryFolder() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'בחר תיקיית אוצריא (תיקיית האב)',
      );

      if (selectedDirectory != null) {
        _logger.info('Selected library folder: $selectedDirectory');

        final otzariaDir = Directory(
            '$selectedDirectory/${DatabaseConstants.otzariaFolderName}');

        if (!await otzariaDir.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'התיקייה "${DatabaseConstants.otzariaFolderName}" לא נמצאה בתיקייה שנבחרה'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Auto-set DB path to database file in the Otzaria folder
        final dbPath =
            DatabaseConstants.getDatabasePathForLibrary(selectedDirectory);
        setState(() {
          _selectedLibraryPath = selectedDirectory;
          _selectedDbPath = dbPath;
        });

        await _checkFileStatus();
        _logger.info('Auto-set database path: $dbPath');
      }
    } catch (e, stackTrace) {
      _logger.severe('Error selecting library folder', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בבחירת תיקייה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _checkFileStatus() async {
    if (_selectedLibraryPath == null) return;

    try {
      final otzariaDir = Directory(
          '$_selectedLibraryPath/${DatabaseConstants.otzariaFolderName}');
      _otzariaFolderExists = await otzariaDir.exists();

      final dbFileInOtzaria = File(
          '$_selectedLibraryPath/${DatabaseConstants.otzariaFolderName}/${DatabaseConstants.databaseFileName}');
      _dbFileExists = await dbFileInOtzaria.exists();

      _priorityFileExists = false;
      _acronymFileExists = false;

      final aboutSoftwareDirHeb = Directory(
          '$_selectedLibraryPath/${DatabaseConstants.otzariaFolderName}/אודות התוכנה');

      if (await aboutSoftwareDirHeb.exists()) {
        final priorityFile = File('${aboutSoftwareDirHeb.path}/priority');
        _priorityFileExists = await priorityFile.exists();

        final acronymFile = File('${aboutSoftwareDirHeb.path}/acronym.json');
        _acronymFileExists = await acronymFile.exists();
      }

      final linksDir = Directory('$_selectedLibraryPath/links');
      _linksDirectoryExists = await linksDir.exists();

      setState(() {});
    } catch (e, stackTrace) {
      _logger.warning('Error checking file status', e, stackTrace);
    }
  }

  // Removed - DB path is now auto-set based on library folder

  Future<void> _startGeneration() async {
    if (_selectedLibraryPath == null || _selectedDbPath == null) {
      _logger.warning(
          'Cannot start generation: missing library path or database path');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש לבחור תיקיית אוצריא (תיקיית האב)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_dbFileExists && _currentStep != GenerationStep.error) {
      return;
    }

    _logger.info('Starting database generation');

    setState(() {
      _progress = GenerationProgress(
        phase: GenerationPhase.initializing,
        message: 'מתחיל...',
      );
      _startTime = DateTime.now();
      _elapsed = Duration.zero;
      _duplicateBooks.clear();
      _duplicateReasons.clear();
      _currentStep = GenerationStep.books;
      _booksProgress = 0.0;
      _linksProgress = 0.0;
      _processedBooks = 0;
      _totalBooks = 0;
      _processedLinks = 0;
      _totalLinks = 0;
      _currentMessage = 'מאתחל...';
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startTime != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!);
        });
      }
    });

    try {
      MyDatabase.initialize();
      final database = MyDatabase.withPath(_selectedDbPath!);
      final repository = SeforimRepository(database);
      await repository.ensureInitialized();

      // Always replace duplicates and track them
      Future<bool> duplicateCallback(String title, int categoryId) async {
        String categoryName = 'לא ידוע';
        try {
          final category = await repository.getCategory(categoryId);
          if (category != null) categoryName = category.title;
        } catch (_) {
          // Ignore
        }

        _duplicateBooks.add({
          'title': title,
          'path': 'נתיב לא זמין',
          'reason': 'ספר קיים הוחלף בקטגוריה: $categoryName',
        });
        _duplicateReasons[title] = 'ספר קיים הוחלף בקטגוריה: $categoryName';
        return _duplicateStrategy == DuplicateBookStrategy.replace;
      }

      late final DatabaseGenerator generator;
      generator = DatabaseGenerator(
        _selectedLibraryPath!,
        repository,
        onProgress: (progress, message) {
          setState(() {
            // Detect links phase by message content
            final isLinksPhase = message.contains('קישור') ||
                message.contains('link') ||
                message.contains('קבצים)');

            if (isLinksPhase) {
              _currentStep = GenerationStep.links;
              _linksProgress = progress;
              // Mark books as complete when entering links phase
              if (_booksProgress < 1.0) {
                _booksProgress = 1.0;
              }
            } else {
              _currentStep = GenerationStep.books;
              _booksProgress = progress;
              _processedBooks =
                  (progress * generator.totalBooksToProcess).toInt();
              _totalBooks = generator.totalBooksToProcess;
            }
            _currentMessage = message;
            _progress = GenerationProgress(
              phase: _currentStep == GenerationStep.links
                  ? GenerationPhase.processingLinks
                  : GenerationPhase.processingBooks,
              message: message,
              progress: progress,
              processedBooks: _processedBooks,
              totalBooks: _totalBooks,
              processedLinks: _processedLinks,
              totalLinks: _totalLinks,
            );
          });
        },
        onDuplicateBook: duplicateCallback,
      );

      await generator.generate();

      // Delete acronym.json file after successful generation
      await _deleteAcronymFileAfterGeneration();

      await repository.close();
      _timer?.cancel();

      if (_duplicateBooks.isNotEmpty) {
        _showDuplicateReport();
      }

      setState(() {
        _currentStep = GenerationStep.complete;
        _booksProgress = 1.0;
        _linksProgress = 1.0;
        _progress = GenerationProgress.complete();
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('הפעלה מחדש נדרשת'),
            content: const Text(
                'תהליך יצירת מסד הנתונים הסתיים בהצלחה.\nיש להפעיל מחדש את התוכנה.'),
            actions: [
              TextButton(
                onPressed: () => exit(0),
                child: const Text('סגור תוכנה'),
              ),
            ],
          ),
        );
      }
    } catch (e, stackTrace) {
      final errorMsg = e.toString();
      _logger.severe('Error during generation: $errorMsg', e, stackTrace);
      setState(() {
        _currentStep = GenerationStep.error;
        _progress = GenerationProgress.error(errorMsg);
      });
      _timer?.cancel();
    }
  }

  /// Delete acronym.json file after successful database generation
  Future<void> _deleteAcronymFileAfterGeneration() async {
    if (_selectedLibraryPath == null) return;

    try {
      final acronymPath =
          '$_selectedLibraryPath/${DatabaseConstants.otzariaFolderName}/אודות התוכנה/acronym.json';
      final acronymFile = File(acronymPath);

      if (await acronymFile.exists()) {
        await acronymFile.delete();
        _logger.info(
            'Deleted acronym.json file after successful generation: $acronymPath');
      }
    } catch (e) {
      _logger.warning('Failed to delete acronym.json file: $e');
      // Don't fail the generation if we can't delete the file
    }
  }

  /// Show report of duplicate books that were replaced
  void _showDuplicateReport() {
    final reportText = StringBuffer();
    reportText
        .writeln('דוח ספרים כפולים - ${_duplicateBooks.length} ספרים הוחלפו:');
    reportText.writeln('=' * 50);

    for (int i = 0; i < _duplicateBooks.length; i++) {
      final bookInfo = _duplicateBooks[i];
      reportText.writeln('${i + 1}. ${bookInfo['title'] ?? 'לא ידוע'}');
    }

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('דוח ספרים כפולים'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: _duplicateBooks.length,
              itemBuilder: (context, index) {
                final title = _duplicateBooks[index]['title'] ?? 'לא ידוע';
                return ListTile(
                  leading: Text('${index + 1}'),
                  title: Text(title),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: reportText.toString()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('הדוח הועתק ללוח')),
                );
              },
              child: const Text('העתק'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Configuration section - only show when idle
              if (_currentStep == GenerationStep.idle) ...[
                _buildConfigurationCard(),
                const SizedBox(height: 24),
              ],

              // Progress section - show during generation
              if (_currentStep != GenerationStep.idle) ...[
                _buildStepsProgressCard(),
                const SizedBox(height: 16),
              ],

              // Error display
              if (_progress.error != null) ...[
                _buildErrorCard(),
                const SizedBox(height: 16),
              ],

              // Action buttons
              _buildActionButtons(),

              const SizedBox(height: 16),

              // Info/completion text
              if (_currentStep == GenerationStep.idle) _buildInfoText(),
              if (_currentStep == GenerationStep.complete &&
                  _progress.error == null)
                _buildCompletionText(),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the steps progress card showing both phases
  Widget _buildStepsProgressCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Timer display
            if (_startTime != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    Text(
                      'התחלה: ${_formatTime(_startTime!)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      'נוכחי: ${_formatTime(DateTime.now())}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(FluentIcons.timer_24_regular, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'זמן שעבר: ${_formatDuration(_elapsed)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Step 1: Books
            _buildStepProgress(
              stepNumber: 1,
              title: 'עיבוד ספרים',
              emoji: '📚',
              progress: _booksProgress,
              processed: _processedBooks,
              total: _totalBooks,
              isActive: _currentStep == GenerationStep.books,
              isComplete: _currentStep == GenerationStep.links ||
                  _currentStep == GenerationStep.complete,
            ),

            const SizedBox(height: 20),

            // Step 2: Links
            _buildStepProgress(
              stepNumber: 2,
              title: 'יצירת קישורים',
              emoji: '🔗',
              progress: _linksProgress,
              processed: _processedLinks,
              total: _totalLinks,
              isActive: _currentStep == GenerationStep.links,
              isComplete: _currentStep == GenerationStep.complete,
            ),

            // Current message
            if (_currentMessage.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                _currentMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[700],
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build individual step progress widget
  Widget _buildStepProgress({
    required int stepNumber,
    required String title,
    required String emoji,
    required double progress,
    required int processed,
    required int total,
    required bool isActive,
    required bool isComplete,
  }) {
    final progressPercent = (progress * 100).toStringAsFixed(1);

    Color getStepColor() {
      if (isComplete) return Colors.green;
      if (isActive) return Colors.blue;
      return Colors.grey[400]!;
    }

    Color getProgressColor() {
      if (isComplete) return Colors.green;
      return Colors.blue;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.blue[50]
            : (isComplete ? Colors.green[50] : Colors.grey[100]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? Colors.blue[300]!
              : (isComplete ? Colors.green[300]! : Colors.grey[300]!),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              // Step number circle
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: getStepColor(),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isComplete
                      ? const Icon(FluentIcons.checkmark_24_regular,
                          color: Colors.white, size: 20)
                      : Text(
                          '$stepNumber',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Title and emoji
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isActive
                        ? Colors.blue[800]
                        : (isComplete ? Colors.green[800] : Colors.grey[600]),
                  ),
                ),
              ),
              // Percentage
              Text(
                '$progressPercent%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: getStepColor(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(getProgressColor()),
            ),
          ),
          // Stats row
          if (total > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$processed / $total',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigurationCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('הגדרות',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildPathSelector(
              label: 'תיקיית אוצריא (תיקיית האב)',
              path: _selectedLibraryPath,
              onTap: _selectLibraryFolder,
              icon: FluentIcons.folder_open_24_regular,
            ),
            const SizedBox(height: 8),
            if (_selectedDbPath != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(FluentIcons.info_24_regular,
                        color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('מסד הנתונים: $_selectedDbPath',
                          style:
                              TextStyle(color: Colors.blue[900], fontSize: 12)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Text('בדיקת קבצים נדרשים',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_selectedLibraryPath != null) ...[
              _buildFileStatusItem('תיקיית אוצריא', _otzariaFolderExists,
                  _otzariaFolderExists ? 'קיימת' : 'לא קיימת'),
              _buildFileStatusItem('קובץ מסד נתונים (אוצריא)', _dbFileExists,
                  _dbFileExists ? 'קיים - יגובה' : 'לא קיים'),
              _buildFileStatusItem('קובץ priority', _priorityFileExists,
                  _priorityFileExists ? 'קיים' : 'לא קיים'),
              _buildFileStatusItem('קובץ acronym.json', _acronymFileExists,
                  _acronymFileExists ? 'קיים' : 'לא קיים'),
              _buildFileStatusItem('תיקיית links', _linksDirectoryExists,
                  _linksDirectoryExists ? 'קיימת' : 'לא קיימת'),
            ] else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(FluentIcons.warning_24_regular,
                        color: Colors.orange[700], size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Text(
                            'יש לבחור תיקיית אוצריא כדי לבדוק את סטטוס הקבצים')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FluentIcons.error_circle_24_regular, color: Colors.red[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: SelectableText(_progress.error!,
                        style: TextStyle(color: Colors.red[700])),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _progress.error!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('השגיאה הועתקה ללוח')),
              );
            },
            icon: const Icon(FluentIcons.copy_24_regular, size: 18),
            label: const Text('העתק שגיאה'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_progress.error != null) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _resetToInitialState,
              icon: const Icon(FluentIcons.arrow_sync_24_regular),
              label: const Text('חזור להתחלה'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _startGeneration,
              icon: const Icon(FluentIcons.arrow_sync_24_regular),
              label: const Text('נסה שוב'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    if (_currentStep == GenerationStep.complete && _progress.error == null) {
      return ElevatedButton.icon(
        onPressed: () => exit(0),
        icon: const Icon(FluentIcons.arrow_reset_24_regular),
        label: Text(_getButtonText(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
      );
    }

    final button = ElevatedButton(
      onPressed: (_currentStep == GenerationStep.idle) &&
              _otzariaFolderExists &&
              !_dbFileExists
          ? _startGeneration
          : null,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: Colors.blue,
        disabledBackgroundColor: Colors.grey[300],
      ),
      child: Text(_getButtonText(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );

    if (_dbFileExists) {
      return Tooltip(
        message: 'מסד הנתונים כבר קיים',
        child: button,
      );
    }

    return button;
  }

  Widget _buildInfoText() {
    return Text(
      'בחר את תיקיית האב של אוצריא.\nמסד הנתונים ייווצר אוטומטית בתיקייה זו.',
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: Colors.grey[600]),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildCompletionText() {
    return Text(
      'מסד הנתונים נוצר בהצלחה!\nזמן כולל: ${_formatDuration(_elapsed)}',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.green[700],
            fontWeight: FontWeight.w500,
          ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildFileStatusItem(String label, bool exists, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
              exists
                  ? FluentIcons.checkmark_circle_24_regular
                  : FluentIcons.error_circle_24_regular,
              color: exists ? Colors.green : Colors.red,
              size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathSelector({
    required String label,
    required String? path,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[50],
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    path ?? 'לחץ לבחירה...',
                    style: TextStyle(
                        color:
                            path != null ? Colors.black87 : Colors.grey[600]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getButtonText() {
    if (!_otzariaFolderExists && _selectedLibraryPath != null) {
      return 'לא ניתן ליצור - תיקיית אוצריא לא קיימת';
    }
    if (_currentStep == GenerationStep.idle) return 'התחל יצירת מסד נתונים';
    if (_currentStep == GenerationStep.complete && _progress.error == null) {
      return 'הפעל מחדש';
    }
    return 'מעבד...';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}
