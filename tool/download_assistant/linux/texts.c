#include "texts.h"

#include <stdarg.h>
#include <string.h>

#include "otz_common.h"

#define RLM "\xE2\x80\x8F"
#define NBSP "\xC2\xA0"

static const char *const hebrew[S_COUNT] = {
    [S_APP_TITLE] = "מסייע ההורדות של אוצריא",
    [S_WELCOME_SUBTITLE] = "ספרייה תורנית חינמית",
    [S_WELCOME_NOTE] = "הכלי אינו מתקין דבר — הוא מוריד את קובצי אוצריא ומכין מהם "
                       "התקנה, גם למחשב בלי אינטרנט.",
    [S_START_BUTTON] = "בואו נתחיל",
    [S_NEXT] = "המשך",
    [S_BACK] = "חזרה",
    [S_START] = "התחל",
    [S_FINISH] = "סיום",
    [S_CANCEL] = "ביטול",
    [S_CLOSE] = "סגור",
    [S_OK] = "אישור",
    [S_STOP_DOWNLOAD] = "עצור הורדה",
    [S_RETRY] = "נסה שוב",
    [S_RESUME] = "המשך",
    [S_OPEN_DOWNLOADS] = "פתח את עמוד ההורדות",
    [S_TECH_DETAILS] = "פרטים טכניים",
    [S_STEP_OF] = "שלב %1 מתוך %2",
    [S_CONNECT_TITLE] = "מתחבר לאתר אוצריא",
    [S_CONNECT_DESC] = "מוריד את רשימת הקבצים של הגרסה העדכנית.",
    [S_CONNECTING_PROGRESS] = "מתחבר לאתר אוצריא…",
    [S_MODE_TITLE] = "לאיזה מחשב מכינים את ההתקנה?",
    [S_MODE_DESC] = "המסייע מוריד את קובצי ההתקנה ושומר אותם בתיקייה. הוא עצמו "
                    "אינו מתקין דבר.",
    [S_MODE_THIS] = "Linux — כמו המחשב הזה",
    [S_MODE_THIS_DESC] = "מתאים למחשב הזה ולכל מחשב עם %1. הקבצים נשמרים בתיקייה, "
                         "להתקנה כאן או להעתקה.",
    [S_THIS_DEB] = "Ubuntu, Debian, Mint או הפצה דומה",
    [S_THIS_RPM] = "Fedora, openSUSE או הפצה דומה",
    [S_THIS_PORTABLE] = "הפצת Linux אחרת",
    [S_THIS_ARM] = "%1 ומעבד ARM",
    [S_MODE_OTHER] = "סוג מחשב אחר",
    [S_MODE_OTHER_DESC] = "מתאים ל-%1. הקבצים נשמרים בתיקייה, להעתקה בדיסק-און-קי.",
    [S_LIST_OR] = "%1 או %2",
    [S_VERSION_TO_DOWNLOAD] = "הגרסה שתורד: %1",
    [S_OTZARIA_VERSION] = "אוצריא %1",
    [S_OTHER_TITLE] = "לאיזה סוג מחשב?",
    [S_OTHER_DESC] = "בחר את סוג המחשב שבו תותקן אוצריא.",
    [S_OTHER_HINT] = "ב-Linux, אם אינך יודע איזו הפצה מותקנת, בחר DEB — היא מתאימה "
                     "לרוב המחשבים.",
    [S_TARGET_ARM] = "%1 · מעבד ARM",
    [S_HINT_MAC] = "מחשבי Mac",
    [S_HINT_ANDROID] = "טלפון או טאבלט",
    [S_HINT_ARM] = "למשל מחשבים עם מעבד Snapdragon",
    [S_HINT_X64] = "מעבד Intel או AMD — כמעט כל המחשבים",
    [S_FORMAT_DEB] = "Ubuntu, Debian, Mint והפצות דומות (DEB)",
    [S_FORMAT_RPM] = "Fedora, openSUSE והפצות דומות (RPM)",
    [S_FORMAT_PORTABLE] = "הפצה אחרת — ללא התקנה",
    [S_PRESET_TITLE] = "מה להוריד",
    [S_PRESET_DESC] = "בחר את היקף ההורדה.",
    [S_PRESET_HINT] = "אפשר לשנות את הבחירה בהמשך.",
    [S_PRESET_FULL_INDEXED] = "התקנה מלאה + אינדקס חיפוש",
    [S_PRESET_FULL_INDEXED_DESC] = "למחשב שאין בו אינטרנט — אינדקס החיפוש מוכן, "
                                   "והחיפוש עובד מיד. כולל" NBSP "חיפוש" NBSP "חכם.",
    [S_PRESET_FULL] = "התקנה מלאה",
    [S_PRESET_FULL_DESC] = "למחשב שאין בו אינטרנט — אינדקס החיפוש ייבנה בתוכנה, וזה "
                           "לוקח זמן. כולל" NBSP "חיפוש" NBSP "חכם.",
    [S_PRESET_BASIC] = "התקנה בסיסית (מומלצת)",
    [S_PRESET_BASIC_DESC] = "למחשב שיש בו אינטרנט — הספרייה תרד מתוך התוכנה.",
    [S_PRESET_UPDATE] = "עדכון התוכנה בלבד",
    [S_PRESET_UPDATE_DESC] = "קובץ ההתקנה של הגרסה החדשה, לעדכון התקנה קיימת.",
    [S_PRESET_CUSTOM] = "בחירה אישית",
    [S_PRESET_CUSTOM_DESC] = "אני רוצה לבחור בעצמי מה להוריד.",
    [S_CARD_SIZE] = "גודל ההורדה: %1",
    [S_REQUIRED_TAG] = "(נדרש)",
    [S_CUSTOM_DESC] = "סמן את הרכיבים שברצונך להוריד.",
    [S_CUSTOM_HINT] = "ליד כל רכיב מופיע גודל ההורדה שלו.",
    [S_FOLDER_TITLE] = "לאן לשמור",
    [S_FOLDER_DESC] = "כברירת מחדל הקבצים נשמרים ליד המסייע עצמו.",
    [S_FOLDER_HINT] = "אפשר לבחור תיקייה אחרת. מהתיקייה הזאת מתקינים — במחשב הזה, או "
                      "אחרי העתקה לדיסק-און-קי גם במחשב בלי אינטרנט.",
    [S_FOLDER_FALLBACK_NOTE] = "אי אפשר לשמור בתיקייה שממנה הופעל המסייע (למשל "
                               "דיסק-און-קי לקריאה בלבד), ולכן הוצעה כאן תיקייה "
                               "אחרת.",
    [S_BROWSE] = "עיון…",
    [S_CHOOSE] = "בחר",
    [S_READY_TITLE] = "מוכנים להתחיל",
    [S_READY_DESC] = "הכול מוכן להורדה.",
    [S_READY_HINT] = "לחץ \"התחל\" כדי להוריד את הקבצים ולהכין מהם התקנה.",
    [S_ROW_VERSION] = "גרסה",
    [S_ROW_WHAT] = "מה יורד",
    [S_ROW_FOR] = "עבור",
    [S_ROW_SAVED_IN] = "נשמר בתיקייה",
    [S_ROW_FILE] = "הקובץ",
    [S_ROW_FOLDER] = "בתיקייה",
    [S_DOWNLOADING_VERSION] = "מוריד את %1…",
    [S_DOWNLOAD_DESC] = "הקבצים יורדים מאתר אוצריא. אפשר לעצור בכל רגע — מה שכבר ירד "
                        "יישמר.",
    [S_DOWNLOADING_ITEM] = "מוריד: %1 (%2 מתוך %3)",
    [S_DOWNLOADED_OF] = "ירדו %1 מתוך %2",
    [S_TIME_LEFT] = "נותרו %1",
    [S_SIZE_OF] = "%1 מתוך %2",
    [S_WORK_TITLE] = "הכנת ההתקנה",
    [S_WORK_DESC] = "רגע, מכינים את הקבצים.",
    [S_PREPARING] = "מתכונן…",
    [S_CHECKING_CACHED] = "בודק קבצים שכבר הורדו: %1",
    [S_JOINING_FILES] = "מחבר את הקבצים: %1",
    [S_CHECKING_JOINED] = "בודק את הקובץ המאוחד: %1",
    [S_COPYING_TO] = "מעתיק לתיקייה שנבחרה: %1",
    [S_FINISHED_TITLE] = "הכול מוכן",
    [S_GUIDE_THIS_FILE] = "אפשר להתקין ממנו עכשיו, או להעתיק אותו למחשב אחר מאותו סוג "
                          "ולהתקין שם.",
    [S_GUIDE_OTHER_FILE] = "העתק את הקובץ הזה לדיסק-און-קי ומשם למחשב המנותק (%1).",
    [S_GUIDE_THIS_FOLDER] = "אפשר להתקין ממנה עכשיו, או להעתיק את כל התיקייה למחשב אחר "
                            "מאותו סוג. הקבצים חייבים להישאר יחד באותה תיקייה.",
    [S_GUIDE_OTHER_FOLDER] = "העתק את כל התיקייה הזאת לדיסק-און-קי ומשם למחשב המנותק "
                             "(%1). הקבצים חייבים להישאר יחד באותה תיקייה.",
    [S_GUIDE_RUN_EXE] = "במחשב המנותק הפעל מתוכה את %1 — אין צורך בחיבור לאינטרנט "
                        "ואין צורך בתוכנות נוספות.",
    [S_GUIDE_JOIN] = "חלק מהקבצים גדולים מדי לקובץ אחד ולכן נשארו מחולקים. במחשב היעד "
                     "מחברים אותם בחלון מסוף (טרמינל), מתוך התיקייה, בפקודה:",
    [S_PREPARED_FILES] = "הקבצים שהוכנו:",
    [S_OPEN_HINT_EXE] = "שם הפעל אותו — אין צורך בחיבור לאינטרנט ואין צורך בתוכנות "
                        "נוספות.",
    [S_OPEN_HINT_DMG] = "שם פתח אותו בלחיצה כפולה וגרור את אוצריא לתיקיית היישומים.",
    [S_OPEN_HINT_PACKAGE] = "שם פתח אותו בלחיצה כפולה כדי להתקין את אוצריא.",
    [S_OPEN_HINT_APK] = "שם העבר אותו לטלפון או לטאבלט ופתח אותו כדי להתקין את "
                        "אוצריא.",
    [S_OPEN_HINT_ARCHIVE] = "שם חלץ אותו והפעל את אוצריא מתוך התיקייה שנוצרה.",
    [S_REVEAL_FILE] = "הצג את הקובץ שהוכן",
    [S_REVEAL_FOLDER] = "הצג את התיקייה שהוכנה",
    [S_OPEN_FOLDER] = "פתח את תיקיית ההתקנה",
    [S_OFFLINE_TITLE] = "אין חיבור לאינטרנט",
    [S_OFFLINE_BODY] = "בדוק את החיבור לאינטרנט ונסה שוב. אפשר גם לפתוח את עמוד "
                       "ההורדות של אוצריא בדפדפן ולהוריד משם ידנית (אפשרות מוגבלת: "
                       "המסייע לא יוכל לבדוק את הקבצים או לחבר אותם).",
    [S_LOAD_FAILED_BODY] = "אפשר לנסות שוב, או לפתוח את עמוד ההורדות של אוצריא בדפדפן "
                           "ולהוריד משם ידנית (אפשרות מוגבלת: המסייע לא יוכל לבדוק "
                           "את הקבצים או לחבר אותם).",
    [S_STOPPED_TITLE] = "ההורדה הופסקה",
    [S_STOPPED_BODY] = "קבצים שכבר ירדו נשמרו, ו\"המשך\" ימשיך מאותו מקום.",
    [S_RUN_FAILED_BODY] = "קבצים שכבר ירדו נשמרו, ו\"נסה שוב\" ימשיך מהמקום שבו "
                          "נעצרה הפעולה.",
    [S_TLS_TITLE] = "אין אפשרות להתחבר באופן מאובטח",
    [S_TLS_BODY] = "במחשב הזה חסר רכיב מערכת שנדרש לחיבור מאובטח לאתר ההורדות. יש "
                   "להתקין את החבילה glib-networking (למשל: %1) ולהפעיל את "
                   "המסייע מחדש.",
    [S_NO_TARGET_TITLE] = "לא נבחר מחשב",
    [S_NO_TARGET_TEXT] = "יש לבחור את סוג המחשב שבו תותקן אוצריא.",
    [S_NOTHING_TITLE] = "לא נבחר רכיב",
    [S_NOTHING_TEXT] = "יש לבחור לפחות רכיב אחד להורדה.",
    [S_FOLDER_BAD_TITLE] = "אי אפשר לשמור בתיקייה הזאת",
    [S_FOLDER_BAD_FALLBACK] = "לא ניתן לשמור בתיקייה שנבחרה. במקומה מוצעת התיקייה:\n%1"
                              "\n\nאפשר להמשיך איתה או לבחור תיקייה אחרת.",
    [S_FOLDER_BAD_TEXT] = "לא ניתן לשמור בתיקייה שנבחרה. נסה תיקייה אחרת.",
    [S_SPACE_TITLE] = "אין מספיק מקום פנוי",
    [S_SPACE_TEXT] = "נראה שאין מספיק מקום פנוי. דרושים בערך %1.\n\nלהמשיך בכל זאת?",
    [S_SPACE_YES] = "להמשיך",
    [S_EXIT_TITLE] = "יציאה מהמסייע",
    [S_EXIT_MESSAGE] = "ההורדה לא הושלמה. קבצים שכבר ירדו יישמרו, והפעלה חוזרת תמשיך "
                       "מהמקום שבו הפסקת.\n\nלצאת עכשיו?",
    [S_EXIT_YES] = "יציאה",
    [S_EXIT_NO] = "המשך",
    [S_CONNECT_STOP_TITLE] = "להפסיק את ההתחברות?",
    [S_CONNECT_STOP_TEXT] = "אפשר להתחיל שוב מתי שתרצה.",
    [S_CONNECT_STOP_YES] = "הפסק",
    [S_CONNECT_STOP_NO] = "המשך להתחבר",
    [S_STOP_TITLE] = "לעצור את ההורדה?",
    [S_STOP_TEXT] = "קבצים שכבר ירדו יישמרו, והפעלה חוזרת תמשיך מאותו מקום.",
    [S_STOP_YES] = "עצור",
    [S_STOP_NO] = "המשך להוריד",
    [S_ERR_FILE_UNAVAILABLE] = "לא ניתן להכין את ההתקנה משום שאחד הקבצים הדרושים אינו "
                               "זמין.",
    [S_ERR_CANNOT_CONNECT] = "לא ניתן להתחבר לאתר ההורדות של אוצריא.",
    [S_ERR_CANNOT_READ_LIST] = "לא ניתן לקרוא את רשימת הקבצים של אוצריא.",
    [S_ERR_CANNOT_PREPARE] = "לא ניתן להכין את ההתקנה.",
    [S_ERR_COPY] = "לא ניתן היה להעתיק את הקבצים לתיקייה שנבחרה.",
    [S_ERR_SAVE] = "לא ניתן היה לשמור את הקבצים. ייתכן שאין מספיק מקום פנוי.",
    [S_ERR_DAMAGED] = "אחד הקבצים שהורדו נמצא פגום ולא נשמר.",
    [S_ERR_WRITE_JOINED] = "לא ניתן היה לכתוב את הקובץ המאוחד. ייתכן שאין מספיק מקום "
                           "פנוי.",
    [S_OUTPUT_SUBFOLDER] = "אוצריא להתקנה ל-%1",
    [S_DURATION_UNDER_MINUTE] = "פחות מדקה",
    [S_DURATION_HOUR] = "שעה",
    [S_DURATION_TWO_HOURS] = "שעתיים",
    [S_DURATION_HOURS] = "%1 שעות",
    [S_DURATION_MINUTE] = "דקה",
    [S_DURATION_MINUTES] = "%1 דקות",
    [S_DURATION_JOIN] = "%1 ו-%2",
};

