import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'measurement_data.dart';
import 'measurement_converter_logic.dart';
import 'package:otzaria/theme/theme_exports.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  MeasurementConverterScreen
//  lib/tools/measurement/measurement_converter_screen.dart
//
//  • לוגיקת המרה הועברה ל-MeasurementConverterLogic (measurement_converter_logic.dart)
//  • רקע: AppSurfaces.panelBackground — כמו מסך ההגדרות
//  • שדות קלט/פלט: _MeasurementTextField — סגנון גלולה, כמו שורת החיפוש
//  • DropdownButtonFormField לשיטה: InputDecoration אחידה עם AppTokens
//  • ווידג'טים: דרך SettingsCard / custom_ui_components
// ═════════════════════════════════════════════════════════════════════════════

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

  // זכירת בחירות לכל קטגוריה
  final Map<String, String> _rememberedFromUnits = {};
  final Map<String, String> _rememberedToUnits = {};
  final Map<String, String> _rememberedOpinions = {};
  final Map<String, String> _rememberedInputValues = {};

  final Map<String, List<String>> _units = {
    'אורך': lengthConversionFactors.keys.toList()..addAll(modernLengthUnits),
    'שטח': areaConversionFactors.keys.toList()..addAll(modernAreaUnits),
    'נפח': volumeConversionFactors.keys.toList()..addAll(modernVolumeUnits),
    'משקל': weightConversionFactors.keys.toList()..addAll(modernWeightUnits),
    'זמן': [
      ...basicAncientTimeUnits,
      ...complexAncientTimeUnits,
      ...modernTimeUnits,
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
  }

  @override
  void dispose() {
    _inputController.dispose();
    _resultController.dispose();
    _inputFocusNode.dispose();
    _screenFocusNode.dispose();
    super.dispose();
  }

  // ── איפוס dropdowns ──────────────────────────────────────────────────────
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

    if (_inputController.text.isNotEmpty) {
      _convert();
    }
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

  // ── המרה ─────────────────────────────────────────────────────────────────
  void _convert() {
    final double? input = double.tryParse(_inputController.text);
    if (input == null ||
        _selectedFromUnit == null ||
        _selectedToUnit == null ||
        _inputController.text.isEmpty) {
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

    setState(() {
      if (result == null) {
        _resultController.clear();
      } else {
        _resultController.text = result;
      }
    });
  }

  bool _shouldShowOpinionSelector() =>
      MeasurementConverterLogic.shouldShowOpinionSelector(
        category: _selectedCategory,
        fromUnit: _selectedFromUnit,
        toUnit: _selectedToUnit,
        modernUnitsMap: _modernUnits,
        opinionsMap: _opinions,
      );

  List<String> _getModernUnitsForCategory(String category) =>
      MeasurementConverterLogic.getModernUnitsForCategory(category);

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bgColor = AppSurfaces.panelBackground(context);

    return Scaffold(
      backgroundColor: bgColor,
      body: Focus(
        focusNode: _screenFocusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final String character = event.character ?? '';
            if (RegExp(r'[0-9.]').hasMatch(character)) {
              if (!_inputFocusNode.hasFocus) {
                _inputFocusNode.requestFocus();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final newText = _inputController.text + character;
                  _inputController.text = newText;
                  _inputController.selection = TextSelection.fromPosition(
                    TextPosition(offset: newText.length),
                  );
                  setState(() => _showResultField = newText.isNotEmpty);
                  _convert();
                });
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.backspace ||
                event.logicalKey == LogicalKeyboardKey.delete) {
              if (!_inputFocusNode.hasFocus) {
                _inputFocusNode.requestFocus();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final cur = _inputController.text;
                  if (cur.isNotEmpty) {
                    final newText = cur.substring(0, cur.length - 1);
                    _inputController.text = newText;
                    _inputController.selection = TextSelection.fromPosition(
                      TextPosition(offset: newText.length),
                    );
                    setState(() => _showResultField = newText.isNotEmpty);
                    _convert();
                  }
                });
                return KeyEventResult.handled;
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCategorySelector(),
              const SizedBox(height: AppTokens.spaceLG),
              Expanded(child: _buildMainContent()),
            ],
          ),
        ),
      ),
    );
  }

  // ── אייקון קטגוריה ────────────────────────────────────────────────────────
  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'אורך':
        return FluentIcons.ruler_24_regular;
      case 'שטח':
        return FluentIcons.square_24_regular;
      case 'נפח':
        return FluentIcons.cube_24_regular;
      case 'משקל':
        return FluentIcons.scales_24_regular;
      case 'זמן':
        return FluentIcons.clock_24_regular;
      default:
        return FluentIcons.apps_24_regular;
    }
  }

  // ── בורר קטגוריה ─────────────────────────────────────────────────────────
  Widget _buildCategorySelector() {
    const categories = ['אורך', 'שטח', 'נפח', 'משקל', 'זמן'];
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return isSmallScreen
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories
                  .map((cat) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _buildCategoryCard(cat, 110.0),
                      ))
                  .toList(),
            ),
          )
        : Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: categories
                .map((cat) => _buildCategoryCard(cat, 140.0))
                .toList(),
          );
  }

  Widget _buildCategoryCard(String category, double width) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedCategory == category;

    return GestureDetector(
      onTap: () {
        if (category != _selectedCategory) {
          _saveCurrentSelections();
          setState(() {
            _selectedCategory = category;
            _resetDropdowns();
          });
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _screenFocusNode.requestFocus());
        }
      },
      child: Container(
        width: width,
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        decoration: BoxDecoration(
          // צבעי theme — primaryContainer/surface, ללא hard-coded
          color: isSelected ? cs.primaryContainer : cs.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.3),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getCategoryIcon(category),
              size: 40,
              color:
                  isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              category,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: AppTokens.fontMD,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── תוכן ראשי ─────────────────────────────────────────────────────────────
  Widget _buildMainContent() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 800;

    if (isSmallScreen) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildOpinionDropdown(),
            const SizedBox(height: AppTokens.spaceMD),
            _buildInputField(),
            if (_showResultField) ...[
              const SizedBox(height: AppTokens.spaceMD),
              _buildResultDisplay(),
            ],
            const SizedBox(height: AppTokens.spaceLG),
            _buildUnitColumnsSmall(),
          ],
        ),
      );
    }

    final fieldWidth = (screenWidth * 0.2).clamp(250.0, 450.0);

    return Center(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildUnitColumns(),
          SizedBox(width: (screenWidth * 0.03).clamp(30.0, 60.0)),
          SizedBox(
            width: fieldWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildOpinionDropdown(),
                SizedBox(height: (screenWidth * 0.015).clamp(16.0, 24.0)),
                _buildInputField(),
                if (_showResultField) ...[
                  SizedBox(height: (screenWidth * 0.015).clamp(16.0, 24.0)),
                  _buildResultDisplay(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── dropdown שיטה ─────────────────────────────────────────────────────────
  Widget _buildOpinionDropdown() {
    final cs = Theme.of(context).colorScheme;
    final opinions = _opinions[_selectedCategory]!;
    final isEnabled = _shouldShowOpinionSelector();

    // fill כמו שדות הקלט
    final fillColor = cs.onSurface.withValues(alpha: 0.07);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusLG),
      borderSide: BorderSide.none,
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusLG),
      borderSide: BorderSide(color: cs.primary, width: 1.5),
    );

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
        DropdownButtonFormField<String>(
          initialValue: _selectedOpinion,
          decoration: InputDecoration(
            filled: true,
            fillColor:
                isEnabled ? fillColor : cs.onSurface.withValues(alpha: 0.04),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMD,
              vertical: AppTokens.spaceSM,
            ),
            isDense: true,
            border: border,
            enabledBorder: border,
            focusedBorder: focusBorder,
            disabledBorder: border,
            enabled: isEnabled,
          ),
          isExpanded: true,
          style: TextStyle(
            fontSize: AppTokens.fontMD,
            color:
                isEnabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.4),
          ),
          items: opinions.map((opinion) {
            return DropdownMenuItem<String>(
              value: opinion,
              child: Text(opinion),
            );
          }).toList(),
          onChanged: isEnabled
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

  // ── שדה ערך להמרה ─────────────────────────────────────────────────────────
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

  // ── שדה תוצאה ─────────────────────────────────────────────────────────────
  Widget _buildResultDisplay() {
    return _MeasurementTextField(
      controller: _resultController,
      labelText: 'תוצאה',
      enabled: false,
      isResult: true,
    );
  }

  // ── כפתורי יחידות — קטן (mobile) ─────────────────────────────────────────
  Widget _buildUnitColumnsSmall() {
    final cs = Theme.of(context).colorScheme;
    final units = _units[_selectedCategory]!;
    final modernUnits = _getModernUnitsForCategory(_selectedCategory);
    final ancientUnits = units.where((u) => !modernUnits.contains(u)).toList();

    // wrapper בסגנון SettingsCard
    Widget unitBox({
      required IconData icon,
      required String title,
      required String? selectedValue,
      required ValueChanged<String?> onChanged,
    }) {
      return Container(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          border: Border.all(
            color: cs.outline.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: cs.primary),
                const SizedBox(width: 8),
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
            const SizedBox(height: 12),
            _buildHorizontalUnitList(
                ancientUnits, modernUnits, selectedValue, onChanged),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        unitBox(
          icon: FluentIcons.arrow_up_24_regular,
          title: 'המר מ:',
          selectedValue: _selectedFromUnit,
          onChanged: (val) {
            setState(() => _selectedFromUnit = val);
            _rememberedFromUnits[_selectedCategory] = val!;
            _convert();
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: IconButton(
              icon: const Icon(FluentIcons.arrow_swap_24_regular),
              iconSize: 28,
              onPressed: () {
                setState(() {
                  final temp = _selectedFromUnit;
                  _selectedFromUnit = _selectedToUnit;
                  _selectedToUnit = temp;
                  _convert();
                });
              },
              tooltip: 'החלף יחידות',
              style: IconButton.styleFrom(
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
              ),
            ),
          ),
        ),
        unitBox(
          icon: FluentIcons.arrow_down_24_regular,
          title: 'המר ל:',
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

  Widget _buildHorizontalUnitList(
    List<String> ancientUnits,
    List<String> modernUnits,
    String? selectedValue,
    ValueChanged<String?> onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;

    Widget label(String text) => Text(
          text,
          style: TextStyle(
            fontSize: AppTokens.fontSM,
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ancientUnits.isNotEmpty) ...[
          label('חז"ל'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: ancientUnits
                .map((u) => _buildUnitChip(u, selectedValue == u, onChanged))
                .toList(),
          ),
          if (modernUnits.isNotEmpty) const SizedBox(height: 12),
        ],
        if (modernUnits.isNotEmpty) ...[
          label('מודרני'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: modernUnits
                .map((u) => _buildUnitChip(u, selectedValue == u, onChanged))
                .toList(),
          ),
        ],
      ],
    );
  }

  // ── כפתורי יחידות — גדול (desktop) ───────────────────────────────────────
  Widget _buildUnitColumns() {
    final cs = Theme.of(context).colorScheme;
    final units = _units[_selectedCategory]!;
    final modernUnits = _getModernUnitsForCategory(_selectedCategory);
    final ancientUnits = units.where((u) => !modernUnits.contains(u)).toList();

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final columnHeight = (screenHeight * 0.65).clamp(450.0, 900.0);
    final columnWidth = (screenWidth * 0.18).clamp(240.0, 450.0);
    final iconSize = (screenWidth * 0.025).clamp(32.0, 48.0);

    Widget column(
      String? selectedValue,
      ValueChanged<String?> onChanged,
    ) =>
        Container(
          width: columnWidth,
          height: columnHeight,
          decoration: BoxDecoration(
            border: Border.all(
              color: cs.outline.withValues(alpha: 0.25),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(AppTokens.radiusSM),
          ),
          child: _buildVerticalUnitList(
              ancientUnits, modernUnits, selectedValue, onChanged),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        column(_selectedFromUnit, (val) {
          setState(() => _selectedFromUnit = val);
          _rememberedFromUnits[_selectedCategory] = val!;
          _convert();
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _screenFocusNode.requestFocus());
        }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: IconButton(
            iconSize: iconSize,
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
        column(_selectedToUnit, (val) {
          setState(() => _selectedToUnit = val);
          _rememberedToUnits[_selectedCategory] = val!;
          _convert();
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _screenFocusNode.requestFocus());
        }),
      ],
    );
  }

  Widget _buildVerticalUnitList(
    List<String> ancientUnits,
    List<String> modernUnits,
    String? selectedValue,
    ValueChanged<String?> onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;

    Widget sectionLabel(String text) => Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppTokens.fontSM,
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ancientUnits.isNotEmpty) ...[
                    sectionLabel('חז"ל'),
                    const SizedBox(height: 6),
                    ...ancientUnits.map((u) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _buildUnitChip(
                              u, selectedValue == u, onChanged,
                              fullWidth: true),
                        )),
                  ],
                ],
              ),
            ),
            if (ancientUnits.isNotEmpty && modernUnits.isNotEmpty)
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: cs.outline.withValues(alpha: 0.18),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (modernUnits.isNotEmpty) ...[
                    sectionLabel('מודרני'),
                    const SizedBox(height: 6),
                    ...modernUnits.map((u) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _buildUnitChip(
                              u, selectedValue == u, onChanged,
                              fullWidth: true),
                        )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── chip יחידה — משותף לרשימות אופקיות ואנכיות ───────────────────────────
  Widget _buildUnitChip(
    String unit,
    bool isSelected,
    ValueChanged<String?> onChanged, {
    bool fullWidth = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final fontSize = fullWidth ? (screenWidth * 0.009).clamp(13.0, 16.0) : 13.0;
    final pad = fullWidth ? (screenWidth * 0.006).clamp(8.0, 12.0) : 8.0;

    return GestureDetector(
      onTap: () => onChanged(unit),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: fullWidth ? pad : 12, vertical: pad),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : cs.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusSM),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.3),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Text(
          unit,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  _MeasurementTextField — שדה קלט/פלט בסגנון גלולת חיפוש
// ═════════════════════════════════════════════════════════════════════════════
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

    // fill — onSurface alpha, תואם לרקע ההגדרות בבהיר ובכהה
    final fillColor = enabled
        ? cs.onSurface.withValues(alpha: 0.07)
        : cs.onSurface.withValues(alpha: 0.04);

    // border — אותו סגנון כמו שורת החיפוש (ללא border ללא פוקוס)
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusLG), // 16dp
      borderSide: BorderSide.none,
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusLG),
      borderSide: BorderSide(color: cs.primary, width: 1.5),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // תווית מעל השדה — כמו סגנון SettingsCard
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
          // cursorColor — onSurface כהה, לא primary/אדום
          cursorColor: cs.onSurface.withValues(alpha: 0.87),
          style: TextStyle(
            fontSize: isResult ? AppTokens.fontXL : AppTokens.fontLG,
            color: enabled ? cs.onSurface : cs.onSurfaceVariant,
            fontWeight: isResult ? FontWeight.w500 : FontWeight.w400,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: fillColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMD,
              vertical: AppTokens.spaceSM,
            ),
            isDense: true,
            // suffix ✕ — מוצג רק כשיש טקסט ויש onClear
            suffixIcon: (onClear != null && controller.text.isNotEmpty)
                ? IconButton(
                    icon: Icon(
                      FluentIcons.dismiss_24_regular,
                      size: 17,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: onClear,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )
                : null,
            border: border,
            enabledBorder: border,
            focusedBorder: focusedBorder,
            disabledBorder: border,
            errorBorder: border,
            focusedErrorBorder: focusedBorder,
          ),
        ),
      ],
    );
  }
}
