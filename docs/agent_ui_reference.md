# רכיבי ממשק והנחיות יישום לסוכנים

קרא רק את הסעיף שאתה צריך. כללי החובה המקוצרים נמצאים בסעיף "UI rules" ב־`AGENTS.md`, והתקן המלא ב־`docs/design-system/DESIGN_SYSTEM.md` (טוקנים ב־§2, קטלוג הרכיבים ב־§3). כשמשהו כאן סותר את התקן, התקן גובר.

**Imports.** `package:otzaria/widgets/widgets_exports.dart` re-exports the dialogs (with `AppDialogFrame`), `ActionButton`, `AppIconButton`, `BarButton`, `BarSplitButton`, `AppSegmentedControl`, `StatusChip`, `AppCard`, `ExpandableCard`, `OtzariaEmptyState`, `OtzariaErrorState`, `ExpandingChevron` and `AppSectionLabel`. Everything else is imported from its own file, given in each section below.

## 1. Icons

| Does `otzaria_icons` have the icon? | Use |
|---|---|
| Yes | `Icon(OtzariaIcons.…)`, always plain `Icon` |
| No | `fluentui_system_icons`, with `Icon` or `RtlIcon` per the table below |
| Only Material has it | Draw it in `otzaria_icons`. Never import Material or Cupertino icons (UIL-005) |

**What `otzaria_icons` is for.** It is not a general-purpose set. It covers four cases:
1. An icon that breaks when mirrored for RTL.
2. An icon that is always shown in an RTL context, so it is simply drawn that way.
3. An icon Fluent does not have (`lectern`, `torah_scroll`, `calendar_yahrzeit`, the `alef_*` / `beit_*` / `tet_*` families for nikud, punctuation and font settings).
4. An icon whose Fluent form fits a seforim library less well (`book_pdf` for a PDF book rather than a generic document).

Generic chrome (`dismiss`, `delete`, `copy`, `folder`, `settings`, `add`, `edit`) stays on Fluent.

**Deliberate exceptions that stay on Fluent:**

| Case | Icon |
|---|---|
| The seforim library itself | `FluentIcons.library_24_regular/filled` |
| In-book search action (toolbar button, side-panel tab, context-menu `חיפוש`) in the text and PDF readers | `FluentIcons.search_24_regular/filled` |
| Search icon inside a **labeled** button (`חפש`, `פתח חיפוש טקסט`) | `FluentIcons.search_24_regular` |
| A direct link to a book or section (`קישור ישיר`, deep links, inserting a hyperlink) | `FluentIcons.link_24_regular` |
| The 8px private-book badge on a library card | `FluentIcons.person_24_regular` (`OtzariaIcons.person_24_regular` everywhere it renders at 16px or more) |

Links *between* books (the `קישורים` tab and menu entry, `דורות וקישורים`) use `OtzariaIcons.link_24_regular`: singular `קישור` is Fluent, plural `קישורים` is Otzaria.

**Scoped search: pick the icon that names what is searched.** The scoped icons have no `filled` twin, so a selected/unselected pair reuses the glyph and colour carries the state.

| Where | `OtzariaIcons.` |
|---|---|
| Library search, `סינון מפרשים`, `חפש בתוך המפרשים המוצגים`, שמור וזכור | `search_in_library_24_regular` |
| Notes search, calendar `חפש גם בתיאור` | `search_in_document_24_regular` |
| Calendar `חפש רק בכותרת` | `search_in_text_24_regular` |
| `הוסף ספרים למעקב` dialog | `search_in_book_24_regular` |
| Settings search | `search_in_settings_24_regular` |
| `איתור כותרת` boxes, bookmarks search, `חפש בתוך הקישורים המוצגים` | `search_in_titles_24_regular` |
| Gematria search | `search_in_numbered_list_24_regular` |

The navigation rail's `חיפוש` keeps `OtzariaIcons.search_24_regular/filled`: it is the app-wide entry point. Pass the scoped icon through `OtzariaSearchField(icon:)` or `ItemsListView(searchIcon:)`; `OtzariaSearchField(leading:)` replaces the icon instead of styling it.

**Finding an icon.** Open the `index.html` catalog (or `icon_manifest.yaml`) in the pinned `otzaria_icons` checkout; `pubspec.yaml` pins it by commit. Names follow the Fluent convention `<name>_24_<regular|filled>`, so look up the Fluent name first. If an icon from the upstream catalog is missing, the pinned commit predates it. Plugin icon names are resolved only through `pluginIconFromName` in `lib/plugins/utils/plugin_icon_resolver.dart`; `test/plugins/utils/plugin_icon_resolver_usage_test.dart` fails on other calls to `OtzariaIcons.allIcons` or `fluentIconFromName`.

**Sizes.** `_24_` in a name is the drawing grid, not a size limit. The size comes from `AppTokens.iconXS…iconXL` (§10). For an "open book" regular/filled pair (nav rail) use `otzaria_icon_2_page_24_regular/filled`.

### `Icon` or `RtlIcon`

`RtlIcon` (`lib/widgets/misc/rtl_icon.dart`) is not a generic mirror. In LTR, and for any icon declared `matchTextDirection: true`, it draws a plain `Icon`. In RTL it acts only on the icons it registers: an icon in `_fluentMirrorMap` is swapped for its opposite-direction Fluent glyph, and an icon in `_flippableIcons` is flipped geometrically. Any other icon is drawn unchanged.

| Icon | Write |
|---|---|
| Any `OtzariaIcons.…` | `Icon(...)`. `RtlIcon(OtzariaIcons.…)` fails UIL-006 |
| Fluent icon with `matchTextDirection: true` (`chevron_left/right`, `arrow_left/right`, `arrow_previous/next`, `text_align_left/right` and others) | `Icon(<the LTR glyph>)`; Flutter mirrors it. Back = `arrow_left`, next/enter = `chevron_right` |
| Fluent icon registered in `rtl_icon.dart` | `RtlIcon(...)` |
| Any other Fluent icon | `Icon(...)`. UIL-006 rejects `RtlIcon` with an unregistered literal icon |

Some widgets route an `IconData` through `RtlIcon` themselves: `ActionButton(icon:)`, `BarButton.icon(flipInRtl: true)`, `SettingsSliderTile`, and the `rtlIcon:` parameter of the settings tiles and `SegmentOption`. Where a widget offers both, pass `OtzariaIcons` and non-directional icons through `icon:` and only registered directional Fluent icons through `rtlIcon:`.

