import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

/// ווידג'ט לניהול אפשרויות חיפוש מתקדמות לכל מילה בנפרד.
/// מחליף את שכפול הקוד בין SearchDialog ל-SearchEditPanel.
class AdvancedSearchControls extends StatefulWidget {
  final SearchingTab tab;
  final bool compactMode;
  final VoidCallback? onEmptySubmit;
  final ValueNotifier<bool>? inputFocusNotifier;

  const AdvancedSearchControls({
    super.key,
    required this.tab,
    this.compactMode = false,
    this.onEmptySubmit,
    this.inputFocusNotifier,
  });

  @override
  State<AdvancedSearchControls> createState() => _AdvancedSearchControlsState();
}

class _AdvancedSearchControlsState extends State<AdvancedSearchControls> {
  final TextEditingController _alternativeWordController =
      TextEditingController();
  final Map<String, TextEditingController> _spacingControllers = {};
  final Map<String, FocusNode> _spacingFocusNodes = {};
  final FocusNode _alternativeWordFocusNode = FocusNode();
  final List<String> _currentAlternatives = [];

  String? _currentWord;
  int? _wordIndex;
  List<String> _words = [];

  @override
  void initState() {
    super.initState();
    widget.tab.queryController.addListener(_onQueryChanged);
    widget.tab.searchFieldFocusNode.addListener(_onFocusChanged);
    _alternativeWordFocusNode.addListener(_updateInputFocusState);
    _analyzeCurrentWord();
  }

  @override
  void dispose() {
    widget.tab.queryController.removeListener(_onQueryChanged);
    widget.tab.searchFieldFocusNode.removeListener(_onFocusChanged);
    _alternativeWordFocusNode.removeListener(_updateInputFocusState);
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

  void _onQueryChanged() {
    if (mounted) _analyzeCurrentWord();
  }

  void _onFocusChanged() {
    if (mounted) _analyzeCurrentWord();
  }

  void _updateInputFocusState() {
    if (widget.inputFocusNotifier == null) return;
    final hasSpacingFocus =
        _spacingFocusNodes.values.any((node) => node.hasFocus);
    widget.inputFocusNotifier!.value =
        _alternativeWordFocusNode.hasFocus || hasSpacingFocus;
  }

  void _analyzeCurrentWord() {
    final text = widget.tab.queryController.text;
    final selection = widget.tab.queryController.selection;

    if (text.isEmpty || selection.baseOffset < 0) {
      if (_currentWord != null) {
        setState(() {
          _currentWord = null;
          _wordIndex = null;
          _currentAlternatives.clear();
        });
      }
      return;
    }

    final words = text.trim().split(RegExp(r'\s+'));
    _words = words;

    int currentPos = 0;
    int? foundIndex;
    String? foundWord;

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isEmpty) continue;

      final wordStart = text.indexOf(word, currentPos);
      if (wordStart == -1) continue;
      final wordEnd = wordStart + word.length;

      if (selection.baseOffset >= wordStart &&
          selection.baseOffset <= wordEnd) {
        foundIndex = i;
        foundWord = word;
        break;
      }
      currentPos = wordEnd;
    }

