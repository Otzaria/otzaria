import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

class ExternalCatalogSettingsHelper {
  static bool _isAutoSyncInProgress = false;

  /// מעדכן במקשה אחת אילו מקורות ספרים חיצוניים יוצגו.
  /// [mode] אחד מ: 'none', 'all', 'otzar', 'hebrewbooks'.
  static Future<void> updateExternalSourceMode(
    BuildContext context,
    String mode,
  ) async {
    final settingsBloc = context.read<SettingsBloc>();

    if (mode == 'none') {
      settingsBloc.add(const UpdateShowExternalBooks(false));
      settingsBloc.add(const UpdateShowOtzarHachochma(false));
      settingsBloc.add(const UpdateShowHebrewBooks(false));
      settingsBloc.add(const UpdateAutoSyncCatalogs(false));
      return;
    }

    final wasEnabled = settingsBloc.state.showExternalBooks;
    if (!await _ensureCatalogDatabaseAvailable(context)) {
      return;
    }

    settingsBloc.add(const UpdateShowExternalBooks(true));
    settingsBloc.add(
      UpdateShowOtzarHachochma(mode == 'all' || mode == 'otzar'),
    );
    settingsBloc.add(
      UpdateShowHebrewBooks(mode == 'all' || mode == 'hebrewbooks'),
    );
    if (!wasEnabled) {
      settingsBloc.add(const UpdateAutoSyncCatalogs(true));
    }
  }

  static Future<bool> _ensureCatalogDatabaseAvailable(
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

  static Future<void> maybeAutoSyncCatalogs(
    SettingsState settingsState, {
    ExternalCatalogRepository? repository,
    VoidCallback? invalidateExternalBooksCache,
  }) async {
    if (!settingsState.showExternalBooks ||
        !settingsState.autoSyncCatalogs ||
        !settingsState.canUseSoftwareAndBookUpdates ||
        _isAutoSyncInProgress) {
      return;
    }

    final catalogsRepository = repository ?? ExternalCatalogRepository.instance;
    if (!await catalogsRepository.databaseExists()) {
      return;
    }

    _isAutoSyncInProgress = true;
    try {
      final updated = await catalogsRepository.updateDatabaseIfNeeded();
      if (updated) {
        (invalidateExternalBooksCache ??
            DataRepository.instance.invalidateExternalBooksCache)();
      }
    } catch (e) {
      debugPrint('Auto-sync external catalogs failed: $e');
    } finally {
      _isAutoSyncInProgress = false;
    }
  }
}