To mirror a Fluent icon that is not registered, prefer drawing it in `otzaria_icons`; adding it to `_flippableIcons` is the fallback, because a geometric flip also mirrors asymmetric detail. Registered entries with no call site in `lib/` stay: a plugin can still name them.

**Never:**
- Material or Cupertino icons, or any icon font other than `otzaria_icons` and `fluentui_system_icons`.
- `Transform.flip` / `Transform.scale(scaleX: -1)` around an icon. On an `OtzariaIcons` icon it points the wrong way. UIL-006 catches a flip whose direct child is an `Icon`/`RtlIcon`, not one further up the tree, so check the call site when replacing an icon.
- Comments explaining why `Icon` or `RtlIcon` was chosen.
- Editing `lib/plugins/utils/fluent_icon_resolver.dart`: it is the generated Fluent-name map for plugins.

## 2. User messages: `UiSnack`

```dart
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/messages_exports.dart';

UiSnack.show(CommonMessages.savedSuccessfully);
UiSnack.showError(ReportMessages.sendFailed);   // a failure is always showError, never show
UiSnack.showWithAction(message: ..., actionLabel: ..., onAction: _undo);
```

Other entry points: `showSuccess`, `showWarning`, `showQuick`, and `showChecking` with `UiSnack.hide(owner:)` for a message that stays until hidden.

- Every text comes from a catalog in `lib/core/messages/`, one class per domain (`CommonMessages`, `SettingsMessages`, `ToolsMessages`, …). Fixed texts are `static const`, parameterized ones are static functions. A shared text goes into `CommonMessages`. A literal at a `UiSnack` call fails UIL-009.
- A failed operation is `showError` (error tone and icon), a "not found / not possible" is `showWarning`. Neutral `show` is for confirmations and information only.
- Never show `e.toString()` to the user.
- No `ScaffoldMessenger` or `SnackBar` (UIL-008), no toast packages, no dialog for a simple message.
- `UiSnack` is not for critical information: use a dialog or an `AppInfoBanner`.

## 3. Text input, search and choice

```dart
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

RtlTextField(
  controller: _controller,
  decoration: const InputDecoration(labelText: 'שם השולחן'),
  onSubmitted: (_) => _save(),
);
OtzariaSearchField(
  controller: _query,
  hintText: 'חיפוש בהערות',
  icon: OtzariaIcons.search_in_document_24_regular,
);
```

- Raw `TextField` / `TextFormField` / `EditableText` fail UIL-011. The label is `InputDecoration.labelText`, a validation error is `InputDecoration.errorText`; the border comes from the theme.
- A button inside a search field is `OtzariaSearchFieldButton` (`lib/widgets/text/otzaria_search_field_button.dart`). Inside a navigation panel the field is built by `NavPanelCollapsibleSearch` (§12).
- The buttons inside a search field are 26 in a narrow field (36), 32 in a regular one (48) and 40 in a form; this is a permitted exception to the 48 tap target (`DESIGN_SYSTEM.md` §2.5.6). **On touch a narrow field uses 40 (and the field is 40) when there is room:** only if at least 116 px remain for the input after the buttons (`minInputWidthTouchButtons` in `otzaria_search_field.dart`; field width minus the 36 icon and 8 padding, minus 40 per button and 48 for the clear X, which is always counted when there is an `onClear`). Actions shown below the field (`actionsBelow`) are not counted. Otherwise they stay 26. The clear X stays 48 on touch.
- **Fonts on iOS:** `AppFonts.availableFonts` also holds system families marked `FontInfo.displayOnly` (names only, no file; `FontDropdownField` labels them "לתצוגה בלבד" and adds the "הוסף גופן מקובץ…" action row through `FontImportFlow`). A consumer that needs bytes (printing, PDF export, Tikkun, plugins) must use `AppFonts.fontsWithFiles` or `systemFamilyFaces` / `pluginSystemFamilyFaces` (null for such a font), and must not assume every listed font is readable.
- `OtzariaSearchField.compactHintText`: a shortened hint shown when the full `hintText` does not fit the free width of the input. The decision is by **measuring** the real width and text scale, not by a fixed window threshold. In the library the full hint is "איתור ספר או מחבר ב{category}" and the short one "איתור ספר או מחבר"; even the short one is cut in an 80px field (320 on touch), which is accepted.
- One of a list: `AppDropdownField<T>(value:, entries:, onSelected:, decoration:)` (`lib/widgets/misc/app_dropdown_field.dart`). `decoration.labelText` shows above the field; in a toolbar use `semanticLabel:` instead.
- Two to four options: `AppSegmentedControl<T>(options: [SegmentOption(value:, label:)], currentValue:, onChanged:)`.
- Menus: `AppPopupMenuButton` or `showAnchoredAppMenu` (`lib/widgets/misc/app_popup_menu.dart`). Raw `PopupMenuButton`, `showMenu` and `MenuAnchor` fail UIL-014.
- Filter chips: Material `FilterChip` / `ChoiceChip` styled by `chipTheme`, or `FilterChipsSelector` (`lib/widgets/lists/filter_chips_widget.dart`).

## 4. Dialogs

All dialog building blocks live in `lib/widgets/dialogs/`. Every dialog has a header band and an icon badge, including `small`; a `small` dialog has no close X.

| Need | Use | Buttons |
|---|---|---|
| Message that must be read | `showSingleActionDialog` | `recommended` |
| Non-destructive yes/no | `showTwoActionsDialog` | `neutral` cancel + `recommended` confirm (focused) |
| Destructive or irreversible action | `showWarningDialog` (error-tone header, `subtitle:` in `cs.error`) | `recommended` cancel (focused) + `warning` confirm |
| Three or more equal actions | `showChoiceDialog` with `AppDialogChoice(value:, label:, recommended:)` | `neutral` cancel + one button per choice |
| One text field | `showInputDialog` | cancel + confirm, Enter confirms |
| One item from a list | `showSelectionDialog` with `SelectionItem` | — |
| Blocking work longer than ~300ms | `runWithBlockingProgress(context:, title:, task:)` | optional cancel |
| Form, list, tabs or anything custom | `AppDialogFrame(title:, icon:, size:, actions:, child:)` | your `ActionButton`s |

