# רכיבי ממשק והנחיות יישום לסוכנים

קרא את הסעיף הרלוונטי רק בעת שינוי ממשק. כללי החובה המקוצרים נמצאים ב־`AGENTS.md`.

## רכיבי ממשק

### 1. Icons - `otzaria_icons` FIRST, `fluentui_system_icons` for the rest
```dart
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

// First choice — the app's own set. ALWAYS plain Icon(), never RtlIcon:
Icon(OtzariaIcons.book_pdf_24_regular)
Icon(OtzariaIcons.otzaria_icon_2_page_24_regular)
Icon(OtzariaIcons.calendar_24_regular)

// Fallback — Fluent, only for what otzaria_icons does not have:
Icon(FluentIcons.settings_24_regular)
RtlIcon(FluentIcons.chevron_right_24_regular)     // in _fluentMirrorMap
RtlIcon(FluentIcons.arrow_left_24_regular)        // in _fluentMirrorMap — auto-mirrors to arrow_right in RTL
```

**What `otzaria_icons` is for.** It is not a general-purpose set and does not try to cover Fluent. It exists for exactly four cases:

1. An icon that **breaks when mirrored** for RTL — a geometric flip mangles it.
2. An icon that is **always shown in an RTL context**, so it should simply be drawn that way.
3. An icon **Fluent does not have** (`lectern`, `torah_scroll`, `calendar_yahrzeit`, the `alef_*`/`beit_*`/`tet_*` families).
4. An icon Fluent has but whose form is **less suitable** for a seforim library (`book_pdf` over a generic document).

Anything outside those four — generic UI chrome like `dismiss`, `delete`, `copy`, `folder`, `settings`, `add`, `edit` — stays on Fluent. Redrawing chrome buys nothing and costs consistency.

**Which library — in this order:**

| Does `otzaria_icons` have an icon for it? | Use |
|---|---|
| Yes | `Icon(OtzariaIcons....)` — always plain `Icon` |
| No | `fluentui_system_icons`, per the `RtlIcon` rule below |
| Neither, but Material does | Draw it in `otzaria_icons` — **never** import Material |

`otzaria_icons` is purpose-built for a Hebrew seforim library, so prefer it even when Fluent has *something* close: `book_pdf` for a PDF book rather than a generic document, `search_in_book` / `search_in_library` / `search_in_settings` for scoped search, the `alef_*` / `beit_*` / `tet_*` families for nikud, punctuation and font settings, `lectern` / `torah_scroll` / `calendar_yahrzeit` where nothing in Fluent applies.

**Deliberate exceptions — these stay on Fluent:**

| Case | Icon | Why |
|---|---|---|
| The seforim library itself | `FluentIcons.library_24_regular/filled` | The Fluent library is the app's established symbol for it |
| In-book search action (toolbar button, side-panel tab, context-menu `חיפוש`) in `text_book/` and `pdf_book/` | `FluentIcons.search_24_regular/filled` | Recognized as *the* search affordance in the reading screen |
| Search icon inside a **labeled** button (`ActionButton`, `FilledButton.icon` — e.g. `פתח חיפוש טקסט`, `חפש`) | `FluentIcons.search_24_regular` | Beside a label the Fluent glyph reads cleaner. Icon-only buttons and field prefixes are not affected |
| A **direct link** to a book or a section (`קישור ישיר`, deep links, inserting a hyperlink) | `FluentIcons.link_24_regular` | Distinct from links *between* books |
| The private-book badge on a library card (8px) | `FluentIcons.person_24_regular` | The Otzaria person is drawn for legible sizes; at 8px it turns to mush. `OtzariaIcons.person_24_regular` stays everywhere it renders at 16px+ |

**Links between books** — the `קישורים` panel tab, the `קישורים` context-menu entry, `דורות וקישורים` — use `OtzariaIcons.link_24_regular`. The rule in practice: singular `קישור` / `קישור ישיר` is Fluent, plural `קישורים` is Otzaria. Two similar icons for the two meanings would be confusing, so keep the split.

