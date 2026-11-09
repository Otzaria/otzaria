import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';

void main() {
  test('בעלות כפתור היא החלטת מארח ולא הרשאה אוטומטית של מניפסט', () {
    expect(pluginValidPermissions, isNot(contains(pluginNewTabPagePermission)));
    expect(effectiveManifestPermissions(['navigation.write']), [
      'navigation.write',
    ]);
  });

  group('pluginBaselinePermissions', () {
    test('כל הרשאת בסיס קיימת ברשימת ההרשאות התקפות', () {
      for (final permission in pluginBaselinePermissions) {
        expect(
          pluginValidPermissions,
          contains(permission),
          reason: 'הרשאת הבסיס $permission חייבת להישאר תקפה לתאימות לאחור',
        );
      }
    });

    test('הרשאות רגישות אינן בסיס', () {
      for (final sensitive in [
        'network.access',
        'network.localhost',
        'library.content.read',
        'fs.user_files.read',
        pluginFolderAccessPermission,
        pluginRunOnStartupPermission,
        'notifications.system',
        'history.read',
        pluginClipboardReadPermission,
        pluginGeolocationPermission,
      ]) {
        expect(pluginBaselinePermissions, isNot(contains(sensitive)));
      }
    });
  });

  group('effectiveManifestPermissions', () {
    test('מסנן הרשאות בסיס ושומר על סדר ההרשאות הנותרות', () {
      final result = effectiveManifestPermissions([
        'plugin.storage.read',
        'network.access',
        'ui.feedback',
        'reader.open',
        'events.subscribe:theme.changed',
      ]);
      expect(result, ['network.access', 'reader.open']);
    });

    test('מניפסט של הרשאות בסיס בלבד — רשימה ריקה', () {
      final result = effectiveManifestPermissions([
        'ui.feedback',
        'plugin.storage.read',
        'plugin.storage.write',
      ]);
      expect(result, isEmpty);
    });

    test('כפילויות מוסרות והרשאה מפורשת חדשה נשמרת', () {
      final result = effectiveManifestPermissions([
        pluginFolderAccessPermission,
        'reader.open',
        'reader.open',
      ]);
      expect(result, [pluginFolderAccessPermission, 'reader.open']);
    });
  });

  group('withBaselinePermissions', () {
    test('מאחד עם הרשאות הבסיס בלי כפילויות וממוין', () {
      final result = withBaselinePermissions([
        'network.access',
        'ui.feedback',
      ]);
      expect(result, containsAll(pluginBaselinePermissions));
      expect(result, contains('network.access'));
      expect(result.toSet().length, result.length);
      expect(result, List.of(result)..sort());
    });
  });

  group('pluginLegacyPermissionAliases', () {
    test('fs.folder_access מכוסה בהצהרת ui.feedback ותיקה', () {
      expect(
        pluginLegacyPermissionAliases[pluginFolderAccessPermission],
        'ui.feedback',
      );
    });
  });
}