```dart
final ok = await showWarningDialog(
  context: context,
  title: 'איפוס הגדרות',
  content: 'כל ההגדרות יחזרו לברירת המחדל.',
  subtitle: 'לא ניתן לבטל פעולה זו',
  confirmText: 'אפס', // ברירת המחדל היא 'איפוס'; תמיד להעביר
);

showDialogUntilTornDown(
  context: context,
  builder: (_) => AppDialogFrame(
    title: 'ייבוא ספרים',
    icon: FluentIcons.folder_add_24_regular,
    size: AppDialogSize.medium,
    scrollable: true,
    actions: [
      ActionButton.neutral(text: 'ביטול', onPressed: ...),
      ActionButton.recommended(text: 'ייבא', onPressed: ...),
    ],
    child: _form(),
  ),
);
```

- **Size** (`AppDialogSize`): `small` 400 for a question, warning, input or selection; `medium` 560 for a form or a question with 3–4 actions; `large` 720 for lists and management; `full` for print preview. Below 600 the frame adapts by itself.
- **Unsaved changes:** pass `isDirty:` to `AppDialogFrame` or `showTwoActionsDialog`; for other content use `DialogDismissGuard` / `confirmDiscardChanges` (`lib/widgets/dialogs/dialog_dismiss_guard.dart`).
- **Opening:** through the `show*` helpers or `showDialogUntilTornDown`, not raw `showDialog` (UIL-028). In the settings screen wrap the builder in `settingsDialogBuilder` (§11).
- **Wording of delete and remove:** the title is a question, "למחוק את X?" / "להסיר את X?", not an action name ("מחיקת X", "הסרת X"). The confirm button is "מחק" when it deletes data and "הסר" when it removes without deleting the source (a library folder, a linked database, a column, a book from a tracking list). A dialog that only closes is labelled "סגור" (not "סגירה"). `AppDialog.singleAction` always renders `ActionButton.recommended`, a prominent button, even with `confirmText: 'סגור'`: the owner decided to leave it loud (19.11, q56, card 212). In a hand-built dialog a quiet close button is an explicit `ActionButton.neutral`; an explicit `ActionButton.recommended` with "סגור" is rejected by `dialog_wording_test`. Enforced by `test/widgets/dialogs/dialog_wording_test.dart`.
- **Opening is only `showDialogUntilTornDown`** (an optional `barrierColor` is inside it); a raw `showDialog` is also caught by `test/widgets/dialogs/dialog_open_path_test.dart`, including one whose builder is `settingsDialogBuilder`.
- `AlertDialog`, `Dialog` and `SimpleDialog` outside `lib/widgets/dialogs/` fail UIL-001.

Behaviour contract (Escape, Enter, focus, barrier): `DESIGN_SYSTEM.md` §3.1. Checklist for a new dialog: `DESIGN_SYSTEM.md` §8.2.

- **Enter** belongs to the focused control: `DialogKeyboardNavigator` (`lib/widgets/misc/keyboard_dialog_navigation.dart`) confirms the dialog on Enter only when the focus is not on a multi-line field or on something that handles `ActivateIntent` (a button, a list item, a switch). So Enter on a focused "ביטול" cancels and does not submit. A custom dialog body that wants the same rule calls `DialogKeyboardNavigator.focusedControlOwnsEnter(primaryFocus!.context!)` instead of re-implementing it.
- A new dialog gets a `testResponsive` scene (§14); `test/design_system/responsive/responsive_dialogs_test.dart` is the model.

## 5. Buttons

Labeled buttons are `ActionButton` named constructors (`lib/widgets/controls/action_buttons.dart`). Each takes `text`, `onPressed` (null = disabled), and optionally `icon`, `isLoading`, `tooltip`, `autofocus`.

| Constructor | Look | Use for |
|---|---|---|
| `ActionButton.recommended` | `FilledButton`, `primary` / `onPrimary` | The main action; one per group |
| `ActionButton.neutral` | `FilledButton.tonal` (`secondaryContainer`) | Secondary actions, and **Cancel in every dialog**. `errorText: true` gives red text for a destructive action that must sit in the same row |
| `ActionButton.ghost` | `TextButton`, transparent, `primary` text | Quiet inline actions that are not Cancel ("דלג") |
| `ActionButton.warning` | `FilledButton` on `cs.error`, `onError` text | The confirm button of a destructive action, inside a warning dialog or after confirmation |
| `ActionButton.warningSoft` | `errorContainer` / `onErrorContainer` | The destructive button on a settings screen or panel (not in a dialog): "נקה הכל", "הסר". The confirm in the dialog it opens is `warning` |
| `ActionButton.inline(text:, onPressed:, color:, tooltip:)` | ghost without minimum size, 8×4 padding | A dense action inside a snack, a row or breadcrumbs. `color` only when the context sets it (a snack tone) |

A first "delete" button in a list or card is `neutral` or an icon button; the irreversible step is confirmed with `showWarningDialog`. For a labeled button with an icon pass `icon:`; never build `FilledButton.icon` yourself.

| Icon and bar buttons | Use |
|---|---|
| Icon-only, general | `AppIconButton(icon: Icon(...), tooltip:, onPressed:, size: AppIconButtonSize.small/medium/large)`; round, icon 16/20/24, `isSelected:` for a toggle. With a background: `fill: AppIconButtonFill.tonal` (`secondaryContainer`) or `neutral` (`surfaceContainerHighest`), or `backgroundColor:`/`foregroundColor:` from the caller; a filled button is a rounded rectangle (radius 8). `extent:` sets the side when the host fixes it (a search field); `selectedIcon:` is the icon in the selected state |
| Square, field height (next to a search field / in a floating toolbar) | `SquareIconButton.field` / `.toolbar` |
| Top bar and action bar | `BarButton.icon(tooltip:, icon:, onPressed:)` / `BarButton.text(text:, onPressed:)` |
| Action plus menu arrow | `BarSplitButton` |
| On/off pill | `AppTogglePill(label:, value:, onChanged:)` (`lib/widgets/controls/toggle_pill.dart`) |
| Status pill in the title bar | `StatusChip(icon:, label:, onPressed:, tooltip:)` |

