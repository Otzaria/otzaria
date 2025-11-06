import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'measurement_data.dart';

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
  String _selectedCategory = 'אורך';
  String? _selectedFromUnit;
  String? _selectedToUnit;
  String? _selectedOpinion;
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _resultController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final FocusNode _screenFocusNode = FocusNode();
  bool _showResultField = false;

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
    _resetDropdowns();
  }

  @override
  void dispose() {
    _inputFocusNode.dispose();
    _screenFocusNode.dispose();
    super.dispose();
  }

  void _resetDropdowns() {
    setState(() {
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

      // Restore remembered input value or clear
      _inputController.text = _rememberedInputValues[_selectedCategory] ?? '';
      _resultController.clear();

      // Update result field visibility based on input
      _showResultField = _inputController.text.isNotEmpty;

      // Convert if there's a remembered input value
      if (_rememberedInputValues[_selectedCategory] != null &&
          _rememberedInputValues[_selectedCategory]!.isNotEmpty) {
        _convert();
      }
    });
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
    return Scaffold(
      body: Focus(
        focusNode: _screenFocusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final String character = event.character ?? '';

            // Check if the pressed key is a number or decimal point
            if (RegExp(r'[0-9.]').hasMatch(character)) {
              // Auto-focus the input field and add the character
              if (!_inputFocusNode.hasFocus) {
                _inputFocusNode.requestFocus();
                // Add the typed character to the input field
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final currentText = _inputController.text;
                  final newText = currentText + character;
                  _inputController.text = newText;
                  _inputController.selection = TextSelection.fromPosition(
                    TextPosition(offset: newText.length),
                  );
                  setState(() {
                    _showResultField = newText.isNotEmpty;
                  });
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
                    String newText;
                    if (event.logicalKey == LogicalKeyboardKey.backspace) {
                      // Remove last character
                      newText =
                          currentText.substring(0, currentText.length - 1);
                    } else {
                      // Delete key - remove first character (or handle as backspace for simplicity)
                      newText =
                          currentText.substring(0, currentText.length - 1);
                    }
                    _inputController.text = newText;
                    _inputController.selection = TextSelection.fromPosition(
                      TextPosition(offset: newText.length),
                    );
                    setState(() {
                      _showResultField = newText.isNotEmpty;
                    });
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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCategorySelector(),
              const SizedBox(height: 20),
              Expanded(
                child: _buildMainContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

  Widget _buildCategorySelector() {
    final categories = ['אורך', 'שטח', 'נפח', 'משקל', 'זמן'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double cardWidth = 140.0;
          const double spacing = 12.0;
          
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            alignment: WrapAlignment.center,
            children: categories
                .map((category) => _buildCategoryCard(category, cardWidth))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildCategoryCard(String category, double width) {
    final isSelected = _selectedCategory == category;
    final icon = _getCategoryIcon(category);

    return GestureDetector(
      onTap: () {
        if (category != _selectedCategory) {
          _saveCurrentSelections();
          setState(() {
            _selectedCategory = category;
            _resetDropdowns();
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _screenFocusNode.requestFocus();
          });
        }
      },
      child: Container(
        width: width,
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              category,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 16.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final screenWidth = MediaQuery.of(context).size.width;
    final fieldWidth = (screenWidth * 0.2).clamp(250.0, 450.0);
    
    return Center(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Right side - Unit columns (narrow and tall)
          _buildUnitColumns(),
          SizedBox(width: (screenWidth * 0.03).clamp(30.0, 60.0)),
          // Left side - Opinion selector and input fields (aligned to top)
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

  Widget _buildUnitColumns() {
    final units = _units[_selectedCategory]!;
    final modernUnits = _getModernUnitsForCategory(_selectedCategory);
    final ancientUnits = units.where((unit) => !modernUnits.contains(unit)).toList();

    // Calculate dynamic sizes based on available space
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final columnHeight = (screenHeight * 0.65).clamp(450.0, 900.0);
    final columnWidth = (screenWidth * 0.18).clamp(240.0, 450.0);
    final iconSize = (screenWidth * 0.025).clamp(32.0, 48.0);
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // From column
        Container(
          width: columnWidth,
          height: columnHeight,
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _buildVerticalUnitList(ancientUnits, modernUnits, _selectedFromUnit, (val) {
            setState(() => _selectedFromUnit = val);
            _rememberedFromUnits[_selectedCategory] = val!;
            _convert();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _screenFocusNode.requestFocus();
            });
          }),
        ),
        // Swap icon
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
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _screenFocusNode.requestFocus();
              });
            },
            tooltip: 'החלף מידות',
          ),
        ),
        // To column
        Container(
          width: columnWidth,
          height: columnHeight,
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _buildVerticalUnitList(ancientUnits, modernUnits, _selectedToUnit, (val) {
            setState(() => _selectedToUnit = val);
            _rememberedToUnits[_selectedCategory] = val!;
            _convert();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _screenFocusNode.requestFocus();
            });
          }),
        ),
      ],
    );
  }

  Widget _buildVerticalUnitList(
    List<String> ancientUnits,
    List<String> modernUnits,
    String? selectedValue,
    ValueChanged<String?> onChanged,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8.0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ancient units column (right)
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ancientUnits.isNotEmpty) ...[
                    Text(
                      'חז"ל',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    ...ancientUnits.map((unit) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: _buildVerticalUnitButton(unit, selectedValue == unit, onChanged),
                    )),
                  ],
                ],
              ),
            ),
            // Divider between columns
            if (ancientUnits.isNotEmpty && modernUnits.isNotEmpty)
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            // Modern units column (left)
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (modernUnits.isNotEmpty) ...[
                    Text(
                      'זמנינו',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    ...modernUnits.map((unit) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: _buildVerticalUnitButton(unit, selectedValue == unit, onChanged),
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

  Widget _buildVerticalUnitButton(
    String unit,
    bool isSelected,
    ValueChanged<String?> onChanged,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontSize = (screenWidth * 0.009).clamp(13.0, 16.0);
    final padding = (screenWidth * 0.006).clamp(8.0, 12.0);
    
    return GestureDetector(
      onTap: () => onChanged(unit),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Text(
          unit,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: fontSize,
          ),
        ),
      ),
    );
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

  // A map to easily check if a unit is modern
  final Map<String, List<String>> _modernUnits = {
    'אורך': modernLengthUnits,
    'שטח': modernAreaUnits,
    'נפח': modernVolumeUnits,
    'משקל': modernWeightUnits,
    'זמן': modernTimeUnits,
  };

  Widget _buildOpinionDropdown() {
    final opinions = _opinions[_selectedCategory]!;
    final isEnabled = _shouldShowOpinionSelector();

    return DropdownButtonFormField<String>(
      initialValue: _selectedOpinion,
      decoration: InputDecoration(
        labelText: 'שיטה',
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
        enabled: isEnabled,
      ),
      isExpanded: true,
      items: opinions.map((opinion) {
        return DropdownMenuItem<String>(
          value: opinion,
          child: Text(
            opinion,
            style: const TextStyle(fontSize: 14.0),
          ),
        );
      }).toList(),
      onChanged: isEnabled ? (value) {
        setState(() {
          _selectedOpinion = value;
          if (value != null) {
            _rememberedOpinions[_selectedCategory] = value;
          }
          _convert();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _screenFocusNode.requestFocus();
        });
      } : null,
    );
  }

  Widget _buildInputField() {
    return TextField(
      controller: _inputController,
      focusNode: _inputFocusNode,
      style: const TextStyle(fontSize: 16.0),
      decoration: InputDecoration(
        labelText: 'ערך להמרה',
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
        suffixIcon: _inputController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(FluentIcons.dismiss_24_regular),
                onPressed: () {
                  setState(() {
                    _inputController.clear();
                    _showResultField = false;
                    _resultController.clear();
                    _rememberedInputValues.remove(_selectedCategory);
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _screenFocusNode.requestFocus();
                  });
                },
              )
            : null,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      onChanged: (value) {
        setState(() {
          _showResultField = value.isNotEmpty;
        });

        if (value.isNotEmpty) {
          _rememberedInputValues[_selectedCategory] = value;
        } else {
          _rememberedInputValues.remove(_selectedCategory);
        }
        _convert();
      },
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );
  }

  Widget _buildResultDisplay() {
    return TextField(
      controller: _resultController,
      readOnly: true,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      decoration: const InputDecoration(
        labelText: 'תוצאה',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );
  }
}