**Scoped search — pick the icon that names *what* is being searched.** A generic magnifier says nothing; these do. None of the scoped icons has a `filled` twin, so a selected/unselected pair reuses the same glyph and lets color carry the state.

| Where | Icon |
|---|---|
| Library screen search, `סינון מפרשים`, `חפש בתוך המפרשים המוצגים`, שמור וזכור search | `search_in_library_24_regular` |
| Notes search, calendar `חפש גם בתיאור` | `search_in_document_24_regular` |
| Calendar `חפש רק בכותרת` | `search_in_text_24_regular` |
| `הוסף ספרים למעקב` dialog | `search_in_book_24_regular` |
| Settings search | `search_in_settings_24_regular` |
| `איתור כותרת` boxes (TOC, alt-TOC), bookmarks search, `חפש בתוך הקישורים המוצגים` | `search_in_titles_24_regular` |
| Gematria search | `search_in_numbered_list_24_regular` |

The **navigation rail's `חיפוש`** item is the exception: it keeps plain `OtzariaIcons.search_24_regular` / `search_24_filled`, because it is the app-wide search entry point and not scoped to anything.

Three shared widgets take an `icon:` / `searchIcon:` parameter for exactly this — `OtzariaSearchField`, `ItemsListView`, and any field's `prefixIcon`. Pass the scoped icon rather than wrapping the prefix in a `leading:` widget, which would drop `OtzariaSearchField`'s focus-color and sizing behaviour.

**Finding an icon:** 135 icons, listed in `OtzariaIcons.values` and in the package's `index.html` catalog. The names follow the Fluent convention (`<name>_24_<regular|filled>`), so a Fluent name is usually the right thing to look up first. `otzaria_icons` is pinned by commit in `pubspec.yaml` and `pubspec.lock`. If an icon in the catalog is undefined in your checkout, the pinned commit predates it.

**Sizes:** every icon is drawn on a 24px grid, and the `_24_` in the name is the grid, not a size limit — pass `size:` freely. But the `book_open_*` family is drawn at different weights for different display sizes; `otzaria_icon_2_page_24_regular/filled` is the general-purpose "open book" and the only one of them with a `filled` twin, so it is what a nav rail or any regular/filled pair needs.

**`OtzariaIcons` NEVER goes through `RtlIcon`.** Every icon in the set is drawn right-to-left already — `RtlIcon` would flip an icon that already faces the correct way. `test/widgets/rtl_icon_registered_usage_test.dart` fails the build on any `RtlIcon(OtzariaIcons....)`.

**When to use `RtlIcon` vs `Icon`:**

| Icon | Use |
|---|---|
| Any `OtzariaIcons.…` | `Icon(...)` — always |
| Fluent icon registered in `rtl_icon.dart` (`_fluentMirrorMap`, `_flippableIcons`) | `RtlIcon(...)` |
| Any other Fluent icon | `Icon(...)` — plain, no wrapper |

**Icons currently registered in `lib/widgets/misc/rtl_icon.dart`:**

*`_fluentMirrorMap` (swaps to opposite-direction variant in RTL):*
- `chevron_right/left_24/20/16_regular`
- `arrow_right/left_24_regular`, `arrow_right/left_24_filled`
- `arrow_previous/next_24_regular`
- `calendar_24_regular/filled` → `calendar_rtl_*`
- `panel_left/right_24_regular`, `panel_left/right_24_filled`
- `text_align_right/left_24_regular`

*`_flippableIcons` (geometrically flipped in RTL — no opposite-direction variant in Fluent):*
- `book_24_regular`, `book_24_filled`
- `book_information_24_regular`
- `text_align_distributed_24_regular`
- `list_24_regular`
- `calendar_week_start_24_regular/filled`, `calendar_month_24_regular/filled`

`_flippableIcons` is a **stopgap, not a destination.** A geometric flip mirrors the whole glyph, including asymmetric detail that was never meant to mirror. When an icon looks wrong flipped, the fix is to draw it right-to-left in `otzaria_icons` and drop it from this set — that is what `book_star_24_regular` did. The remaining six are the open candidates.