- `TextButton`, `FilledButton`, `OutlinedButton`, `ElevatedButton` outside `lib/widgets/controls/` fail UIL-002.
- Every icon-only button has a `tooltip` (UIL-003 for `IconButton`). A shortcut goes in it as `"הדפסה (Ctrl+P)"`, via `ShortcutHelper.formatShortcutForDisplay`.

## 6. Cards, lists and chips

| Need | Use | File |
|---|---|---|
| Information card | `AppCard(child:, onTap:, padding:, tone: AppCardTone.normal/primary/error/inset)`; `inset` is a card inside a card | `lib/widgets/layout/app_card.dart` |
| Group of rows in one card | `AppCard.section(children:)`; rows are separated by a 1.5 transparent gap | same |
| Search or tool result | `ResultCardFrame(child:)`; in tools `ToolResultCardShell(child:, onTap:)`; above the results `ToolResultsHeader(label:)` | `lib/widgets/layout/` |
| History, bookmarks, short repeated data | `ItemsListView`: one light card per group in the `AppCard.section` style (`AppSurfaces.card` rows, rounded group ends, `AppCard.sectionSpacing` gap, no divider) | `lib/widgets/lists/items_list_view.dart` |
| Expanding card | `ExpandableCard(header:, isExpanded:, children:)`, also in settings | `lib/widgets/layout/expandable_card.dart`, `lib/settings/widgets/expandable_settings_tile.dart` |
| Expand arrow | `ExpandingChevron(isExpanded:, style: ExpandingChevronStyle.accordion/tree)` | `lib/widgets/misc/expanding_chevron.dart` |
| Read-only tag or counter | `MetaChip(label:, tone: MetaChipTone.…, size: MetaChipSize.regular/small)` | `lib/widgets/layout/meta_chip.dart` |
| Icon badge in a row | `ListIconBadge(icon:)` | `lib/widgets/lists/list_icon_badge.dart` |
| Section heading | `AppSectionLabel('…')` | `lib/widgets/text/app_section_label.dart` |

- An `AppCard` has radius 8, an `outlineVariant` border and no shadow. Do not rebuild it with `Container` + `BoxDecoration`. Raw `Card` fails UIL-012.
- `MetaChipTone.success` is the neutral brown `secondaryContainer`, not green. `MetaChipTone.tertiary` and `AppInfoBannerTone.tertiary` are `tertiaryContainer` on `onTertiaryContainer` (used by the search result source tag, the plugin DEV badge, the plugin fix-session banner and the layout-fix suggestion).
- A link inside text: `AppInlineLink(text:, onTap:, tooltip:, style:, textDirection:)` (`lib/widgets/text/app_inline_link.dart`): `primary` text with an underline of the same colour, `InkWell` radius 8, horizontal padding 2, normal keyboard focus. In the middle of a sentence (`Text.rich`) use `TextSpan(style: AppInlineLink.styleOf(context, base), recognizer: ...)`.
- A colour choice circle: `AppColorSwatch` (`lib/widgets/controls/app_color_swatch.dart`). New colour pickers use it and do not draw their own circle (diameter 40, tap target 48, a check mark and a thick border when selected, `Semantics(selected)`, `color: null` = "no colour").
- The short description is back in the library book card (up to 3 lines, 1 in a card shorter than 100, 120 characters); a category card (`CategoryGridItem`) shows its short description (`Category.shortDescription`), up to two lines, in the lines left under the title (and under the parent path in search results). When the card height leaves no room (a two-line title in the narrow band) the description is hidden; the full text stays in the info button tooltip.

## 7. Settings rows

Settings cards and tiles are in `lib/settings/widgets/settings_card.dart` (all exported by `lib/settings/widgets/settings_widgets_exports.dart`).

```dart
SettingsCard(
  title: context.settingsText('תצוגה'), // String או Widget
  children: [
    SettingsSwitchTile(
      icon: FluentIcons.eye_24_regular,
      title: context.settingsText('הצג ניקוד'),
      value: state.showNikud,
      onChanged: (v) => bloc.add(...),
    ),
    SettingsSegmentedTile<String>(
      title: context.settingsText('הצגת הניקוד'),
      options: [SegmentOption(value: 'always', label: context.settingsText('הצג תמיד')), ...],
      currentValue: mode,
      onChanged: (v) => bloc.add(...),
    ),
  ],
);
```

| Row | Use |
|---|---|
| On/off | `SettingsSwitchTile(title:, value:, onChanged:)` |
| One of a list | `SettingsDropdownTile<T>(title:, value:, entries:, onSelected:)` with `AppMenuEntry(value:, label:)` |
| Two to four options | `SettingsSegmentedTile<T>(title:, options:, currentValue:, onChanged:)` |
| Number range | `SettingsSliderTile(icon:, title:, valueLabel:, value:, min:, max:, onChanged:)` (`lib/settings/widgets/settings_slider_tile.dart`) |
| Folder path | `SettingsPathTile(icon:, title:, currentPath:, onFolderChanged:, onOpenFolder:)` |
| Anything else | `SettingsActionTile.text(title:, subtitle:, actions: [...])`, `SettingsActionTile.path(title:, path:, placeholder:)`, `SettingsActionTile.radioOption(title:, selected:, onTap:)`, or the default constructor with a `Widget` title |

- A settings tab is `SettingsTabScrollView` + `SettingsCard`s. The spacing between cards comes from the card header; do not add spacers.
- Tile icons: `icon:` draws a plain `Icon`, `rtlIcon:` goes through `RtlIcon` (§1).
- The title of a setting row (`SettingsActionTile.text`/`.path`, `SettingsSwitchTile`, `SettingsSegmentedTile`, `SettingsDropdownTile`, `ExpandableSettingsTile`) gets **up to two lines** (`maxLines: 2`, ellipsis only after the second), on every settings screen. Never cut a title to one line. A subtitle wraps without a limit. Test: `test/settings/widgets/settings_title_lines_test.dart`.
- Action buttons in a row are `ActionButton`s or `AppIconButton`s.
- Every string goes through `context.settingsText` (§11).

## 8. Loading, empty, error and notices

Files are in `lib/widgets/feedback/`.

