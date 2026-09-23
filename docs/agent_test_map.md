# מפת בדיקות לפי תחום

הרשימה מסייעת בבחירת בדיקות רלוונטיות; היא אינה תחליף לחיפוש בקבצים הקיימים.
לפני הרצה, אמת את הנתיב עם `rg --files test | rg <name>`; הוסף לכאן בדיקות חדשות רק אם המיפוי שלהן אינו מובן מאליו.
הקובץ נקרא לפי צורך בלבד; אין לייבא אותו אוטומטית מ־`AGENTS.md`.

**Text Book Viewer**
| Area | Test File |
|------|-----------|
| Screen actions (overflow, layout) | `test/text_book/view/text_book_screen_actions_test.dart` |
| שימור חלונית הניווט במעבר טאב | `test/text_book/view/text_book_nav_panel_preserved_test.dart` |
| יעד סיור לחלונית הניווט (מפתח יציב) | `test/text_book/view/widgets/nav_panel_tour_target_test.dart` |
| Search controller sync | `test/text_book/text_book_search_query_sync_test.dart` |
| Search screen | `test/text_book/view/text_book_search_screen_test.dart` |
| מסלול המנוע בחלונית החיפוש בספר (מרווח, זיהוי הספר) | `test/text_book/view/text_book_search_engine_route_test.dart` |
| קאש שורות הספר לחיפוש (שחרור בטאב רקע) | `test/text_book/view/text_book_search_content_cache_test.dart` |
| TOC navigator UI | `test/text_book/view/toc_navigator_screen_test.dart` |
| TOC navigator internals | `test/text_book/view/toc_navigator_internals_test.dart` |
| דיבורי-המתחיל כמבנה מסונתז בלשונית 'כותרות' (בניית הערכים, קיצור מילים, הערך הפעיל) | `test/text_book/utils/dibburim_structure_test.dart`, `test/text_book/view/alt_toc_sidebar_dibburim_test.dart` |
| Combined view helpers (shouldShow…) | `test/text_book/view/combined_view/combined_book_screen_test.dart` |
| TabbedCommentaryPanel tab switching / onTabChanged | `test/text_book/view/tabbed_commentary_panel_test.dart` |
| Page shape commentary selection | `test/text_book/view/page_shape_commentary_selection_test.dart` |
| התאמת מפרשי צורת הדף בין ספרים (היקף קטגוריה) | `test/text_book/view/page_shape/page_shape_category_commentator_matching_test.dart` |
| הסתרת טורים בצורת הדף — נשמרת לצד בחירת המפרשים (קטגוריה/ספר/שולחן עבודה) | `test/text_book/view/page_shape/page_shape_column_visibility_scope_test.dart` |
| חלונית הצד של צורת הדף (3 לשוניות) | `test/text_book/view/page_shape/page_shape_sidebar_tabs_test.dart` |
| תפריט הקשר בצורת הדף (מפרשים / קטע היעד) | `test/text_book/view/page_shape/simple_text_viewer_context_menu_test.dart` |
| תת-תפריט "מפרשים" המשותף + מדיניות הצגה | `test/text_book/utils/commentators_context_menu_test.dart` |
| SimpleTextViewer | `test/text_book/view/page_shape/simple_text_viewer_test.dart` |
| Selected text copy/restore | `test/text_book/view/selection/selected_text_copy_test.dart`, `…selected_text_restore_test.dart` |
| SelectionSyncController | `test/text_book/view/selection/selection_sync_controller_test.dart` |
| בחירה כלפי מעלה מעבר לנקודת העיגון של הרשימה (sliver הפוך) | `test/text_book/view/selection/selection_upward_across_anchor_test.dart` |
| Commentary open-filter request | `test/text_book/view/commentary_list_base_open_filter_test.dart` |
| Commentary search focus | `test/text_book/view/commentary_search_focus_test.dart` |
| Commentary grouping | `test/text_book/commentary_grouping_test.dart` |
| הסתרת כותרת מקור מיותרת במקטע מפרש | `test/text_book/view/commentary_item_title_visibility_test.dart` |
| Book source dialog | `test/text_book/view/book_source_dialog_test.dart` |
| Error report dialog | `test/text_book/view/error_report_dialog_test.dart` |
| הצעת תיקון בדיאלוג הדיווח (עורך, diff, מחיקה מול ללא-הצעה, מיפוי בחירה לשורה הגולמית) | `test/text_book/view/text_correction_editor_test.dart` |

**Text Book BLoC**
| Area | Test File |
|------|-----------|
| BLoC state equality | `test/text_book/bloc/text_book_state_test.dart` |
| Background content loading | `test/text_book/bloc/background_full_content_loading_test.dart` |
| Continuous reading mode | `test/text_book/bloc/continuous_reading_mode_test.dart` |
| Selected link types persistence | `test/text_book/bloc/selected_link_types_persistence_test.dart` |
| visibleIndices throttling (scroll perf) | `test/text_book/bloc/visible_indices_throttle_test.dart` |

