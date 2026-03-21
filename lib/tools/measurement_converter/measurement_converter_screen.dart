// lib/tools/measurement_converter/measurement_converter_screen.dart
//
// שינויים מהגרסה הקודמת:
//  • בורר קטגוריות על הצד הימני (sidebar) — רחב (≥700px)
//  • מסך צר (<700): chip-bar גלילה אופקית מעל התוכן
//  • כרטיסי יחידות לבנים (surface) + נבחר = secondaryContainer (כמו SegmentedButtonTile)
//  • כל האזורים משתמשים ב-AppSurfaces.panelBackground
//  • UiSnack להעתקה (לא ScaffoldMessenger ישיר)

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/tools/measurement_converter/measurement_data.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_logic.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/app_menu.dart';
import 'package:otzaria/widgets/sidebar_nav_item.dart';

class MeasurementConverterScreen extends StatefulWidget {
  const MeasurementConverterScreen({super.key});

  @override
  State<MeasurementConverterScreen> createState() =>
      _MeasurementConverterScreenState();
}

class _MeasurementConverterScreenState
    extends State<MeasurementConverterScreen> {
  String _selectedCategory = 'אורך';
  String? _selectedFromUnit;
  String? _selectedToUnit;
  String? _selectedOpinion;

  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _resultController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final FocusNode _screenFocusNode = FocusNode();
  bool _showResultField = false;
  // sidebar state: wide=toggle, narrow=auto panel
  bool _sidebarVisible = true;
  bool _narrowShowCategories = false;

  final Map<String, String> _rememberedFromUnits = {};
  final Map<String, String> _rememberedToUnits = {};
  final Map<String, String> _rememberedOpinions = {};
  final Map<String, String> _rememberedInputValues = {};

  static const List<String> _categories = ['אורך', 'שטח', 'נפח', 'משקל', 'זמן'];

  final Map<String, List<String>> _units = {
    'אורך': lengthConversionFactors.keys.toList()..addAll(modernLengthUnits),
    'שטח': areaConversionFactors.keys.toList()..addAll(modernAreaUnits),
    'נפח': volumeConversionFactors.keys.toList()..addAll(modernVolumeUnits),
    'משקל': weightConversionFactors.keys.toList()..addAll(modernWeightUnits),
    'זמן': [
      ...basicAncientTimeUnits,
      ...complexAncientTimeUnits,
      ...modernTimeUnits
    ],
  };

  final Map<String, List<String>> _opinions = {
    'אורך': modernLengthFactors.keys.toList(),
    'שטח': modernAreaFactors.keys.toList(),
    'נפח': modernVolumeFactors.keys.toList(),
    'משקל': modernWeightFactors.keys.toList(),
    'זמן': modernTimeFactors.keys.toList(),
  };

  final Map<String, List<String>> _modernUnits = {
    'אורך': modernLengthUnits,
    'שטח': modernAreaUnits,
    'נפח': modernVolumeUnits,
    'משקל': modernWeightUnits,
    'זמן': modernTimeUnits,
  };

  @override
  void initState() {
    super.initState();
    _resetDropdowns();
    // Close categories panel when input gets focus (narrow mode)
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus) {
        setState(() => _narrowShowCategories = false);
      }
    });
  }

  /// מבקש פוקוס למסך המרת המידות.
  void requestKeyboardFocus() {
    requestFocusIfNeeded(_screenFocusNode);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _resultController.dispose();
    _inputFocusNode.dispose();
    _screenFocusNode.dispose();
    super.dispose();
  }

  void _resetDropdowns() {
    setState(() {
      _selectedFromUnit = _rememberedFromUnits[_selectedCategory] ??
          _units[_selectedCategory]!.first;
      _selectedToUnit = _rememberedToUnits[_selectedCategory] ??
          _units[_selectedCategory]!.first;
      _selectedOpinion = _rememberedOpinions[_selectedCategory] ??
          _opinions[_selectedCategory]?.first;

      if (!_units[_selectedCategory]!.contains(_selectedFromUnit)) {
        _selectedFromUnit = _units[_selectedCategory]!.first;
      }
      if (!_units[_selectedCategory]!.contains(_selectedToUnit)) {
        _selectedToUnit = _units[_selectedCategory]!.first;
      }
      if (_opinions[_selectedCategory] != null &&
          !_opinions[_selectedCategory]!.contains(_selectedOpinion)) {
        _selectedOpinion = _opinions[_selectedCategory]!.first;
      }
      _inputController.text = _rememberedInputValues[_selectedCategory] ?? '1';
      _resultController.clear();
      _showResultField = _inputController.text.isNotEmpty;
    });
    if (_inputController.text.isNotEmpty) _convert();
  }

  void _saveCurrentSelections() {
    if (_selectedFromUnit != null) {
      _rememberedFromUnits[_selectedCategory] = _selectedFromUnit!;
    }
    if (_selectedToUnit != null) {
      _rememberedToUnits[_selectedCategory] = _selectedToUnit!;
    }
    if (_selectedOpinion != null) {
      _rememberedOpinions[_selectedCategory] = _selectedOpinion!;
    }
  }

  void _convert() {
    final double? input = double.tryParse(_inputController.text);
    if (input == null || _selectedFromUnit == null || _selectedToUnit == null) {
      setState(() => _resultController.clear());
      return;
    }
    final result = MeasurementConverterLogic.convertMeasurement(
      category: _selectedCategory,
      fromUnit: _selectedFromUnit!,
      toUnit: _selectedToUnit!,
      input: input,
      opinion: _selectedOpinion,
      modernUnitsForCategory:
          MeasurementConverterLogic.getModernUnitsForCategory(
              _selectedCategory),
    );
    setState(() => _resultController.text = result ?? '');
  }

  bool _shouldShowOpinionSelector() =>
      MeasurementConverterLogic.shouldShowOpinionSelector(
        category: _selectedCategory,
        fromUnit: _selectedFromUnit,
        toUnit: _selectedToUnit,
        modernUnitsMap: _modernUnits,
        opinionsMap: _opinions,
      );

  IconData _getCategoryIcon(String category) {
    return switch (category) {
      'אורך' => FluentIcons.ruler_24_regular,
      'שטח' => FluentIcons.square_24_regular,
      'נפח' => FluentIcons.cube_24_regular,
      'משקל' => FluentIcons.scales_24_regular,
      'זמן' => FluentIcons.clock_24_regular,
      _ => FluentIcons.apps_24_regular,
    };
  }

  IconData _getCategoryIconFilled(String category) {
    return switch (category) {
      'אורך' => FluentIcons.ruler_24_filled,
      'שטח' => FluentIcons.square_24_filled,
      'נפח' => FluentIcons.cube_24_filled,
      'משקל' => FluentIcons.scales_24_filled,
      'זמן' => FluentIcons.clock_24_filled,
      _ => FluentIcons.apps_24_filled,
    };
  }

  void _copyResult() {
    final text = '${_inputController.text} $_selectedFromUnit = '
        '${_resultController.text} $_selectedToUnit';
    Clipboard.setData(ClipboardData(text: text));
    UiSnack.show(UiSnack.textCopied);
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bgColor = AppSurfaces.panelBackground(context);

    return Focus(
      focusNode: _screenFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;
          return isWide
              ? _buildWide(bgColor, constraints)
              : _buildNarrow(bgColor);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  מסך רחב: תוכן מרכזי + sidebar קטגוריות בימין
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildWide(Color bgColor, BoxConstraints constraints) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Sidebar קטגוריות — ימין (leading ב-RTL) ───────────────────────
        AnimatedSize(
          duration: AppTokens.animNormal,
          curve: Curves.easeInOut,
          child: _sidebarVisible
              ? Container(
                  width: 150,
                  color: bgColor,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTokens.spaceMD,
                    horizontal: AppTokens.spaceSM,
                  ),
                  child: Column(
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppTokens.spaceXS),
                        child: SidebarNavItem(
                          icon: _getCategoryIcon(cat),
                          iconFilled: _getCategoryIconFilled(cat),
                          label: cat,
                          isSelected: isSelected,
                          onTap: () {
                            if (cat != _selectedCategory) {
                              _saveCurrentSelections();
                              setState(() {
                                _selectedCategory = cat;
                                _resetDropdowns();
                              });
                              WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => _screenFocusNode.requestFocus());
                            }
                          },
                          verticalPadding: 0,
                        ),
                      );
                    }).toList(),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        // ── VerticalDivider ────────────────────────────────────────────────
        if (_sidebarVisible)
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: cs.outlineVariant,
          ),
        // ── תוכן מרכזי מוגבל ברוחב ─────────────────────────────────────────
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.spaceMD),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // כפתור לפתיחה/סגירה של ה-sidebar
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: () =>
                            setState(() => _sidebarVisible = !_sidebarVisible),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.spaceMD,
                            vertical: AppTokens.spaceSM,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: AppTokens.animFast,
                              transitionBuilder: (child, animation) {
                                return RotationTransition(
                                  turns: Tween<double>(begin: 0.5, end: 0.0)
                                      .animate(animation),
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                );
                              },
                              child: Icon(
                                _sidebarVisible
                                    ? FluentIcons
                                        .panel_right_contract_24_regular
                                    : FluentIcons.panel_right_24_regular,
                                size: 18,
                                color: cs.onSurface,
                                key: ValueKey(_sidebarVisible),
                              ),
                            ),
                            const SizedBox(width: AppTokens.spaceXS),
                            Text(
                              'קטגוריה - $_selectedCategory',
                              style: TextStyle(
                                fontSize: AppTokens.fontMD,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: _buildUnitColumns()),
                    const SizedBox(height: AppTokens.spaceMD),
                    _buildOpinionDropdown(),
                    const SizedBox(height: AppTokens.spaceMD),
                    _buildInputField(),
                    if (_showResultField) ...[
                      const SizedBox(height: AppTokens.spaceMD),
                      _buildResultDisplay(),
                      const SizedBox(height: AppTokens.spaceSM),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ToolCopyButton(onPressed: _copyResult),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  מסך צר: סרגל צף + תוכן
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNarrow(Color bgColor) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // ── תוכן ראשי ─────────────────────────────────────────────────────
        Column(
          children: [
            // ── שורת כותרת + כפתור קטגוריות ───────────────────────────────
            Container(
              color: bgColor,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMD, vertical: AppTokens.spaceSM),
              child: Row(
                children: [
                  // כפתור פתיחת סרגל צד
                  FilledButton.tonal(
                    onPressed: () => setState(
                        () => _narrowShowCategories = !_narrowShowCategories),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceMD,
                        vertical: AppTokens.spaceSM,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          FluentIcons.panel_right_24_regular,
                          size: 18,
                          color: cs.onSurface,
                        ),
                        const SizedBox(width: AppTokens.spaceXS),
                        Text(
                          'קטגוריה - $_selectedCategory',
                          style: TextStyle(
                            fontSize: AppTokens.fontMD,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── תוכן ───────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTokens.spaceMD),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildUnitSectionNarrow(),
                    const SizedBox(height: AppTokens.spaceMD),
                    _buildOpinionDropdown(),
                    const SizedBox(height: AppTokens.spaceMD),
                    _buildInputField(),
                    if (_showResultField) ...[
                      const SizedBox(height: AppTokens.spaceSM),
                      _buildResultDisplay(),
                      const SizedBox(height: AppTokens.spaceSM),
                      _buildResultRow(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        // ── רקע שקוף לסגירה ───────────────────────────────────────────────
        if (_narrowShowCategories)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _narrowShowCategories = false),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
              ),
            ),
          ),
        // ── סרגל צד צף (כמו במסך רחב) ────────────────────────────────────
        if (_narrowShowCategories)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Material(
              elevation: 16,
              color: bgColor,
              child: Container(
                width: 150,
                color: bgColor,
                padding: const EdgeInsets.symmetric(
                  vertical: AppTokens.spaceMD,
                  horizontal: AppTokens.spaceSM,
                ),
                child: Column(
                  children: _categories.map((cat) {
                    final isSelected = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppTokens.spaceXS),
                      child: SidebarNavItem(
                        icon: _getCategoryIcon(cat),
                        iconFilled: _getCategoryIconFilled(cat),
                        label: cat,
                        isSelected: isSelected,
                        onTap: () {
                          if (cat != _selectedCategory) {
                            _saveCurrentSelections();
                            setState(() {
                              _selectedCategory = cat;
                              _narrowShowCategories = false;
                              _resetDropdowns();
                            });
                          } else {
                            setState(() => _narrowShowCategories = false);
                          }
                        },
                        verticalPadding: 0,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
      ],
    );
  } // ── תצוגת תוצאה פשוטה (narrow) ────────────────────────────────────────────

  Widget _buildResultRow() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMD, vertical: AppTokens.spaceSM),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_inputController.text} $_selectedFromUnit = '
              '${_resultController.text} $_selectedToUnit',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTokens.fontLG,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
          ),
          ToolCopyButton(onPressed: _copyResult),
        ],
      ),
    );
  }

  // ── Dropdown שיטה ──────────────────────────────────────────────────────────
  Widget _buildOpinionDropdown() {
    final cs = Theme.of(context).colorScheme;
    final opinions = _opinions[_selectedCategory]!;
    final isEnabled = _shouldShowOpinionSelector();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'שיטה',
          style: TextStyle(
            fontSize: AppTokens.fontSM,
            color: isEnabled
                ? cs.onSurfaceVariant
                : cs.onSurface.withValues(alpha: 0.3),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        AppDropdownField<String>(
          value: _selectedOpinion,
          decoration: InputDecoration(
            filled: true,
            fillColor: isEnabled
                ? cs.onSurface.withValues(alpha: 0.07)
                : cs.onSurface.withValues(alpha: 0.04),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMD, vertical: AppTokens.spaceSM),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusLG),
              borderSide: BorderSide.none,
            ),
            enabled: isEnabled,
          ),
          entries: opinions
              .map((opinion) => AppMenuEntry(value: opinion, label: opinion))
              .toList(),
          onSelected: isEnabled
              ? (value) {
                  setState(() {
                    _selectedOpinion = value;
                    if (value != null) {
                      _rememberedOpinions[_selectedCategory] = value;
                    }
                    _convert();
                  });
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _screenFocusNode.requestFocus());
                }
              : null,
        ),
      ],
    );
  }

  // ── Input field ────────────────────────────────────────────────────────────
  Widget _buildInputField() {
    return _MeasurementTextField(
      controller: _inputController,
      focusNode: _inputFocusNode,
      labelText: 'ערך להמרה',
      onClear: () {
        setState(() {
          _inputController.clear();
          _showResultField = false;
          _resultController.clear();
          _rememberedInputValues.remove(_selectedCategory);
        });
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _screenFocusNode.requestFocus());
      },
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      onChanged: (value) {
        setState(() => _showResultField = value.isNotEmpty);
        if (value.isNotEmpty) {
          _rememberedInputValues[_selectedCategory] = value;
        } else {
          _rememberedInputValues.remove(_selectedCategory);
        }
        _convert();
      },
    );
  }

  Widget _buildResultDisplay() {
    return _MeasurementTextField(
      controller: _resultController,
      labelText: 'תוצאה',
      enabled: false,
      isResult: true,
    );
  }

  // ── עמודות יחידות (wide) ────────────────────────────────────────────────────
  Widget _buildUnitColumns() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: _buildUnitCard(
              title: 'המר מ:',
              icon: FluentIcons.arrow_up_24_regular,
              selectedValue: _selectedFromUnit,
              onChanged: (val) {
                setState(() => _selectedFromUnit = val);
                _rememberedFromUnits[_selectedCategory] = val!;
                _convert();
                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _screenFocusNode.requestFocus());
              },
            ),
          ),
        ),
        // ── כפתור החלפה ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMD),
          child: IconButton(
            iconSize: 32,
            icon: const Icon(FluentIcons.arrow_swap_24_regular),
            onPressed: () {
              setState(() {
                final temp = _selectedFromUnit;
                _selectedFromUnit = _selectedToUnit;
                _selectedToUnit = temp;
                _convert();
              });
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _screenFocusNode.requestFocus());
            },
            tooltip: 'החלף יחידות',
          ),
        ),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: _buildUnitCard(
              title: 'המר ל:',
              icon: FluentIcons.arrow_down_24_regular,
              selectedValue: _selectedToUnit,
              onChanged: (val) {
                setState(() => _selectedToUnit = val);
                _rememberedToUnits[_selectedCategory] = val!;
                _convert();
                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _screenFocusNode.requestFocus());
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── כרטיס יחידות (white card) ──────────────────────────────────────────────
  Widget _buildUnitCard({
    required String title,
    required IconData icon,
    required String? selectedValue,
    required ValueChanged<String?> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final units = _units[_selectedCategory]!;
    final modernUnits =
        MeasurementConverterLogic.getModernUnitsForCategory(_selectedCategory);
    final ancientUnits = units.where((u) => !modernUnits.contains(u)).toList();

    return Container(
      // ✅ לבן/surface
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // כותרת הכרטיס
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMD, vertical: AppTokens.spaceSM),
            child: Row(
              children: [
                Icon(icon, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTokens.fontMD,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.spaceSM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ancientUnits.isNotEmpty) ...[
                    _sectionLabel('חז"ל'),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: ancientUnits
                          .map((u) =>
                              _buildChip(u, selectedValue == u, onChanged))
                          .toList(),
                    ),
                    const SizedBox(height: AppTokens.spaceSM),
                  ],
                  if (modernUnits.isNotEmpty) ...[
                    _sectionLabel('מודרני'),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: modernUnits
                          .map((u) =>
                              _buildChip(u, selectedValue == u, onChanged))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: AppTokens.fontSM,
        fontWeight: FontWeight.w600,
        color: cs.onSurface.withValues(alpha: 0.55),
      ),
    );
  }

  // ── יחידות narrow ──────────────────────────────────────────────────────────
  Widget _buildUnitSectionNarrow() {
    final units = _units[_selectedCategory]!;
    final modernUnits =
        MeasurementConverterLogic.getModernUnitsForCategory(_selectedCategory);
    final ancientUnits = units.where((u) => !modernUnits.contains(u)).toList();
    final cs = Theme.of(context).colorScheme;

    Widget unitBox({
      required String title,
      required IconData icon,
      required String? selectedValue,
      required ValueChanged<String?> onChanged,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
        padding: const EdgeInsets.all(AppTokens.spaceSM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(title,
                    style: TextStyle(
                      fontSize: AppTokens.fontMD,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    )),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSM),
            if (ancientUnits.isNotEmpty) ...[
              _sectionLabel('חז"ל'),
              const SizedBox(height: 4),
              Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: ancientUnits
                      .map((u) => _buildChip(u, selectedValue == u, onChanged))
                      .toList()),
              const SizedBox(height: AppTokens.spaceSM),
            ],
            if (modernUnits.isNotEmpty) ...[
              _sectionLabel('מודרני'),
              const SizedBox(height: 4),
              Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: modernUnits
                      .map((u) => _buildChip(u, selectedValue == u, onChanged))
                      .toList()),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        unitBox(
          title: 'המר מ:',
          icon: FluentIcons.arrow_up_24_regular,
          selectedValue: _selectedFromUnit,
          onChanged: (val) {
            setState(() => _selectedFromUnit = val);
            _rememberedFromUnits[_selectedCategory] = val!;
            _convert();
          },
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
            child: IconButton(
              icon: const Icon(FluentIcons.arrow_swap_24_regular),
              iconSize: 26,
              onPressed: () {
                setState(() {
                  final temp = _selectedFromUnit;
                  _selectedFromUnit = _selectedToUnit;
                  _selectedToUnit = temp;
                  _convert();
                });
              },
              tooltip: 'החלף יחידות',
            ),
          ),
        ),
        unitBox(
          title: 'המר ל:',
          icon: FluentIcons.arrow_down_24_regular,
          selectedValue: _selectedToUnit,
          onChanged: (val) {
            setState(() => _selectedToUnit = val);
            _rememberedToUnits[_selectedCategory] = val!;
            _convert();
          },
        ),
      ],
    );
  }

  // ── Chip יחידה — secondaryContainer לנבחר ─────────────────────────────────
  Widget _buildChip(
      String unit, bool isSelected, ValueChanged<String?> onChanged) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(unit),
      child: AnimatedContainer(
        duration: AppTokens.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          // ✅ secondaryContainer (כמו SegmentedButtonTile)
          color: isSelected ? cs.secondaryContainer : cs.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusSM),
          border: Border.all(
            color:
                isSelected ? cs.secondary : cs.outline.withValues(alpha: 0.25),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          unit,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? cs.onSecondaryContainer : cs.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ── keyboard handler ────────────────────────────────────────────────────────
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final character = event.character ?? '';
    if (RegExp(r'[0-9.]').hasMatch(character) && !_inputFocusNode.hasFocus) {
      _inputFocusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final newText = _inputController.text + character;
        _inputController.text = newText;
        _inputController.selection =
            TextSelection.fromPosition(TextPosition(offset: newText.length));
        setState(() => _showResultField = newText.isNotEmpty);
        _convert();
      });
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete) &&
        !_inputFocusNode.hasFocus) {
      _inputFocusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final cur = _inputController.text;
        if (cur.isNotEmpty) {
          final newText = cur.substring(0, cur.length - 1);
          _inputController.text = newText;
          _inputController.selection =
              TextSelection.fromPosition(TextPosition(offset: newText.length));
          setState(() => _showResultField = newText.isNotEmpty);
          _convert();
        }
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

// ── CustomSidebarItem ───────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════
//  _MeasurementTextField
// ═══════════════════════════════════════════════════════════════════════════
class _MeasurementTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final FocusNode? focusNode;
  final VoidCallback? onClear;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool isResult;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _MeasurementTextField({
    required this.controller,
    required this.labelText,
    this.focusNode,
    this.onClear,
    this.onChanged,
    this.enabled = true,
    this.isResult = false,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fillColor = enabled
        ? cs.onSurface.withValues(alpha: 0.07)
        : cs.onSurface.withValues(alpha: 0.04);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusLG),
      borderSide: BorderSide.none,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          labelText,
          style: TextStyle(
            fontSize: AppTokens.fontSM,
            color: enabled
                ? cs.onSurfaceVariant
                : cs.onSurface.withValues(alpha: 0.35),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontSize: isResult ? AppTokens.fontXL : AppTokens.fontLG,
            color: enabled ? cs.onSurface : cs.onSurfaceVariant,
            fontWeight: isResult ? FontWeight.w500 : FontWeight.w400,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: fillColor,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMD, vertical: AppTokens.spaceSM),
            isDense: true,
            suffixIcon: (onClear != null && controller.text.isNotEmpty)
                ? IconButton(
                    icon: Icon(FluentIcons.dismiss_24_regular,
                        size: 17, color: cs.onSurfaceVariant),
                    onPressed: onClear,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )
                : null,
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusLG),
              borderSide: BorderSide(color: cs.primary, width: 1.5),
            ),
            disabledBorder: border,
          ),
        ),
      ],
    );
  }
}
