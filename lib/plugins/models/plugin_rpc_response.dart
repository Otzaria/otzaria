class PluginRpcResponse {
  final bool success;
  final dynamic data;
  final PluginRpcError? error;

  const PluginRpcResponse._({
    required this.success,
    this.data,
    this.error,
  });

  const PluginRpcResponse.success(dynamic data)
    : this._(success: true, data: data);

  PluginRpcResponse.error({
    required String code,
    required String message,
  }) : this._(
         success: false,
         error: PluginRpcError(code: code, message: message),
       );

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'data': success ? data : null,
      'error': success ? null : error?.toJson(),
    };
  }
}

class PluginRpcError {
  static const int schemaVersion = 1;

  final String code;
  final String message;
  final Object? details;
  final bool retryable;
  final String category;

  PluginRpcError({
    required this.code,
    required this.message,
    this.details,
    bool? retryable,
    String? category,
  }) : retryable = retryable ?? _isRetryable(code),
       category = category ?? _categoryFor(code);

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'code': code,
      'message': message,
      if (details != null) 'details': details,
      'retryable': retryable,
      'category': category,
    };
  }

  static bool _isRetryable(String code) =>
      code == 'error.timeout' || code == 'error.rate_limited';

  static String _categoryFor(String code) {
    if (code == 'permission_denied' ||
        code == 'error.permission_denied' ||
        code == 'error.forbidden') {
      return 'permission';
    }
    if (code == 'error.timeout') return 'timeout';
    if (code == 'error.conflict') return 'conflict';
    if (code == 'error.not_found' || code == 'error.highlight_not_found') {
      return 'not_found';
    }
    if (code == 'error.section_too_large' ||
        code == 'error.payload_too_large' ||
        code == 'error.rate_limited') {
      return 'too_large';
    }
    // unknown_method/unavailable אינם קלט שגוי — הם "אין דבר כזה כאן",
    // אותה משמעות של unsupported מבחינת התוסף.
    if (code == 'error.unsupported_context' ||
        code == 'error.unsupported_layer' ||
        code == 'error.unsupported' ||
        code == 'error.unknown_method' ||
        code == 'error.unavailable') {
      return 'unsupported';
    }
    if (code == 'error.internal') return 'internal';
    return 'validation';
  }
}
