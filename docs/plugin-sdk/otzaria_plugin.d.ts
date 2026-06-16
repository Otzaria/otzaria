/**
 * Otzaria Plugin SDK — TypeScript Definitions
 * Version: 1.1.0
 *
 * Provides full type-safety when writing Otzaria plugins in TypeScript.
 *
 * Usage:
 *   Add to tsconfig.json: "include": ["otzaria_plugin.d.ts"]
 *   Or: /// <reference path="./otzaria_plugin.d.ts" />
 *
 * The `Otzaria` global is injected automatically by the host.
 * You do NOT need to import or load any script.
 *
 * ---------------------------------------------------------------------------
 * HTML Layout Requirements
 * ---------------------------------------------------------------------------
 *
 * SCROLLING
 *   The plugin runs inside a WebView2 (Windows) / WKWebView (iOS/macOS) /
 *   WebView (Android/Linux). Scrolling is NOT automatic — you must explicitly
 *   allow overflow on the root elements, otherwise the page will be clipped
 *   with no scrollbar and no mouse-wheel response:
 *
 *     html, body {
 *       height: 100%;
 *       overflow-y: auto;   ← required for vertical scroll
 *       overflow-x: hidden; ← or auto, depending on your layout
 *     }
 *
 *   If you use a custom scroll container (e.g. a div that fills the viewport),
 *   apply overflow-y: auto / scroll to that container instead of body.
 *   Avoid `overflow: hidden` on any ancestor of scrollable content.
 *
 * TAB VISIBILITY (manifest: contributes.toolTab.defaultPinned)
 *   Set `defaultPinned: true` in your manifest if you want the plugin tab to
 *   appear automatically in the toolbar after installation.
 *   If `defaultPinned: false`, the user must manually pin the plugin from the
 *   plugin side panel (🧩 button) before it appears as a tab.
 *
 * RTL SUPPORT
 *   Add `dir="rtl"` to the <html> element for Hebrew / Arabic content:
 *     <html dir="rtl" lang="he">
 */

// ---------------------------------------------------------------------------
// Shared types
// ---------------------------------------------------------------------------

/** Response envelope returned by every `Otzaria.call()` invocation. */
export interface OtzariaResponse<T = unknown> {
  success: boolean;
  data: T;
  error: { code: string; message: string } | null;
}

export interface ColorScheme {
  // ── שדות יסוד (SDK 1.0.0) — תמיד מוחזרים ──────────────────────────────
  primary: string;
  onPrimary: string;
  secondary: string;
  onSecondary: string;
  surface: string;
  onSurface: string;
  surfaceContainerHighest: string;
  error: string;
  onError: string;
  outline: string;

  // ── תפקידי צבע נוספים (נוספו ב-SDK 1.1.0) ─────────────────────────────
  // אופציונליים כדי לשמור תאימות לאחור: תוסף שרץ על גרסת אוצריא ישנה (1.0)
  // לא יקבל אותם. כשהם קיימים — מוחזרים יחד עם שדות היסוד מ-`app.getTheme`.
  primaryContainer?: string;
  onPrimaryContainer?: string;
  /** רקע כפתור ניווט פעיל בסרגל הצד (ה-pill) */
  secondaryContainer?: string;
  /** אייקון/טקסט מעל secondaryContainer */
  onSecondaryContainer?: string;
  tertiary?: string;
  onTertiary?: string;
  tertiaryContainer?: string;
  onTertiaryContainer?: string;
  onSurfaceVariant?: string;
  surfaceContainerLowest?: string;
  surfaceContainerLow?: string;
  surfaceContainer?: string;
  /** רקע הסרגל העליון (AppTopBar) במסכי הספרים */
  surfaceContainerHigh?: string;
  errorContainer?: string;
  onErrorContainer?: string;
  outlineVariant?: string;
  inverseSurface?: string;
  onInverseSurface?: string;
  inversePrimary?: string;
  shadow?: string;
  scrim?: string;
  surfaceTint?: string;
}

