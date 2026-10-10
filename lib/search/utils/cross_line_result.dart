/// מוצג בכרטיס תוצאה שהביטוי בה נמשך מסוף השורה אל תחילת השורה הבאה.
const String crossLineResultNote = 'הביטוי נמשך מסוף השורה אל השורה הבאה';

/// שורות התוצאה בספר: השורה עצמה, ובביטוי שנמשך — גם השורה הבאה.
Set<int> searchResultLinesFor(int line, {required bool continuesToNextLine}) =>
    {line, if (continuesToNextLine) line + 1};