There is no `_materialMirrorMap` any more: `lib/` contains **zero** Material icons, and nothing can feed one to `RtlIcon` (plugins declare icons by *Fluent* name through `fluentIconFromName`), so the map was dead code.

Some Fluent entries here have no call site left in `lib/` — the app moved to the `OtzariaIcons` equivalent. **Do not delete those:** a plugin can still name a Fluent icon through `fluentIconFromName` in `lib/plugins/utils/fluent_icon_resolver.dart`, and it reaches `RtlIcon` as a variable.

**If you need to flip a Fluent icon that is NOT yet registered:**
Prefer drawing it in `otzaria_icons` — that is exactly what the package is for. Registering it in `_flippableIcons` is the fallback when you cannot. Either way, do NOT add manual `Transform.flip`/`Transform.scale` in feature files.

**Never use:**
- Material Icons — no exceptions. `lib/` is Material-free; if Material has something Fluent lacks, draw it in `otzaria_icons`
- Cupertino Icons
- Any icon font other than `otzaria_icons` and `fluentui_system_icons`
- `RtlIcon` with an `OtzariaIcons` icon — it is already RTL
- `mirrorIcon` parameter on any widget — **FORBIDDEN**, removed in commit 3b4d357
- Manual `Transform.scale(scaleX: -1, ...)` or `Transform.flip(flipX: true, ...)` around icons — register in `rtl_icon.dart` instead. **On an `OtzariaIcons` icon this silently points it the wrong way**, and neither the analyzer nor `rtl_icon_registered_usage_test.dart` catches it — when replacing a Fluent icon, check the call site for a hand-rolled flip first
- Comments explaining why `RtlIcon` or `Icon(...)` was chosen — the decision rule is documented here; do NOT repeat it inline in code
- Editing `lib/plugins/utils/fluent_icon_resolver.dart` to point at `otzaria_icons` — it is the generated Fluent-name contract for plugins

### 2. User Messages - ONLY via `UiSnack`
```dart
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/messages_exports.dart';

UiSnack.show(CommonMessages.savedSuccessfully);
UiSnack.showError(ReportMessages.sendFailed);
UiSnack.show(UiSnack.textCopied);          // Legacy alias → CommonMessages
```

**Message texts are centralized (MANDATORY):** Never pass a hardcoded string literal to `UiSnack`. Every message lives in `lib/core/messages/` — one catalog per domain (`CommonMessages`, `ReportMessages`, `SettingsMessages`, `TextBookMessages`, `ToolsMessages`, `NotesMessages`, `LibraryMessages`, `PluginMessages`, `PdfMessages`). Fixed texts are `static const`; parameterized texts are static functions. Add new messages to the matching catalog (or `CommonMessages` if shared).

**Never use:**
- Hardcoded message strings at `UiSnack` call sites — add to `lib/core/messages/` instead
- `ScaffoldMessenger.of(context).showSnackBar()`
- Custom snackbar widgets
- Toast packages
- Alert dialogs for simple messages

### 3. Text Input - ONLY `RtlTextField`
```dart
import 'package:otzaria/widgets/rtl_text_field.dart';

RtlTextField(
  controller: _controller,
  decoration: InputDecoration(labelText: 'חיפוש'),
  onSubmitted: (value) => _handleSearch(),
  autofocus: true,
)
```
**NEVER use regular `TextField`** - it breaks RTL support!

### 4. Dialogs - ONLY from `custom_ui_components`
```dart
import 'package:otzaria/widgets/widgets_exports.dart';

// Single button dialog (confirm only)
showSingleActionDialog(
  context: context,
  title: 'כותרת',
  content: 'תוכן הדיאלוג',
  confirmText: 'אישור',
);

// Two-button dialog (cancel + confirm)
showTwoActionsDialog(
  context: context,
  title: 'כותרת',
  content: 'תוכן הדיאלוג',
  cancelText: 'ביטול',
  confirmText: 'אישור',
);

// Warning dialog (user should ideally cancel)
showWarningDialog(
  context: context,
  title: 'אזהרה',
  content: 'פעולה זו היא סופית',
  subtitle: 'שים לב שלא ניתן לבטל פעולה זו',  // red text
  cancelText: 'ביטול',
  confirmText: 'המשך',
);
```