export interface Typography {
  fontFamily: string;
  fontSize: number;
  lineHeight: number;
  commentatorsFontFamily: string;
  commentatorsFontSize: number;
}

export interface ThemePayload {
  mode: 'light' | 'dark';
  colorScheme: ColorScheme;
  typography: Typography;
}

/** Delivered via `plugin.boot` exactly once, before any user interaction. */
export interface BootPayload {
  plugin: { id: string; version: string };
  app: {
    version: string;
    buildNumber?: string;
    platform: 'windows' | 'linux' | 'macos' | 'android' | 'ios' | string;
    locale: string;
    textDirection: 'ltr' | 'rtl';
  };
  theme: ThemePayload;
  /** Currently granted permissions at boot time.
   *  For a fresh runtime snapshot, call `app.getGrantedPermissions()` or
   *  listen to `plugin.permissions_changed`. */
  permissions: string[];
}

export interface PermissionSnapshot {
  permissions: string[];
}

export interface BookMeta {
  bookId: string;
  title: string;
  topics?: string[];
}

export interface SearchResult {
  book: string;
  text: string;
  index: number;
}

export interface TocEntry {
  text: string;
  index: number;
  level: number;
}

export type JewishHolidayKind =
  | 'yomTov'
  | 'roshChodesh'
  | 'taanit'
  | 'special';

export interface JewishHoliday {
  text: string;
  kind: JewishHolidayKind;
}

export interface JewishDate {
  year: number;
  month: number;
  day: number;
  /** ISO 8601 Gregorian equivalent */
  gregorian: string;
  monthName: string;
  isLeapYear: boolean;
  isShabbat: boolean;
  holidays: JewishHoliday[];
}

export interface CalendarEvent {
  id: string;
  title: string;
  /** ISO 8601 */
  date: string;
  description: string;
}

export interface ReaderState {
  currentBook: string | null;
  currentBookId: string | null;
  currentIndex: number;
  currentRef: string | null;
  openTabs: Array<{ bookId: string; book: string; index: number; currentRef: string | null }>;
}

export interface ReaderRefState {
  currentBook: string | null;
  currentBookId: string | null;
  currentIndex: number;
  currentRef: string | null;
}

export interface ReaderSelection {
  text: string;
  start: number | null;
  end: number | null;
  currentRef: string | null;
  currentBook: string;
  currentBookId: string;
  currentIndex: number;
}

export type PublishedDataType =
  | 'calendar.event'
  | 'saved.query'
  | 'note.draft'
  | 'reference.link'
  | 'tool.badge';

export interface PublishedRecord<TPayload = unknown> {
  type: PublishedDataType;
  /** 'global' | 'workspace:<id>' | 'book:<bookId>' */
  scope: string;
  key: string;
  payload: TPayload;
}

/** Payload shape for a `calendar.event` published record */
export interface CalendarEventPayload {
  title: string;
  /** ISO 8601 */
  startsAt: string;
  /** ISO 8601 (optional) */
  endsAt?: string;
  source: string;
  importance?: 'high' | 'medium' | 'low';
  description?: string;
}

// ---------------------------------------------------------------------------
// Event map
// ---------------------------------------------------------------------------