**Data / Database**
| Area | Test File |
|------|-----------|
| DatabaseLibraryProvider (links, alt-toc, isolate regressions) | `test/data_providers/database_library_provider_test.dart` |
| DatabaseLibraryProvider has-book | `test/data_providers/database_library_provider_has_book_test.dart` |
| טעינת `line_dh.dhDisplay` (מסד ישן בלי טבלה/עמודה → מפה ריקה) | `test/data_providers/database_library_provider_dibburim_test.dart` |
| UserBooksDB | `test/data_providers/user_books_database_holder_test.dart` |
| FileSystemLibraryProvider | `test/data_providers/file_system_library_provider_test.dart` |
| ExternalCatalogMapper | `test/data_providers/external_catalog_mapper_test.dart` |
| TantivyDataProvider (search index) | `test/data/data_providers/tantivy_data_provider_test.dart` |
| External books scanner | `test/data/data_providers/scan_external_books_test.dart` |
| Library book search (fuzzy + acronyms) | `test/data/repository/book_search_fuzzy_match_test.dart` |
| מפת היכולות של מסד (טבלאות אופציונליות, VIEW/וירטואלית אינן יכולת) | `test/data/db_capabilities_test.dart` |
| מסד בפורמט seforim.db בלי טבלאות (minimal, בלי קטגוריות/מחברים) | `test/data_providers/seforim_optional_tables_test.dart` (מסדי בדיקה: `test/helpers/seforim_fixture_db.dart`) |

**Attached libraries (מסדי ספרים אישיים, `lib/attached_libraries/`)**
| Area | Test File |
|------|-----------|
| בדיקת קובץ מסד (כותרת, VIEW מתחזה, טבלאות תוסף, יומן תלוי, slug, פתיחה מוקשחת) | `test/attached_libraries/attached_library_probe_test.dart` |
| שמירת הרשימה בהגדרות + registry (פתיחה עצלה, שחרור, זמן סרק, מאגר ישן אחרי שחרור, שער העלייה, בדיקת פתיחה מוגבלת בזמן) | `test/attached_libraries/attached_library_registry_test.dart` |
| צירוף, העתקה, הסרה, תיקיות מסדים, slug כפול, לא זמין, טביעת אצבע | `test/attached_libraries/attached_libraries_repository_test.dart` |
| עץ הספרייה (שורש נפרד, מיזוג, מוסתר/לא זמין, בלי קטגוריות) + טקסט ותוכן עניינים מקצה לקצה; קטלוג ב-isolate — מסד איטי/מת/שבור מבודד ומסומן לא-זמין | `test/attached_libraries/attached_library_catalog_test.dart` |
| תוכן עשיר בספר מצורף: קישורים ותוכן מפרש, מפרשים, דורות מהמסד שלו, מפרשי ברירת מחדל, 'כותרות', דיבורי-המתחיל, מהדורות, PDF בנתיב יחסי; מסד מינימלי ריק בלי חריגה | `test/attached_libraries/attached_library_rich_content_test.dart` |
| קישורים חוצי-מסדים (`external_link`): יעד לפי heRef ואחרת מספר שורה, יעד שלא נפתר נשמט, מפרש מצורף על ספר רשמי (אינדקס-צד ב-cache.db), בנייה מחדש בשינוי קובץ/גרסה רשמית, הסרה, מסד לא נגיש | `test/attached_libraries/attached_external_links_test.dart` |
| נתיב קובץ ספר במסד מצורף (יחסי בלבד, בלי `..`/מוחלט/UNC) + החלת יומן מוקשחת על עותק | `test/attached_libraries/attached_file_path_test.dart` |
| כרטיס "מסדי ספרים אישיים" בהגדרות | `test/attached_libraries/attached_libraries_panel_test.dart` |
| מסד עוין (VIEW/טריגר/ATTACH, ZIP, library_id עם `../`, נתיבי קובץ בורחים, סכמה זבל), חיבור מוקשח (בלי mmap), שחרור נעילה, לא-זמין וחזרה, סדר במיזוג | `test/attached_libraries/attached_library_security_test.dart` |
| אינדקס החיפוש למסד מצורף: מפתח `db:`, סדר הקטלוג בסוף (צירוף אינו מזיז ספרים), יתומים (הוסר ⇒ נמחק, לא-זמין/מוסתר ⇒ נשמר) | `test/indexing/repository/attached_library_index_test.dart` |
| קובץ מסד שהשתנה ⇒ אינדוקס מחדש רק של ספריו | `test/attached_libraries/attached_libraries_repository_test.dart`, `test/library/bloc/library_attached_reindex_test.dart` |
| איתור מקורות בספר ממסד מצורף (כותרת, כינוי, line_ref של המסד, תוכן עניינים, הפרדה מספר רשמי) | `test/find_ref/find_ref_attached_library_test.dart` |
| כינויים ודורות פר-מסד (AcronymsCache / GenerationCache) | `test/data/cache/attached_library_caches_test.dart` |
| API התוספים לספר ממסד מצורף (resolveRef לפי מקור+מזהה, getLinks לפי `source`/`bookUid`, line_ref של המסד המצורף) | `test/plugins/bridge/plugin_bridge_adapter_test.dart`, `test/plugins/bridge/plugin_bridge_links_api_test.dart`, `test/attached_libraries/attached_library_rich_content_test.dart` |
| קישורי טווח ההדפסה דרך `TextBookRepository` (כולל קישורי משתמש וחוצי-מסדים) | `test/printing/print_range_links_test.dart` |
| מפתח הערות אישיות `title\|db:<slug>`: איתור הספר לפי המפתח, עיגון לתוכן המסד המצורף | `test/personal_notes/personal_notes_book_key_test.dart`, `test/attached_libraries/attached_library_rich_content_test.dart` |
| גיבוי ושחזור רשימת המסדים ותיקיותיהם (קובץ חסר ⇒ 'לא זמין') | `test/settings/services/backup_service_test.dart` |
| תוכן ספר אינו מפעיל פעולות `otzaria://`; מפרש ממסד מצורף בלי 'דווח על טעות' | `test/utils/text/html_link_handler_test.dart`, `test/utils/context_menu_optional_bloc_test.dart` |
| חיפוש הספרייה: כינויים ודור לפי מקור, דירוג אחרי רשמי ואישי | `test/data/repository/book_search_fuzzy_match_test.dart` |
| עדכוני מסד מצורף — נעיצת המקור (TOFU) וסטייה, מניפסט, חתימת ed25519, מדיניות רשת, הורדת חלקים ובנייה | `test/attached_libraries/update/` |
| עדכוני מסדים מצורפים — בדיקה מתוזמנת (שערי הגדרות/לא מקוון/תדירות), בדיקה ידנית, התקנה בקישור ובעותק, שחזור (קובץ פגום / מפתח / library_id / גרסה), שחזור .bak-update אחרי קריסה, ביטול, מקום בדיסק, שחרור נעילה | `test/attached_libraries/update/attached_library_update_service_test.dart` |
| הורדה והרכבה ב-isolate (HTTP אמיתי, ביטול דרך הפורט) | `test/attached_libraries/update/attached_update_downloader_test.dart` |
| כרטיס המסדים: צ'יפ מקור העדכונים, שורת העדכון, דיאלוג האישור, סיכום הצירוף | `test/attached_libraries/update/attached_library_update_panel_test.dart` |
| כלי המפרסם `tool/personal_db_update.dart` (keygen/pack/sign/verify, הלוך-חזור עם zstd) ודיווח המאמת על שדות העדכון | `test/tool/personal_db_update_tool_test.dart` |

