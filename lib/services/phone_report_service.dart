import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/messages/report_messages.dart';
import '../models/phone_report_data.dart';

/// Service for submitting phone error reports to Google Apps Script
class PhoneReportService {
  static const String _endpoint =
      'https://script.google.com/macros/s/AKfycbyhLP5nbbRN33TFb7kR625BNZzzmhEljT8vX9bgckd6Vx6KPSz9Fgh9aDEk4rZe36Bf/exec';

  static const Duration _timeout = Duration(seconds: 10);
  static const int _maxRetries = 2;

  /// Submit a phone error report
  /// Returns true if successful, false otherwise
  Future<PhoneReportResult> submitReport(PhoneReportData reportData) async {
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        debugPrint('Submitting phone report (attempt $attempt/$_maxRetries)');

        final response = await http
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'application/json',
              },
              body: jsonEncode(reportData.toJson()),
            )
            .timeout(_timeout);

        debugPrint('Response status: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');

        if (response.statusCode == 200) {
          return PhoneReportResult.success(ReportMessages.phoneSent);
        } else if (response.statusCode >= 400 && response.statusCode < 500) {
          // Client error - don't retry
          return PhoneReportResult.error(
            _getClientErrorMessage(response.statusCode),
          );
        } else if (response.statusCode >= 500) {
          // Server error - retry if not last attempt
          if (attempt == _maxRetries) {
            return PhoneReportResult.error(
              ReportMessages.phoneServerUnavailable,
            );
          }
          // Continue to next attempt
          await Future.delayed(Duration(seconds: attempt));
          continue;
        } else {
          return PhoneReportResult.error(
            ReportMessages.phoneUnexpectedStatus(response.statusCode),
          );
        }
      } on SocketException catch (e) {
        debugPrint('Network error on attempt $attempt: $e');
        if (attempt == _maxRetries) {
          return PhoneReportResult.error(ReportMessages.phoneNoInternet);
        }
        await Future.delayed(Duration(seconds: attempt));
      } on http.ClientException catch (e) {
        debugPrint('HTTP client error on attempt $attempt: $e');
        if (attempt == _maxRetries) {
          return PhoneReportResult.error(ReportMessages.phoneClientError);
        }
        await Future.delayed(Duration(seconds: attempt));
      } on Exception catch (e) {
        debugPrint('Unexpected error on attempt $attempt: $e');
        if (attempt == _maxRetries) {
          return PhoneReportResult.error(ReportMessages.phoneUnexpectedRetry);
        }
        await Future.delayed(Duration(seconds: attempt));
      }
    }

    return PhoneReportResult.error(ReportMessages.phoneUnexpected);
  }

  /// Get user-friendly error message for client errors
  String _getClientErrorMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return ReportMessages.phoneBadRequest;
      case 401:
        return ReportMessages.phoneUnauthorized;
      case 403:
        return ReportMessages.phoneForbidden;
      case 404:
        return ReportMessages.phoneServiceUnavailable;
      case 429:
        return ReportMessages.phoneTooManyRequests;
      default:
        return ReportMessages.phoneSendDataError(statusCode);
    }
  }

  /// Test connection to the reporting endpoint
  Future<bool> testConnection() async {
    try {
      final response = await http
          .head(Uri.parse(_endpoint))
          .timeout(const Duration(seconds: 5));
      return response.statusCode < 500;
    } catch (e) {
      debugPrint('Connection test failed: $e');
      return false;
    }
  }
}

/// Result of a phone report submission
class PhoneReportResult {
  final bool isSuccess;
  final String message;
  final String? errorCode;

  const PhoneReportResult._({
    required this.isSuccess,
    required this.message,
    this.errorCode,
  });

  factory PhoneReportResult.success(String message) {
    return PhoneReportResult._(
      isSuccess: true,
      message: message,
    );
  }

  factory PhoneReportResult.error(String message, [String? errorCode]) {
    return PhoneReportResult._(
      isSuccess: false,
      message: message,
      errorCode: errorCode,
    );
  }

  @override
  String toString() {
    return 'PhoneReportResult(isSuccess: $isSuccess, message: $message, errorCode: $errorCode)';
  }
}