static const char *const english_texts[S_COUNT] = {
    [S_APP_TITLE] = "Otzaria Download Assistant",
    [S_WELCOME_SUBTITLE] = "Free Torah Library",
    [S_WELCOME_NOTE] = "This tool doesn't install anything — it downloads the Otzaria "
                       "files and prepares an installation from them, even for a "
                       "computer without internet.",
    [S_START_BUTTON] = "Let's Get Started",
    [S_NEXT] = "Continue",
    [S_BACK] = "Back",
    [S_START] = "Start",
    [S_FINISH] = "Finish",
    [S_CANCEL] = "Cancel",
    [S_CLOSE] = "Close",
    [S_OK] = "OK",
    [S_STOP_DOWNLOAD] = "Stop Download",
    [S_RETRY] = "Try Again",
    [S_RESUME] = "Continue",
    [S_OPEN_DOWNLOADS] = "Open the Downloads Page",
    [S_TECH_DETAILS] = "Technical details",
    [S_STEP_OF] = "Step %1 of %2",
    [S_CONNECT_TITLE] = "Connecting to the Otzaria website",
    [S_CONNECT_DESC] = "Getting the list of files for the latest version.",
    [S_CONNECTING_PROGRESS] = "Connecting to the Otzaria website…",
    [S_MODE_TITLE] = "Which computer is this for?",
    [S_MODE_DESC] = "The assistant downloads the installation files and saves them in "
                    "a folder. It doesn't install anything itself.",
    [S_MODE_THIS] = "Linux — like this computer",
    [S_MODE_THIS_DESC] = "For this computer and any computer with %1. The files are "
                         "saved in a folder, to install here or to copy.",
    [S_THIS_DEB] = "Ubuntu, Debian, Mint or a similar distribution",
    [S_THIS_RPM] = "Fedora, openSUSE or a similar distribution",
    [S_THIS_PORTABLE] = "another Linux distribution",
    [S_THIS_ARM] = "%1 and an ARM processor",
    [S_MODE_OTHER] = "A different kind of computer",
    [S_MODE_OTHER_DESC] = "For %1. The files are saved in a folder, to copy to a USB "
                          "drive.",
    [S_LIST_OR] = "%1 or %2",
    [S_VERSION_TO_DOWNLOAD] = "Version to download: %1",
    [S_OTZARIA_VERSION] = "Otzaria %1",
    [S_OTHER_TITLE] = "Which kind of computer?",
    [S_OTHER_DESC] = "Choose the kind of computer Otzaria will be installed on.",
    [S_OTHER_HINT] = "On Linux, if you're not sure which distribution is installed, "
                     "choose DEB — it fits most computers.",
    [S_TARGET_ARM] = "%1 · ARM processor",
    [S_HINT_MAC] = "Mac computers",
    [S_HINT_ANDROID] = "A phone or tablet",
    [S_HINT_ARM] = "For example, computers with a Snapdragon processor",
    [S_HINT_X64] = "Intel or AMD processor — almost every computer",
    [S_FORMAT_DEB] = "Ubuntu, Debian, Mint and similar distributions (DEB)",
    [S_FORMAT_RPM] = "Fedora, openSUSE and similar distributions (RPM)",
    [S_FORMAT_PORTABLE] = "Another distribution — no installation needed",
    [S_PRESET_TITLE] = "What to download",
    [S_PRESET_DESC] = "Choose how much to download.",
    [S_PRESET_HINT] = "You can change this later.",
    [S_PRESET_FULL_INDEXED] = "Full installation + search index",
    [S_PRESET_FULL_INDEXED_DESC] = "For a computer without internet — search works "
                                   "right away. Smart" NBSP "Search" NBSP "included.",
    [S_PRESET_FULL] = "Full installation",
    [S_PRESET_FULL_DESC] = "For a computer without internet — Otzaria builds the search "
                           "index first. Smart" NBSP "Search" NBSP "included.",
    [S_PRESET_BASIC] = "Basic installation (recommended)",
    [S_PRESET_BASIC_DESC] = "For a computer with internet — the library downloads from "
                            "within Otzaria.",
    [S_PRESET_UPDATE] = "Update Otzaria only",
    [S_PRESET_UPDATE_DESC] = "The installer of the new version, to update an existing "
                             "installation.",
    [S_PRESET_CUSTOM] = "Custom selection",
    [S_PRESET_CUSTOM_DESC] = "I want to choose what to download myself.",
    [S_CARD_SIZE] = "Download size: %1",
    [S_REQUIRED_TAG] = "(required)",
    [S_CUSTOM_DESC] = "Check the items you want to download.",
    [S_CUSTOM_HINT] = "Each item shows its download size.",
    [S_FOLDER_TITLE] = "Where to save",
    [S_FOLDER_DESC] = "By default, the files are saved next to the assistant itself.",
    [S_FOLDER_HINT] = "You can choose a different folder. You install from this folder "
                      "— on this computer, or after copying it to a USB drive, also on "
                      "a computer without internet.",
    [S_FOLDER_FALLBACK_NOTE] = "The assistant can't save in the folder it was started "
                               "from (for example, a read-only USB drive), so a "
                               "different folder is suggested here.",
    [S_BROWSE] = "Browse…",
    [S_CHOOSE] = "Choose",
    [S_READY_TITLE] = "Ready to start",
    [S_READY_DESC] = "Everything is ready to download.",
    [S_READY_HINT] = "Click \"Start\" to download the files and prepare an installation "
                     "from them.",
    [S_ROW_VERSION] = "Version",
    [S_ROW_WHAT] = "What to download",
    [S_ROW_FOR] = "For",
    [S_ROW_SAVED_IN] = "Saved in",
    [S_ROW_FILE] = "File",
    [S_ROW_FOLDER] = "In folder",
    [S_DOWNLOADING_VERSION] = "Downloading %1…",
    [S_DOWNLOAD_DESC] = "The files are downloading from the Otzaria website. You can "
                        "stop at any time — whatever was already downloaded is kept.",
    [S_DOWNLOADING_ITEM] = "Downloading: %1 (%2 of %3)",
    [S_DOWNLOADED_OF] = "%1 of %2 downloaded",
    [S_TIME_LEFT] = "%1 left",
    [S_SIZE_OF] = "%1 of %2",
    [S_WORK_TITLE] = "Preparing the installation",
    [S_WORK_DESC] = "One moment, preparing the files.",
    [S_PREPARING] = "Getting ready…",
    [S_CHECKING_CACHED] = "Checking files that were already downloaded: %1",
    [S_JOINING_FILES] = "Joining the files: %1",
    [S_CHECKING_JOINED] = "Checking the joined file: %1",
    [S_COPYING_TO] = "Copying to the chosen folder: %1",
    [S_FINISHED_TITLE] = "Everything's ready",
    [S_GUIDE_THIS_FILE] = "You can install from it now, or copy it to another computer "
                          "of the same kind and install there.",
    [S_GUIDE_OTHER_FILE] = "Copy this file to a USB drive, and from there to the "
                           "offline computer (%1).",
    [S_GUIDE_THIS_FOLDER] = "You can install from it now, or copy the whole folder to "
                            "another computer of the same kind. The files must stay "
                            "together in the same folder.",
    [S_GUIDE_OTHER_FOLDER] = "Copy this whole folder to a USB drive, and from there to "
                             "the offline computer (%1). The files must stay together "
                             "in the same folder.",
    [S_GUIDE_RUN_EXE] = "On the offline computer, run %1 from it — no internet "
                        "connection or other software is needed.",
    [S_GUIDE_JOIN] = "Some files are too large to be a single file, so they were left "
                     "in parts. On the target computer, join them in a terminal window, "
                     "from inside the folder, with this command:",
    [S_PREPARED_FILES] = "Prepared files:",
    [S_OPEN_HINT_EXE] = "There, run it — no internet connection or other software is "
                        "needed.",
    [S_OPEN_HINT_DMG] = "There, double-click it and drag Otzaria to the Applications "
                        "folder.",
    [S_OPEN_HINT_PACKAGE] = "There, double-click it to install Otzaria.",
    [S_OPEN_HINT_APK] = "There, move it to the phone or tablet and open it to install "
                        "Otzaria.",
    [S_OPEN_HINT_ARCHIVE] = "There, extract it and run Otzaria from the folder that was "
                            "created.",
    [S_REVEAL_FILE] = "Show the prepared file",
    [S_REVEAL_FOLDER] = "Show the prepared folder",
    [S_OPEN_FOLDER] = "Open the Installation Folder",
    [S_OFFLINE_TITLE] = "No internet connection",
    [S_OFFLINE_BODY] = "Check your internet connection and try again. You can also open "
                       "the Otzaria downloads page in your browser and download manually "
                       "from there (a limited option: the assistant won't be able to "
                       "check the files or join them).",
    [S_LOAD_FAILED_BODY] = "You can try again, or open the Otzaria downloads page in "
                           "your browser and download manually from there (a limited "
                           "option: the assistant won't be able to check the files or "
                           "join them).",
    [S_STOPPED_TITLE] = "The download was stopped",
    [S_STOPPED_BODY] = "Files that were already downloaded are saved, and \"Continue\" "
                       "picks up from the same point.",
    [S_RUN_FAILED_BODY] = "Files that were already downloaded are saved, and \"Try "
                          "Again\" continues from where it stopped.",
    [S_TLS_TITLE] = "Can't connect securely",
    [S_TLS_BODY] = "This computer is missing a system component needed for a secure "
                   "connection to the downloads site. Install the glib-networking "
                   "package (for example: %1) and start the assistant again.",
    [S_NO_TARGET_TITLE] = "No computer selected",
    [S_NO_TARGET_TEXT] = "Choose the kind of computer Otzaria will be installed on.",
    [S_NOTHING_TITLE] = "Nothing selected",
    [S_NOTHING_TEXT] = "Choose at least one item to download.",
    [S_FOLDER_BAD_TITLE] = "Can't save in this folder",
    [S_FOLDER_BAD_FALLBACK] = "The chosen folder can't be used for saving. This folder "
                              "is suggested instead:\n%1\n\nYou can continue with it or "
                              "choose another folder.",
    [S_FOLDER_BAD_TEXT] = "The chosen folder can't be used for saving. Try another "
                          "folder.",
    [S_SPACE_TITLE] = "Not enough free space",
    [S_SPACE_TEXT] = "There doesn't seem to be enough free space. About %1 is needed."
                     "\n\nContinue anyway?",
    [S_SPACE_YES] = "Continue",
    [S_EXIT_TITLE] = "Exit the assistant",
    [S_EXIT_MESSAGE] = "The download isn't finished. Files that were already downloaded "
                       "are kept, and running the assistant again continues from where "
                       "you stopped.\n\nExit now?",
    [S_EXIT_YES] = "Exit",
    [S_EXIT_NO] = "Continue",
    [S_CONNECT_STOP_TITLE] = "Stop connecting?",
    [S_CONNECT_STOP_TEXT] = "You can start again whenever you like.",
    [S_CONNECT_STOP_YES] = "Stop",
    [S_CONNECT_STOP_NO] = "Keep Connecting",
    [S_STOP_TITLE] = "Stop the download?",
    [S_STOP_TEXT] = "Files that were already downloaded will be kept, and running the "
                    "assistant again continues from the same point.",
    [S_STOP_YES] = "Stop",
    [S_STOP_NO] = "Keep Downloading",
    [S_ERR_FILE_UNAVAILABLE] = "Can't prepare the installation because one of the "
                               "required files isn't available.",
    [S_ERR_CANNOT_CONNECT] = "Can't connect to the Otzaria downloads site.",
    [S_ERR_CANNOT_READ_LIST] = "Can't read the list of Otzaria files.",
    [S_ERR_CANNOT_PREPARE] = "Can't prepare the installation.",
    [S_ERR_COPY] = "Couldn't copy the files to the chosen folder.",
    [S_ERR_SAVE] = "Couldn't save the files. There may not be enough free space.",
    [S_ERR_DAMAGED] = "One of the downloaded files was damaged, so it wasn't saved.",
    [S_ERR_WRITE_JOINED] = "Couldn't write the joined file. There may not be enough "
                           "free space.",
    [S_OUTPUT_SUBFOLDER] = "Otzaria setup for %1",
    [S_DURATION_UNDER_MINUTE] = "less than a minute",
    [S_DURATION_HOUR] = "1 hour",
    [S_DURATION_TWO_HOURS] = "2 hours",
    [S_DURATION_HOURS] = "%1 hours",
    [S_DURATION_MINUTE] = "1 minute",
    [S_DURATION_MINUTES] = "%1 minutes",
    [S_DURATION_JOIN] = "%1 %2",
};

