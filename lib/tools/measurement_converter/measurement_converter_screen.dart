// lib/tools/measurement_converter/measurement_converter_screen.dart
//
// שינויים עיצוביים (מ-PR mdb2-devsh):
//  • ניווט קטגוריות: AppTopBar + AdaptiveSidePane + SidebarNavItem (במקום כרטיסים עליונים)
//  • יחידות: כרטיסי chip (במקום רשימות אנכיות/אופקיות)
//  • שדות קלט ותוצאה: בסרגל העליון (AppTopBar)
//  • UiSnack להעתקה, CallbackShortcuts לקיצור Ctrl+F

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'measurement_data.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/navigation/sidebar_nav_item.dart';
import 'package:otzaria/widgets/inputs/app_input_tokens.dart';
import 'package:otzaria/core/ui_snack.dart';

// START OF ADDITIONS - MODERN UNITS
const List<String> modernLengthUnits = ['מ"מ', 'ס"מ', 'מטר', 'ק"מ'];
const List<String> modernAreaUnits = ['ס"מ רבוע', 'מ"ר', 'ק"מ רבוע', 'דונם'];
const List<String> modernVolumeUnits = [
  'מ"מ מעוקב',
  'ס"מ מעוקב',
  'סמ"ק',
  'מ"ל',
  'ליטר',
  'מטר מעוקב',
  'קוב'
];
const List<String> modernWeightUnits = ['מ"ג', 'גרם', 'ק"ג', 'טון'];
const List<String> modernTimeUnits = ['שניות', 'חלקים', 'דקות', 'שעות', 'ימים'];

// Basic ancient time units (first row)
const List<String> basicAncientTimeUnits = [
  'הילוך אמה',
  'הילוך מיל',
  'הילוך פרסה'
];

// Complex ancient time units (second row) - ordered by size
const List<String> complexAncientTimeUnits = [
  'הילוך ארבע אמות',
  'הילוך מאה אמה',
  'הילוך שלושה רבעי מיל',
  'הילוך ארבעה מילים',
  'הילוך עשרה פרסאות'
];
// END OF ADDITIONS

class MeasurementConverterScreen extends StatefulWidget {
  const MeasurementConverterScreen({super.key});

  @override
  State<MeasurementConverterScreen> createState() =>
      _MeasurementConverterScreenState();
}

