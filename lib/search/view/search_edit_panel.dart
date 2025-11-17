import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

/// פאנל עריכת חיפוש - מופיע מתחת לשורת "מוצגות תוצאות של..."
/// מאפשר עריכת החיפוש הנוכחי ללא יצירת כרטיסייה חדשה
class SearchEditPanel extends StatefulWidget {
  final SearchingTab tab;
  final VoidCallback onClose;

  const SearchEditPanel({
    super.key,
    required this.tab,
    required this.onClose,
  });

  @override
  State<SearchEditPanel> createState() => _SearchEditPanelState();
}

class _SearchEditPanelState extends State<SearchEditPanel> {
  final TextEditingController _alternativeWordController = TextEditingController();
  final Map<String, TextEditingController> _spacingControllers = {};
  final Map<String, FocusNode> _spacingFocusNodes = {};
  final FocusNode _alternativeWordFocusNode = FocusNode();
  final List<String> _currentAlternatives = [];

  @override
  void initState() {
    super.initState();
    
    // מאזין לשינויים בתיבת החיפוש
    widget.tab.queryController.addListener(() {
      if (mounted) {
        setState(() {
          _updateAlternativesList();
        });
      }
    });

    // בקשת פוקוס לשדה החיפוש
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.tab.searchFieldFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _alternativeWordController.dispose();
    _alternativeWordFocusNode.dispose();
    for (final controller in _spacingControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _spacingFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _updateAlternativesList() {
    final wordIndex = _getCurrentWordIndex();
    if (wordIndex != null) {
      final alternatives = widget.tab.alternativeWords[wordIndex] ?? [];
      if (_currentAlternatives.length != alternatives.length ||
          !_currentAlternatives.every((alt) => alternatives.contains(alt))) {
        _currentAlternatives.clear();
        _currentAlternatives.addAll(alternatives);
      }

      final words = widget.tab.queryController.text.trim().split(RegExp(r'\s+'));
      final totalWords = words.where((w) => w.isNotEmpty).length;
      if (wordIndex < totalWords - 1) {
        final key = '$wordIndex-${wordIndex + 1}';
        final controller = _getSpacingController(wordIndex, wordIndex + 1);
        final spacing = widget.tab.spacingValues[key] ?? '';
        if (controller.text != spacing) {
          controller.text = spacing;
        }
      }
    } else {
      if (_currentAlternatives.isNotEmpty) {
        _currentAlternatives.clear();
      }
    }
  }

  TextEditingController _getSpacingController(int leftIndex, int rightIndex) {
    final key = '$leftIndex-$rightIndex';
    if (!_spacingControllers.containsKey(key)) {
      final controller = TextEditingController();
      if (widget.tab.spacingValues.containsKey(key)) {
        controller.text = widget.tab.spacingValues[key]!;
      }
      _spacingControllers[key] = controller;
    }
    return _spacingControllers[key]!;
  }

  FocusNode _getSpacingFocusNode(int leftIndex, int rightIndex) {
    final key = '$leftIndex-$rightIndex';
    if (!_spacingFocusNodes.containsKey(key)) {
      _spacingFocusNodes[key] = FocusNode();
    }
    return _spacingFocusNodes[key]!;
  }

  String? _getCurrentWord() {
    final text = widget.tab.queryController.text;
    final cursorPosition = widget.tab.queryController.selection.baseOffset;

    if (text.isEmpty || cursorPosition < 0) return null;

    final words = text.trim().split(RegExp(r'\s+'));
    int currentPos = 0;

    for (final word in words) {
      if (word.isEmpty) continue;

      final wordStart = text.indexOf(word, currentPos);
      if (wordStart == -1) continue;
      final wordEnd = wordStart + word.length;

      if (cursorPosition >= wordStart && cursorPosition <= wordEnd) {
        return word;
      }

      currentPos = wordEnd;
    }

    return null;
  }

  int? _getCurrentWordIndex() {
    final text = widget.tab.queryController.text;
    final cursorPosition = widget.tab.queryController.selection.baseOffset;

    if (text.isEmpty || cursorPosition < 0) return null;

    final words = text.trim().split(RegExp(r'\s+'));
    int currentPos = 0;

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isEmpty) continue;

      final wordStart = text.indexOf(word, currentPos);
      if (wordStart == -1) continue;
      final wordEnd = wordStart + word.length;

      if (cursorPosition >= wordStart && cursorPosition <= wordEnd) {
        return i;
      }

      currentPos = wordEnd;
    }

    return null;
  }

