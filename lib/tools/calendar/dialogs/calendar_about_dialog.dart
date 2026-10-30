import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// "אודות חישובי הלוח": על מי מיוסדים החישובים, ומה אין בהם.
Future<void> showCalendarAboutDialog(BuildContext context) async {
  await showSingleActionDialog(
    context: context,
    title: 'אודות חישובי הלוח',
    icon: FluentIcons.info_24_regular,
    headerBand: true,
    confirmText: 'הבנתי',
    customContent: const SizedBox(
      width: 520,
      child: AppSelectionArea(
        child: SingleChildScrollView(
          child: DetailsCard(
            children: [
              DetailsText(
                'חישובי הלוח בתוכנה זו מיוסדים על דרכו של הרב ישראל דוד הרפנס, כפי שנתבארה בספרו ישראל והזמנים ובשאר ספריו העוסקים בענייני זמני הלכה. מטרת הדברים איננה להציג חישוב עצמאי חדש, אלא ליישם בצורה מסודרת, מדויקת ובהירה את כללי חשבון הלוח העברי על פי הביאור והסידור שנתפרשו בספריו.',
              ),
              DetailsText(
                'הרב הרפנס, מו"ץ בהתאחדות הרבנים ורב קהילת ישראל והזמנים, נודע במיוחד בבירור סוגיות הזמן בהלכה, וספרו ישראל והזמנים הוא ספר היסוד שעל פיו נבנתה תשתית החישוב שבתוכנה. לצד ספר זה, חיבר הרב גם ספרים נוספים בענייני הלכה שונים.',
              ),
              DetailsText(
                'אין בהבאת זמנים אלו משום נקיטת צד באופן החישוב, והם הובאו רק משום הקלות לשלבם בתוכנה.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
