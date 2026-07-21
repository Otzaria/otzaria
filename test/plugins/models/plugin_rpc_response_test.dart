import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_rpc_response.dart';

void main() {
  test('RPC error includes the additive v1 error schema', () {
    final response = PluginRpcResponse.error(
      code: 'error.highlight_not_found',
      message: 'Highlight was not found',
    ).toJson();

    expect(response['success'], isFalse);
    expect(response['data'], isNull);
    expect(response['error'], {
      'schemaVersion': 1,
      'code': 'error.highlight_not_found',
      'message': 'Highlight was not found',
      'retryable': false,
      'category': 'not_found',
    });
  });

  test('timeout and rate-limit errors are retryable', () {
    for (final code in ['error.timeout', 'error.rate_limited']) {
      final error = PluginRpcError(code: code, message: 'Try later').toJson();
      expect(error['retryable'], isTrue);
    }
  });

  test('legacy permission code keeps compatibility and gets a category', () {
    final error = PluginRpcError(
      code: 'permission_denied',
      message: 'Permission denied',
    ).toJson();

    expect(error['code'], 'permission_denied');
    expect(error['category'], 'permission');
  });
}