static gboolean english = FALSE;

static gboolean is_hebrew_tag(const char *tag) {
  return g_str_has_prefix(tag, "he") || g_str_has_prefix(tag, "iw");
}

gboolean otz_detect_english(void) {
  const char *forced = g_getenv("OTZARIA_ASSISTANT_LANG");
  if (forced != NULL && (strcmp(forced, "he") == 0 || strcmp(forced, "en") == 0))
    return strcmp(forced, "en") == 0;
  const char *const *names = g_get_language_names();
  for (gsize i = 0; names[i] != NULL; i++) {
    if (strcmp(names[i], "C") == 0 || strcmp(names[i], "POSIX") == 0) continue;
    return !is_hebrew_tag(names[i]);
  }
  return TRUE;
}

void otz_set_english(gboolean value) { english = value; }

gboolean otz_english(void) { return english; }

const char *otz_tr(OtzString key) {
  const char *text = english ? english_texts[key] : hebrew[key];
  return text != NULL ? text : "";
}

char *otz_trf(OtzString key, ...) {
  const char *args[9] = {NULL};
  int count = 0;
  va_list list;
  va_start(list, key);
  const char *arg;
  while (count < 9 && (arg = va_arg(list, const char *)) != NULL) args[count++] = arg;
  va_end(list);
  /* One pass over the template, so an argument's own "%2" stays as it is. */
  GString *text = g_string_new(NULL);
  for (const char *c = otz_tr(key); *c != '\0'; c++) {
    int index = c[0] == '%' && c[1] >= '1' && c[1] <= '9' ? c[1] - '1' : -1;
    if (index >= 0 && index < count) {
      g_string_append(text, args[index]);
      c++;
    } else {
      g_string_append_c(text, *c);
    }
  }
  return g_string_free(text, FALSE);
}