**Search**
| Area | Test File |
|------|-----------|
| Find-match utils | `test/search/find_match_utils_test.dart` |
| Catalogue order helper | `test/search/search_catalogue_order_helper_test.dart` |
| Enhanced search field | `test/search/enhanced_search_field_test.dart` |
| Book facet | `test/search/book_facet_test.dart` |
| Facet helper | `test/search/facet_helper_test.dart` |
| Search BLoC facet counts | `test/search/search_bloc_facet_counts_test.dart` |
| Search scope preferences | `test/search/search_scope_preferences_test.dart` |
| זכירת המיון ואיחוד התוצאות (העדפה, BLoC, טאב חדש) | `test/search/search_results_preferences_test.dart` |
| אותן העדפות בלי אתחול `Settings` | `test/search/search_results_preferences_uninitialized_test.dart` |
| עץ ניווט תוצאות (רשימת סינון, גלוּת הבחירה, פתיחת ענפים) | `test/search/search_navigation_tree_test.dart` |
| חלונית סינון התוצאות מקצה לקצה (שדה "איתור ספר") | `test/search/search_facet_filtering_book_filter_test.dart` |
| צמצום מקומי בלחיצה בעץ התוצאות (זיהוי הספר לפי המפתח היציב) | `test/search/search_client_side_facet_narrow_test.dart` |
| זיהוי ספר של תוצאת חיפוש לפי מפתח האינדקס היציב | `test/search/search_result_book_resolution_test.dart` |
| ניתוב חיפוש-בספר: פשוט מול מנוע | `test/search/utils/in_book_search_routing_test.dart` |
| מדיניות ההתאמה (טווח קרבה + התאמת מילים) | `test/search/search_match_policy_test.dart` |
| פתיחת תוצאה: העברת הקונפיגורציה לטאב הקריאה | `test/search/tantivy_search_results_in_book_routing_test.dart` |
| זיהוי הספר של תוצאה מול הקטלוג (מפתח האינדקס + אימות כותרת) | `test/search/search_result_book_resolution_test.dart` |
| פתיחת תוצאה מאינדקס שאינו מסונכרן (מסלול הלחיצה) | `test/search/search_result_stale_index_open_test.dart` |
| שקילות מנוע ↔ הדגשה במרווח בין מילים | `test/search/highlight_engine_distance_parity_test.dart` |
| הדגשה במדיניות התאמה — רק בשורות שהמנוע החזיר | `test/utils/highlight_match_policy_test.dart` |
| שימור קונפיגורציית החיפוש בשכפול/שחזור טאב ובשמירה ל-JSON | `test/tabs/models/tab_search_state_clone_test.dart` |
| איחוד התוצאות וטווח הקרבה ב-JSON של טאב החיפוש | `test/tabs/models/searching_tab_json_config_test.dart` |
| Gematria search | `test/tools/gematria/gematria_search_test.dart` |

**Personal Notes**
| Area | Test File |
|------|-----------|
| Notes screen | `test/personal_notes/personal_notes_screen_test.dart` |
| Note tile | `test/personal_notes/widgets/note_tile_test.dart` |
| Note editor | `test/personal_notes/personal_note_editor_test.dart` |
| Note draft service | `test/personal_notes/personal_note_draft_service_test.dart` |
| Note content view | `test/personal_notes/personal_note_content_view_test.dart` |
| Notes export | `test/personal_notes/personal_notes_export_test.dart` |
| סינון "הצג רק הערות לטקסט הנראה" (BLoC) | `test/personal_notes/bloc/personal_notes_visible_filter_test.dart` |
| שורות גלויות בחלונית ההערות (הרכבה, גלילה, PDF) | `test/personal_notes/widgets/personal_notes_sidebar_visible_lines_test.dart` |

