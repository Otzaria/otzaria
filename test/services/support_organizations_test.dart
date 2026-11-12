import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/support_organization.dart';
import 'package:otzaria/services/support_organizations_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'השירות טוען את הקובץ דרך rootBundle — הנתיב שהאפליקציה משתמשת בו',
    () async {
      SupportOrganizationsService.resetCache();
      final organizations = await SupportOrganizationsService.load();
      expect(organizations.emergencyLines, isNotEmpty);
      expect(organizations.supportOrgs, isNotEmpty);
    },
  );

  group('SupportOrganization.fromJson', () {
    test('מחבר את שורות הפרטים לטקסט אחד', () {
      final org = SupportOrganization.fromJson(const {
        'name': 'ארגון',
        'phone': '*1234',
        'logo': 'assets/logos/x.png',
        'details': ['שורה א', 'שורה ב'],
      });

      expect(org.details, 'שורה א\nשורה ב');
      expect(org.phones, isEmpty);
      expect(org.registeredCount, isNull);
    });

    test('מציב את כמות הנרשמים עם מפריד אלפים במקום ה-placeholder', () {
      final org = SupportOrganization.fromJson(const {
        'name': 'ארגון',
        'phone': '*1234',
        'logo': 'assets/logos/x.png',
        'registeredCount': 102631,
        'details': ['7 - כמות הנרשמים (מעל {registered})'],
      });

      expect(org.details, '7 - כמות הנרשמים (מעל 102,631)');
    });
  });

  group('קובץ הנתונים ${SupportOrganizationsService.assetPath}', () {
    late SupportOrganizations organizations;

    setUpAll(() {
      final file = File(SupportOrganizationsService.assetPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'קובץ הנתונים חסר — הפופאפ ייפתח ריק',
      );
      organizations = SupportOrganizations.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
    });

    test('לכל ארגון שם, טלפון וקובץ לוגו קיים', () {
      final all = [
        ...organizations.emergencyLines,
        ...organizations.supportOrgs,
      ];
      for (final org in all) {
        expect(org.name.trim(), isNotEmpty);
        expect(org.phone.trim(), isNotEmpty);
        expect(
          File(org.logo).existsSync(),
          isTrue,
          reason: 'הלוגו ${org.logo} של "${org.name}" לא קיים בדיסק',
        );
      }
    });

    test('כל יחס תמונה נמצא בתחום שפענוח ה-cover מכסה', () async {
      final all = [
        ...organizations.emergencyLines,
        ...organizations.supportOrgs,
      ];
      for (final org in all) {
        final buffer = await ui.ImmutableBuffer.fromFilePath(org.logo);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final ratio = descriptor.width / descriptor.height;
        final directionalRatio = ratio >= 1 ? ratio : 1 / ratio;
        descriptor.dispose();
        buffer.dispose();

        expect(
          directionalRatio,
          lessThanOrEqualTo(
            SupportOrganizationsService.maxLogoAspectRatio,
          ),
          reason: 'הלוגו של "${org.name}" דורש הגדלת maxLogoAspectRatio',
        );
      }
    });

    test('כמות הנרשמים מוצבת — לא נשאר placeholder בטקסט המוצג', () {
      final all = [
        ...organizations.emergencyLines,
        ...organizations.supportOrgs,
      ];
      for (final org in all) {
        expect(
          org.details,
          isNot(contains('{registered}')),
          reason: 'ל"${org.name}" יש {registered} בלי registeredCount',
        );
      }
    });

    test('ארגון עם registeredCount מציג אותו בפרטים', () {
      final all = [
        ...organizations.emergencyLines,
        ...organizations.supportOrgs,
      ].where((org) => org.registeredCount != null);

      expect(all, isNotEmpty);
      for (final org in all) {
        expect(
          org.details,
          contains('כמות הנרשמים'),
          reason: 'ל"${org.name}" יש registeredCount שלא מופיע בפרטים',
        );
      }
    });
  });
}