export interface OtzariaEventMap {
  /** Fired once after the SDK is ready, carries full boot context. */
  'plugin.boot': BootPayload;
  /** Fired once after boot. No payload. */
  'plugin.ready': undefined;
  /** Theme / dark-mode changed. */
  'theme.changed': ThemePayload;
  /** Top-level screen navigation changed. */
  'navigation.changed': { screen: 'library' | 'reading' | 'more' | 'settings' };
  /** Active book in the reader changed. */
  'reader.current_book_changed': { book: string; index: number };
  /** Current reading location changed (page, chapter, section). */
  'reader.current_ref_changed': {
    currentBook: string | null;
    currentBookId: string | null;
    currentIndex: number;
    currentRef: string | null;
  };
  /** Selected calendar date changed. */
  'calendar.date_changed': { date: string };
  /** Active workspace changed. */
  'workspace.changed': { workspaceId: string };
  /** A whitelisted app setting changed. */
  'settings.changed': { key: string; newValue: unknown };
  /** Permissions snapshot changed (list of all currently granted permissions). */
  'plugin.permissions_changed': { permissions: string[] };
  /** User selected text in the reader. Requires permission: events.subscribe:reader.selection_changed */
  'reader.selection_changed': {
    text: string;
    currentRef: string;
    currentBook: string;
    currentBookId: string;
    currentIndex: number;
  };
  /** User clicked a plugin-registered context menu item. Sent only to the registering plugin. */
  'reader.context_menu_item_clicked': {
    itemId: string;
    selectedText: string;
    currentRef: string;
    currentBook: string;
    currentBookId: string;
    currentIndex: number;
  };
}

export type NavigationTarget = 'library' | 'reading' | 'more' | 'settings';

// ---------------------------------------------------------------------------
// All valid method strings
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Database types
// ---------------------------------------------------------------------------

export interface DatabaseSourceSummary {
  id: string;
  label: string;
  available: boolean;
}

export interface DatabaseTableSchema {
  name: string;
  columns: string[];
}

export interface DatabaseSourceDescription {
  source: { id: string; label: string };
  schema: { tables: DatabaseTableSchema[] };
  limits: { maxLimit: number; maxBatchQueries: number };
}

export interface DatabaseSelectItem {
  expr: string;
  as?: string;
}

export interface DatabaseJoinCondition {
  left: string;
  op: '=';
  right: string;
}

export interface DatabaseJoin {
  type: 'inner' | 'left';
  table: string;
  alias?: string;
  on: DatabaseJoinCondition[];
}

export type DatabaseWhereOp =
  | '=' | '!=' | '>' | '>=' | '<' | '<='
  | 'in' | 'between' | 'like'
  | 'isNull' | 'isNotNull';

export interface DatabaseWhereLeaf {
  op: DatabaseWhereOp;
  left: string;
  value?: unknown;
}

export interface DatabaseWhereNode {
  op: 'and' | 'or';
  conditions: DatabaseWhereCondition[];
}

export type DatabaseWhereCondition = DatabaseWhereLeaf | DatabaseWhereNode;

export interface DatabaseOrderBy {
  expr: string;
  direction?: 'asc' | 'desc';
}

export interface DatabaseQuerySpec {
  sourceId: string;
  from: { table: string; alias?: string };
  select: DatabaseSelectItem[];
  joins?: DatabaseJoin[];
  where?: DatabaseWhereCondition;
  orderBy?: DatabaseOrderBy[];
  limit?: number;
  offset?: number;
  rowFormat?: 'array' | 'object';
}

export interface DatabaseQueryMeta {
  sourceId: string;
  rowCount: number;
  limit: number;
  offset: number;
  hasMore: boolean;
  elapsedMs: number;
}

export interface DatabaseColumnMeta {
  name: string;
}

export interface DatabaseQueryResult {
  meta: DatabaseQueryMeta;
  columns: DatabaseColumnMeta[];
  /** array format: each row is an array of values in columns order */
  rows: unknown[][] | Record<string, unknown>[];
}

export interface DatabaseBatchQuerySpec {
  queries: DatabaseQuerySpec[];
}

export interface DatabaseBatchQueryResult {
  results: DatabaseQueryResult[];
}

/** Where a `shortcut.create` deep-link shortcut is placed. `startMenu` is Windows-only. */
export type ShortcutLocation = 'desktop' | 'startMenu';

/**
 * Arguments for `shortcut.create`. The shortcut always opens the calling plugin
 * (`otzaria://open/plugin/<id>`); the host builds the deep-link itself, so the
 * plugin only supplies a display name and an optional location.
 */