**Settings**
| Area | Test File |
|------|-----------|
| Nikud display service | `test/settings/nikud_display_service_test.dart` |
| Settings repository | `test/settings/settings_repository_test.dart` |
| Settings screen controller | `test/settings/settings_screen_controller_test.dart` |
| Bookmark model | `test/settings/history/bookmark_model_test.dart` |
| Custom folders BLoC | `test/settings/services/custom_folders/custom_folders_bloc_test.dart` |
| Backup service (roundtrip, plugins, auto-backup, per-book, tabs) | `test/settings/services/backup_service_test.dart` |
| כיסוי מקומות השמירה — כל box/תיקייה מוכרע כמגובה או לא | `test/settings/services/backup_storage_coverage_test.dart` |
| Backup store (blobs, dedup, GC) + maintenance helpers | `test/unit/settings/backup/backup_store_test.dart` |
| Backup rotation (GFS) | `test/unit/settings/backup/backup_rotation_test.dart` |
| Backup archive merge rules | `test/unit/settings/backup/backup_merge_test.dart` |
| ייבוא ספרים אישיים במובייל (קבצים, ותיקייה שלמה באנדרואיד דרך SAF) | `test/settings/panels/personal_books_import_panel_test.dart`, `test/settings/services/custom_folders/personal_books_import_service_test.dart`, `…android_folder_import_channel_test.dart` |
| SegmentedSettingsTile | `test/settings/widgets/segmented_settings_tile_test.dart` |
| נתיב ב-`SettingsActionTile.path` מוצג משמאל לימין | `test/settings/widgets/settings_action_tile_path_direction_test.dart` |
| SwitchSettingsTile | `test/settings/widgets/switch_settings_tile_test.dart` |