**Dialog Styling Rules (CRITICAL):**
- **SingleActionDialog**: single button - FilledButton (primary/onPrimary)
- **TwoActionsDialog**: 
  - Cancel = FilledButton.tonal (surfaceContainerHighest/onSurface)
  - Confirm = FilledButton (primary/onPrimary)
- **WarningDialog**: 
  - Cancel = FilledButton (primary/onPrimary) - recommended (safe choice)
  - Confirm = TextButton (transparent background, error text color) - dangerous
  - Subtitle = error color (red)

**Never use:**
- `showDialog` with custom `AlertDialog` directly
- Material `SimpleDialog`
- Custom dialog widgets without the standard styling
- Hardcoded colors (Colors.red, Colors.blue, etc.)

### 5. Action Buttons - ONLY `ActionButton` named constructors
```dart
import 'package:otzaria/widgets/widgets_exports.dart';

// Recommended action button (Primary style)
ActionButton.recommended(
  text: 'שנה מיקום',
  onPressed: () => _changeLocation(),
  isLoading: false,  // optional - shows loading indicator
);

// Neutral/non-recommended action button (Tonal style)
ActionButton.neutral(
  text: 'איפוס',
  onPressed: () => _resetSettings(),
  isLoading: false,  // optional - shows loading indicator
);

// Ghost (transparent, neutral)
ActionButton.ghost(
  text: 'ביטול',
  onPressed: () => _cancel(),
);

// Warning (transparent background, error-color text — for destructive actions)
ActionButton.warning(
  text: 'מחק לצמיתות',
  onPressed: () => _delete(),
);
```

**Button Styling Rules (CRITICAL):**
- **ActionButton.recommended**: FilledButton (primary background, onPrimary text)
- **ActionButton.neutral**: FilledButton.tonal (surfaceContainerHighest background, onSurface text)
- **ActionButton.ghost**: TextButton (transparent, neutral color)
- **ActionButton.warning**: TextButton (transparent, cs.error text — for destructive confirmations)
- **NEVER use hardcoded colors** - always use `Theme.of(context).colorScheme`