```dart
return switch (state) {
  Loading() => const LoadingIndicator(),
  Empty() => const OtzariaEmptyState(
      icon: OtzariaIcons.otzaria_icon_2_page_24_regular,
      title: 'אין סימניות',
      message: 'סמן קטע בספר כדי לשמור אותו כאן'),
  Failed() => OtzariaErrorState(
      title: 'טעינת הסימניות נכשלה',
      actions: [ActionButton.neutral(text: 'נסה שוב', onPressed: _reload)]),
  Loaded(:final items) => _list(items),
};
```

- Loading: `LoadingIndicator()`, `LoadingIndicator(message:)`, `LoadingIndicator(icon:)` (an `OtzariaIcons` glyph inside the ring; used by the library and book loading screens), inside a row `LoadingIndicator.inline()`, in a narrow panel with a message `LoadingIndicator.compact(message:)` (spinner 24, stroke 2, the message under it in `bodySmall`; used by the commentary panels and it does not follow the commentary font), skeleton `SkeletonLines(widths:)`. Raw `CircularProgressIndicator` fails UIL-013. Only the content area loads; the search field and toolbar stay.
- Empty: `OtzariaEmptyState` (`isCompact: true` in a panel); a whole empty screen is `OtzariaEmptyState.large`.
- Error: `OtzariaErrorState(title:, actions:)`, never red `Text`; the action is a retry (`ActionButton.neutral(text: 'נסה שוב')`; the library load error and the Shamor Zachor `ErrorBoundary` use `ActionButton.recommended`, with that single "נסה שוב" button; both failure screens of the library, `loadFailed` and `noLibraryData`, carry a recommended "נסה שוב" that sends `RefreshLibrary`) whenever one can work. `details:` is printed as is, so pass a sentence for the user and not a raw exception (a path or another LTR value is wrapped in isolation characters, `DESIGN_SYSTEM.md` §6.1). `isCompact: true` inside a panel.
- Banner inside a screen: `AppInfoBanner(message:, title:, tone: AppInfoBannerTone.info/warning/error/success/tertiary)`; `AppInfoBanner.rich` takes a `TextSpan`, and `trailing`, `messageMaxLines`, `onTap`/`focusNode` are available.
- A busy button: `ActionButton(isLoading: true)`.

## 9. Screen layout

| Pattern | Use |
|---|---|
| Panel screen (settings, library, tools) | `AppTopBar(leadingItems:, center:, trailingItems:)` on `AppSurfaces.panelBackground(context)`, content limited to `LayoutConstraints.panelContentMaxWidth` |
| Screen title | `Text(title, style: AppTopBar.titleStyle(context))`, subtitle `AppTopBar.subtitleStyle(context)` |
| Top-bar text size | Wrap the bar's title in `AppTopBarTitle`: it grows with the system text scale only up to `AppTopBar.maxTextScale` (1.3), like the bottom navigation labels, because the bar height is fixed. A search field (or the PDF page-number field) in the bar is wrapped in `AppTopBarField`: it grows up to `AppTopBar.maxFieldTextScale` (1.6), above the title ceiling; every new search field in a bar must use it. Buttons in the bar are not clamped |
| Tool built around a search field | `ToolScaffold(topBar:, body:, filters:, footer:, loading:, loadError:, onRetry:)` (`lib/widgets/layout/tool_scaffold.dart`) |
| Action bar that collapses | `ResponsiveActionBar` with `ActionButtonData`, items rendered as `BarButton` |
| Navigation panel | `NavSidePanel` (§12) |
| Other side or floating panel | `AdaptiveSidePane` / `ContextOverlayPanel` (`lib/widgets/layout/`) |
| Scrollable or centered content | `PanelScrollableContent` / `CenteredScrollableState` |
| Reader screens | `AppSurfaces.readerBackground(context)`, no cards around book text |

