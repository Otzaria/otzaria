# AI Agent Guidelines for Otzaria

## CRITICAL: Communication Language
**ALWAYS respond in Hebrew!** This includes:
- All answers and explanations
- Your thinking process
- Error messages and debugging info
- Only code/comments can be in English when appropriate

## Mandatory Workflow
1. **Plan** - Create detailed action plan before execution
2. **Execute** - Step by step until completion
3. **Validate** - Run `flutter analyze` after EVERY change
4. **Fix ALL errors before proceeding to next step**
5. **Never skip validation - errors compound quickly!**

## Bug Fix Workflow (MANDATORY)

**Primary rule: Investigate first, ask only if you truly must.**

Before writing any fix, perform the following steps **on your own** without asking the user:

1. **Understand the symptom** - What did the user report? If critical details are missing that are needed to *execute* the fix (not to analyze) - ask everything **in a single message**.
2. **Investigate git** - Run `git log --oneline -20` and check commits that touched relevant code.
3. **Read the code** - Read the code before proposing any fix. Don't assume, know.
4. **Identify the root cause** - If found, explain to the user what caused the bug before fixing it.

### Decision Tree

```
User reports bug
       │
       ▼
  Investigate first:
  git log + read code
       │
       ▼
 Root cause found?
   ┌───┴───┐
  YES      NO
   │           │
   ▼           ▼
Apply MINIMAL  Ask user ONE message
fix & explain  with ALL missing info
               then investigate again
```

### Proving a bug fix

Reproduce the reported behavior when practical. For a regression, prefer a focused test that fails before the fix and passes afterward, using the reporter's relevant conditions. Inspect all callers before changing shared code; preserve their behavior. Do not weaken an existing test just to make the change pass. For visible UI bugs, compare before/after behavior when practical. Report exactly which checks passed, failed or were not run.

### Fix Philosophy - CRITICAL

**Bug fix ≠ adding code!**

- **FIRST** - try to **remove** or **revert** code that caused the bug
- **SECOND** - try to **change** existing logic minimally
- **LAST RESORT** - add new code, only if truly necessary
- Adding more code to work around a bug = introducing future bugs

### Red Flags - Stop and Ask

If you find yourself about to:
- Add a `try/catch` to silence an error → find out *why* the error occurs first
- Add a null check that "shouldn't be needed" → find out *why* it's null
- Add a workaround flag/boolean → reconsider the root cause
- Write more than ~15 lines to fix a single bug → something is wrong, reassess

## Scope and artifacts

Follow the user's task scope. Do not create Markdown files for plans, progress logs, change summaries or test results by default; report those in the conversation or PR. Create or update a Markdown file when the user requests it, when it is a durable reference needed by this repository, or when an existing repository process explicitly requires it. Prefer updating an existing document.

## Other Contributors' Open Pull Requests (MANDATORY)

Several contributors work on `dev` in parallel and their pull requests are merged continuously. A change that ignores them duplicates work or conflicts as soon as theirs is merged.

- **Before starting** - list open PRs (`gh pr list -R Otzaria/otzaria --state open --json number,author,title,files`) and look for the same issue or the files you plan to change. If an open PR already fixes the issue, do not fix it again. If one touches the same code, build on its approach or coordinate in that PR.
- **Before opening a PR** - check each overlapping open PR for conflicts with yours: `git fetch upstream pull/<N>/head:pr-<N>` and `git merge-tree --write-tree pr-<N> HEAD`.
- **In the PR description** - name every overlapping open PR and whether it merges cleanly with yours.

## Architecture

### Design Patterns
- **BLoC Pattern** - State management (every feature needs: bloc/event/state)
- **Repository Pattern** - Separates data access from business logic
- **Provider** - For dependency injection across the app

### Feature Structure (MUST follow)
```
lib/feature_name/
├── bloc/
│   ├── feature_bloc.dart      # Business logic
│   ├── feature_event.dart     # User actions/events
│   └── feature_state.dart     # UI states
├── models/
│   └── feature_model.dart     # Data models
├── repository/
│   └── feature_repository.dart # Data layer
└── view/
    ├── feature_screen.dart    # Main screen
    └── widgets/               # Feature-specific widgets
```