    if (foundIndex != _wordIndex || foundWord != _currentWord) {
      setState(() {
        _wordIndex = foundIndex;
        _currentWord = foundWord;
        _updateLocalStateForWord(foundIndex);
      });
    }
  }

  void _updateLocalStateForWord(int? index) {
    if (index == null) {
      _currentAlternatives.clear();
      return;
    }

    _currentAlternatives.clear();
    final alts = widget.tab.alternativeWords[index];
    if (alts != null) {
      _currentAlternatives.addAll(alts);
    }

    final wordsCount = _words.where((w) => w.isNotEmpty).length;
    if (index < wordsCount - 1) {
      final key = '$index-${index + 1}';
      final spacing = widget.tab.spacingValues[key] ?? '';
      _getSpacingController(index, index + 1).text = spacing;
    }
  }

  TextEditingController _getSpacingController(int leftIndex, int rightIndex) {
    final key = '$leftIndex-$rightIndex';
    return _spacingControllers.putIfAbsent(key, () => TextEditingController());
  }

  FocusNode _getSpacingFocusNode(int leftIndex, int rightIndex) {
    final key = '$leftIndex-$rightIndex';
    return _spacingFocusNodes.putIfAbsent(key, () {
      final node = FocusNode();
      node.addListener(_updateInputFocusState);
      return node;
    });
  }

  void _navigateToWord(int newIndex) {
    if (newIndex < 0 || newIndex >= _words.length) return;

    final text = widget.tab.queryController.text;
    int currentPos = 0;
    for (int i = 0; i < newIndex; i++) {
      final wordStart = text.indexOf(_words[i], currentPos);
      currentPos = wordStart + _words[i].length;
    }

    final targetWordStart = text.indexOf(_words[newIndex], currentPos);
    if (targetWordStart != -1) {
      final newOffset = targetWordStart + (_words[newIndex].length ~/ 2);
      widget.tab.queryController.selection =
          TextSelection.collapsed(offset: newOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = _currentWord != null && _wordIndex != null;

    if (!isEnabled && !widget.compactMode) {
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

    if (widget.compactMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNavigationRow(isEnabled),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isEnabled) ...[
                SizedBox(width: 200, child: _buildInputColumn(isEnabled)),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: _buildCheckboxGrid(isEnabled, compactMode: true),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _buildNavigationRow(isEnabled),
              const SizedBox(height: 16),
              _buildInputColumn(isEnabled),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          flex: 3,
          child: _buildCheckboxGrid(isEnabled, compactMode: false),
        ),
      ],
    );
  }

  Widget _buildNavigationRow(bool isEnabled) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(FluentIcons.chevron_left_24_regular),
          onPressed: isEnabled && _wordIndex! > 0
              ? () => _navigateToWord(_wordIndex! - 1)
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
            isEnabled ? _currentWord! : 'בחר מילה',
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
          onPressed: isEnabled && _wordIndex! < _words.length - 1
              ? () => _navigateToWord(_wordIndex! + 1)
              : null,
          tooltip: 'מילה הבאה',
        ),
      ],
    );
  }

  Widget _buildInputColumn(bool isEnabled) {
    final spacingController = _wordIndex != null
        ? _getSpacingController(_wordIndex!, _wordIndex! + 1)
        : null;

    return Column(
      children: [
        Opacity(
          opacity: isEnabled ? 1.0 : 0.5,
          child: RtlTextField(
            enabled: isEnabled,
            controller: spacingController,
            focusNode: isEnabled && _wordIndex != null
                ? _getSpacingFocusNode(_wordIndex!, _wordIndex! + 1)
                : null,
            decoration: InputDecoration(
              labelText: 'מרווח למילה הבאה',
              hintText: '0-30',
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              suffixIcon: IconButton(
                icon: const Icon(FluentIcons.dismiss_24_regular, size: 20),
                onPressed: isEnabled && _wordIndex != null
                    ? () {
                        final key = '${_wordIndex!}-${_wordIndex! + 1}';
                        widget.tab.spacingValues.remove(key);
                        widget.tab.spacingValuesChanged.value++;
                        _getSpacingController(_wordIndex!, _wordIndex! + 1)
                            .clear();
                      }
                    : null,
              ),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              FilteringTextInputFormatter.allow(
                RegExp(r'^([0-9]|[12][0-9]|30)$'),
              ),
            ],
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.right,
            onChanged: (text) {
              if (isEnabled && _wordIndex != null && text.trim().isNotEmpty) {
                final key = '${_wordIndex!}-${_wordIndex! + 1}';
                widget.tab.spacingValues[key] = text.trim();
                widget.tab.spacingValuesChanged.value++;
              }
            },
            onSubmitted: (text) {
              if (text.trim().isNotEmpty && _wordIndex != null) {
                final key = '${_wordIndex!}-${_wordIndex! + 1}';
                widget.tab.spacingValues[key] = text.trim();
                widget.tab.spacingValuesChanged.value++;
              } else {
                widget.onEmptySubmit?.call();
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        RtlTextField(
          controller: _alternativeWordController,
          focusNode: _alternativeWordFocusNode,
          enabled: isEnabled,
          decoration: InputDecoration(
            labelText: 'מילה חילופית',
            hintText: 'הקלד מילה...',
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            prefixIcon: IconButton(
              icon: const Icon(FluentIcons.add_24_regular, size: 20),
              onPressed: isEnabled ? _addAlternative : null,
            ),
          ),
          style: const TextStyle(fontSize: 14),
          textAlign: TextAlign.right,
          onSubmitted: (text) {
            if (text.trim().isNotEmpty) {
              _addAlternative();
            } else {
              widget.onEmptySubmit?.call();
            }
          },
        ),
        if (_currentAlternatives.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildAlternativeWordsList(),
        ]
      ],
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
              onPressed: () => _removeAlternative(index),
            ),
          );
        },
      ),
    );
  }

  void _addAlternative() {
    final text = _alternativeWordController.text.trim();
    if (text.isEmpty || _wordIndex == null) return;

    setState(() {
      if (!_currentAlternatives.contains(text)) {
        _currentAlternatives.add(text);
      }
    });

    widget.tab.alternativeWords.putIfAbsent(_wordIndex!, () => []);
    if (!widget.tab.alternativeWords[_wordIndex!]!.contains(text)) {
      widget.tab.alternativeWords[_wordIndex!]!.add(text);
    }
    widget.tab.alternativeWordsChanged.value++;
    _alternativeWordController.clear();
  }

  void _removeAlternative(int index) {
    if (_wordIndex == null) return;
    final word = _currentAlternatives[index];

    setState(() {
      _currentAlternatives.removeAt(index);
    });

    widget.tab.alternativeWords[_wordIndex!]?.remove(word);
    if (widget.tab.alternativeWords[_wordIndex!]?.isEmpty ?? false) {
      widget.tab.alternativeWords.remove(_wordIndex!);
    }
    widget.tab.alternativeWordsChanged.value++;
  }

  Widget _buildCheckboxGrid(bool isEnabled, {required bool compactMode}) {
    const List<String> options = [
      'קידומות דקדוקיות',
      'סיומות דקדוקיות',
      'קידומות',
      'סיומות',
      'כתיב מלא/חסר',
      'חלק ממילה',
    ];

    Widget buildCheckbox(String option) {
      bool isChecked = false;
      if (isEnabled) {
        final key = '${_currentWord}_$_wordIndex';
        isChecked = widget.tab.searchOptions[key]?[option] ?? false;
      }

      return Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: InkWell(
          onTap: isEnabled
              ? () {
                  final key = '${_currentWord}_$_wordIndex';
                  setState(() {
                    widget.tab.searchOptions.putIfAbsent(key, () => {});
                    widget.tab.searchOptions[key]![option] = !isChecked;
                  });
                  widget.tab.searchOptionsChanged.value++;
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
      );
    }

    if (!compactMode) {
      return Wrap(
        spacing: 16,
        runSpacing: 8,
        children: options
            .map((option) => SizedBox(width: 180, child: buildCheckbox(option)))
            .toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSingleColumn = constraints.maxWidth < 600;

        if (useSingleColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: options.map(buildCheckbox).toList(),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: buildCheckbox(options[0])),
                const SizedBox(width: 8),
                Expanded(child: buildCheckbox(options[1])),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: buildCheckbox(options[2])),
                const SizedBox(width: 8),
                Expanded(child: buildCheckbox(options[3])),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: buildCheckbox(options[4])),
                const SizedBox(width: 8),
                Expanded(child: buildCheckbox(options[5])),
              ],
            ),
          ],
        );
      },
    );
  }
}
