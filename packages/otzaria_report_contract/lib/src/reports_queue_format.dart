/// גרסת מבנה תור הדיווחים ש"עדכוני אוצריא" קוראת וכותבת ב-`user_state.db`:
/// טבלת `pending_reports`, סוגים `<box>/pending_reports` ו-`<box>/sent_reports`
/// (box: `error_reports_queue`, `app_reports_queue`, `plugin_reports_queue`),
/// ו-`payload_json` = `toJson()` של [DirectErrorReport] / [AppReport] /
/// [PluginReportRecord]. מעלים אותה בכל שינוי שקורא ישן לא יבין.
const int kReportsQueueFormat = 1;
