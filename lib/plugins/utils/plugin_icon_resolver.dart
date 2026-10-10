import 'package:flutter/widgets.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// תחילית שכופה פתרון מספריית האייקונים של אוצריא בלבד.
const String kOtzariaIconPrefix = 'otzaria:';

/// תחילית שכופה פתרון מ-FluentUI בלבד.
const String kFluentIconPrefix = 'fluent:';

/// פותר שם נוכחי או כינוי תאימות; אוצריא קודמת לפלואנט.
/// תחילית כופה ספרייה אחת בלבד; שם לא מוכר מחזיר null.
IconData? pluginIconFromName(String? name) {
  if (name == null) return null;
  if (name.startsWith(kOtzariaIconPrefix)) {
    return _otzariaIconFromName(name.substring(kOtzariaIconPrefix.length));
  }
  if (name.startsWith(kFluentIconPrefix)) {
    return fluentIconFromName(name.substring(kFluentIconPrefix.length));
  }
  return _otzariaIconFromName(name) ?? fluentIconFromName(name);
}

IconData? _otzariaIconFromName(String name) =>
    OtzariaIcons.allIcons[name] ?? _legacyOtzariaIcons[name];

// שמות שהצהירו תוספים חייבים להמשיך להיפתר גם לאחר שינוי שם בספרייה.
const _legacyOtzariaIcons = <String, IconData>{
  'alef_addition_24_regular': OtzariaIcons.alef_add_24_filled,
  'alef_deletion_24_regular': OtzariaIcons.alef_delete_24_filled,
  'alef_half_filled_24_regular': OtzariaIcons.alef_mix_24_regular,
  'alef_with_eraser_24_regular': OtzariaIcons.alef_eraser_24_filled,
  'alef_with_exclamation_24_regular': OtzariaIcons.alef_exclamation_24_filled,
  'alef_with_flavors_24_regular': OtzariaIcons.alef_niqqud_taamim_24_filled,
  'alef_with_information_24_regular': OtzariaIcons.alef_information_24_filled,
  'alef_with_punctuation_24_regular': OtzariaIcons.alef_punctuation_24_filled,
  'alef_with_score_24_regular': OtzariaIcons.alef_niqqud_24_filled,
  'book_md_24_filled': OtzariaIcons.book_24_filled,
  'book_md_24_regular': OtzariaIcons.book_24_regular,
  'book_open_medium_line_24_filled':
      OtzariaIcons.book_open_medium_lines_24_filled,
  'book_open_medium_line_24_regular':
      OtzariaIcons.book_open_medium_lines_24_regular,
  'book_open_small_line_24_filled':
      OtzariaIcons.book_open_small_lines_24_filled,
  'book_open_small_line_24_regular':
      OtzariaIcons.book_open_small_lines_24_regular,
  'book_zim_24_filled': OtzariaIcons.book_24_filled,
  'book_zim_24_regular': OtzariaIcons.book_24_regular,
  'clipboard_text_24_filled': OtzariaIcons.clipboard_text_rtl_24_filled,
  'icon_x_24_regular': OtzariaIcons.cross_24_filled,
  'link_book_empty_24_regular': OtzariaIcons.link_book_24_regular,
  'link_book_exclamation_24_regular': OtzariaIcons.link_exclamation_24_regular,
  'link_deletion_24_regular': OtzariaIcons.link_delete_24_regular,
  'link_with_eraser_24_regular': OtzariaIcons.link_eraser_24_regular,
  'link_with_information_24_regular': OtzariaIcons.link_information_24_regular,
  'otzaria_icon_2_page_line_24_filled':
      OtzariaIcons.otzaria_icon_2_page_lines_24_filled,
  'otzaria_icon_2_page_line_24_regular':
      OtzariaIcons.otzaria_icon_2_page_lines_24_regular,
  'otzaria_icon_line_24_filled': OtzariaIcons.otzaria_icon_lines_24_filled,
  'otzaria_icon_line_24_regular': OtzariaIcons.otzaria_icon_lines_24_regular,
  'search_in_the_book_24_filled': OtzariaIcons.search_in_book_24_filled,
  'search_in_the_book_24_regular': OtzariaIcons.search_in_book_24_regular,
  'search_in_the_document_24_filled': OtzariaIcons.search_in_document_24_filled,
  'search_in_the_document_24_regular':
      OtzariaIcons.search_in_document_24_regular,
  'search_in_the_library_24_filled': OtzariaIcons.search_in_library_24_filled,
  'search_in_the_library_24_regular': OtzariaIcons.search_in_library_24_regular,
  'search_in_the_person_24_filled': OtzariaIcons.search_in_person_24_filled,
  'search_in_the_person_24_regular': OtzariaIcons.search_in_person_24_regular,
  'search_in_the_quote_24_filled': OtzariaIcons.search_in_quote_24_filled,
  'search_in_the_quote_24_regular': OtzariaIcons.search_in_quote_24_regular,
  'search_in_the_settings_24_filled': OtzariaIcons.search_in_settings_24_filled,
  'search_in_the_settings_24_regular':
      OtzariaIcons.search_in_settings_24_regular,
  'search_in_the_text_24_filled': OtzariaIcons.search_in_text_24_filled,
  'search_in_the_text_24_regular': OtzariaIcons.search_in_text_24_regular,
  'stander_24_filled': OtzariaIcons.lectern_24_filled,
  'stander_24_regular': OtzariaIcons.lectern_24_regular,
  'text_continuous_24_filled': OtzariaIcons.text_continuous_rtl_24_filled,
  'text_continuous_24_regular': OtzariaIcons.text_continuous_rtl_24_regular,
  'yoma_deilula_24_regular': OtzariaIcons.calendar_yahrzeit_24_regular,
};
