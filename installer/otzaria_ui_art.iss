[Files]
; העיצוב של שכבת התצוגה, משותף למסייע ולמתקינים. נכלל לפני כל [Files] אחר: עם SolidCompression
; ExtractTemporaryFile של תמונה מאוחרת היה פורס קודם את כל מה שלפניה, והפתיחה הייתה ממתינה.
; הערות ';' תקפות רק מחוץ ל-[Code], ולכן גם ה-.isi נכלל כאן ולא בראש הקובץ.
#if VER < EncodeVer(6, 7, 1)
  #error "שכבת התצוגה של אוצריא דורשת Inno Setup 6.7.1 ומעלה (Requires Inno Setup 6.7.1 or newer)"
#endif
; השכבה נשענת על פרטים של WizardForm ו-Pascal Script; גרסה ראשית חדשה נבדקת לפני שמתירים אותה.
#if VER >= EncodeVer(7, 0, 0)
  #error "שכבת התצוגה של אוצריא לא נבדקה ב-Inno Setup 7 (Not verified with Inno Setup 7; use 6.7.x)"
#endif
#define AssistantArtIsi AddBackslash(SourcePath) + "assistant_art\assistant_art.isi"
#if !FileExists(AssistantArtIsi)
  #error "חסר העיצוב ב-installer\assistant_art. יש למשוך אותו לפני הבנייה (Art missing: fetch installer\assistant_art before compiling)"
#endif
#include AssistantArtIsi
#ifndef AA_TITLE_BAR_H
  #define AA_TITLE_BAR_H AA_CAP_H
#endif
#if AA_SCALES != "100,125,150,175,200,250"
  #error "רשימת קני המידה של העיצוב השתנתה: יש לעדכן את [Files] (Art scales changed: update [Files])"
#endif
#ifndef AA_BOOK_SRC_SCALE
  #error "העיצוב ישן: נדרשת גרסה 1.2.0 ומעלה (Art too old: 1.2.0 or newer required)"
#endif

; כל מוצר מטמיע רק את כותרת הפתיחה ואת הסמלים שלו: OtzariaUiProduct מוגדר לפני ההכללה
; ("installer" במתקינים; בלעדיו — המסייע).
#ifndef OtzariaUiProduct
  #define OtzariaUiProduct "assistant"
#endif
#if OtzariaUiProduct == "installer"
  #if !Defined(AA_TITLE_INST) || !Defined(AA_LOGO_SM_SIZE)
    #error "העיצוב ישן למתקינים: נדרשת גרסה 1.5.0 ומעלה (Art too old for the installers: 1.5.0 or newer required)"
  #endif
  #define UiTitleFiles "title_inst_*"
  #define UiTitleSkip ""
  #define UiArtSkip ",ico_this_pc_*,ico_other_pc_*,ico_windows_*,ico_macos_*,ico_linux_*,ico_android_*,ico_arch_*,ico_fmt_*,ico_preset_*,ico_folder_*,ico_component_*,badge_offline_*,badge_paused_*,logo_1*,logo_2*,mark_*"
#else
  #define UiTitleFiles "title_*"
  #define UiTitleSkip "title_inst_*"
  #define UiArtSkip ",logo_sm_*,ico_only_me_*,ico_all_users_*,ico_portable_*,ico_install_folder_*,ico_books_folder_*,ico_desktop_shortcut_*,ico_start_menu_*,ico_calendar_shortcut_*,ico_reset_settings_*,ico_webview2_*,ico_update_*,ico_launch_*,ico_app_*,ico_warning_*"
#endif

; התמונות נשלפות לתיקייה הזמנית בזמן ריצה בלבד; שום דבר אינו מותקן.
; הספר והכותרת נשמרים רק בקנה המידה הגדול, ו-Stretch מקטין אותם לכל קנה מידה אחר.
Source: "assistant_art\book_*_{#AA_BOOK_SRC_SCALE}.png"; Flags: dontcopy nocompression
Source: "assistant_art\{#UiTitleFiles}_{#AA_TITLE_SRC_SCALE}.png"; Excludes: "{#UiTitleSkip}"; Flags: dontcopy nocompression
; כל קנה מידה ברצף משלו, כדי ששליפה תקרא רק את הקבצים של קנה המידה שנבחר.
Source: "assistant_art\*_100.png"; Excludes: "book_*,title_*{#UiArtSkip}"; Flags: dontcopy nocompression
Source: "assistant_art\*_125.png"; Excludes: "book_*,title_*{#UiArtSkip}"; Flags: dontcopy nocompression
Source: "assistant_art\*_150.png"; Excludes: "book_*,title_*{#UiArtSkip}"; Flags: dontcopy nocompression
Source: "assistant_art\*_175.png"; Excludes: "book_*,title_*{#UiArtSkip}"; Flags: dontcopy nocompression
Source: "assistant_art\*_200.png"; Excludes: "book_*,title_*{#UiArtSkip}"; Flags: dontcopy nocompression
Source: "assistant_art\*_250.png"; Excludes: "book_*,title_*{#UiArtSkip}"; Flags: dontcopy nocompression