const char *otz_tr_hebrew(OtzString key) {
  return hebrew[key] != NULL ? hebrew[key] : "";
}

const char *otz_tr_message(const char *message) {
  static const OtzString known[] = {
      S_ERR_FILE_UNAVAILABLE, S_ERR_CANNOT_CONNECT, S_ERR_CANNOT_READ_LIST,
      S_ERR_CANNOT_PREPARE,   S_ERR_COPY,           S_ERR_SAVE,
      S_ERR_DAMAGED,          S_ERR_WRITE_JOINED,
  };
  for (gsize i = 0; message != NULL && i < G_N_ELEMENTS(known); i++) {
    if (strcmp(message, hebrew[known[i]]) == 0) return otz_tr(known[i]);
  }
  return message != NULL ? message : "";
}

char *otz_ltr(const char *text) {
  return english ? g_strdup(text) : otz_ltr_isolate(text);
}

char *otz_bidi(const char *text) {
  if (english) return g_strdup(text);
  g_auto(GStrv) lines = g_strsplit(text, "\n", -1);
  GString *out = g_string_new(NULL);
  for (guint i = 0; lines[i] != NULL; i++) {
    if (i > 0) g_string_append_c(out, '\n');
    if (*lines[i] == '\0') continue;
    g_string_append(out, RLM);
    g_auto(GStrv) parts = g_strsplit(lines[i], ", ", -1);
    g_autofree char *joined = g_strjoinv("," RLM " ", parts);
    g_string_append(out, joined);
  }
  return g_string_free(out, FALSE);
}

