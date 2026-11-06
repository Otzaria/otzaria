import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' show Bidi;
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

SettingsLanguage _reportLanguage(BuildContext context) {
  final scope = context.getInheritedWidgetOfExactType<SettingsTextScope>();
  return scope?.language ??
      (Settings.isInitialized
          ? resolveSettingsLanguage(
              Settings.getValue<String>(
                SettingsRepository.keySettingsLanguage,
              ),
            )
          : SettingsLanguage.source);
}

Widget _reportLanguageScope(
  BuildContext context,
  SettingsLanguage language,
  Widget child,
) => Localizations.override(
  context: context,
  locale: Locale(language.code),
  delegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  child: Directionality(
    textDirection: language.textDirection,
    child: SettingsTextScope(language: language, child: child),
  ),
);

/// Keeps framework text menus in the report language without changing the
/// application's locale or any user-authored report content.
Widget wrapWithReportScope(BuildContext context, Widget child) =>
    _reportLanguageScope(context, _reportLanguage(context), child);

WidgetBuilder reportDialogBuilder(BuildContext context, WidgetBuilder builder) {
  final language = _reportLanguage(context);
  return (dialogContext) => _reportLanguageScope(
    dialogContext,
    language,
    Builder(builder: builder),
  );
}

String reportText(
  BuildContext context,
  String hebrew, {
  Map<String, Object?>? args,
}) {
  return resolveSettingsText(
    hebrew,
    language: _reportLanguage(context),
    args: args,
  );
}

const _reportTargets = {'אוצריא', 'ספריא'};

/// Recipient names are interface labels. The stored routing value is unchanged.
String reportTargetText(BuildContext context, String target) =>
    _reportTargets.contains(target) ? context.settingsText(target) : target;

/// Book direction follows the content language; source text and offsets stay
/// unchanged. HTML is inspected only to choose the display direction.
TextDirection reportContentDirection(String text, {bool isHtml = false}) =>
    Bidi.detectRtlDirectionality(text, isHtml: isHtml)
    ? TextDirection.rtl
    : TextDirection.ltr;

/// Localizes only known delivery-service messages, keeping their parameter
/// values and user-authored report text untouched.
String reportFeedbackText(BuildContext context, String message) {
  for (final template in const [
    ReportMessages.correctionNotSupportedTemplate,
    ReportMessages.bodyTooLargeTemplate,
    ReportMessages.duplicateReportTemplate,
    ReportMessages.queuedOfflineTemplate,
    ReportMessages.queuedAfterFailureTemplate,
    ReportMessages.serverPermanentFailureTemplate,
    ReportMessages.serverTransientFailureTemplate,
    ReportMessages.proposalTooLongTemplate,
    ReportMessages.originalTooLongTemplate,
  ]) {
    final placeholder = RegExp(r'\{([^}]+)\}').firstMatch(template)!;
    final before = template.substring(0, placeholder.start);
    final after = template.substring(placeholder.end);
    if (!message.startsWith(before) || !message.endsWith(after)) continue;
    final value = message.substring(
      before.length,
      message.length - after.length,
    );
    final displayValue =
        placeholder[1] == 'target' && _reportTargets.contains(value)
        ? reportText(context, value)
        : value;
    return reportText(context, template, args: {placeholder[1]!: displayValue});
  }
  return reportText(context, message);
}