**Widgets (shared)**
| Area | Test File |
|------|-----------|
| App menu | `test/widgets/app_menu_test.dart` |
| App top bar | `test/widgets/app_top_bar_test.dart` |
| Context overlay panel | `test/widgets/context_overlay_panel_test.dart` |
| Context menu (incl. hover preview + pinning) | `test/widgets/app_context_menu_test.dart` |
| Link preview panel (placement, pin, scroll anchor) | `test/widgets/link_preview_overlay_test.dart` |
| Nav rail item | `test/widgets/nav_rail_item_test.dart` |
| Responsive action bar | `test/widgets/responsive_action_bar_test.dart` |
| רוחב עמודת הטקסט (בסיס אזור הקריאה, יציב בפתיחת חלונית) | `test/widgets/layout/reading_area_width_test.dart` |
| Scrollable list scrollbar | `test/widgets/scrollable_positioned_list_scrollbar_test.dart` |
| Smooth mouse-wheel scrolling | `test/widgets/smooth_wheel_scroll_test.dart` |
| עיגון מחדש של מיקום הקריאה בשינוי רוחב | `test/widgets/lists/scroll_position_reanchor_test.dart` |
| גלילה אוטומטית בלחיצת גלגל העכבר | `test/widgets/middle_click_autoscroll_test.dart` |
| פתיחה בכרטיסייה חדשה בלחיצת גלגל (`MiddleClickOpen`) | `test/widgets/middle_click_open_test.dart` |
| זיהוי קישור `<a>` תחת הסמן (תפריט הקשר / לחיצת גלגל) | `test/widgets/inline_link_targets_test.dart` |
| הקשת מגע על קישור שנפתח בריחוף → תצוגה מקדימה מקובעת (issue #1320) | `test/widgets/smart_text/smart_text_touch_preview_test.dart` |
| Smart text render settings | `test/widgets/smart_text/render_settings_test.dart` |
| הדגשת חיפוש כששם הוי"ה מוחלף (הדגשה לפני ההחלפה, issue #1248) | `test/widgets/smart_text/text_renderer_holy_name_highlight_test.dart` |
| Smart text ↔ plugin section sync gate | `test/widgets/smart_text/smart_text_section_sync_gate_test.dart` |
| קיבוע מדויק של גובה השורה (סימוני הערות, `<big>`) בשלושת מסלולי הרינדור | `test/widgets/smart_text/exact_line_height_test.dart` |
| Work/indexing status overlays | `test/widgets/work_status_overlay_test.dart`, `…indexing_status_overlay_test.dart` |
| App dropdown/search menu | `test/widgets/app_dropdown_field_test.dart`, `…app_search_menu_test.dart` |
| Search pane base | `test/widgets/search_pane_base_test.dart` |
| כל `TextPainter` ב-`lib` מקבל `textDirection` (issue #1474) | `test/widgets/text_painter_direction_test.dart` |
| חיפוש בלשונית חלונית הניווט (אייקון בכותרת, X סוגר ומנקה, חיצים לשורות) | `test/widgets/nav_panel_search_test.dart` |
| חלונית לא נעוצה מרחפת מעל התוכן; נעיצה אינה בונה מחדש את התוכן | `test/widgets/adaptive_side_pane_test.dart` |
| נתוני פופאפ "אוצריא מתגייסת" (`assets/support_organizations.json`) | `test/services/support_organizations_test.dart` |
| פופאפ "אוצריא מתגייסת" (תצוגה, שגיאת טעינה, פענוח לוגואים ומטמון) | `test/widgets/dialogs/ad_popup_dialog_test.dart` |

**Navigation / Startup**
| Area | Test File |
|------|-----------|
| Navigation BLoC | `test/navigation/navigation_bloc_test.dart` |
| כיווניות הכרום בשפת ממשק LTR | `test/navigation/chrome_direction_test.dart` |
| תפריט ההקשר של כרטיסיה (משותף לרצועה העליונה ולעמודה) | `test/navigation/tab_context_menu_test.dart` |
| Startup guard / auto-reindex | `test/navigation/startup_work_gate_test.dart`, `…startup_auto_reindex_test.dart`, `…refresh_indexing_dedupe_test.dart` |

**Other Features**
| Area | Test File |
|------|-----------|
| Bookmarks BLoC | `test/bookmarks/bookmark_bloc_test.dart` |
| דיאלוג איתור מקורות (פריסה, הצעות, ניווט מקלדת, גדלי מסך) | `test/find_ref/find_ref_dialog_view_test.dart` |
| האיתורים האחרונים (שמירה, מכסה, ערך פגום) | `test/find_ref/find_ref_recent_store_test.dart` |
| סימניה מרוכזת (מודל + bloc) | `test/bookmarks/bookmark_group_test.dart` |
| Workspaces BLoC | `test/workspaces/bloc/workspace_bloc_test.dart` |
| מחוות החלקה בין טאבים (סינון התקנים, כיוון) | `test/tabs/reading_screen_move_tab_state_test.dart`, `…tab_swipe_direction_test.dart` |
| Windows installer scripts (`.iss` invariants) | `test/installer/installer_scripts_test.dart` |
| App paths / install-mode detection | `test/core/app_paths_test.dart` |
| Library browser | `test/library/view/library_browser_preview_width_test.dart`, `…grid_items_test.dart`, `…library_browser_flat_tree_test.dart` |
| שמירת טקסט החיפוש בניווט בספרייה ("חזור"/"בית") | `test/library/bloc/library_navigation_keeps_search_test.dart`, `test/library/view/library_empty_state_navigation_test.dart` |
| Empty library screen | `test/empty_library/empty_library_screen_test.dart` |
| PDF isolate | `test/printing/pdf_isolate_test.dart` |
| טקסט מעוצב ב-PDF (גופן Type0 עם גליפים מ-shaper, פריסה ויישור, bidi) | `test/printing/shaped_text/pdf_shaped_font_test.dart`, `…shaped_text_layout_test.dart` |
| גופן לא מוטמע ב-PDF (עברית נעלמת מתצוגה/חיפוש/אינדוקס — `PdfFontFallback`) | `test/pdf_book/pdf_font_fallback_test.dart` |
| PDF in-book search highlight pattern | `test/pdf_book/pdf_search_highlight_pattern_test.dart` |
| צבעי מסך ה-PDF נגזרים מערכת הצבעים (issue #1469) | `test/pdf_book/pdf_hardcoded_colors_test.dart`, `test/pdf_book/pdf_link_hover_color_test.dart`, `test/pdf_book/pdf_theme_rendering_test.dart` |
| ניתוב החיפוש בתוך PDF (פשוט מול מנוע) | `test/pdf_book/pdf_search_in_book_routing_test.dart` |
| Printing models | `test/printing/print_content_models_test.dart` |
| File sync / background sync | `test/migration/sync/file_sync_service_prune_test.dart`, `…background_db_sync_worker_test.dart`, `…background_sync_initializer_test.dart` |
| כותרות וגרסאות לספרים אישיים — פענוח, בניית העץ ואיתור לפי טקסט | `test/user_content_import/user_headings_import_test.dart` |
| קליטת `<ספר>.כותרות.csv` / `גרסאות.csv` מתיקיית הספרים והייבוא מההגדרות, ניקוי במחיקת ספר | `test/user_content_import/user_sidecar_sync_test.dart` |
| קריאת לשונית 'כותרות' של ספר אישי (ניווט, כותרת פעילה, סימני חלוקה) | `test/user_content_import/user_alt_toc_repository_test.dart` |
| קבוצת הגרסאות של ספר אישי + דיאלוג 'גרסאות' | `test/user_content_import/user_book_versions_test.dart`, `test/library/view/book_versions_dialog_test.dart` |
| גרסה אישית של ספר רשמי/ממסד מצורף (קישור לפי כותרת, ראשי שלא נמצא, בורר הנוסחאות, מהדורה מקבילה, קריאה; שדרוג הטבלה) | `test/user_content_import/user_book_versions_catalog_test.dart`, `test/migration/user_books_schema_extensions_test.dart`, `test/user_content_import/user_import_parser_test.dart` |
| DB migration / generator | `test/migration/generator_create_and_process_book_test.dart`, `test/migration/dao/daos/database_locked_test.dart` |
| Indexing repository | `test/indexing/repository/indexing_repository_test.dart` |
| External catalog | `test/external_catalog/external_catalog_repository_test.dart`, `…settings_helper_test.dart` |
| Plugins | `test/plugins/utils/reader_location_resolver_test.dart`, `…plugin_store_link_parser_test.dart`, `…plugin_bridge_adapter_test.dart` |
| Plugin links API (`getLinks`, `getRawLinks`, `getCommentators`, `getLinkContent`) | `test/plugins/bridge/plugin_bridge_links_api_test.dart` |
| דגל שינויים שלא נשמרו בתוסף (`ui.setUnsavedChanges`, רגיסטרי, שומר סגירת כרטיסיה) | `test/plugins/bridge/plugin_bridge_set_unsaved_changes_test.dart`, `test/plugins/services/plugin_unsaved_changes_registry_test.dart`, `test/tabs/utils/confirm_close_tabs_test.dart` |
| תוסף ללא ממשק (`headless`: מניפסט, אימות חוסם, המעטפת הווירטואלית) | `test/plugins/services/plugin_headless_test.dart`, `test/tools/tool_catalog_test.dart` |
| Plugin permission enforcement / rate limiting | `test/plugins/bridge/plugin_bridge_handler_test.dart` |
| קיצורי ניווט של התוכנה בתוך WebView של תוסף (רשימה מוזרקת, תפיסה ב-JS, הזרקה לצינור המקלדת) | `test/plugins/services/plugin_host_shortcuts_test.dart`, `test/plugins/view/plugin_host_shortcut_script_test.dart` |
| Plugin highlights / reader section tracking | `test/plugins/services/plugin_highlight_registry_test.dart`, `…reader_section_content_tracker_test.dart`, `…reader_section_sync_gate_test.dart` |
| Plugin foreground suspend/resume | `test/plugins/services/plugin_runtime_dispatcher_test.dart` |
| פוקוס מקלדת ל-WebView של תוסף (הקלדה מיד בפתיחה) | `test/plugins/services/plugin_webview_focus_test.dart`, `…plugin_keyboard_focus_test.dart` |
| שחזור פוקוס ה-WebView של תוסף בחזרה לחלון (Alt-Tab) | `test/plugins/view/widgets/plugin_webview_focus_restorer_test.dart` |
| בדיקת עדכוני תוספים מהחנות (שירות batch, קוביט, צ'יפ "עדכון זמין") | `test/plugins/services/plugin_update_check_service_test.dart`, `test/plugins/bloc/plugin_updates_cubit_test.dart`, `test/plugins/view/plugin_update_chip_test.dart` |

**Tools & plugins as reading tabs**
| Area | Test File |
|------|-----------|
| ToolTab model (JSON, clone, dedupe) | `test/tabs/models/tool_tab_test.dart` |
| כותרת מיקום לטאב טקסט שטרם נבנה (שאילתת DB יחידה, בלי טעינת תוכן) | `test/tabs/models/text_tab_location_title_test.dart` |
| Tool catalog + availability reasons | `test/tools/tool_catalog_test.dart` |
| Tools launcher panel (search, grouping, grid columns, tile layout) | `test/tools/tools_launcher_panel_test.dart` |
| Tool tab focus (WebView regression) | `test/tools/tool_tab_focus_test.dart` |
| Tool tab dedupe / focus-existing | `test/tabs/bloc/tool_tab_dedupe_test.dart` |
| `readingPane` (plugin reader API context) | `test/tabs/reading_pane_test.dart` |

| Shamor Zachor | `test/shamor_zachor/shamor_zachor_test.dart` (+ 4 more in that dir) |
| Dictionary lookup | `test/tools/dictionary/dictionary_lookup_repository_test.dart` |
| Laaz Rashi commentary line-lookup | `test/tools/dictionary/laaz_rashi_line_lookup_test.dart` |
| Laaz Rashi commentary sub-block widget | `test/tools/dictionary/laaz_commentary_subblock_test.dart` |
| Laaz Rashi commentary wiring (surfaces) | `test/tools/dictionary/laaz_commentary_wiring_test.dart` |
| Commentary reverse links | `test/text_book/commentary_reverse_links_test.dart` |
| Inline links | `test/models/inline_links_test.dart` |
| Dialog navigation | `test/widgets/dialogs/dialog_navigation_test.dart` |
| Focus restore | `test/core/focus_restore_test.dart` |
| Models (books, links) | `test/models/books_test.dart`, `…links_test.dart`, `…phone_report_data_test.dart` |
| Link types (נרמול, סוג קנוני, תוויות) | `test/models/link_types_test.dart` |
| Utils (page map builder, page converter, TOC parser) | `test/utils/page_map_builder_test.dart`, `…page_converter_test.dart`, `…toc_parser_test.dart` |
| Utils (link processing) | `test/text_book/utils/link_processing_test.dart` |
| חיתוך HTML לפי טווח הבחירה (שימור עיצוב בהעתקה חלקית) | `test/utils/text/html_slice_test.dart` |
| גודל פענוח תמונות (cacheWidth על נכסים כבדים) | `test/utils/ui/image_decode_size_test.dart` |
| Hebrew text utils (migration) | `test/migration/hebrew_text_utils_test.dart` |
| Text book searcher (in-book search) | `test/text_book/models/text_book_searcher_test.dart` |
| Note text utils | `test/personal_notes/note_text_utils_test.dart` |
| Shortcut validator | `test/shortcuts/shortcut_validator_test.dart` |
| Core (activation queue/channel, error log) | `test/core/` |
| כל הודעה ל-`UiSnack` מגיעה מקטלוג `lib/core/messages/` (issue #1473) | `test/core/messages/uisnack_literal_scan_test.dart` |
| תעודות ה-CA של נטפרי שנטענות בהפעלה (שלושת הבאנדלים ב-`assets/ca/`) | `test/core/netfree_ca_assets_test.dart` |
| Error logging | `test/core/main_error_logging_test.dart`, `test/services/direct_error_report_service_test.dart` |
| דיווח על התוכנה — מודל (חוזה, גבולות, חיתוך גוף, JSON) | `test/app_report/app_report_model_test.dart` |
| דיווח על התוכנה — חתימת קריסה (נרמול פריימים, hash) | `test/app_report/crash_signature_test.dart` |
| דיווח על התוכנה — הסתרת מידע אישי (פרופיל, שם משתמש, מייל) | `test/app_report/app_report_redactor_test.dart` |
| דיווח על התוכנה — איסוף אבחון ולוג (מקטע שנכשל, חלון 7 ימים, ארכיטקטורה) | `test/app_report/app_report_collector_test.dart` |
| דיווח על התוכנה — שירות השליחה (תור, 409/422/429, היסטוריה, סקריפט אופליין) | `test/app_report/app_report_service_test.dart` |
| זיהוי יציאה לא נקייה (נעילת הפעלה, ראיות, מגבלת דיווח אוטומטי) | `test/app_report/unclean_exit_detector_test.dart` |
| טופס הדיווח (BLoC: איסוף, ולידציה לפי מקור, החרגת צרופות, שמירת מייל) | `test/app_report/bloc/app_report_bloc_test.dart` |
| דיאלוג הדיווח הידני (מייל חובה, תצוגה מקדימה, הודעות סיום) | `test/app_report/view/app_report_dialog_test.dart` |
| הצעת דיווח אחרי קריסה (בלי מייל, בחירת "תמיד"/"אל תשאל") | `test/app_report/view/crash_prompt_dialog_test.dart` |
| צירוף צילומי מסך לדיווח (הדבקה מכל הטופס, בחירה, הסרה, מכסה וגודל) | `test/app_report/view/app_report_images_section_test.dart` |
| עריכת דיווח תוכנה שמור בתור (שדות, שימור צרופות, מייל לפי מקור) | `test/app_report/view/app_report_edit_fields_test.dart` |
| הכרעת הדיווח אחרי קריסה (מצב × מועמד × מגבלה, כותרת, מפתח מגבלה) | `test/app_report/crash_report_decision_test.dart` |
| זרימת הקריסה בעלייה (never/ask/always, auto_crash, רישום במגבלה) | `test/app_report/crash_report_flow_test.dart` |
| תיקוני טקסט — חוזה A (מודל schema 2, round-trip מדויק, null מול "", לקוח ישן, 409/413/429, `correction_supported`) | `test/models/direct_error_report_text_correction_test.dart`, `test/services/direct_error_report_service_test.dart` |
| digest קנוני OCJ-1 מול ה-fixtures המשותפים לאתר | `test/utils/canonical_json_test.dart` |
| סקריפט שליחה אופליין (bat/sh) — ה-payload מגיע לשרת כלשונו (הרצה אמיתית ב-bash/PowerShell) | `test/services/offline_report_script_payload_test.dart` |

**Calendar (`lib/tools/calendar/`)**
| Area | Test File |
|------|-----------|
| Cubit (אירועים, פלאגינים, התראות) | `test/tools/calendar/utils/calendar_cubit_test.dart` |
| סדר אירועים (לפי שעה) — cubit + משווים | `test/tools/calendar/utils/calendar_event_sorting_test.dart` |
| סדר אירועים בתצוגה (פאנל + תא היום) | `test/tools/calendar/widgets/calendar_events_order_test.dart` |
| זמני היום / אזורי זמן | `test/tools/calendar/utils/calendar_daily_times_test.dart`, `…calendar_timezone_test.dart` |
| כרטיסי זמנים (composite) ורישום הזמנים | `test/tools/calendar/widgets/calendar_composite_entries_test.dart` |
| עזרי זמנים / מולד | `test/tools/calendar/helpers/zmanim_helpers_test.dart`, `…molad_helpers_test.dart` |
| דיאלוגים | `test/tools/calendar/dialogs/calendar_dialogs_test.dart` |
| תא היום (JewishCalendar משותף) | `test/tools/calendar/widgets/day_cell_shared_calendar_test.dart` |
| פוקוס וניווט מקלדת | `test/tools/calendar/widgets/calendar_widget_focus_test.dart`, `…calendar_top_bar_focus_test.dart` |
| החלקה בין חודשים | `test/tools/calendar/widgets/calendar_main_panel_swipe_test.dart` |
| פריסה רספונסיבית | `test/tools/calendar/calendar_screen_responsive_test.dart` |
| הדפסה (טקסט מעוצב וקטורי בשלוש התצוגות) | `test/tools/calendar/helpers/calendar_print_pdf_test.dart` |

## מיפויים נוספים

### `test/data/`

| Area | Test File |
|------|-----------|
| אינדקס הביגרמים של הכינויים (איתור מקורות — קבוצת-על) | `test/data/cache/acronyms_bigram_index_test.dart` |

### `test/find_ref/`

| Area | Test File |
|------|-----------|
| פתרון ספר של מפרש בדיאלוג "איתור מקורות" (id → כותרת, אינדקס העץ) | `test/find_ref/find_ref_book_by_id_test.dart` |

### `test/library/`

| Area | Test File |
|------|-----------|
| תאריך עברי + דף יומי בסרגל הספרייה (היום הלוחי) | `test/library/view/library_daf_yomi_test.dart` |

### `test/migration/`

| Area | Test File |
|------|-----------|
| עמידות סריקה לקובץ פגום (§76) | `test/migration/generator_corrupted_file_test.dart` |
| אינטגרציה: סריקת תיקייה לכל הפורמטים → DB → פתיחה → זיהוי שינוי | `test/migration/sync/file_sync_document_formats_test.dart` |
| ייבוא ספרים בכל קידוד לתוך SQLite (סריקה→שורות→TOC) | `test/migration/sync/file_sync_text_encodings_test.dart` |

### `test/tabs/`

| Area | Test File |
|------|-----------|
| מעבר לטאב שנפתח כשמסך הקריאה מנותק (issue #877) | `test/tabs/reading_screen_offscreen_tab_open_test.dart` |

### `test/tool/`

| Area | Test File |
|------|-----------|
| מחולל קורפוס ה-fixtures (כל פורמט נפתח, כל מקרה-קצה נכשל נכון) | `test/tool/document_fixtures_generator_test.dart` |

### `test/tour/`

| Area | Test File |
|------|-----------|
| כיוון כרטיסי הסיור/טיפים לפי שפת ההגדרות | `test/tour/widgets/tour_cards_direction_test.dart` |

### `test/utils/`

| Area | Test File |
|------|-----------|
| זיהוי פורמט מסמך + registry הסיומות | `test/utils/file/document_format_test.dart` |
| עקביות ה-registry מול הצרכנים (FilePicker, סורק, מודל הספר) | `test/utils/file/format_registry_consistency_test.dart` |
| Golden regression של ממיר Word (17 תרחישים, שקילות DOCX/DOCM/DOTX/DOTM) | `test/utils/file/docx_golden_test.dart` (fixtures ב-`docx_golden_fixtures.dart`) |
| שרשרת מלאה לפורמטי OOXML (סריקה→המרה→TOC→אינדוקס) | `test/utils/file/ooxml_formats_pipeline_test.dart` |
| ממיר ODT | `test/utils/file/odt_to_otzaria_test.dart` |
| Parser RTF (state machine, דפי-קוד, עברית) | `test/utils/file/rtf_to_otzaria_test.dart` |
| קריאת ספר file-backed לפי פורמט | `test/utils/file/read_file_backed_book_text_test.dart` |
| מגבלות פריסת ZIP (zip bomb) | `test/utils/file/zip_limits_test.dart` |
| הקשחה מול קובץ פגום/קטוע/זדוני (כשל בקול, לא פלט חלקי) | `test/utils/file/malformed_document_hardening_test.dart` |
| קורא מכולת CFB/OLE2 (תשתית ל-DOC/WBK) | `test/utils/file/cfb_reader_test.dart` |
| ממיר Word בינארי ישן (FIB, piece table, ניתוב WBK) | `test/utils/file/legacy_word_to_otzaria_test.dart` |
| שכבת המאפיינים של Word הבינארי (sprm, וריאנט Bi, יישור) | `test/utils/file/legacy_word_properties_test.dart` |
| חילוץ תמונות מ-Word הבינארי (עץ OfficeArt, תקרות, קלט פגום) | `test/utils/file/legacy_word_pictures_test.dart` |
| ממיר Word שנשמר כ-XML (Flat OPC ו-WordML 2003) | `test/utils/file/word_xml_to_otzaria_test.dart` |
| צימוד פלט הממיר לגרסתו (מונע מטמון שמגיש פלט באגי) | `test/utils/file/converter_versions_test.dart` |
| זיהוי קידוד טקסט — שרשרת הזיהוי, BOM, זנב קטוע, כפיית קידוד | `test/utils/file/text_encoding_detection_test.dart` |
| טבלאות המיפוי (Windows-1255, ISO-8859-8, CP862) מול התקנים | `test/utils/file/text_encoding_tables_test.dart` |
| קורפוס הזהב של הקידודים (40+ קבצים, טווחי confidence) | `test/utils/file/text_encoding_corpus_test.dart` (מחולל ב-`tool/generate_text_encoding_fixtures.dart`) |
| רגרסיה מול מפענח הקידודים הקודם (מה נשמר, מה השתנה בכוונה) | `test/utils/file/text_encoding_regression_test.dart` |
| תכונות הקידוד על קלט מוגרל (סבב שלם, שיבוש, חיתוך, דטרמיניזם) | `test/utils/file/text_encoding_fuzz_test.dart` |
| צנרת הקידודים מקצה לקצה (פתיחת ספר, בניית DB, אינדוקס) | `test/utils/file/text_encoding_pipeline_test.dart` |
| ביצועי הזיהוי (חסימת דגימה, תפוקת batch, השוואה לקודם) | `test/utils/file/text_encoding_performance_test.dart` |
| קורפוס קידודים חיצוני אמיתי (מדלג כשאינו על המכונה) | `test/utils/file/text_encoding_real_corpus_test.dart` |

### `test/widgets/`

| Area | Test File |
|------|-----------|
| שימור כיוון הפותח בתפריטים מעוגנים (הגדרות באנגלית) | `test/widgets/app_menu_direction_test.dart` |