char *otz_size_text(gint64 bytes) {
  g_autofree char *size = otz_human_size(bytes);
  return otz_ltr(size);
}

char *otz_speed_text(double bytes_per_second) {
  gint64 per_second = bytes_per_second > 0 ? (gint64)bytes_per_second : 0;
  g_autofree char *text =
      per_second >= 1048576
          ? g_strdup_printf("%" G_GINT64_FORMAT ".%" G_GINT64_FORMAT NBSP "MB/s",
                            per_second * 10 / 1048576 / 10,
                            per_second * 10 / 1048576 % 10)
          : g_strdup_printf("%" G_GINT64_FORMAT NBSP "KB/s", per_second / 1024);
  return otz_ltr(text);
}

/* Whole hours and rounded minutes, like HumanDuration on Windows. */
char *otz_duration_text(double seconds) {
  if (seconds < 60) return g_strdup(otz_tr(S_DURATION_UNDER_MINUTE));
  gint64 whole = (gint64)seconds;
  gint64 hours = whole / 3600;
  gint64 minutes = (whole % 3600 + 30) / 60;
  if (minutes == 60) {
    hours++;
    minutes = 0;
  }
  g_autofree char *hours_text = NULL;
  if (hours == 1) {
    hours_text = g_strdup(otz_tr(S_DURATION_HOUR));
  } else if (hours == 2) {
    hours_text = g_strdup(otz_tr(S_DURATION_TWO_HOURS));
  } else if (hours > 2) {
    g_autofree char *count = g_strdup_printf("%" G_GINT64_FORMAT, hours);
    hours_text = otz_trf(S_DURATION_HOURS, count, NULL);
  }
  if (minutes == 0) return g_strdup(hours_text != NULL ? hours_text : "");
  g_autofree char *count = g_strdup_printf("%" G_GINT64_FORMAT, minutes);
  g_autofree char *minutes_text = minutes == 1 ? g_strdup(otz_tr(S_DURATION_MINUTE))
                                               : otz_trf(S_DURATION_MINUTES, count, NULL);
  if (hours_text == NULL) return g_steal_pointer(&minutes_text);
  return otz_trf(S_DURATION_JOIN, hours_text, minutes_text, NULL);
}