- **No room?** One of four, in this order, and never an essential action that just disappears (`DESIGN_SYSTEM.md` §5.4): shorten the label (to an icon plus tooltip), move actions to "עוד ⋮" (`ResponsiveActionBar`, `toolbarOverflowOrder`), wrap to a second line, or scroll. `AppTopBar` does not scroll. An item with `priority: AppTopBarPriority.normal` or `.low` plus a `menuAction` moves to a trailing "עוד ⋮" menu when the leading (or trailing) items are wider than the space they get: `low` first, then `normal`, and among equals the later item first. `critical` (the default) never moves. The decision is made at layout time from the measured widths, so adaptive items (`LayoutBuilder`, `flexible: true`, `ResponsiveActionBar`) still get a bounded width. `AppTopBar(mergeFoldedIntoTrailingMenu: true)` — the folded leading items do not get a ⋮ of their own. They are added at the top of the ⋮ menu of the trailing `ResponsiveActionBar(absorbTopBarFolds: true)` (the reader bar), so the bar has one ⋮. The trailing items must contain such a bar, otherwise the folded items would not appear anywhere. The menu row of a folded item is disabled when its `AppTopBarMenuAction.onPressed` is null (e.g. the back row when there is no history); rebuild the bar when that changes.
- Side-pane dimensions (`minMainContentWidth`, `minPaneWidth`, `maxPaneWidth`, fixed width, fraction) come from `SidePaneSpecs.<screen>` (`lib/widgets/layout/side_pane_specs.dart`); do not write `minMainContentWidth: 300` in a screen (`test/design_system/side_pane_specs_test.dart` fails). The default commentary pane width is `LayoutConstraints.commentaryPaneDefaultWidth` (350), shared by the text and PDF readers under `key-commentary-pane-width`. A pane the user closed stays closed when the window is narrowed and widened again; a pane closed automatically by narrowing reopens. `ContextOverlayPanel` defaults to `SidePaneSpecs.overlayPanelWidth` (350, like the commentary pane); `LayoutConstraints.overlayPanelWidth` (400) is only for the Shamor Zachor completion overlay. The resize handle (`ResizableDragHandle`) hit area is 24 (18 in compact density) with a mouse and 32 on touch (`AppTokens.dragHandleTouchHitSize`: 4 inside the pane, `kPaneHandleInnerReach`, and 28 outside the edge); on touch the small grip is visible at rest (`showIdleGrip`, default true). The whole hit area is tappable, including the part outside the pane edge: in the wide layout the handle sits in a layer above the whole row (`_buildWideHandleLayer`), not inside the pane slot. Tests that pin 24 and the transparent handle run as a Windows variant (`TargetPlatformVariant.only(TargetPlatform.windows)`), because the default test theme is touch. The navigation pane opens automatically (default, search, pin) only when there is room to push: not under 600, and the window holds the saved pane width plus `SidePaneSpecs.textReaderNav.minMainContentWidth` (520; `pdfReaderNav`: 200; with the default width 842 in the text reader and 522 in the PDF reader). In a medium window the pane stays closed and the user opens it (as an overlay). Decide auto-open only through `shouldAutoOpenReadingLeftPane` / `resolveInitialReadingLeftPaneVisibility` (`lib/utils/ui/reading_left_pane_policy.dart`, `readingLeftPaneFitsSideBySide`) with the reader's `minMainContentWidth`; an explicit user request always opens it.
- The search results bar (`SearchResultsLayout`, regular and semantic search): under 600 the search terms (`SearchTermsDisplay` inside `OtzariaSearchDisplayBar`) move to a second `AppTopBar` row (`secondaryRow`) at full width, and the first row keeps the buttons; from 600 they are in the middle of the bar. Keyboard in full-text results: Enter on a result that is not yet in the preview shows it there; Enter on a result already in the preview (focus on its card, or on the list after it was shown) opens the book, like a double click; with the preview off Enter opens the book directly; Enter with Ctrl/Shift/Alt/Meta is unchanged.
- Window-level decisions (dialog size, navigation style, column count) use `WindowClass.of(context)` (`lib/theme/layout_tokens.dart`). A decision about the space a widget got uses `LayoutBuilder` and a named `static const` threshold in that widget. Never orientation or `Platform.isX` for a width question, never a bare width literal (UIL-022).
- Use `EdgeInsetsDirectional`, `AlignmentDirectional` and `start`/`end` (UIL-021).
- Scrollbars sit on the physical right in every direction, in their own 12px lane when the content scrolls (`EdgeScrollbarBehavior.right()` on the `MaterialApp`). Do not add padding for the scrollbar. An explicit bar (fixed thumb, own controller) is `AppScrollbar(controller:, thumbVisibility:, contentInset:)` from `lib/widgets/feedback/app_scrollbar.dart`; raw `Scrollbar`/`RawScrollbar` fails UIL-031. `side: ScrollbarOrientation.left` only for a pane on the left of the content.
- **Touch or mouse:** on Android and iOS the last pointer decides the tap-target size and density (`InputModalityScope(adaptTheme: true)`, once above the app in `lib/app.dart`; read it with `InputModality.lastPointerIsMouseOf(context)`): a mouse or trackpad gives desktop sizes (`MaterialTapTargetSize.shrinkWrap`, `VisualDensity.compact`), a finger or pen gives touch. The default, and the default in tests, is touch. On Windows, Linux and macOS it is always desktop. A component that reads `BarButton.isTouch` or the theme `materialTapTargetSize` updates without any change; only `adaptTheme: true` replaces the theme.
- **A new selection area:** a direct `SelectionArea` / `SelectableRegion` must wrap its content in `PenSelectionGestures(onSelectionChanged: <the same handler>)` (`lib/widgets/selection/pen_selection_gestures.dart`), otherwise a pen does not select in it. Pass the handler you give the area's own `onSelectionChanged`, because `SelectableRegion` does not report a pen drag that did not pass through it. `AppSelectionArea` already does this.
- **Sharing selected text (mobile only):** `TextShareService` (`lib/core/share/text_share_service.dart`, `share_plus`) is the share interface; `shareSelectedText` shares text through the system share sheet, passes the publisher copy limit (`ensureCopyAllowed`, `BookProtection`) and strips divine-name joiners. Show a "שתף" button only on mobile: in the touch toolbar of `AppSelectionArea` (by `Theme.platform`, Android/iOS) and in the reader action row (`buildReaderIconRow(onShare:)`, by `DeviceChrome.isMobile`, after "העתקה"). In tests replace `TextShareService.instance` with a fake; never open a real sheet. Do not use Flutter's `ContextMenuButtonType.share`: it exists on Android only and bypasses the copy limit. On Windows the plugin adds a native library to `generated_plugins.cmake` (unused by our code). Not tested on a real device.
- **Mac Edit-menu shortcuts:** the `MacMenuBar` Edit menu items (`buildMacEditMenu`) carry their keys (Cmd+Z, Cmd+Shift+Z, Cmd+X, Cmd+C, Cmd+V, Cmd+A) only when `kMacEditMenuShortcutsEnabled` (`lib/core/windowing/mac_menu_bar.dart`) is true; it is `false`, with a `TODO(q114)`. Tests turn the keys on with `buildMacEditMenu(shortcutsEnabled: true)`. Do not enable the flag before testing on a real Mac: a declared menu key is taken by macOS before Flutter and could swallow Cmd+C before a plugin WebView.
- **Keyboard context menu:** Menu / Shift+F10 opens the topmost visible `keyboardPreferred` region (`ContextMenuRegion.keyboardPreferred`, `AppContextMenuRegion.keyboardPreferred`, default `false`) when the focus is on a component above several regions, and only if there is none the topmost visible region. In the reader (page shape and combined view) the preferred region is the selected row, the item with the selection marker in the margin. The anchor is the centre of the visible part of the region, so a multi-line item opens near the middle of the paragraph.
- A widget that fits only one feature stays in that feature's `view/widgets/` folder, built from these components (`DESIGN_SYSTEM.md` §8.5).

## 10. Tokens

Tokens live in `lib/theme/` (`AppTokens` in `lib/theme/app_tokens.dart`, `AppSurfaces` in `lib/theme/app_surfaces.dart`). Values and rationale: `DESIGN_SYSTEM.md` §2.

