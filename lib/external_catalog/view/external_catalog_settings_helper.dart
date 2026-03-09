import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';

class ExternalCatalogSettingsHelper {
  static Future<void> updateExternalBooks(
    BuildContext context,
    bool enabled,
  ) async {
    final settingsBloc = context.read<SettingsBloc>();
    if (enabled && !await _ensureCatalogDatabaseAvailable(context)) {
      return;
    }

    settingsBloc.add(UpdateShowExternalBooks(enabled));
    settingsBloc.add(UpdateShowHebrewBooks(enabled));
    settingsBloc.add(UpdateShowOtzarHachochma(enabled));
  }

  static Future<void> updateOtzarBooks(
    BuildContext context,
    bool enabled,
  ) async {
    final settingsBloc = context.read<SettingsBloc>();
    if (enabled && !await _ensureCatalogDatabaseAvailable(context)) {
      return;
    }

    if (enabled) {
      settingsBloc.add(const UpdateShowExternalBooks(true));
    }
    settingsBloc.add(UpdateShowOtzarHachochma(enabled));
  }

  static Future<void> updateHebrewBooks(
    BuildContext context,
    bool enabled,
  ) async {
    final settingsBloc = context.read<SettingsBloc>();
    if (enabled && !await _ensureCatalogDatabaseAvailable(context)) {
      return;
    }

    if (enabled) {
      settingsBloc.add(const UpdateShowExternalBooks(true));
    }
    settingsBloc.add(UpdateShowHebrewBooks(enabled));
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

    final shouldDownload = await showTwoActionsDialog(
      context: context,
      title: 'מסד הקטלוגים חסר',
      content:
          'כדי להציג ספרים מאוצר החכמה ומהיברובוקס צריך להוריד את מסד הקטלוגים החיצוני. האם להוריד אותו עכשיו?',
      cancelText: 'לא עכשיו',
      confirmText: 'הורד',
    );

    if (shouldDownload != true) {
      UiSnack.show('ללא מסד הקטלוגים לא יוצגו ספרים חיצוניים');
      return false;
    }
    if (!context.mounted) {
      return false;
    }

    try {
      UiSnack.show('מוריד את מסד הקטלוגים החיצוני...');
      await repository.downloadLatestDatabase();
      DataRepository.instance.invalidateExternalBooksCache();
      UiSnack.showSuccess('מסד הקטלוגים הורד בהצלחה');
      return true;
    } catch (e) {
      UiSnack.showError('שגיאה בהורדת מסד הקטלוגים: $e');
      return false;
    }
  }
}