### Key Code Locations
```
lib/
├── data/repository/
│   └── data_repository.dart           # Central books/library access
├── models/
│   └── books.dart                     # Book model (title, path, etc)
├── theme/                             # Tokens: AppTokens, AppSurfaces, AppDensity, AppMotion, WindowClass
├── widgets/                           # Shared UI catalog (see "UI rules")
│   ├── dialogs/ controls/ layout/ feedback/ navigation/ text/ misc/
│   └── text/rtl_text_field.dart       # RTL text input (USE THIS!)
├── core/
│   ├── ui_snack.dart                  # UiSnack for messages
│   └── messages/                      # Message catalogs (CommonMessages, ...)
├── search/
│   ├── bloc/                          # Search state management
│   └── search_repository.dart         # Search engine
├── settings/
│   ├── engine/                        # SettingsRepository, SettingsBloc
│   └── widgets/                       # SettingsCard and settings tiles
├── bookmarks/repository/              # Bookmarks system
├── history/                           # Reading history
├── personal_notes/                    # User notes feature
├── book_common/                       # Shared by text and PDF books
├── pdf_book/                          # PDF viewer screens
├── text_book/                         # Text viewer screens
└── utils/navigation/
    └── open_book.dart                 # Book opening logic
tool/ui_lint/                          # UI lint engine, config.yaml, baseline.json
docs/design-system/                    # Binding UI standard (see "UI rules")
```


## Startup Path (MANDATORY)

**The rule: nothing runs during startup unless it must run before the first frame.**

Every `await` added to `main()` is paid by every user on every launch, forever. Startup
regressions are also the hardest bugs in this app to diagnose: they reproduce only on the
reporter's machine, and the blocking call is usually invisible from Dart. Issues #343, #989 and
#1192 were three instances of the same mistake.

### Why Windows startup is different

On Windows the Dart **UI isolate runs on the platform thread**. A synchronous native call — COM /
WinRT, a registry write, `Process.run`, a plugin's `initialize()` — blocks that thread, and with
it **every Dart frame and every Dart timer**. In #1192 a notification-plugin init that costs ~50ms
on a dev machine blocked for **30 seconds** inside one COM call on a reporter's machine.

Two consequences that are easy to get wrong:

- **A `Future.timeout` does not protect you.** The timer that would fire it is queued on the same
  blocked thread. You cannot defend against synchronous native work with a Dart timeout — you can
  only avoid making the call.