| Need | Use | Not |
|---|---|---|
| Colour | `ColorScheme` roles (`cs.onSurfaceVariant`, `cs.outlineVariant`, `cs.error`, …), then `AppSurfaces.*` | `Color(0x…)`, `Colors.<hue>` (UIL-015), `.withValues(alpha:)`/`withAlpha`/`withOpacity` (UIL-016), `theme.primaryColor` (UIL-004), `brightness == Brightness.dark` |
| Surfaces | `AppSurfaces.panelBackground(context)`, `topBarBackground(context)`, `navPanelBackground(context)`, `card(context)`, `readerBackground(context)` | `cs.surface` + `BoxDecoration` |
| Row states | `AppSurfaces.selectedRow(cs)` / `onSelectedRow(cs)`, `hoverRow(cs)`, `focusedRow(cs)`, `subtleDivider(cs)` | local alpha mixes |
| Warning / success | `AppSurfaces.warning(context)`, `onWarning`, `warningContainer`, `onWarningContainer`; success = `cs.secondaryContainer` | `Colors.orange`, `Colors.green` |
| Text on content background | `readableInkOn(background)` (`lib/theme/readable_ink.dart`): dark `1F1F1F` above relative luminance 0.179, white below; computed at display time | a fixed theme colour for text on a highlight or note background |
| Text selection | `AppThemeData.textSelection` (`primary` at 0.38 light / 0.28 dark) | a local `selectionColor` |
| Borders | `AppTokens.borderHairline` 0.5, `borderThin` 1, `multiSelectedBorderWidth` 1.5, `focusRingWidth` 2, `borderThick` 3 | a literal `width:` |
| Spacing | `AppTokens.space2XS` 2, `spaceXS` 4, `spaceSM` 8, `spaceSMD` 12, `spaceMD` 16, `spaceLG` 24, `spaceXL` 32; `cardPadding`, `listItemGap`, `dialogPadding` | other literals (UIL-020); off-scale rounds up, 6→8, 10→12, 14→16 |
| Radius | `AppTokens.radius` (8), `borderRadiusAll`, `roundedShape` | `circular(n)`, `StadiumBorder` (UIL-019) |
| Icon size | `AppTokens.iconXS` 14, `iconSM` 16, `iconMD` 20, `iconLG` 24, `iconXL` 48 | `size: 18` (UIL-029) |
| Elevation / shadow | `0`, `AppTokens.elevation1`, `elevation2`; shadows from `AppShadows` (`lib/theme/app_shadows.dart`) | `elevation: 6`, `BoxShadow(` (UIL-030) |
| Animation | `AppMotion.duration(context, AppTokens.animFast/animNormal/animPanelOpacity/animPanelSlide)` | `Duration(milliseconds: 250)` (UIL-023) |
| Density | `AppDensity.of(context).isCompact` | `SettingsBloc` state's `compactMenuMode` in a widget |
| UI text | `Theme.of(context).textTheme.<slot>`, `.copyWith(fontWeight:, color:)` | `fontSize:`, also `AppTokens.font*` (UIL-017); literal `fontFamily` (UIL-018) |
| Monospace | `AppTextStyles.monospaceFamily` | `'monospace'` |

- The only radius exceptions: an icon-only button is round, and `BarSplitButton` is a pill.
- `hoverColor`, `splashColor` and `overlayColor` fail UIL-007. The one exception is `hoverColor: Colors.transparent` on a `ListTile` that has `onTap` and buttons in `trailing`.
- Book text typography (font, size, line height) comes from the reading settings, not from `textTheme`. A UI message inside the reading area ("טוען…") uses `textTheme`.
- Local colour is allowed only for content, export/print and OS-chrome imitation, with a `// ui-lint: allow UIL-xxx — <reason> (DD-24)` comment. The exception process is in `AGENTS.md`.

## 11. Settings and chrome text: `settingsText`

The settings screen has an English mode (`lib/settings/l10n/`). Every new user-visible string under `lib/settings/` is wrapped, or it stays Hebrew in English mode.

```dart
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

Text(context.settingsText('גודל גופן הספר'))
// Placeholders, never interpolation, so the translation can reorder them:
context.settingsText('יש כרגע {count} דיווחים שמורים בתור', args: {'count': pendingCount})
// Identical Hebrew with different translations:
context.settingsText('ספריה', context: 'titleBar')
```

- The Hebrew source string is the key. Never invent a key like `'settings.font.size'`. The English text lives only in `lib/settings/l10n/settings_en.arb`.
- After adding or changing a string run `dart run tool/generate_settings_l10n.dart`; it writes `lib/settings/l10n/settings_catalogs.g.dart` (never edit it by hand). The build hook also runs it on `flutter run/build/test`, but not on hot reload.
- Run `flutter test test/settings/l10n/`. `test/settings/l10n/settings_l10n_test.dart` reads literal `settingsText` arguments and fails on a key missing from the ARB, or an ARB entry no longer used.
- A string that reaches `settingsText` through a variable is invisible to that scan: add a case to `test/settings/l10n/settings_variable_labels_test.dart`.
- A dialog builds in the Navigator's overlay and inherits neither language nor direction. Open it with `settingsDialogBuilder`:
  ```dart
  showDialogUntilTornDown(context: context, builder: settingsDialogBuilder(context, (_) => const MyDialog()));
  ```
- Direction: `ChromeDirectionality` for app chrome, `ContentDirectionality` for library and reader content. No ad hoc `textDirection` or `Directionality` to fix English mode.

Outside `lib/settings/`, `SettingsTextScope` in `lib/app.dart` makes `context.settingsText` available everywhere. Translate the interface labels (not book, category or plugin names) in:
- `lib/navigation/`: the navigation rail and the title-bar screen names.
- Main-screen chrome: the library browser, Find Sources dialog, library search dialog and tools launcher. Direction is covered by `test/navigation/chrome_direction_test.dart`.
- `lib/tour/`: every tour step title/body and live-tip title/description needs an ARB entry. A step's `body` stays a plain string literal, with variable values as placeholders. See `docs/guided_tour_developer_guide.md`.

## 12. Navigation side panel: `NavSidePanel`

Every navigation panel (search facets, notes, Shamor Zachor, text/PDF book, commentators tabs) uses the widgets in `lib/widgets/navigation/nav_side_panel.dart`. They own the panel's colour, its attachment to the top bar and the corner where it meets the content.

```dart
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

NavSidePanel(
  isOpen: _isNavVisible,
  isPinned: _isPinned,          // omit on screens without a pin (default: docked)
  onClose: () => setState(() => _isNavVisible = false),
  paneContent: _buildTree(),
  mainContent: _buildContent(),
)
NavPanelToggleButton(isOpen: _isNavVisible, onToggle: _toggleNav) // first leadingItems entry
NavPanelPinButton(isPinned: _isPinned, onToggle: _togglePin)      // next, only while open
NavPanelTabHeader(controller: _tabController, tabs: const [(icon: ..., iconFilled: ..., label: 'ניווט')])
```

