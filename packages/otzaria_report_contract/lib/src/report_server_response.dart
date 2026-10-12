import 'dart:convert';

/// משמעות תשובת השרת לשליחת דיווח (ספר, תוכנה או תוסף).
enum ReportResponseKind {
  /// 2xx: הדיווח נקלט; `duplicate:true` = כבר התקבל קודם.
  accepted,

  /// 409: התוכן הזה לא נקלט תחת המזהה; שליחה חוזרת היא הגשה חדשה במזהה חדש.
  idConflict,

  /// 400/413/422: השרת דחה את התוכן; ניסיון חוזר לא יעזור.
  rejected,

  /// 503 עם `{"error":"shabbat"}`: האתר סגור בשבת; לנסות שוב אחריה.
  closedForShabbat,

  /// כל השאר (408/429/5xx וכו'): כשל זמני, לנסות שוב.
  transient,
}

/// תשובת השרת לשליחת דיווח, מסווגת לפי החוזה.
class ReportServerResponse {
  ReportServerResponse(this.statusCode, this.body)
    : kind = _classify(statusCode, body);

  final int statusCode;

  /// גוף התשובה כאובייקט JSON, או null כשאינו כזה.
  final Map<String, dynamic>? body;

  final ReportResponseKind kind;

  /// התוכן כבר התקבל בשליחה קודמת.
  bool get duplicate => body?['duplicate'] == true;

  /// שם השדה שהשרת דחה, כשציין.
  String? get rejectedField {
    final field = body?['field'];
    return field is String ? field : null;
  }

  static ReportResponseKind _classify(int status, Map<String, dynamic>? body) {
    if (status >= 200 && status < 300) return ReportResponseKind.accepted;
    return switch (status) {
      409 => ReportResponseKind.idConflict,
      400 || 413 || 422 => ReportResponseKind.rejected,
      503 when body?['error'] == 'shabbat' =>
        ReportResponseKind.closedForShabbat,
      _ => ReportResponseKind.transient,
    };
  }

  /// מפענח גוף תשובה ל-JSON; null לגוף שאינו אובייקט JSON.
  static Map<String, dynamic>? decodeBody(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