class _MeasurementConverterScreenState
    extends State<MeasurementConverterScreen> {
  static const _categories = ['אורך', 'שטח', 'נפח', 'משקל', 'זמן'];

  String _selectedCategory = 'אורך';
  String? _selectedFromUnit;
  String? _selectedToUnit;
  String? _selectedOpinion;
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _resultController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final FocusNode _screenFocusNode = FocusNode();

  // sidebar state: wide=toggle, narrow=auto panel
  bool _sidebarVisible = true;
  bool _narrowShowCategories = false;
  double _categoriesPaneWidth = 170.0;

  // Maps to remember user selections for each category
  final Map<String, String> _rememberedFromUnits = {};
  final Map<String, String> _rememberedToUnits = {};
  final Map<String, String> _rememberedOpinions = {};
  final Map<String, String> _rememberedInputValues = {};

  // Updated to include modern units
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

  @override
  void initState() {
    super.initState();
    _restoreSelectionsForCurrentCategory();
    if (_inputController.text.isNotEmpty) {
      _convert();
    }
  }

  void requestKeyboardFocus() {
    if (!_screenFocusNode.canRequestFocus) return;
    _screenFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _resultController.dispose();
    _inputFocusNode.dispose();
    _screenFocusNode.dispose();
    super.dispose();
  }

  void _restoreSelectionsForCurrentCategory() {
    // Restore remembered selections or use defaults
    _selectedFromUnit = _rememberedFromUnits[_selectedCategory] ??
        _units[_selectedCategory]!.first;
    _selectedToUnit = _rememberedToUnits[_selectedCategory] ??
        _units[_selectedCategory]!.first;
    _selectedOpinion = _rememberedOpinions[_selectedCategory] ??
        _opinions[_selectedCategory]?.first;

    // Validate that remembered selections are still valid for current category
    if (!_units[_selectedCategory]!.contains(_selectedFromUnit)) {
      _selectedFromUnit = _units[_selectedCategory]!.first;
    }
    if (!_units[_selectedCategory]!.contains(_selectedToUnit)) {
      _selectedToUnit = _units[_selectedCategory]!.first;
    }
    if (_opinions[_selectedCategory] != null &&
        !_opinions[_selectedCategory]!.contains(_selectedOpinion)) {
      _selectedOpinion = _opinions[_selectedCategory]?.first;
    }

    // Restore remembered input value or use default '1'
    _inputController.text = _rememberedInputValues[_selectedCategory] ?? '1';
    _resultController.clear();
  }

  void _selectCategory(String category, {required bool closeOnSelect}) {
    if (category == _selectedCategory) {
      if (closeOnSelect) {
        setState(() => _narrowShowCategories = false);
      }
      return;
    }

    _saveCurrentSelections();
    setState(() {
      _selectedCategory = category;
      if (closeOnSelect) {
        _narrowShowCategories = false;
      }
      _restoreSelectionsForCurrentCategory();
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
    // Save the current input value
    if (_inputController.text.isNotEmpty) {
      _rememberedInputValues[_selectedCategory] = _inputController.text;
    }
  }

  // Helper function to handle small inconsistencies in unit names
  // e.g., 'אצבעות' vs 'אצבע', 'רביעיות' vs 'רביעית'
  String _normalizeUnitName(String unit) {
    const Map<String, String> normalizationMap = {
      'אצבעות': 'אצבע',
      'טפחים': 'טפח',
      'זרתות': 'זרת',
      'אמות': 'אמה',
      'קנים': 'קנה',
      'מילים': 'מיל',
      'פרסאות': 'פרסה',
      'בית רובע': 'בית רובע',
      'בית קב': 'בית קב',
      'בית סאה': 'בית סאה',
      'בית סאתיים': 'בית סאתיים',
      'בית לתך': 'בית לתך',
      'בית כור': 'בית כור',
      'רביעיות': 'רביעית',
      'לוגים': 'לוג',
      'קבים': 'קב',
      'עשרונות': 'עשרון',
      'הינים': 'הין',
      'סאים': 'סאה',
      'איפות': 'איפה',
      'לתכים': 'לתך',
      'כורים': 'כור',
      'דינרים': 'דינר',
      'שקלים': 'שקל',
      'סלעים': 'סלע',
      'טרטימרים': 'טרטימר',
      'מנים': 'מנה',
      'ככרות': 'כיכר',
      'קנטרים': 'קנטר',
    };
    return normalizationMap[unit] ?? unit;
  }

  // Core logic to get the conversion factor from any unit to a base modern unit
  double? _getFactorToBaseUnit(String category, String unit, String opinion) {
    final normalizedUnit = _normalizeUnitName(unit);

    switch (category) {
      case 'אורך': // Base unit: cm
        if (modernLengthUnits.contains(unit)) {
          if (unit == 'מ"מ') return 0.1;
          if (unit == 'ס"מ') return 1.0;
          if (unit == 'מטר') return 100.0;
          if (unit == 'ק"מ') return 100000.0;
        } else {
          if (opinion.isEmpty) {
            return null; // Opinion required for ancient units
          }
          final value = modernLengthFactors[opinion]![normalizedUnit];
          if (value == null) return null;
          // Units in data are cm, m, km. Convert all to cm.
          if (['קנה', 'מיל'].contains(normalizedUnit)) {
            return value * 100; // m to cm
          }
          if (['פרסה'].contains(normalizedUnit)) {
            return value * 100000; // km to cm
          }
          return value; // Already in cm
        }
        break;
      case 'שטח': // Base unit: m^2
        if (modernAreaUnits.contains(unit)) {
          if (unit == 'ס"מ רבוע') return 0.0001;
          if (unit == 'מ"ר') return 1.0;
          if (unit == 'ק"מ רבוע') return 1000000.0;
          if (unit == 'דונם') return 1000.0;
        } else {
          if (opinion.isEmpty) {
            return null; // Opinion required for ancient units
          }
          final value = modernAreaFactors[opinion]![normalizedUnit];
          if (value == null) return null;
          // Units in data are m^2, dunam. Convert all to m^2
          if (['בית סאתיים', 'בית לתך', 'בית כור'].contains(normalizedUnit) ||
              (opinion == 'חתם סופר' && normalizedUnit == 'בית סאה')) {
            return value * 1000; // dunam to m^2
          }
          return value; // Already in m^2
        }
        break;
      case 'נפח': // Base unit: cm^3
        if (modernVolumeUnits.contains(unit)) {
          if (unit == 'מ"מ מעוקב') return 0.001;
          if (unit == 'ס"מ מעוקב') return 1.0;
          if (unit == 'סמ"ק') return 1.0;
          if (unit == 'מ"ל') return 1.0;
          if (unit == 'ליטר') return 1000.0;
          if (unit == 'מטר מעוקב') return 1000000.0;
          if (unit == 'קוב') return 1000000.0;
        } else {
          if (opinion.isEmpty) {
            return null; // Opinion required for ancient units
          }
          final value = modernVolumeFactors[opinion]![normalizedUnit];
          if (value == null) return null;
          // Units in data are cm^3, L. Convert all to cm^3
          if (['קב', 'עשרון', 'הין', 'סאה', 'איפה', 'לתך', 'כור']
              .contains(normalizedUnit)) {
            return value * 1000; // L to cm^3
          }
          return value; // Already in cm^3
        }
        break;
      case 'משקל': // Base unit: g
        if (modernWeightUnits.contains(unit)) {
          if (unit == 'מ"ג') return 0.001;
          if (unit == 'גרם') return 1.0;
          if (unit == 'ק"ג') return 1000.0;
          if (unit == 'טון') return 1000000.0;
        } else {
          if (opinion.isEmpty) {
            return null; // Opinion required for ancient units
          }
          final value = modernWeightFactors[opinion]![_normalizeUnitName(unit)];
          if (value == null) return null;
          // Units in data are g, kg. Convert all to g
          if (['כיכר', 'קנטר'].contains(normalizedUnit)) {
            return value * 1000; // kg to g
          }
          return value; // Already in g
        }
        break;
      case 'זמן': // Base unit: seconds
        if (modernTimeUnits.contains(unit)) {
          if (unit == 'שניות') return 1.0;
          if (unit == 'חלקים') {
            return 10.0 / 3.0; // 3.333... seconds (3 seconds and 1/3)
          }
          if (unit == 'דקות') return 60.0;
          if (unit == 'שעות') return 3600.0;
          if (unit == 'ימים') return 86400.0;
        } else {
          if (opinion.isEmpty) {
            return null; // Opinion required for ancient units
          }
          final value = modernTimeFactors[opinion]![unit];
          if (value == null) return null;
          return value; // Already in seconds
        }
        break;
    }
    return null;
  }

  void _convert() {
    final double? input = double.tryParse(_inputController.text);
    if (input == null ||
        _selectedFromUnit == null ||
        _selectedToUnit == null ||
        _inputController.text.isEmpty) {
      setState(() {
        _resultController.clear();
      });
      return;
    }

    // Check if both units are ancient
    final modernUnits = _getModernUnitsForCategory(_selectedCategory);
    bool fromIsAncient = !modernUnits.contains(_selectedFromUnit);
    bool toIsAncient = !modernUnits.contains(_selectedToUnit);

    double result = 0.0;

    // ----- CONVERSION LOGIC -----
    if (fromIsAncient && toIsAncient) {
      // Case 1: Ancient to Ancient conversion (doesn't need opinion)
      double conversionFactor = 1.0;
      switch (_selectedCategory) {
        case 'אורך':
          conversionFactor =
              lengthConversionFactors[_selectedFromUnit]![_selectedToUnit]!;
          break;
        case 'שטח':
          conversionFactor =
              areaConversionFactors[_selectedFromUnit]![_selectedToUnit]!;
          break;
        case 'נפח':
          conversionFactor =
              volumeConversionFactors[_selectedFromUnit]![_selectedToUnit]!;
          break;
        case 'משקל':
          conversionFactor =
              weightConversionFactors[_selectedFromUnit]![_selectedToUnit]!;
          break;
        case 'זמן':
          conversionFactor =
              timeConversionFactors[_selectedFromUnit]![_selectedToUnit]!;
          break;
      }
      result = input * conversionFactor;
    } else if (!fromIsAncient && !toIsAncient) {
      // Case 2: Modern to Modern conversion (doesn't need opinion)
      // Convert directly using base unit factors
      final factorFrom =
          _getFactorToBaseUnit(_selectedCategory, _selectedFromUnit!, '');
      final factorTo =
          _getFactorToBaseUnit(_selectedCategory, _selectedToUnit!, '');

      if (factorFrom == null || factorTo == null) {
        _resultController.clear();
        return;
      }

      final valueInBaseUnit = input * factorFrom;
      result = valueInBaseUnit / factorTo;
    } else {
      // Case 3: Conversion between ancient and modern units (requires an opinion)
      if (_selectedOpinion == null) {
        _resultController.text = "נא לבחור שיטה";
        return;
      }

      // Step 1: Convert input from 'FromUnit' to the base unit (e.g., cm for length)
      final factorFrom = _getFactorToBaseUnit(
          _selectedCategory, _selectedFromUnit!, _selectedOpinion!);
      if (factorFrom == null) {
        _resultController.clear();
        return;
      }
      final valueInBaseUnit = input * factorFrom;

      // Step 2: Convert the value from the base unit to the 'ToUnit'
      final factorTo = _getFactorToBaseUnit(
          _selectedCategory, _selectedToUnit!, _selectedOpinion!);
      if (factorTo == null) {
        _resultController.clear();
        return;
      }
      result = valueInBaseUnit / factorTo;
    }

    setState(() {
      if (result.isNaN || result.isInfinite) {
        _resultController.clear();
      } else {
        _resultController.text = result
            .toStringAsFixed(4)
            .replaceAll(RegExp(r'([.]*0+)(?!.*\d)'), '');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = AppSurfaces.panelBackground(context);
    final cs = Theme.of(context).colorScheme;
    final showOpinion = _shouldShowOpinionSelector();
    final hasResult = _resultController.text.isNotEmpty;

    final searchShortcutSetting = context.select(
      (SettingsBloc bloc) =>
          bloc.state.shortcuts['key-shortcut-search-current-window'] ??
          ShortcutValidator
              .defaultShortcuts['key-shortcut-search-current-window'] ??
          'ctrl+f',
    );
    return CallbackShortcuts(
      bindings: {
        ShortcutHelper.activatorFromShortcut(searchShortcutSetting) ??
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _inputFocusNode.requestFocus();
        },
      },
      child: Focus(
        focusNode: _screenFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Column(
          children: [
            BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) => LayoutBuilder(
                builder: (context, barConstraints) {
                  // כשיש מקום מספיק — תוצאה בשורה הראשונה; אחרת — שורה שנייה
                  final singleRow = barConstraints.maxWidth >= 560;
                  final isWideBar = barConstraints.maxWidth >= 700;
                  final isCompact = settingsState.compactMenuMode;
                  final fieldHeight = AppInputTokens.height(isCompact);
                  final fieldFontSize = AppInputTokens.fontSize(isCompact);
                  final fieldRadius = AppInputTokens.radius(isCompact);

                  // סטטוס הסרגל: רחב=_sidebarVisible, צר=_narrowShowCategories
                  final sidebarOpen =
                      isWideBar ? _sidebarVisible : _narrowShowCategories;

                  // ── ווידג'ט תוצאה (משותף לשני המצבים) ──────────────────
                  Widget resultSection({required bool inPrimaryRow}) => Row(
                        mainAxisSize:
                            inPrimaryRow ? MainAxisSize.min : MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (inPrimaryRow)
                            SizedBox(
                              height: 24,
                              child: VerticalDivider(
                                width: AppTokens.spaceMD * 2,
                                thickness: 1,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                          Text('תוצאה',
                              style: _barLabelStyle(cs, muted: !hasResult)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: fieldHeight,
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(alpha: 0.07),
                                borderRadius:
                                    BorderRadius.circular(fieldRadius),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.spaceSM,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    hasResult ? _resultController.text : '—',
                                    textAlign: TextAlign.start,
                                    textDirection: TextDirection.rtl,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: fieldFontSize + 2,
                                      fontWeight: FontWeight.w600,
                                      color: hasResult
                                          ? cs.onSurface
                                          : cs.onSurface
                                              .withValues(alpha: 0.25),
                                      height: 1.0,
                                      leadingDistribution:
                                          TextLeadingDistribution.even,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTokens.spaceSM),
                          AnimatedOpacity(
                            opacity: hasResult ? 1.0 : 0.3,
                            duration: AppTokens.animFast,
                            child: IgnorePointer(
                              ignoring: !hasResult,
                              child: ToolCopyButton(onPressed: _copyResult),
                            ),
                          ),
                        ],
                      );

                  return AppTopBar(
                    leadingItems: [
                      AppTopBarItem(
                        widget: IconButton(
                          icon: AnimatedSwitcher(
                            duration: AppTokens.animFast,
                            transitionBuilder: (child, animation) =>
                                RotationTransition(
                              turns: Tween<double>(begin: 0.5, end: 0.0)
                                  .animate(animation),
                              child: FadeTransition(
                                  opacity: animation, child: child),
                            ),
                            child: Icon(
                              sidebarOpen
                                  ? FluentIcons.panel_right_contract_24_regular
                                  : FluentIcons.panel_right_24_regular,
                              key: ValueKey(sidebarOpen),
                              size: 24,
                            ),
                          ),
                          tooltip:
                              sidebarOpen ? 'הסתר קטגוריות' : 'הצג קטגוריות',
                          onPressed: () => setState(() {
                            if (isWideBar) {
                              _sidebarVisible = !_sidebarVisible;
                            } else {
                              _narrowShowCategories = !_narrowShowCategories;
                            }
                          }),
                          visualDensity: VisualDensity.standard,
                          splashRadius: 22,
                        ),
                      ),
                    ],
                    center: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ── שיטה ──────────────────────────────────────────────
                        AnimatedOpacity(
                          opacity: showOpinion ? 1.0 : 0.35,
                          duration: AppTokens.animFast,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text('שיטה',
                                  style:
                                      _barLabelStyle(cs, muted: !showOpinion)),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 130,
                                child: AppDropdownField<String>(
                                  enabled: showOpinion,
                                  value: _selectedOpinion,
                                  decoration: _barFieldDecoration(cs,
                                      enabled: showOpinion,
                                      isCompact: isCompact),
                                  entries: _opinions[_selectedCategory]!
                                      .map((o) =>
                                          AppMenuEntry(value: o, label: o))
                                      .toList(),
                                  onSelected: showOpinion
                                      ? (value) {
                                          setState(() {
                                            _selectedOpinion = value;
                                            if (value != null) {
                                              _rememberedOpinions[
                                                  _selectedCategory] = value;
                                            }
                                            _convert();
                                          });
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) =>
                                                  _screenFocusNode
                                                      .requestFocus());
                                        }
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppTokens.spaceSM),
                        // ── ערך להמרה ──────────────────────────────────────────
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text('ערך להמרה', style: _barLabelStyle(cs)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: SizedBox(
                                  height: fieldHeight,
                                  child: RtlTextField(
                                    controller: _inputController,
                                    focusNode: _inputFocusNode,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d*')),
                                    ],
                                    onChanged: (value) {
                                      setState(() {});
                                      if (value.isNotEmpty) {
                                        _rememberedInputValues[
                                            _selectedCategory] = value;
                                      } else {
                                        _rememberedInputValues
                                            .remove(_selectedCategory);
                                      }
                                      _convert();
                                    },
                                    onSubmitted: (_) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (mounted &&
                                            _screenFocusNode.canRequestFocus) {
                                          _screenFocusNode.requestFocus();
                                        }
                                      });
                                    },
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: fieldFontSize,
                                      color: cs.onSurface,
                                      height: 1.0,
                                      leadingDistribution:
                                          TextLeadingDistribution.even,
                                    ),
                                    decoration: _barFieldDecoration(cs,
                                            isCompact: isCompact)
                                        .copyWith(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12),
                                      suffixIcon: _inputController
                                              .text.isNotEmpty
                                          ? IconButton(
                                              icon: Icon(
                                                  FluentIcons
                                                      .dismiss_24_regular,
                                                  size: 15,
                                                  color: cs.onSurfaceVariant),
                                              onPressed: () {
                                                setState(() {
                                                  _inputController.clear();
                                                  _resultController.clear();
                                                  _rememberedInputValues.remove(
                                                      _selectedCategory);
                                                });
                                                WidgetsBinding.instance
                                                    .addPostFrameCallback((_) =>
                                                        _screenFocusNode
                                                            .requestFocus());
                                              },
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── תוצאה בשורה הראשונה (רק כשיש מקום) ───────────────
                        if (singleRow)
                          Expanded(child: resultSection(inPrimaryRow: true)),
                      ],
                    ),
                    // ── תוצאה בשורה שנייה (כשאין מקום) ──────────────────────
                    secondaryRow: singleRow
                        ? null
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppTokens.spaceMD, vertical: 6),
                            child: resultSection(inPrimaryRow: false),
                          ),
                  );
                },
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 700;
                  return _buildAdaptiveContent(bgColor, isWide: isWide);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── עיצוב אחיד לשדות הסרגל ──────────────────────────────────────────────
  InputDecoration _barFieldDecoration(
    ColorScheme cs, {
    bool enabled = true,
    bool isCompact = false,
  }) {
    final radius = AppInputTokens.radius(isCompact);
    final noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      filled: true,
      fillColor: cs.onSurface.withValues(
          alpha: enabled
              ? AppInputTokens.unfocusedAlpha
              : AppInputTokens.disabledAlpha),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSM, vertical: 6),
      isDense: true,
      border: noBorder,
      enabledBorder: noBorder,
      disabledBorder: noBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(
          color: cs.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
    );
  }

  TextStyle _barLabelStyle(ColorScheme cs, {bool muted = false}) => TextStyle(
        fontSize: AppTokens.fontSM,
        fontWeight: FontWeight.w500,
        color:
            muted ? cs.onSurface.withValues(alpha: 0.3) : cs.onSurfaceVariant,
      );

  // ── אייקוני קטגוריה ─────────────────────────────────────────────────────
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

  // ── העתקת תוצאה ─────────────────────────────────────────────────────────
  void _copyResult() {
    final text = '${_inputController.text} $_selectedFromUnit = '
        '${_resultController.text} $_selectedToUnit';
    Clipboard.setData(ClipboardData(text: text));
    UiSnack.show(UiSnack.textCopied);
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  אדפטיבי: AdaptiveSidePane
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildAdaptiveContent(Color bgColor, {required bool isWide}) {
    return AdaptiveSidePane(
      isOpen: isWide ? _sidebarVisible : _narrowShowCategories,
      alignment:
          AlignmentDirectional.centerEnd, // ימין בעברית (RTL) - סרגל ניווט
      paneWidth: _categoriesPaneWidth,
      minMainContentWidth: 420,
      onClose: () {
        setState(() {
          if (isWide) {
            _sidebarVisible = false;
          } else {
            _narrowShowCategories = false;
          }
        });
      },
      onOpen: () {
        setState(() {
          if (isWide) {
            _sidebarVisible = true;
          } else {
            _narrowShowCategories = true;
          }
        });
      },
      isResizable: true,
      minPaneWidth: 150,
      maxPaneWidth: 280,
      onPaneWidthChanged: (nextWidth) {
        _categoriesPaneWidth = nextWidth;
      },
      wrapPaneInFloatingPanel: true,
      mainContent: isWide
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.spaceMD),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: _buildUnitColumns(),
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.spaceMD),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildUnitSectionNarrow(),
                ],
              ),
            ),
      paneContent: _buildCategoriesPane(
        bgColor,
        closeOnSelect: !isWide,
      ),
    );
  }

  Widget _buildCategoriesPane(
    Color bgColor, {
    required bool closeOnSelect,
  }) {
    return Container(
      color: AppSurfaces.solidPanelBackground(context),
      padding: const EdgeInsets.symmetric(
        vertical: AppTokens.spaceMD,
        horizontal: AppTokens.spaceSM,
      ),
      child: Column(
        children: _categories.map((cat) {
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXS),
            child: SidebarNavItem(
              icon: _getCategoryIcon(cat),
              iconFilled: _getCategoryIconFilled(cat),
              label: cat,
              isSelected: isSelected,
              onTap: () {
                _selectCategory(cat, closeOnSelect: closeOnSelect);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _screenFocusNode.requestFocus(),
                );
              },
              verticalPadding: 0,
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── עמודות יחידות ────────────────────────────────────────────────────────────
  Widget _buildUnitColumns() {
    final swapButton = IconButton(
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
    );

    final fromCard = _buildUnitCard(
      title: 'המר מ:',
      icon: FluentIcons.arrow_up_24_regular,
      selectedValue: _selectedFromUnit,
      onChanged: (val) {
        setState(() => _selectedFromUnit = val);
        _rememberedFromUnits[_selectedCategory] = val!;
        _convert();
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _screenFocusNode.requestFocus());
      },
    );

    final toCard = _buildUnitCard(
      title: 'המר ל:',
      icon: FluentIcons.arrow_down_24_regular,
      selectedValue: _selectedToUnit,
      onChanged: (val) {
        setState(() => _selectedToUnit = val);
        _rememberedToUnits[_selectedCategory] = val!;
        _convert();
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _screenFocusNode.requestFocus());
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 460;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: fromCard),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSM, vertical: AppTokens.spaceMD),
                child: swapButton,
              ),
              Expanded(child: toCard),
            ],
          );
        } else {
          return Column(
            children: [
              fromCard,
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
                child: Center(child: swapButton),
              ),
              toCard,
            ],
          );
        }
      },
    );
  }

  // ── חלק סרגל (narrow) ──────────────────────────────────────────────────────
  Widget _buildUnitSectionNarrow() {
    final swapButton = IconButton(
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
    );

    final fromCard = _buildUnitCard(
      title: 'המר מ:',
      icon: FluentIcons.arrow_up_24_regular,
      selectedValue: _selectedFromUnit,
      onChanged: (val) {
        setState(() => _selectedFromUnit = val);
        _rememberedFromUnits[_selectedCategory] = val!;
        _convert();
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _screenFocusNode.requestFocus());
      },
    );

    final toCard = _buildUnitCard(
      title: 'המר ל:',
      icon: FluentIcons.arrow_down_24_regular,
      selectedValue: _selectedToUnit,
      onChanged: (val) {
        setState(() => _selectedToUnit = val);
        _rememberedToUnits[_selectedCategory] = val!;
        _convert();
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _screenFocusNode.requestFocus());
      },
    );

    return Column(
      children: [
        fromCard,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
          child: Center(child: swapButton),
        ),
        toCard,
      ],
    );
  }

  // ── כרטיס יחידה ────────────────────────────────────────────────────────────
  Widget _buildUnitCard({
    required String title,
    required IconData icon,
    required String? selectedValue,
    required ValueChanged<String?> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final units = _units[_selectedCategory]!;
    final modernUnits = _getModernUnitsForCategory(_selectedCategory);
    final ancientUnits = units.where((u) => !modernUnits.contains(u)).toList();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMD,
              vertical: AppTokens.spaceSM,
            ),
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
          Padding(
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
                        .map(
                            (u) => _buildChip(u, selectedValue == u, onChanged))
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
                        .map(
                            (u) => _buildChip(u, selectedValue == u, onChanged))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Chip יחידה ──────────────────────────────────────────────────────────────
  Widget _buildChip(
      String unit, bool isSelected, ValueChanged<String?> onChanged) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        onChanged(unit);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _screenFocusNode.requestFocus());
      },
      child: AnimatedContainer(
        duration: AppTokens.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? cs.secondaryContainer : cs.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusSM),
          border: Border.all(
            color: isSelected
                ? cs.secondary
                : cs.outline.withValues(alpha: 0.25),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          unit,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? cs.onSecondaryContainer : cs.onSurface,
          ),
        ),
      ),
    );
  }

  // ── כותרת קבוצה ─────────────────────────────────────────────────────────────
  Widget _sectionLabel(String label) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      label,
      style: TextStyle(
        fontSize: AppTokens.fontSM,
        fontWeight: FontWeight.w600,
        color: cs.onSurface.withValues(alpha: 0.6),
      ),
    );
  }

  // ── לוגיקת הצגת בחירת שיטה ───────────────────────────────────────────────
  bool _shouldShowOpinionSelector() {
    if (!_opinions.containsKey(_selectedCategory) ||
        _opinions[_selectedCategory]!.isEmpty) {
      return false;
    }

    final moderns = _modernUnits[_selectedCategory] ?? [];
    final bool isFromModern = moderns.contains(_selectedFromUnit);
    final bool isToModern = moderns.contains(_selectedToUnit);

    return (isFromModern || isToModern) && !(isFromModern && isToModern);
  }

  List<String> _getModernUnitsForCategory(String category) {
    switch (category) {
      case 'אורך':
        return modernLengthUnits;
      case 'שטח':
        return modernAreaUnits;
      case 'נפח':
        return modernVolumeUnits;
      case 'משקל':
        return modernWeightUnits;
      case 'זמן':
        return modernTimeUnits;
      default:
        return [];
    }
  }

  final Map<String, List<String>> _modernUnits = {
    'אורך': modernLengthUnits,
    'שטח': modernAreaUnits,
    'נפח': modernVolumeUnits,
    'משקל': modernWeightUnits,
    'זמן': modernTimeUnits,
  };

  // ── טיפול במקלדת ────────────────────────────────────────────────────────────
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final String character = event.character ?? '';

      // Check if the pressed key is a number or decimal point
      if (RegExp(r'[0-9.]').hasMatch(character)) {
        // Auto-focus the input field and add the character
        if (!_inputFocusNode.hasFocus) {
          _inputFocusNode.requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final currentText = _inputController.text;
            final newText = currentText + character;
            _inputController.text = newText;
            _inputController.selection = TextSelection.fromPosition(
              TextPosition(offset: newText.length),
            );
            setState(() {});
            _convert();
          });
          return KeyEventResult.handled;
        }
      }
      // Check if the pressed key is a delete/backspace key
      else if (event.logicalKey == LogicalKeyboardKey.backspace ||
          event.logicalKey == LogicalKeyboardKey.delete) {
        // Auto-focus the input field and handle deletion
        if (!_inputFocusNode.hasFocus) {
          _inputFocusNode.requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final currentText = _inputController.text;
            if (currentText.isNotEmpty) {
              final newText = currentText.substring(0, currentText.length - 1);
              _inputController.text = newText;
              _inputController.selection = TextSelection.fromPosition(
                TextPosition(offset: newText.length),
              );
              setState(() {});
              _convert();
            }
          });
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }
}