- **A slow machine is not a slower version of yours.** Filtering agents, antivirus, managed
  profiles and roaming registry hives change the *shape* of the cost, not just its size: process
  spawn becomes ~1s each (#989), a registry subtree becomes unwritable, an OS service stops
  answering. Never conclude "it's fast" from your own box.

### Before adding anything to `main()` / `AppBootstrap`

Answer all three, in this order:

| Question | If the answer is… |
|---|---|
| Is it required to paint the first frame? | No → run it after reveal (below) |
| Do the call sites already initialize on demand? | Yes → **delete it** — that is the whole fix |
| Can it be skipped based on stored state? | Yes → gate on that state and run only when needed |

#1192 answered all three: the notification plugin was initialized eagerly, every call site already
did `if (!isInitialized) await init()`, and the one genuine need — restoring already-scheduled
alerts — applies only when alerts are actually stored. The fix deleted the call rather than
speeding it up.

### Running work after the window is revealed

Deferred work lives in a `_runDeferredX()` function in `main.dart`, launched with `unawaited(...)`,
and waits for the reveal with a timeout so it still runs if the reveal never lands:

```dart
Future<void> _runDeferredThing() async {
  try {
    await _mainWindowRevealedCompleter.future.timeout(const Duration(seconds: 20));
  } on TimeoutException {
    // ממשיכים בכל זאת — אחרת המשימה לא תרוץ כלל.
  }
  try {
    await doTheThing();
  } catch (error, stackTrace) {
    _logNonFatalInitializationError('Thing', error, stackTrace);
  }
}
```

Three parts, all mandatory:

1. **Once per process** for anything per-process or per-machine (registry, system
   notifications, update checks, error-report flush). `main()` runs once, so start it there; work
   started from a per-window widget (e.g. `MainWindowScreen`) is gated with
   `ProcessDuties.of(context).isProcessOwner`, or every Dart window repeats it.
2. **Reveal gate with a timeout** — never an unguarded `await` on the completer.
   **Exception:** a step that makes a synchronous native call (e.g. building the Sentry options over FFI in
   `_initializeSentry`) awaits the reveal with **no** timeout. Running it before reveal is the
   #1192 block itself, and it would hit exactly the machines whose reveal is slow. Our
   sentry_flutter fork loads `sentry.dll` and runs `sentry_init` on helper isolates (#3422).
3. **Non-fatal failure** — a startup step must never abort the boot. It logs through
   `_logNonFatalInitializationError` and returns.

### Forbidden on the startup path

| Never | Instead |
|---|---|
| Synchronous COM / WinRT / FFI on the main isolate | Defer past reveal, or don't call it |
| `Process.run` in a loop (`reg.exe`, `which`, …) | Use the direct API (#989: 10 spawns blew every timeout) |
| A network call without a timeout | Explicit timeout on every request (#343) |
| Heavy CPU on the main isolate (parsing, scanning, hashing) | `compute` / `Isolate.run` |
| Sync file I/O over a directory tree | Async, off the reveal path, memoized |
| A failure that propagates out of an init step | `_logNonFatalInitializationError` |

**Cosmetic extras are best-effort, and must say so.** A step that only improves polish — a shell
icon, an Office trusted-protocol key, a cache warm-up — swallows its own failures per item, so one
denied write does not abort the rest and does not reach the error log. Registering a real handler
is not cosmetic; marking it trusted is.

### Instrumentation

`StartupTimeline` (`lib/core/startup_timeline.dart`) records phases and marks and writes a
`=== Slow startup` record to `errors.txt` only when reveal exceeded its threshold. It carries a
**deliberately small permanent skeleton** — the bootstrap phases, `reveal:*`, `mainScreenInit`,
`bootstrapDone`/`bootstrapReady` and the stall detector.

- Wrap a new heavy startup step in `StartupTimeline.instance.phase('name', ...)` — that is the
  skeleton growing correctly.
- **Never put a mark inside `build()` or a per-frame callback.** Marks added while chasing a
  specific report are temporary: remove them in the same PR that fixes the cause.
- A `stall:<ms>` mark means the isolate stopped answering — the blocker is synchronous, and if no
  Dart mark brackets it, it is **native**.

When Dart-side marks show nothing, use the native stall detector in
`windows/runner/startup_watchdog.cpp`. It suspends the main thread, unwinds it without dbghelp, and
appends `=== Startup heartbeat delay` with module+RVA frames to `errors.txt`. It stops itself at reveal and
is silent on a healthy launch. That is how #1192 was found after three rounds of Dart instrumentation
missed it.

After reveal, `windows/runner/hang_monitor.cpp` polls `IsHungAppWindow` once a second (no WM_TIMER,
which floods starve) and writes `=== App hang` / `=== App hang recovered`; Dart offers a report
under the crash-report setting (`lib/app_report/services/app_hang_report.dart`).

**Reading a hang stack.** Every Dart-code hang ends in the same engine frames (`DartEntry::Invoke*`
called from `BeginFrame` or a platform message). The cause is in the `app.so+0x…` frames above them.
Name those frames with the release asset `otzaria-dart-symbols-windows-<arch>.debug`:
`dart run tool/symbolize_hang_report.dart --symbols <file> errors.txt`. The tool skips any record
whose `Dart build-id` does not match the file. `Build commit` identifies a dev build, and those have no
published symbols. Windows builds published by `build-and-announce.yml` ship a patched `flutter_windows.dll`
(`.github/actions/patched-flutter-engine`): name its frames with the `.pdb` from the `palmoni5/flutter` release
`otzaria-3.47.7-a11y.1`, picked by the GUID in the record's `Module PDB:` line (x64
`9A3F8E48-5EA7-4A0A-8316-21352F723250`, arm64 `7324F4D1-92B4-455F-BA47-E65B47E2E69B`). Other builds use the official PDB from
`flutter_infra_release/flutter/<engine.version>/windows-x64-release/windows-x64-flutter.zip`.
For system-DLL frames, fetch the PDB from the Microsoft symbol server using the record's `Module PDB`
line (the tool prints the URL).

## Developer diagnostics (measuring the real app)

To compare performance before and after a change, run the real app with developer diagnostics
instead of guessing from code. It records frame timings, memory (the app and, on Windows, every
WebView2 process by kind), slow frames with app context, the startup timeline and, in debug builds,
rebuild counts per widget type.

**Enable it** with Ctrl+Shift+I in the running app (for this run only), or at launch:

```bash
build/windows/x64/runner/Release/otzaria.exe --dev-diagnostics       # panel + log
build/windows/x64/runner/Release/otzaria.exe --dev-diagnostics=log   # log only, no panel
OTZARIA_DEV_DIAGNOSTICS=log flutter run -d windows --profile          # env var form
```

**Output:** JSON lines appended to `<data root>/logs/developer_diagnostics.jsonl` (next to
`errors.txt`; `%APPDATA%\otzaria\logs` on Windows). Override with `OTZARIA_DEV_DIAGNOSTICS_OUT`.

| `type` | When | Fields |
|---|---|---|
| `session` | collection starts | version, buildMode, os, cores, pid, launchMode |
| `startup` | once, after the window is revealed | revealMs, phases, marks |
| `context` | the screen or current tab changed | screen, tabs, currentTab, currentTitle |
| `stats` | every second with frames, rebuilds, estimate refreshes or rendered lines, and every 5 s with a process sample | fps, build/raster avg and max ms, slowInWindow, slowTotal, rssMb, peakRssMb, rebuilds (debug), processes, estimates (reader lists' estimate refreshes in that second: count, totalMs when each list refreshed once, items, deferred, skipped; only when one of them is non-zero), smartText (SmartTextWidget lines per path, full-path reasons, processText cache, fwfh subtree build ms) |
| `slow_frame` | a frame took 100 ms or more | buildMs, rasterMs, totalMs, context |
| `snapshot` | the panel's camera button | stats + processes + context + startup (also written to errors.txt) |

`processes` is private memory (commit charge) in MB: `hostPrivMb`, `webviewPrivMb`, and per kind
`webview.<KIND>.count/privMb`, with `eachMb` and `pages` (the main frame of each renderer) for
`RENDERER`. Kinds come from `WebViewEnvironment.getProcessInfos()`. It is sampled every 5 s, only
after reveal, on Windows (Linux: WPE children via `/proc`); other platforms have no WebView pids.

`t` is milliseconds since collection started. Use profile or release builds for timings; debug
builds are several times slower but are the only ones with `rebuilds`, repaint rainbow and layout
bounds. Compare runs on the same machine, library and scenario, and repeat each side at least
twice.

## UI rules

The binding UI standard is the design system in `docs/design-system/`. Read only the section you need; do not load the whole folder for unrelated tasks.

| Document | Use it for |
|---|---|
| `DESIGN_SYSTEM.md` | The standard. Start with its "מתחילים כאן" section (need → component table, the five things never to write, what to do when ui_lint fails). Then: tokens (§2), component catalog (§3), layer boundaries (§4), responsive rules (§5), RTL/keyboard/accessibility (§6), themes (§7), and how to work with it (§8: picking a token, building a dialog/field/card/screen, loading-empty-error states, new components, exceptions, ui_lint failures, required tests) |
| `DESIGN_DECISIONS.md` | Settled decisions (DD-xx). Follow them; do not re-decide in a PR. Each one lists the alternatives, the reason, what is implemented and the commits |
| `CI_ENFORCEMENT.md` | The `tool/ui_lint` rules, baseline, goldens and CI guards |

Component-specific usage notes (icons, UiSnack catalogs, settings strings, nav panels) are in `docs/agent_ui_reference.md`.

### Core rules
- Pick a role, not a value. Colour comes from `ColorScheme` / `AppSurfaces`, UI text from `textTheme` (no `fontSize:` or literal `fontFamily` in feature code), and spacing, radius (8 only), icon size and motion from `AppTokens` / `AppDensity` / `AppMotion`. Book-content typography comes from the reading settings. Do not add colour overrides in feature files.
- Layout decisions use `WindowClass` or the parent's `LayoutBuilder` constraints, never orientation. Use directional APIs (`EdgeInsetsDirectional`, `AlignmentDirectional`, `start`/`end`).
- Every icon-only button has a `tooltip`. A tappable widget that is not a Material button needs `Semantics(button:)`, Enter/Space and focus.
- Icons: prefer `otzaria_icons` for its supported cases, and use Fluent for generic chrome and the documented exceptions. `OtzariaIcons` always uses plain `Icon`; registered directional Fluent icons use `RtlIcon`. Never use Material/Cupertino icons, and never flip icons manually.
- New settings, navigation and tour strings use `context.settingsText` and `settings_en.arb`. Regenerate the catalog and run `flutter test test/settings/l10n/`.
- Messages go through the `UiSnack` catalogs in `lib/core/messages/`. Never show `e.toString()` to the user.
- Navigation panels use `NavSidePanel` and its shared search/tree components. Middle-click autoscroll is global; use `AutoScrollBarrier` only where middle-click has another action.

### Which shared component to use
Never add a raw `AlertDialog`/`Dialog`/`TextButton`/`FilledButton`/`OutlinedButton`/`Card`/`CircularProgressIndicator`/`PopupMenuButton`. Use the catalog, which is documented in full in `DESIGN_SYSTEM.md` §3:

| Need | Use | Where |
|---|---|---|
| Dialog | `showSingleActionDialog` / `showTwoActionsDialog` / `showWarningDialog` / `showChoiceDialog` / `showInputDialog` / `showSelectionDialog`; custom content in `AppDialogFrame` (`AppDialogSize`) | `lib/widgets/dialogs/` |
| Unsaved-changes guard | `DialogDismissGuard`, `confirmDiscardChanges` | `lib/widgets/dialogs/dialog_dismiss_guard.dart` |
| Buttons | `ActionButton` (variants), `SquareIconButton`, `AppIconButton`, `BarButton`, `AppTogglePill`, `StatusChip` | `lib/widgets/controls/` |
| Text input and search | `RtlTextField`, `OtzariaSearchField` (+ `OtzariaSearchFieldButton`) | `lib/widgets/text/` |
| Choice | `AppSegmentedControl`, `AppDropdownField`, `AppPopupMenuButton` / `showAnchoredAppMenu` | `lib/widgets/controls/`, `lib/widgets/misc/` |
| Cards and results | `AppCard`, `ResultCardFrame`, `ToolResultCardShell`, `ToolResultsHeader`, `MetaChip` | `lib/widgets/layout/` |
| Section headings | `AppSectionLabel` | `lib/widgets/text/` |
| Loading, empty, error, notices | `LoadingIndicator` / `SkeletonLines`, `OtzariaEmptyState`, `OtzariaErrorState`, `AppInfoBanner`, `UiSnack` | `lib/widgets/feedback/`, `lib/core/ui_snack.dart` |
| Screen layout | `AppTopBar`, `ToolScaffold`, `AdaptiveSidePane`, `ContextOverlayPanel`, `NavSidePanel`, `SearchResultNavigator` | `lib/widgets/layout/`, `lib/widgets/navigation/` |
| Settings | `SettingsCard` and its tiles (`SettingsSwitchTile`, `SettingsDropdownTile`, `SettingsSegmentedTile`, `SettingsSliderTile`, `SettingsPathTile`, `SettingsActionTile`) | `lib/settings/widgets/` |
| Window caption (Windows) | `AppWindowCaption`, `AppCaptionIconButton` | `lib/core/windowing/` |

A widget that only fits one feature's content or geometry may stay in `lib/<feature>/view/widgets/`. It must be built from catalog components and tokens, and it is not imported by other modules (`DESIGN_SYSTEM.md` §8.5).

### ui_lint and baseline
- `tool/ui_lint` checks the design rules (UIL-xxx, catalog in `CI_ENFORCEMENT.md`). Rules at the blocking stage fail `test/design_system/ui_lint_test.dart` on any new violation and on any stale baseline entry.
- Run `dart tool/ui_lint_cli.dart` for the report. After you fix existing debt, run `dart tool/ui_lint_cli.dart --update-baseline` so the fixed entries leave `tool/ui_lint/baseline.json`.
- Never add your own violations to the baseline to pass the test. Fix them, or justify them as exceptions (below). Growth in the baseline (`--allow-growth`) needs the `ui-baseline` label from a maintainer (`ui_baseline_guard.yml`).
- A changed golden PNG needs the `goldens-approved` label (`goldens_guard.yml`), and the reviewer checks the GitHub image diff. The threshold stays 0.05% (DD-22).

### Processes
- **Adding a token.** Use an existing role or scale value first (`DESIGN_SYSTEM.md` §8.1). A value off the scale rounds up. A theme-dependent surface or state goes into `AppSurfaceColors` (`lib/theme/app_surface_colors.dart`) and is read through `AppSurfaces`; a state colour derived directly from a `ColorScheme` role can be an `AppSurfaces` function. Either way, with a one-line comment, in the same PR that uses it. A new scale value or semantic colour needs a DD in `DESIGN_DECISIONS.md` approved by a maintainer, plus `test/theme/` contrast coverage for all seeds.
- **Adding a shared component.** Only when the same role appears in 3+ places or 2+ modules and no existing component can take a variant (`DESIGN_SYSTEM.md` §8.5). Keep the API small (variants, not booleans; no escape hatches), with no feature imports. Add a contract test in `test/design_system/contracts/`, plus a golden if it has a look. Move the call sites that justified it in the same PR, and go through the checklist in `DESIGN_SYSTEM.md` §8.5. Before replacing an existing API, find every caller and write the contract test first; keep a temporary compatibility layer only when it is really needed, with a written removal condition, so two competing implementations do not remain (`DESIGN_SYSTEM.md` §3).
- **Getting an exception approved.** Put `// ui-lint: allow UIL-xxx — <reason>` on the line directly above the flagged node. Use one rule per comment, with a real reason (12+ characters) and the DD that allows it, e.g. `(DD-24)`. Local colour is allowed only for content, export/print and OS-chrome imitation. A whole-folder exception goes into `tool/ui_lint/config.yaml` with `reason:` and needs maintainer approval. Never use `// ignore:` for ui-lint rules, and never exempt a whole file.

### PR checklist for visual changes
Before opening the PR, confirm that no open PR already covers the topic, that the branch is current with `dev`, that it carries no unrelated files, and that the design decisions it relies on are approved. The PR description states:
1. The goal.
2. The DD ids it implements.
3. The problems it fixes (what was wrong before).
4. Changed infrastructure files (theme, `lib/widgets/`, `tool/ui_lint`).
5. Affected components and screens.
6. Impact on behaviour.
7. Before/after shots from the same scenario at the same size.
8. Tests that were run.
9. Tests that were not run.
10. Remaining exceptions (allow comments, baseline).
11. Regression risks.
12. Related PRs.

The checklist is also in `.github/PULL_REQUEST_TEMPLATE.md`. The per-change checks (light, dark and the "לבן" (white) theme, RTL, width 360 and full, text ×1.3) and the required tests are in `DESIGN_SYSTEM.md` §8.7.

## Code Guidelines

### RTL Support (Critical!)
The app uses `locale: Locale("he", "IL")` + `GlobalWidgetsLocalizations.delegate` in `MaterialApp`.
This sets `Directionality.rtl` **globally** for the entire widget tree — every `Text` inherits RTL automatically.

**textDirection rule — Critical:**
- **NEVER add** `textDirection: TextDirection.rtl` to `Text` — it is completely redundant.
- **ADD** `textDirection: TextDirection.ltr` **only** for inherently LTR content:
  - OS file / folder paths
  - Email addresses
  - Version numbers / hash values
  - URLs
  - Technical identifiers (clearly LTR format)
- For parameters like `subtitleDirection` — pass `textDirection` to `Text` **only when the value is LTR**:
  ```dart
  // Correct:
  textDirection: subtitleDirection == TextDirection.ltr ? TextDirection.ltr : null,
  // Wrong — never pass TextDirection.rtl:
  // textDirection: subtitleDirection,  // ❌ when the default is rtl
  ```
- Use `RtlTextField` for all text inputs
- Test UI with Hebrew text before committing

### BLoC Pattern Implementation
```dart
// 1. Events - User actions
sealed class FeatureEvent extends Equatable {
  const FeatureEvent();
}

class LoadDataEvent extends FeatureEvent {
  const LoadDataEvent();
  @override
  List<Object> get props => [];
}

// 2. States - UI states
sealed class FeatureState extends Equatable {
  const FeatureState();
}

class InitialState extends FeatureState {
  @override
  List<Object> get props => [];
}

class LoadingState extends FeatureState {
  @override
  List<Object> get props => [];
}

class LoadedState extends FeatureState {
  final Data data;
  const LoadedState(this.data);
  @override
  List<Object> get props => [data];
}

// 3. Bloc - Logic
class FeatureBloc extends Bloc<FeatureEvent, FeatureState> {
  final FeatureRepository repository;
  
  FeatureBloc({required this.repository}) : super(InitialState()) {
    on<LoadDataEvent>(_onLoadData);
  }
  
  Future<void> _onLoadData(
    LoadDataEvent event,
    Emitter<FeatureState> emit,
  ) async {
    emit(LoadingState());
    try {
      final data = await repository.fetchData();
      emit(LoadedState(data));
    } catch (e) {
      emit(ErrorState(e.toString()));
      UiSnack.showError(CommonMessages.loadFailed); // never show e.toString()
    }
  }
}
```

### Repository Pattern
```dart
class FeatureRepository {
  final DataSource dataSource;  // Could be API, DB, file system
  
  FeatureRepository({required this.dataSource});
  
  Future<List<Item>> getItems() async {
    try {
      final rawData = await dataSource.fetch();
      return rawData.map((e) => Item.fromJson(e)).toList();
    } catch (e) {
      throw RepositoryException('Failed to get items: $e');
    }
  }
}
```

### Error Handling
```dart
try {
  await riskyOperation();
} catch (e, stackTrace) {
  // Log for debugging
  debugPrint('Error: $e\n$stackTrace');
  
  // Show user-friendly message
  UiSnack.showError(CommonMessages.loadFailed); // a catalog message, not the exception
  
  // Update state if needed
  emit(ErrorState(e.toString()));
}
```

### Documentation (Hebrew for public APIs)
```dart
/// Returns a list of books by category
///
/// [category] - the category name
/// Returns [Future<List<Book>>] - list of books or error
/// Throws [RepositoryException] if data not found
Future<List<Book>> getBooksByCategory(String category) async {
  // Implementation
}
```

### Code Comments — Minimal & For the First-Time Reader (MANDATORY)

**הכלל: פחות הערות, וקצרות. הוסף הערה רק כשהיא באמת נצרכת.**

- **כמות** - אל תוסיף הרבה הערות. רוב הקוד צריך להסביר את עצמו דרך שמות ברורים.
- **אורך** - הערה נצרכת תהיה קצרה - **מקסימום 2 שורות**.
- **קהל היעד** - כתוב הערה רק למי שקורא את הקוד **בפעם הראשונה**. ההערה מסבירה *למה* הקוד עושה משהו לא מובן מאליו, או מתעדת מלכוד שאם ישנו אותו יחזור באג. זו ההצדקה היחידה להערה.
- **לא רלוונטי** - אסור להערות שמתעדות היסטוריה: "פעם היה כך", "שונה ב-commit X", "הוספנו כי...", "TODO ישן", קוד מבוטל בהערה. למשתמש שקורא עכשיו לא מעניין מה היה - הגיט מתעד את זה.

```dart
// ❌ רע - מתעד היסטוריה, לא רלוונטי לקורא:
// פעם השתמשנו ב-setFullScreen אבל זה איבד WS_VISIBLE אז שינינו

// ✅ טוב - מזהיר ממלכוד שיחזיר באג אם ישונה (קצר):
// setFullScreen על חלון מוסתר מאבד WS_VISIBLE - חובה להציג קודם
```

**אם נתקלת בהערה קיימת שמפרה את ההנחיה משמעותית** (ארוכה מדי, מתעדת היסטוריה, מיותרת) - **תקן/מחק אותה** כחלק מהעבודה על אותו קובץ.

## Testing Strategy

### Before Every Commit (MANDATORY)
```bash
flutter analyze              # Must pass with ZERO errors/warnings
flutter test test/feature/   # Run ONLY tests related to your changes
dart format lib/file.dart    # Format ONLY files you modified
```

> **Tip:** The project uses `dart_pre_commit` as a git pre-commit hook.
> After cloning, run once: `dart run tool/install_git_hooks.dart`.
> From that point, `dart format` and `dart analyze` run automatically on staged files
> before every commit. Tests must still be run manually — they are not part of the hook.

### When to Run Which Tests
| Change Type | Tests to Run |
|-------------|--------------|
| Modified `lib/search/` | `flutter test test/search/` |
| Modified shared widget | All tests using that widget |
| New feature | All tests for that feature |
| Changed interface/contract | All affected integration tests |
| Modified core logic | Full test suite |

### Choosing tests

Run the tests relevant to the change. Start with `rg --files test | rg '<feature|symbol>'`; consult `docs/agent_test_map.md` when the matching suite is unclear. Read only the relevant section. Do not load the full map for every task.

### Writing Tests
- **Bloc**: Use `bloc_test` package
- **Repository**: Mock dependencies with `mockito`
- **Always add/update tests** for code you change
- Example:
```dart
blocTest<SearchBloc, SearchState>(
  'emits SearchLoaded when search succeeds',
  build: () => SearchBloc(repository: mockRepository),
  act: (bloc) => bloc.add(SearchRequested('query')),
  expect: () => [SearchLoading(), SearchLoaded(results)],
);
```

## Keeping a Branch Up to Date

`dev` moves quickly; a branch that falls behind it conflicts or is tested against code that no longer exists.

- Branch from the latest `upstream/dev`.
- Before opening a PR and before every push, rebase on the latest `upstream/dev`, then rerun `flutter analyze` and the tests related to your change.
- Keep diffs in shared files as small as possible; every extra line is a potential conflict.

## Essential Commands
```bash
flutter pub get              # Install dependencies
flutter pub outdated         # Check for updates
dart fix --apply            # Auto-fix common issues
flutter clean && flutter pub get  # Nuclear option for build issues
```

`pubspec.lock` is committed. Do not run `flutter pub upgrade` as part of an unrelated change: a pull request that changes `pubspec.lock` without changing `pubspec.yaml` fails the Lockfile Guard check, and CI resolves dependencies with `--enforce-lockfile`.

### Native libraries (search engine, OpenType shaper)

Both packages ship their Rust library through a Dart build hook (`hook/build.dart`), not a platform plugin: it downloads the signed binary published for the crate hash, or compiles it with cargo (needs [rustup](https://rustup.rs)) when none is published, as for a Git-pinned engine. `flutter build` and `flutter test` both run it; the library lands in `build/native_assets/<os>/` and next to the app. To force the source build, set `hooks: user_defines: otzaria_search_engine: build_from_source: true` in `pubspec.yaml`. With a Git- or path-pinned engine whose hash has no published binary, every `flutter test` needs Rust installed: the hook fails instead of the engine tests skipping.

If copying `search_engine.dll` fails, a process may hold the destination open (often an orphaned `flutter_tester.exe`). Identify the holder before stopping it; a running app's DLL under `runner/Debug` is unrelated. Tests load a separate copy from `build/test_engine/` via `test/support/search_engine_test_init.dart`; do not point them back to the build output.

## Platform Support
**Supported:** Windows, Linux, Android, iOS, macOS

Use platform checks when needed:
```dart
import 'dart:io';

if (Platform.isAndroid || Platform.isIOS) {
  // Mobile-specific code
} else {
  // Desktop-specific code
}
```
