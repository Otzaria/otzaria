import 'dart:convert';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'google_calendar_credentials.dart';

class GoogleCalendarApiClient {
  final auth.AuthClient client;
  final cal.CalendarApi api;

  GoogleCalendarApiClient({required this.client})
    : api = cal.CalendarApi(client);

  void close() => client.close();
}

class GoogleCalendarService {
  GoogleCalendarService({
    SettingsRepository? settingsRepository,
  }) : _settingsRepository = settingsRepository ?? SettingsRepository();

  // calendarList.list דורש scope נפרד מ-calendar.events — בלעדיו בחירת
  // היומנים מחזירה תמיד רשימה ריקה (403, issue #1075)
  static const List<String> scopes = <String>[
    cal.CalendarApi.calendarEventsScope,
    cal.CalendarApi.calendarCalendarlistReadonlyScope,
  ];

  final SettingsRepository _settingsRepository;

  Future<bool> isSignedIn() async {
    final creds = _settingsRepository.getGoogleCalendarCredentialsJson();
    return creds.isNotEmpty;
  }

  Future<void> signOut() async {
    await _settingsRepository.updateGoogleCalendarCredentialsJson('');
  }

  Future<GoogleCalendarApiClient?> getApiClient({
    bool interactive = false,
  }) async {
    final auth.AuthClient? client = await _getAuthClient(
      interactive: interactive,
    );

    if (client == null) return null;
    return GoogleCalendarApiClient(client: client);
  }

  Future<auth.AuthClient?> _getAuthClient({
    required bool interactive,
  }) async {
    // Check if credentials are configured
    if (GoogleCalendarCredentials.clientId ==
            'YOUR_CLIENT_ID.apps.googleusercontent.com' ||
        GoogleCalendarCredentials.clientSecret == 'YOUR_CLIENT_SECRET') {
      // Credentials not configured yet
      throw Exception(
        'Google Calendar OAuth credentials not configured.\n'
        'Please update clientId and clientSecret in google_calendar_credentials.dart\n'
        'See GOOGLE_CALENDAR_SETUP.md for instructions.',
      );
    }

    final id = auth_io.ClientId(
      GoogleCalendarCredentials.clientId,
      GoogleCalendarCredentials.clientSecret,
    );
    final storedJson = _settingsRepository.getGoogleCalendarCredentialsJson();

    if (storedJson.isNotEmpty) {
      final creds = _parseStoredCredentials(storedJson);
      if (creds != null &&
          canUseStoredCredentials(creds, interactive: interactive)) {
        return auth_io.autoRefreshingClient(id, creds, http.Client());
      }
      // JSON פגום או טוקן שאינו מכסה את כל ה-scopes — הסכמה מחדש
      await _settingsRepository.updateGoogleCalendarCredentialsJson('');
    }

    if (!interactive) return null;

    try {
      final authClient = await auth_io.clientViaUserConsent(
        id,
        scopes,
        (url) async {
          await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          );
        },
      );

      await _persistCredentials(authClient);
      return authClient;
    } catch (e) {
      throw Exception('Failed to authenticate with Google: $e');
    }
  }

  /// האם להשתמש בהרשאות השמורות במקום לפתוח מסך הסכמה מחדש. טוקן שנשמר
  /// לפני הוספת scope נדחה רק בפעולה יזומה, כדי לא לנתק סנכרון רקע תקין.
  static bool canUseStoredCredentials(
    auth.AccessCredentials credentials, {
    required bool interactive,
  }) => !interactive || scopes.every(credentials.scopes.contains);

  static auth.AccessCredentials? _parseStoredCredentials(String storedJson) {
    try {
      return auth.AccessCredentials.fromJson(
        jsonDecode(storedJson) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistCredentials(auth.AuthClient client) async {
    if (client is auth_io.AutoRefreshingAuthClient) {
      final jsonStr = jsonEncode(client.credentials.toJson());
      await _settingsRepository.updateGoogleCalendarCredentialsJson(jsonStr);
    }
  }
}
