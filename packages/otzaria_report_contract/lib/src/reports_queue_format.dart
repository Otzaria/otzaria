/// גרסת מבנה תור הדיווחים ש"עדכוני אוצריא" קוראת וכותבת ב-`user_state.db`:
/// טבלת `pending_reports`, סוגים `<box>/pending_reports` ו-`<box>/sent_reports`
/// (box: `error_reports_queue`, `app_reports_queue`, `plugin_reports_queue`),
/// ו-`payload_json` = `toJson()` של [DirectErrorReport] / [AppReport] /
/// [PluginReportRecord]. מעלים אותה בכל שינוי שקורא ישן לא יבין.
// פורמט 2 מחייב שימור AppReport.schema; קורא ישן משכתב ל-1 ועלול לאבד
// דיווח תקין של 10/20 MiB שיידחה לצמיתות לפי מדיניות הצרופות הישנה.
const int kReportsQueueFormat = 2;

/// קורא אופליין ישן אינו בוחר סוג זה, גם אם קובץ היכולות חסר או נדרס.
const String kAppReportsPendingKindV2 = 'app_reports_queue/pending_reports_v2';

/// `carriedBy` ברשומת היסטוריה ש"עדכוני אוצריא" אספה מהתור ושולחת בעצמה;
/// לצידו `carriedAt` (ISO-8601).
const String kCarriedByOfflineUpdate = 'offline-update';
