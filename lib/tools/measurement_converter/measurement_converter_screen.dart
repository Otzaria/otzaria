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
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tools/measurement_converter/measurement_data.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_logic.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/app_menu.dart';
import 'package:otzaria/widgets/app_top_bar.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/widgets/sidebar_nav_item.dart';
import 'package:otzaria/widgets/inputs/app_input_tokens.dart';
import 'package:otzaria/widgets/adaptive_side_pane.dart';

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
  // sidebar state: wide=toggle, narrow=auto panel
  // sidebar state: wide=toggle, narrow=auto panel
  bool _sidebarVisible = true;
  bool _narrowShowCategories = false;
  double _categoriesPaneWidth = 170.0;

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
        if (_inputController.text.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_inputFocusNode.hasFocus) return;
            _inputController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _inputController.text.length,
            );
          });
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusInputField());
  }

  /// מבקש פוקוס למסך המרת המידות.
  void requestKeyboardFocus() {
    _focusInputField();
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

  void _focusInputField() {
    if (!mounted || !_inputFocusNode.canRequestFocus) return;
    requestFocusIfNeeded(_inputFocusNode);
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════════

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
                  // גובה, פונט ורדיוס תלויים במצב קומפקטי — משתמשים ב-AppInputTokens
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
                  return _buildAdaptiveContent(
                    bgColor,
                    isWide: isWide,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

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
      paneColor: AppSurfaces.solidPanelBackground(context),
      isResizable: true,
      minPaneWidth: 150,
      maxPaneWidth: 280,
      onPaneWidthChanged: (nextWidth) {
        setState(() {
          _categoriesPaneWidth = nextWidth;
        });
      },
      wrapPaneInFloatingPanel: false,
      mainContent: isWide
          ? Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMD),
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
      widePaneBuilder: (context, paneContent, paneWidth) => Container(
        width: paneWidth,
        color: AppSurfaces.solidPanelBackground(context),
        child: paneContent,
      ),
      narrowPaneBuilder: (context, paneContent) => Material(
        color: AppSurfaces.solidPanelBackground(context),
        child: SafeArea(child: paneContent),
      ),
    );
  }

  Widget _buildCategoriesPane(
    Color bgColor, {
    required bool closeOnSelect,
  }) {
    return Container(
      color: bgColor,
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
                if (cat != _selectedCategory) {
                  _saveCurrentSelections();
                  setState(() {
                    _selectedCategory = cat;
                    if (closeOnSelect) {
                      _narrowShowCategories = false;
                    }
                    _resetDropdowns();
                  });
                } else if (closeOnSelect) {
                  setState(() => _narrowShowCategories = false);
                }
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

  // ── עמודות יחידות (wide) ────────────────────────────────────────────────────
  Widget _buildUnitColumns() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
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
        Flexible(
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
        setState(() {});
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
          setState(() {});
          _convert();
        }
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
