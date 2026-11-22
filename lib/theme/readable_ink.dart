import 'package:flutter/painting.dart';

/// צבע הטקסט על רקע תוכן שאינו מהערכה (הדגשה בהערה אישית, הדגשת קטע ספר על
/// ידי תוסף). הערכה צובעת טקסט לפי הרקע שלה, לא לפי רקע התוכן, ובכהה יוצא
/// טקסט בהיר על צהוב בהיר. הצבע נגזר מבהירות הרקע בזמן ההצגה, כך שהוא נכון
/// גם לתוכן שנשמר לפני התיקון ולמשתמש שעובר בין בהיר לכהה.
const Color inkOnLightBackground = Color(0xFF1F1F1F);
const Color inkOnDarkBackground = Color(0xFFFFFFFF);

/// הבהירות היחסית שבה לבן ושחור נותנים אותה ניגודיות: מעליה כהה קריא יותר.
const double _luminanceCrossover = 0.179;

/// הטקסט הקריא על [background] אטום: כהה על רקע בהיר ולבן על רקע כהה.
Color readableInkOn(Color background) =>
    background.computeLuminance() > _luminanceCrossover
    ? inkOnLightBackground
    : inkOnDarkBackground;