  void _performSearch() {
    final query = widget.tab.queryController.text.trim();

    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('נא להזין טקסט לחיפוש'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // עדכון החיפוש באותה כרטיסייה (לא יצירת כרטיסייה חדשה!)
    widget.tab.searchBloc.add(
      UpdateSearchQuery(
        query,
        customSpacing: widget.tab.spacingValues,
        alternativeWords: widget.tab.alternativeWords,
        searchOptions: widget.tab.searchOptions,
      ),
    );

    // סגירת הפאנל
    widget.onClose();
  }

  Widget _buildSearchModeToggle(SearchState state) {
    final modes = [
      {'label': 'מתקדם', 'mode': SearchMode.advanced},
      {'label': 'מדוייק', 'mode': SearchMode.exact},
      {'label': 'מקורב', 'mode': SearchMode.fuzzy},
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: modes.map((modeData) {
        final isSelected = state.configuration.searchMode == modeData['mode'];
        return Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: ChoiceChip(
            label: Text(modeData['label'] as String),
            selected: isSelected,
            onSelected: (selected) {
              if (selected) {
                widget.tab.searchBloc.add(SetSearchMode(modeData['mode'] as SearchMode));
              }
            },
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        final currentWord = _getCurrentWord();
        final wordIndex = _getCurrentWordIndex();
        final isEnabled = currentWord != null && wordIndex != null;

        final words = widget.tab.queryController.text.trim().split(RegExp(r'\s+'));
        final totalWords = words.where((w) => w.isNotEmpty).length;

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // שורה עליונה: מצב חיפוש + מרווח כללי
              Row(
                children: [
                  Text(
                    'מצב חיפוש:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _buildSearchModeToggle(state),
                  const SizedBox(width: 32),
                  // מרווח כללי - רק אם אין מרווחים מותאמים אישית
                  if (widget.tab.spacingValues.isEmpty && !state.fuzzy) ...[
                    Text(
                      'מרווח כללי בין מילים:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: '0-30',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          isDense: true,
                        ),
                        controller: TextEditingController(text: state.distance.toString()),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          FilteringTextInputFormatter.allow(RegExp(r'^([0-9]|[12][0-9]|30)$')),
                        ],
                        textAlign: TextAlign.center,
                        onChanged: (value) {
                          final distance = int.tryParse(value);
                          if (distance != null && distance >= 0 && distance <= 30) {
                            widget.tab.searchBloc.add(UpdateDistance(distance));
                          }
                        },
                      ),
                    ),
                  ],
                  const Spacer(),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // שורה שנייה: שדה חיפוש + כפתורים
              Row(
                children: [
                  // שדה חיפוש
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: widget.tab.queryController,
                      focusNode: widget.tab.searchFieldFocusNode,
                      decoration: InputDecoration(
                        hintText: 'הזן טקסט לחיפוש...',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(FluentIcons.dismiss_24_regular),
                          onPressed: () {
                            widget.tab.queryController.clear();
                          },
                        ),
                      ),
                      textAlign: TextAlign.right,
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // כפתור חיפוש
                  ElevatedButton.icon(
                    onPressed: _performSearch,
                    icon: const Icon(FluentIcons.search_24_regular),
                    label: const Text('חפש'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // כפתור סגירה
                  IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular),
                    onPressed: widget.onClose,
                    tooltip: 'סגור',
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // שורה תחתונה: אפשרויות מתקדמות בפריסה רחבה (רק בחיפוש מתקדם)
              if (state.configuration.searchMode == SearchMode.advanced)
                _buildAdvancedOptions(isEnabled, currentWord, wordIndex, totalWords, words)
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      'אפשרויות מתקדמות זמינות רק במצב "חיפוש מתקדם"',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdvancedOptions(
    bool isEnabled,
    String? currentWord,
    int? wordIndex,
    int totalWords,
    List<String> words,
  ) {
    // אם אין מילה נבחרת, הצג הודעה
    if (!isEnabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(
                FluentIcons.cursor_click_24_regular,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'לחץ על מילה בשדה החיפוש כדי להגדיר אפשרויות מתקדמות',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // עמודה שמאלית: תיבות טקסט
        Expanded(
          flex: 2,
          child: Column(
            children: [
              // ניווט בין מילים
              _buildWordNavigation(isEnabled, currentWord, wordIndex, totalWords, words),
              
              const SizedBox(height: 16),
              
              // תיבת מרווח
              _buildSpacingField(isEnabled, wordIndex),
              
              const SizedBox(height: 16),
              
              // תיבת מילה חילופית
              _buildAlternativeWordField(isEnabled, wordIndex),
              
              // רשימת מילים חילופיות
              if (_currentAlternatives.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildAlternativeWordsList(),
              ],
            ],
          ),
        ),
        
        const SizedBox(width: 24),
        
        // עמודה ימנית: תיבות סימון בפריסה רחבה
        Expanded(
          flex: 3,
          child: _buildCheckboxGrid(isEnabled, currentWord, wordIndex),
        ),
      ],
    );
  }

  Widget _buildWordNavigation(
    bool isEnabled,
    String? currentWord,
    int? wordIndex,
    int totalWords,
    List<String> words,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(FluentIcons.chevron_left_24_regular),
          onPressed: isEnabled && wordIndex != null && wordIndex > 0
              ? () {
                  final text = widget.tab.queryController.text;
                  int currentPos = 0;
                  for (int i = 0; i < wordIndex - 1; i++) {
                    final wordStart = text.indexOf(words[i], currentPos);
                    currentPos = wordStart + words[i].length;
                  }
                  final targetWordStart = text.indexOf(words[wordIndex - 1], currentPos);
                  widget.tab.queryController.selection = TextSelection.collapsed(
                    offset: targetWordStart + words[wordIndex - 1].length ~/ 2,
                  );
                  setState(() {});
                }
              : null,
          tooltip: 'מילה קודמת',
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isEnabled
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isEnabled ? currentWord! : 'בחר מילה',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isEnabled
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Colors.grey.shade500,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(FluentIcons.chevron_right_24_regular),
          onPressed: isEnabled && wordIndex != null && wordIndex < totalWords - 1
              ? () {
                  final text = widget.tab.queryController.text;
                  int currentPos = 0;
                  for (int i = 0; i <= wordIndex; i++) {
                    final wordStart = text.indexOf(words[i], currentPos);
                    currentPos = wordStart + words[i].length;
                  }
                  final targetWordStart = text.indexOf(words[wordIndex + 1], currentPos);
                  widget.tab.queryController.selection = TextSelection.collapsed(
                    offset: targetWordStart + words[wordIndex + 1].length ~/ 2,
                  );
                  setState(() {});
                }
              : null,
          tooltip: 'מילה הבאה',
        ),
      ],
    );
  }

  Widget _buildSpacingField(bool isEnabled, int? wordIndex) {
    return Opacity(
      opacity: isEnabled && wordIndex != null ? 1.0 : 0.5,
      child: TextField(
        enabled: isEnabled && wordIndex != null,
        focusNode: wordIndex != null ? _getSpacingFocusNode(wordIndex, wordIndex + 1) : null,
        decoration: InputDecoration(
          labelText: 'מרווח למילה הבאה',
          hintText: '0-30',
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          suffixIcon: IconButton(
            icon: const Icon(FluentIcons.dismiss_24_regular, size: 20),
            onPressed: isEnabled && wordIndex != null
                ? () {
                    final key = '$wordIndex-${wordIndex + 1}';
                    widget.tab.spacingValues.remove(key);
                    widget.tab.spacingValuesChanged.value++;
                    _getSpacingController(wordIndex, wordIndex + 1).clear();
                  }
                : null,
            tooltip: 'מחק מרווח',
          ),
        ),
        controller: wordIndex != null
            ? _getSpacingController(wordIndex, wordIndex + 1)
            : TextEditingController(),
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          FilteringTextInputFormatter.allow(RegExp(r'^([0-9]|[12][0-9]|30)$')),
        ],
        style: const TextStyle(fontSize: 14),
        textAlign: TextAlign.right,
        onChanged: (text) {
          if (isEnabled && wordIndex != null && text.trim().isNotEmpty) {
            final key = '$wordIndex-${wordIndex + 1}';
            widget.tab.spacingValues[key] = text.trim();
            widget.tab.spacingValuesChanged.value++;
          }
        },
        onSubmitted: (text) {
          if (text.trim().isNotEmpty && wordIndex != null) {
            final key = '$wordIndex-${wordIndex + 1}';
            widget.tab.spacingValues[key] = text.trim();
            widget.tab.spacingValuesChanged.value++;
          } else {
            _performSearch();
          }
        },
      ),
    );
  }

  Widget _buildAlternativeWordField(bool isEnabled, int? wordIndex) {
    return TextField(
      controller: _alternativeWordController,
      focusNode: _alternativeWordFocusNode,
      enabled: isEnabled,
      decoration: InputDecoration(
        labelText: 'מילה חילופית',
        hintText: 'הקלד מילה...',
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        prefixIcon: IconButton(
          icon: const Icon(FluentIcons.add_24_regular, size: 20),
          onPressed: isEnabled
              ? () {
                  final text = _alternativeWordController.text.trim();
                  if (text.isNotEmpty && wordIndex != null) {
                    setState(() {
                      if (!_currentAlternatives.contains(text)) {
                        _currentAlternatives.add(text);
                      }
                    });
                    if (!widget.tab.alternativeWords.containsKey(wordIndex)) {
                      widget.tab.alternativeWords[wordIndex] = [];
                    }
                    if (!widget.tab.alternativeWords[wordIndex]!.contains(text)) {
                      widget.tab.alternativeWords[wordIndex]!.add(text);
                    }
                    widget.tab.alternativeWordsChanged.value++;
                    _alternativeWordController.clear();
                  }
                }
              : null,
        ),
      ),
      style: const TextStyle(fontSize: 14),
      textAlign: TextAlign.right,
      onSubmitted: (text) {
        if (text.trim().isNotEmpty && wordIndex != null) {
          setState(() {
            if (!_currentAlternatives.contains(text.trim())) {
              _currentAlternatives.add(text.trim());
            }
          });
          if (!widget.tab.alternativeWords.containsKey(wordIndex)) {
            widget.tab.alternativeWords[wordIndex] = [];
          }
          if (!widget.tab.alternativeWords[wordIndex]!.contains(text.trim())) {
            widget.tab.alternativeWords[wordIndex]!.add(text.trim());
          }
          widget.tab.alternativeWordsChanged.value++;
          _alternativeWordController.clear();
        } else {
          _performSearch();
        }
      },
    );
  }

  Widget _buildAlternativeWordsList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 100),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _currentAlternatives.length,
        itemBuilder: (context, index) {
          return ListTile(
            dense: true,
            title: Text(
              _currentAlternatives[index],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14),
            ),
            trailing: IconButton(
              icon: const Icon(FluentIcons.delete_24_regular, size: 18),
              onPressed: () {
                final wordIndex = _getCurrentWordIndex();
                if (wordIndex != null) {
                  setState(() {
                    final word = _currentAlternatives[index];
                    _currentAlternatives.removeAt(index);
                    widget.tab.alternativeWords[wordIndex]?.remove(word);
                    widget.tab.alternativeWordsChanged.value++;
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildCheckboxGrid(bool isEnabled, String? currentWord, int? wordIndex) {
    const List<String> options = [
      'קידומות דקדוקיות',
      'סיומות דקדוקיות',
      'קידומות',
      'סיומות',
      'כתיב מלא/חסר',
      'חלק ממילה',
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: options.map((option) {
        bool isChecked = false;

        if (isEnabled && currentWord != null && wordIndex != null) {
          final key = '${currentWord}_$wordIndex';
          isChecked = widget.tab.searchOptions[key]?[option] ?? false;
        }

        return SizedBox(
          width: 180,
          child: Opacity(
            opacity: isEnabled ? 1.0 : 0.5,
            child: InkWell(
              onTap: isEnabled
                  ? () {
                      if (currentWord != null && wordIndex != null) {
                        setState(() {
                          final key = '${currentWord}_$wordIndex';
                          if (!widget.tab.searchOptions.containsKey(key)) {
                            widget.tab.searchOptions[key] = {};
                          }
                          widget.tab.searchOptions[key]![option] = !isChecked;
                          widget.tab.searchOptionsChanged.value++;
                        });
                      }
                    }
                  : null,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isEnabled && isChecked
                              ? Theme.of(context).primaryColor
                              : Colors.grey.shade600,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(3),
                        color: isEnabled && isChecked
                            ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                            : Colors.transparent,
                      ),
                      child: isEnabled && isChecked
                          ? Icon(
                              FluentIcons.checkmark_24_regular,
                              size: 14,
                              color: Theme.of(context).primaryColor,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(
                          fontSize: 14,
                          color: isEnabled
                              ? Theme.of(context).textTheme.bodyMedium?.color
                              : Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
