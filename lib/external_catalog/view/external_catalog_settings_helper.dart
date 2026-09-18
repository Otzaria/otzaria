import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

class ExternalCatalogSettingsHelper {
  /// מעדכן במקשה אחת אילו מקורות ספרים חיצוניים יוצגו.
  /// [mode] אחד מ: 'none', 'all', 'otzar', 'hebrewbooks'.
  static Future<void> updateExternalSourceMode(
    BuildContext context,
    String mode,
  ) async {
    final settingsBloc = context.read<SettingsBloc>();
    final current = settingsBloc.state.enabledExternalProviders;
    // ספקים שאינם חלק מתפריט הקטלוג המשותף (פרויקט השו"ת) אינם מושפעים
    // ממנו — הבחירה כאן היא על אוצר החכמה והיברובוקס בלבד.
    final untouched = current.difference({
      ExternalProviderRegistry.otzar.id,
      ExternalProviderRegistry.hebrewBooks.id,
    });

    if (mode == 'none') {
      settingsBloc.add(UpdateEnabledExternalProviders(untouched));
      return;
    }

    if (!await ensureCatalogDatabaseAvailable(context)) {
      return;
    }

    settingsBloc.add(
      UpdateEnabledExternalProviders({
        ...untouched,
        if (mode == 'all' || mode == 'otzar') ExternalProviderRegistry.otzar.id,
        if (mode == 'all' || mode == 'hebrewbooks')
          ExternalProviderRegistry.hebrewBooks.id,
      }),
    );
  }

  /// מוודא שמסד הקטלוגים קיים; אם חסר — מציע להוריד אותו (בכפוף למצב רשת
  /// ולעדכונים מופעלים). מחזיר `true` אם בסוף קיים קטלוג זמין.
  static Future<bool> ensureCatalogDatabaseAvailable(
    BuildContext context,
  ) async {
    final repository = ExternalCatalogRepository.instance;
    if (await repository.databaseExists()) {
      return true;
    }
    if (!context.mounted) {
      return false;
    }

    final settingsState = context.read<SettingsBloc>().state;
    if (settingsState.isOfflineMode ||
        !settingsState.softwareAndBookUpdatesEnabled) {
      await showSingleActionDialog(
        context: context,
        title: 'מסד הקטלוגים חסר',
        content: settingsState.isOfflineMode
            ? 'לא ניתן להוריד את מסד הקטלוגים החיצוני במצב מנותק.'
            : 'לא ניתן להוריד את מסד הקטלוגים כשהאפשרות עדכוני תוכנה וספרים מושבתת.',
        confirmText: 'הבנתי',
      );
      return false;
    }

    final shouldDownload = await showTwoActionsDialog(
      context: context,
      title: 'מסד הקטלוגים חסר',
      content:
          'כדי להציג ספרים מאוצר החכמה ומהיברובוקס צריך להוריד את מסד הקטלוגים החיצוני. האם להוריד אותו עכשיו?',
      cancelText: 'לא עכשיו',
      confirmText: 'הורד',
    );

    if (shouldDownload != true) {
      UiSnack.show(SettingsMessages.noCatalogNoExternalBooks);
      return false;
    }
    if (!context.mounted) {
      return false;
    }

    try {
      UiSnack.show(SettingsMessages.downloadingCatalogDb);
      await repository.downloadLatestDatabase();
      DataRepository.instance.invalidateExternalBooksCache();
      UiSnack.showSuccess(SettingsMessages.catalogDbDownloaded);
      return true;
    } catch (e) {
      UiSnack.showError(SettingsMessages.catalogDbDownloadError(e));
      return false;
    }
  }
}