export interface ShortcutCreateArgs {
  /** Display name and file name of the shortcut. */
  label: string;
  /** Target location. Defaults to `'desktop'`. */
  location?: ShortcutLocation;
}

/** Result of `shortcut.create`. */
export interface ShortcutCreateResult {
  /** `false` when the user declined the confirmation dialog. */
  created: boolean;
  /** Absolute path of the created shortcut file (present only when `created` is `true`). */
  path?: string;
}

export type OtzariaMethod =
  | 'app.getInfo'
  | 'app.getTheme'
  | 'app.getLocale'
  | 'app.getUserEmail'
  | 'app.getGrantedPermissions'
  | 'library.findBooks'
  | 'library.getBookMetadata'
  | 'library.listRecentBooks'
  | 'library.getBookContent'
  | 'library.getBookToc'
  | 'search.fullText'
  | 'reader.openBook'
  | 'reader.openBookAtRef'
  | 'reader.getCurrentState'
  | 'reader.getCurrentRef'
  | 'reader.getSelection'
  | 'navigation.goTo'
  | 'notes.list'
  | 'notes.getBookNotesSummary'
  | 'notes.add'
  | 'notes.update'
  | 'notes.delete'
  | 'ui.showMessage'
  | 'ui.showSuccess'
  | 'ui.showError'
  | 'ui.showConfirm'
  | 'ui.showWarning'
  | 'storage.get'
  | 'storage.set'
  | 'storage.remove'
  | 'storage.list'
  | 'settings.get'
  | 'settings.getMany'
  | 'calendar.getSelectedDate'
  | 'calendar.getDailyTimes'
  | 'calendar.getHalachicTimes'
  | 'calendar.getJewishDate'
  | 'calendar.getEvents'
  | 'publishedData.upsert'
  | 'publishedData.remove'
  | 'publishedData.listOwn'
  | 'feedback.sendEmail'
  | 'history.list'
  | 'history.listSearches'
  | 'history.clear'
  | 'history.remove'
  | 'notifications.showInApp'
  | 'notifications.sendSystem'
  | 'notifications.scheduleSystem'
  | 'notifications.cancel'
  | 'notifications.cancelAll'
  | 'notifications.checkPermissions'
  | 'notifications.requestPermissions'
  | 'database.listSources'
  | 'database.describeSource'
  | 'database.query'
  | 'database.batchQuery'
  | 'network.fetch'
  | 'network.download'
  | 'shortcut.create'
  | 'reader.addContextMenuItem'
  | 'reader.removeContextMenuItem'
  | 'reader.setHighlight'
  | 'reader.getHighlights'
  | 'reader.clearHighlight'
  | 'reader.clearAllHighlights';

// ---------------------------------------------------------------------------
// The global Otzaria object
// ---------------------------------------------------------------------------

export interface OtzariaGlobal {
  /**
   * Call a Host API method.
   *
   * @param method  Dot-separated, e.g. `'library.findBooks'`
   * @param payload Method arguments
   */
  call<T = unknown>(
    method: OtzariaMethod | string,
    payload?: Record<string, unknown>
  ): Promise<OtzariaResponse<T>>;

  /** Subscribe to a host-dispatched event. */
  on<K extends keyof OtzariaEventMap>(
    event: K,
    callback: (detail: OtzariaEventMap[K]) => void
  ): void;
  on(event: string, callback: (detail: unknown) => void): void;

  /** Unsubscribe. Must use the exact same function reference passed to `on()`. */
  off<K extends keyof OtzariaEventMap>(
    event: K,
    callback: (detail: OtzariaEventMap[K]) => void
  ): void;
  off(event: string, callback: (detail: unknown) => void): void;
}

// ---------------------------------------------------------------------------
// Augment global Window
// ---------------------------------------------------------------------------

declare global {
  interface Window {
    /** Injected automatically into every plugin WebView. */
    Otzaria: OtzariaGlobal;
  }
  const Otzaria: OtzariaGlobal;
}

export {};
