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

  static const List<String> _scopes = <String>[
    cal.CalendarApi.calendarEventsScope,
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
    final auth.AuthClient? client =
        await _getAuthClient(interactive: interactive);

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
      throw Exception('Google Calendar OAuth credentials not configured.\n'
          'Please update clientId and clientSecret in google_calendar_credentials.dart\n'
          'See GOOGLE_CALENDAR_SETUP.md for instructions.');
    }

    final id = auth_io.ClientId(
      GoogleCalendarCredentials.clientId,
      GoogleCalendarCredentials.clientSecret,
    );
    final storedJson = _settingsRepository.getGoogleCalendarCredentialsJson();

    if (storedJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(storedJson) as Map<String, dynamic>;
        final creds = auth.AccessCredentials.fromJson(decoded);
        return auth_io.autoRefreshingClient(id, creds, http.Client());
      } catch (e) {
        // fall through to interactive flow if parsing failed
        // Clear invalid credentials
        await _settingsRepository.updateGoogleCalendarCredentialsJson('');
      }
    }

    if (!interactive) return null;

    try {
      final authClient = await auth_io.clientViaUserConsent(
        id,
        _scopes,
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

  Future<void> _persistCredentials(auth.AuthClient client) async {
    if (client is auth_io.AutoRefreshingAuthClient) {
      final jsonStr = jsonEncode(client.credentials.toJson());
      await _settingsRepository.updateGoogleCalendarCredentialsJson(jsonStr);
    }
  }
}