**When to use which button:**
- `ActionButton.recommended` - recommended actions (change settings, choose location, update, add)
- `ActionButton.neutral` - neutral or dangerous actions (reset, delete, remove, stop)
- `ActionButton.ghost` - secondary inline text actions (cancel, close, skip)
- `ActionButton.warning` - destructive confirmation (delete, clear, overwrite — matches WarningDialog's confirm button)

**Never use:**
- `ElevatedButton`, `TextButton`, `OutlinedButton` directly
- Custom button widgets without the standard styling
- Material `IconButton` for primary actions
- Hardcoded colors

### 6. Settings Cards - ONLY `SettingsCard`
```dart
import 'package:otzaria/settings/settings_card.dart';

SettingsCard(
  title: 'כותרת הקטגוריה',
  subtitle: 'תיאור אופציונלי',  // אופציונלי
  children: [
    ListTile(...),
    // Divider is added automatically between items
    SwitchListTile(...),
  ],
);
```

**Card Styling Rules:**
- Title: titleMedium, bold, primary color
- Subtitle: bodySmall, onSurfaceVariant color (optional)
- Card: surface color, rounded corners (20), subtle border
- Dividers: Automatic between children, surfaceContainerHighest color, thickness 1.5

**Hover Effects:**
- Remove hover from ListTile rows containing action buttons: `hoverColor: Colors.transparent`
- Hover should ONLY appear on the action buttons themselves
- This prevents double-hover effect and improves UX

### 8. Color Overrides — FORBIDDEN outside `lib/theme/`

**NEVER add the following anywhere outside `lib/theme/`:**
- `hoverColor` on `InkWell` / `ListTile` / any widget (except `Colors.transparent` on ListTile with action buttons)
- `splashColor` on any widget
- `overlayColor` on any widget
- `.withValues(alpha: ...)` — color transparency overrides

**Why:** These were used to work around a dark-mode color bug (fixed in commit f938a1860 via `ColorScheme.fromSeed`). Now the theme computes all interaction colors correctly. Adding them manually breaks theme consistency and will break again when themes change.

**If you need to define a custom interaction color or transparency:**
→ Define it in `lib/theme/app_theme_data.dart` or `lib/theme/app_surfaces.dart`, not in feature files.

**Exceptions (the only allowed uses outside `lib/theme/`):**
- `hoverColor: Colors.transparent` on a `ListTile` that contains action buttons in its trailing/leading (prevents double-hover)
- `BoxShadow` colors with `.withValues(alpha: ...)` — shadows require transparency by nature
- Loading overlays / semi-transparent backgrounds that are structural (not interaction feedback)

### 7. Segmented Settings - ONLY `SegmentedSettingsTile`
```dart
import 'package:otzaria/widgets/widgets_exports.dart';

// Setting with 2-4 options
SegmentedSettingsTile<String>(
  icon: FluentIcons.text_font_info_24_regular,
  title: 'הצגת הניקוד',
  subtitle: 'הניקוד יוצג בכל הספרים',
  options: const [
    SegmentOption(value: 'always', label: 'הצג תמיד'),
    SegmentOption(value: 'tanach_only', label: 'הצג בתנ"ך'),
    SegmentOption(value: 'never', label: 'אל תציג'),
  ],
  currentValue: nikudDisplayMode,
  onChanged: (value) {
    // update BLoC
  },
);
```

**When to use SegmentedSettingsTile:**
- Settings with 2-4 mutually exclusive options
- When the user needs to pick exactly one value from a small set
- Modern alternative to a RadioButton group or multiple SwitchListTiles

**Styling:**
- Selected: primary color with 20% opacity background
- Unselected: card color background
- Rounded corners (8)
- Fits in single row within SettingsCard

**Title can be:**
- String - plain text
- Widget - for advanced styling (e.g. RichText with mixed colors)

**Never use:**
- RadioButton groups for 2-4 options
- Multiple SwitchListTile for mutually exclusive options
- Custom segmented button implementations

### 9. Settings Screen Text — ALWAYS Through `settingsText`

The settings screen has an English mode (`lib/settings/l10n/`). **Every new user-visible string under `lib/settings/` must be wrapped** — an unwrapped string silently stays Hebrew when the user picks English.

```dart
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

Text(context.settingsText('גודל גופן הספר'))

// Placeholders — never string interpolation, so the translation can reorder them:
context.settingsText('יש כרגע {count} דיווחים שמורים בתור', args: {'count': pendingCount})

// Identical Hebrew with different translations — separate with a context:
context.settingsText('ספריה', context: 'titleBar')   // → "Library"
context.settingsText('ספריה')                        // → "Seforim Library"
```

**The Hebrew source string IS the translation key.** Never invent a key like `'settings.font.size'`: a maintainer looking for a screen greps the Hebrew text they see on it, and that has to keep working. The English text lives only in `lib/settings/l10n/settings_en.arb`.

**After adding or changing a string, regenerate the catalog:**
```bash
dart run tool/generate_settings_l10n.dart
```
It reads the ARB and writes the `const` map in `lib/settings/l10n/settings_catalogs.g.dart`. It also runs on `flutter run` / `flutter build` / `flutter test` via the build hook — but **not on hot reload**, so an ARB edit needs a restart to appear.

The generator validates the ARB itself (duplicate keys, placeholder mismatch). What catches a *missing* translation is `test/settings/l10n/settings_l10n_test.dart`, which scans the code for `settingsText` calls and fails on any key absent from the ARB — plus the reverse, an ARB entry no longer used. Run it after touching any settings string:
```bash
flutter test test/settings/l10n/
```

**Never do:**
- A bare string literal on a settings widget's `title` / `subtitle` / `label` / `tooltip` / dialog text
- String interpolation inside the key (`'שמור ${count} ספרים'`) — use `args:` instead
- A non-Hebrew invented key
- Editing `settings_catalogs.g.dart` by hand — it is generated, and your edit is lost on the next build
- Ad hoc `textDirection` or `Directionality` to fix English mode — use `ChromeDirectionality` / `ContentDirectionality` for app chrome and reading content

**Two traps that make a string render Hebrew even though it looks wrapped:**

1. **A string reaching `settingsText` through a variable is invisible to the scanner.** It reads literal arguments only, so `context.settingsText(item.label)` passes the coverage test with no translation existing. When the text arrives via a variable, field, or table, add an explicit case to `test/settings/l10n/settings_variable_labels_test.dart`.

2. **A dialog builds in the Navigator's Overlay, outside the settings widget tree**, so it inherits neither the language nor the direction. Open it through `settingsDialogBuilder`:
   ```dart
   showDialog(context: context, builder: settingsDialogBuilder(context, (_) => const MyDialog()));
   ```

Most strings outside `lib/settings/` remain Hebrew-only. The app-wide `SettingsTextScope` in `lib/app.dart` makes `context.settingsText` available in the translated interface chrome; only settings dialogs require `settingsDialogBuilder`. Translate interface labels in the following areas, while book titles, category titles, plugin names and content stay as they are:

- **`lib/navigation/`** — the fixed navigation rail and the title-bar screen names, because the settings screen is reached from them.
- **Main-screen interface chrome** — the library browser, Find Sources dialog, library search dialog and tools launcher. When `settingsText` receives a variable, cover its values in `test/settings/l10n/settings_variable_labels_test.dart`.
- **Direction** — `ChromeDirectionality` applies the interface language direction to title bar, navigation rail, tabs column and tools launcher; `ContentDirectionality` keeps library and reader content RTL. Use directional padding/alignment, not fixed left/right, for new chrome. Covered by `test/navigation/chrome_direction_test.dart`.
- **`lib/tour/`** — the guided tour and the live tips. **Every new tour step title/body and every live-tip title/description needs an ARB entry**, same as a settings string; see `docs/guided_tour_developer_guide.md`. Two rules specific to the tour: a step's `body` must stay a plain string literal (a variable value goes in as a placeholder — a keyboard shortcut via `shortcut:` filling `{shortcut}`), and coverage is guarded by `test/settings/l10n/settings_variable_labels_test.dart`, which builds the steps for real, so a step with no translation fails there rather than rendering Hebrew.


### 10. Navigation Side Panel — ONLY `NavSidePanel`

Every navigation panel in the app (search facets, notes, Shamor Zachor, text/PDF book, commentators tabs) uses the **same** widgets from `lib/widgets/navigation/nav_side_panel.dart`. It is the single source of truth for that panel's look — attachment to the top bar, background color, and the concave corner where it meets the content.

```dart
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

NavSidePanel(                      // wraps AdaptiveSidePane; never pass
  isOpen: _isNavVisible,           // attachToTopEdge / paneColor / scrollbarTopMargin yourself
  isPinned: _isPinned,             // omit on screens without a pin (defaults to docked)
  onClose: () => setState(() => _isNavVisible = false),
  paneContent: _buildTree(),
  mainContent: _buildContent(),
)

NavPanelToggleButton(              // the ONE icon that opens/closes it — first leadingItems entry
  isOpen: _isNavVisible,
  onToggle: () => setState(() => _isNavVisible = !_isNavVisible),
)

NavPanelPinButton(                 // next leadingItems entry, only while the panel is open
  isPinned: _isPinned,
  onToggle: () => setState(() => _isPinned = !_isPinned),
)

NavPanelTabHeader(                 // tabs only — the pin is NOT here
  controller: _tabController,
  tabs: const [(icon: ..., iconFilled: ..., label: 'ניווט')],
)
```

**Pinned vs. unpinned** (issues #1350, #1361): a pinned panel pushes the content; an unpinned one floats over it with a scrim and closes on a click on the content. Nothing closes a panel on scroll — never add a scroll listener that hides it. A panel that opens by itself with the book (default-open setting, opened from search) starts pinned, so the scrim never hides a book the user just opened. Switching pin state moves both contents between layouts by `GlobalKey` — never rebuild them.

**Search inside a panel** lives in the tab, under the tab row (`lib/widgets/navigation/nav_panel_search.dart`) — never in `AppTopBar`:
- the screen owns a `NavPanelSearchHost`, keeps `activeTab` in sync with its `TabController`, and wraps `paneContent` in `NavPanelSearchScope`; each `TabBarView` child is wrapped in `NavPanelSearchSlot(index: i, …)`
- a tab whose whole purpose is search (in-book search) draws its field permanently — `SearchPaneBase`
- any other tab with a search wraps its list in `NavPanelCollapsibleSearch(delegate: NavPanelSearchDelegate(...))` and puts `const NavPanelSearchToggle()` in the `trailing` of its main `NavTreeHeader`. The field opens from that icon, and its X (or Escape) closes it and clears the filter. A filter that is already set keeps it open
- a tab with no search shows nothing — no disabled field
- never build a bare `OtzariaSearchField` inside a nav-panel tab
- keyboard: Left/Right stay in the text; Up/Down move focus into the panel's rows (`NavPanelSearchHost.paneFocusScope`), and from there Flutter's directional traversal walks the rows and Enter activates — same behavior as the bookmarks/history dialogs. A tab whose delegate supplies `onArrowDown`/`onArrowUp` overrides this: the arrows browse a highlight through its results while focus stays in the field (find_ref model — the user keeps typing mid-browse), and Enter opens the highlighted result via `onSubmitted`

**Panel content** is built from `lib/widgets/lists/nav_tree_tile.dart`:
- `NavTreeHeader` — the main title above the list (primary color, bold) and any sub-tree root
- `NavTreeTile.category` / `NavTreeTile.book` — tree rows; `NavTreeContentRow` for free-form rows (search snippets)
- `NavTreeGroupCard` — a continuous run of rows shares one card (`isGroupStart` / `isGroupEnd` at its edges); a heading that owns sub-rows is its own standalone card
- `NavTreeFocusGroup` — wrap the list so Tab lands on the **selected** row, not the first; it also sorts before the tab row, so Arrow-Down from the search field enters the rows
- Horizontal inset comes from `kNavTreeSideInset` inside the card/header; lists pass only `kNavTreeListPadding`

**Never:**
- `AdaptiveSidePane` directly for a *navigation* panel — it is the mechanism (responsive layout, drag, overlay) and stays for other panel kinds
- A hand-rolled `TabBar` + `AnimatedPinButton` row as a panel header
- A per-screen open icon (`text_continuous`, `line_horizontal_3`, …) — the toggle is `NavPanelToggleButton`
- Hand-built tree rows with `Border(bottom:)`, explicit `fontSize`, or `primary`-colored icons
- Passing `paneColor` / `attachToTopEdge` to a nav panel — `NavSidePanel` owns them
- Adding a per-panel list `padding` for the tree — the inset lives in `NavTreeGroupCard` / `NavTreeHeader` (`kNavTreeSideInset`), and lists use `kNavTreeListPadding`
- A per-panel search field built from `RtlTextField` + `InputDecoration` — every field inside a nav panel is `OtzariaSearchField`

### 11. Middle-click autoscroll — already global, never re-implement

`MiddleClickAutoScroll` wraps the whole app once in `lib/app.dart`, so **every** scrollable area already supports middle-click autoscroll: lists, reading screens, the library, settings, dialogs, and the PDF viewer. It works by dispatching synthetic wheel events down the hit-test path captured on click, so anything that reacts to the mouse wheel reacts to it too — no per-screen wiring.

**Never:**
- Add a per-screen middle-click scroll handler, an anchor overlay, or an autoscroll timer — the global widget already covers it
- Wrap a screen in a second `MiddleClickAutoScroll`

**Do** wrap a region in `AutoScrollBarrier` when middle-click there is reserved for something else (a tab that closes on middle-click):
```dart
import 'package:otzaria/widgets/misc/middle_click_autoscroll.dart';

Listener(
  onPointerDown: (e) { if (e.buttons == kMiddleMouseButton) closeTab(tab); },
  child: AutoScrollBarrier(child: tabContent),
)
```
A barrier anywhere in the hit-test path suppresses autoscroll for that click.

