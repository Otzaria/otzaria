import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/app_scope/external_activation_service.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/core/update_check_frequency.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library_update/repository/library_update_repository.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/library_update/services/github_rate_limit.dart';
import 'package:otzaria/library_update/services/streaming_patch_downloader.dart';
import 'package:otzaria/plugins/bloc/plugin_updates_cubit.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// ספקים ברמת התהליך, שאינם קוראים ספק של [WindowScopeProviders]. מעט מצב חלון
/// שנשאר בהם (`_dismissed` של [PluginUpdatesCubit]) יפוצל בהמשך.
class AppScopeProviders extends StatelessWidget {
  const AppScopeProviders({
    super.key,
    required this.settingsRepository,
    required this.child,
  });

  final SettingsRepository settingsRepository;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SettingsRepository>(
          create: (_) => settingsRepository,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>(
            create: (_) => StartupTimeline.instance.phaseSync(
              'settingsBloc',
              () => SettingsBloc(
                repository: settingsRepository,
                initialSettings: settingsRepository.readSettings(),
              )..add(LoadSettings()),
            ),
          ),
          BlocProvider<IndexingBloc>(
            create: (_) => IndexingBloc.create(),
          ),
          BlocProvider<BookmarkBloc>(
            create: (_) => BookmarkBloc(BookmarkRepository()),
          ),
          ChangeNotifierProvider<ShamorZachorDataProvider>(
            lazy: true,
            create: (_) => ShamorZachorDataProvider(),
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>(
            lazy: true,
            create: (_) => ShamorZachorProgressProvider(),
          ),
          BlocProvider<LibraryUpdateBloc>(
            lazy: true,
            create: (context) => LibraryUpdateBloc(
              repository: LibraryUpdateRepository(
                discovery: LibraryUpdateDiscovery(
                  client: GithubLibraryReleaseClient(
                    httpClient: GithubRateLimitAwareClient(),
                  ),
                  supportedDbSchemaVersion:
                      DatabaseConstants.readableDbSchemaVersion,
                ),
                // זורם לדיסק: patch גדול נפרס בלי לשבת ב-RAM (ראו את המחלקה).
                downloader: StreamingPatchDownloader(),
              ),
              companionAssets: CompanionAssetsService(
                // רק אחרי שהמשתמש הוריד את נתוני החיפוש הסמנטי; אחרת לא עושה דבר.
                scheduleSemanticVectorsUpdate: (tag) => SemanticSearchRepository
                    .instance
                    .scheduleVectorsUpdate(libraryTag: tag),
              ),
              isOfflineMode: () =>
                  Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ??
                  false,
              areUpdatesEnabled: () =>
                  Settings.getValue<bool>(
                    SettingsRepository.keySoftwareAndBookUpdatesEnabled,
                  ) ??
                  true,
              // עדכוני ספרייה תמיד ליציב בלבד — מנותק מערוץ הפיתוח, שמשפיע רק
              // על עדכוני התוכנה.
              allowPrerelease: () => false,
              onCheckSucceeded: () => recordSuccessfulUpdateCheck(
                SettingsRepository.keyLastLibraryUpdateCheck,
              ),
            ),
          ),
          BlocProvider<PluginUpdatesCubit>(
            lazy: true,
            create: (_) => PluginUpdatesCubit(),
          ),
          // נוצר רק כשהחלון הראשי מבקש אותו; חלונות Dart נרשמים אליו.
          Provider<ExternalActivationService>(
            lazy: true,
            create: (_) => ExternalActivationService(),
            dispose: (_, service) => service.dispose(),
          ),
        ],
        child: child,
      ),
    );
  }
}