- A pinned panel pushes the content; an unpinned one floats with a scrim and closes on a click on the content. Nothing closes a panel on scroll. A panel that opens by itself with a book starts pinned. Switching pin state moves both contents by `GlobalKey`; never rebuild them.
- **Search inside a panel** sits under the tab row, never in `AppTopBar` (`lib/widgets/navigation/nav_panel_search.dart`). The screen owns a `NavPanelSearchHost`, keeps its `activeTab` in sync with the `TabController`, wraps `paneContent` in `NavPanelSearchScope(host:)`, and wraps each tab in `NavPanelSearchSlot(index:)`.
  - A tab that is all search (in-book search) draws its field permanently: `SearchPaneBase`.
  - Navigation, alternate headings, and result-book filters use `NavPanelCollapsibleSearch(presentation: NavPanelSearchPresentation.persistent, delegate: NavPanelSearchDelegate(...))`. The field stays above the scrolling list, including after clearing it. Other filters keep the default collapsible presentation. Put `const NavPanelSearchToggle()` in the `trailing` of the `NavTreeHeader`; it hides itself when the field is visible.
  - A tab without search shows no field. Never build a bare `OtzariaSearchField` or `RtlTextField` in a panel tab.
  - Up/Down move focus from the field into the rows (`NavPanelSearchHost.paneFocusScope`). A delegate with `onArrowDown`/`onArrowUp` instead browses a highlight while focus stays in the field.
  - Header actions that should stay reachable after the header scrolls away go in `floatingActions`; they remain available with a persistent field too. `NavPanelSearchHost.openCollapsibleSearch(tab)` opens or focuses a tab's field from outside.
  - The screen requests focus only when its active panel or tab opens, on a wide screen. Do not request it on rebuild, scrolling, or results arrival, or from a hidden/background panel. Persistent presentation alone never requests focus.
- **Panel content** comes from `lib/widgets/lists/nav_tree_tile.dart`: `NavTreeHeader` for titles, `NavTreeTile.category` / `NavTreeTile.book` for tree rows, `NavTreeContentRow` for free-form rows, `NavTreeGroupCard(isGroupStart:, isGroupEnd:)` for a run of rows in one card, and `NavTreeFocusGroup` so Tab lands on the selected row. In a reading tree set `focusOnTap: true` so arrows continue from the clicked row; leave it off where focus must stay in a search field. The horizontal inset is `kNavTreeSideInset` inside the card/header; a list passes only `kNavTreeListPadding`.

**Never:** `AdaptiveSidePane` directly for a navigation panel; passing `paneColor` / `attachToTopEdge` yourself; a hand-rolled `TabBar` + `AnimatedPinButton` header; a per-screen open icon instead of `NavPanelToggleButton`; tree rows with `Border(bottom:)`, a `fontSize` or `primary` icons.

## 13. Middle-click autoscroll

`MiddleClickAutoScroll` wraps the whole app once in `lib/app.dart`, so every scrollable area already autoscrolls on middle-click. Never add a per-screen handler or a second `MiddleClickAutoScroll`.

Where middle-click has another meaning (a tab that closes on middle-click), wrap the region in `AutoScrollBarrier` from `lib/widgets/misc/middle_click_autoscroll.dart`:

```dart
Listener(
  onPointerDown: (e) { if (e.buttons == kMiddleMouseButton) closeTab(tab); },
  child: AutoScrollBarrier(child: tabContent),
)
```

## 14. Responsive tests: `testResponsive`

Every new screen or layout change gets at least one scene in `test/design_system/responsive/<area>_responsive_test.dart`. The harness is `test/design_system/responsive/responsive_harness.dart`; the rules and the policy for what to do when a scene fails are in `DESIGN_SYSTEM.md` §5.4 and §5.5.

```dart
import '../../test_helpers/stub_settings_bloc.dart'; // stubs and fakes live in test/test_helpers/
import 'responsive_harness.dart';

testResponsive(
  'bookmark dialog',
  wrapApp: (app) => BlocProvider<SettingsBloc>.value(
    value: StubSettingsBloc(), // optional SettingsState argument
    child: app,
  ),
  build: (context) => const BookmarkDialog(),
  act: (tester, run) async {
    await tester.pumpAndSettle();
  },
  verify: (tester, run) async {
    expectVisible(tester, run, find.text('שמור'), name: 'save button');
    await expectReachable(tester, run, find.text('הערה'),
        name: 'note field', scrollable: find.byType(Scrollable).first);
    expectInsideViewport(tester, run, find.byType(AppDialogFrame), name: 'dialog');
    if (run.viewport.touch) {
      expectTapTarget(tester, run, find.byType(AppIconButton), name: 'close');
    }
  },
);
```

- One test is registered per window of the tier: **quick** (6 windows, runs in CI with `run-ci`) or **full** (`--dart-define=RESPONSIVE_TIER=full`, about 40 windows: all widths 320 to 1920, heights 400 to 1080, dark, text scale 1.3 / 1.5 / 2.0, compact density). `viewports:` replaces the matrix when a widget only matters at one width.
- After every run the harness itself fails the test on RenderFlex overflow or any other layout error, and on horizontal scroll nobody asked for (`horizontalScroll: true` or `allowedHorizontalScrolls:` for a deliberate one). Assertions you add are for the **essential actions**: `expectVisible` (always in reach), `expectReachable` (inside a scroll), `expectInsideViewport`, `expectNoClippedText`, `expectTapTarget` (48 on touch), `expectNoHorizontalScroll`.
- `viewport.touch` runs the scene as `TargetPlatform.android` with `DeviceChrome.isMobile` on (no window buttons, 48 targets, no scrollbar lane). Other windows run as Windows. `compact` is the compact density, `textScale` the OS text scale, `keyboardHeight:` a virtual keyboard.
- `run.allowError(pattern)` only for a known overflow that waits for a decision, with a comment saying what and why. Never loosen an existing scene to make it pass.
- A screen that cannot be built without a database, an engine or a WebView is built with the existing stubs and fakes; if that is truly impossible, test its inner components and write down why.
- Run it: `flutter test test/design_system/responsive/<file> -r expanded --timeout 60s`.
