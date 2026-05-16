import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/exception_redactor.dart';

void main() {
  group('ExceptionRedactor', () {
    test('redacts authorization bearer tokens case-insensitively', () {
      final redacted = ExceptionRedactor.redactText(
          'Authorization: Bearer abc.def-123\nauthorization: bearer TOKEN_456\nBearer bare-token');

      expect(redacted, contains('Authorization: Bearer [REDACTED]'));
      expect(redacted, contains('authorization: bearer [REDACTED]'));
      expect(redacted, contains('Bearer [REDACTED]'));
      expect(redacted, isNot(contains('abc.def-123')));
      expect(redacted, isNot(contains('TOKEN_456')));
      expect(redacted, isNot(contains('bare-token')));
    });

    test('redacts secret-like key value pairs only', () {
      final redacted = ExceptionRedactor.redactText(
          'api_key=key-123 apikey: key-456 access_token=access-789 '
          'refresh_token=refresh-789 password=hunter2 secret=sauce token=plain');

      expect(redacted, isNot(contains('key-123')));
      expect(redacted, isNot(contains('key-456')));
      expect(redacted, isNot(contains('access-789')));
      expect(redacted, isNot(contains('refresh-789')));
      expect(redacted, isNot(contains('hunter2')));
      expect(redacted, isNot(contains('sauce')));
      expect(redacted, isNot(contains('plain')));
      expect(RegExp(r'\[REDACTED\]').allMatches(redacted), hasLength(7));
    });

    test('redacts metadata values for common secret-like key variants', () {
      final redacted = ExceptionRedactor.redactMetadata(const <String, Object?>{
        'client_secret': 'client-secret-value',
        'refreshToken': 'refresh-token-value',
        'accessToken': 'access-token-value',
        'apiKey': 'api-key-value',
        'auth-token': 'auth-token-value',
        'pairingSecret': 'pairing-secret-value',
        'id': '123e4567-e89b-12d3-a456-426614174000',
      });

      expect(redacted['client_secret'], '[REDACTED]');
      expect(redacted['refreshToken'], '[REDACTED]');
      expect(redacted['accessToken'], '[REDACTED]');
      expect(redacted['apiKey'], '[REDACTED]');
      expect(redacted['auth-token'], '[REDACTED]');
      expect(redacted['pairingSecret'], '[REDACTED]');
      expect(redacted['id'], '123e4567-e89b-12d3-a456-426614174000');
    });

    test('does not redact arbitrary UUIDs or hashes', () {
      const uuid = '123e4567-e89b-12d3-a456-426614174000';
      const hash =
          '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

      final redacted = ExceptionRedactor.redactText('id=$uuid sha256=$hash');

      expect(redacted, contains(uuid));
      expect(redacted, contains(hash));
    });

    test('strips query strings from http and https urls', () {
      final redacted = ExceptionRedactor.redactText(
          'GET https://example.com/a/b?api_key=secret&x=1 and '
          'http://localhost:4317/run?id=abc#frag');

      expect(redacted, contains('https://example.com/a/b?[REDACTED_QUERY]'));
      expect(redacted,
          contains('http://localhost:4317/run?[REDACTED_QUERY]#frag'));
      expect(redacted, isNot(contains('api_key=secret')));
      expect(redacted, isNot(contains('id=abc')));
    });

    test('redacts absolute Windows user paths preserving basename', () {
      final redacted = ExceptionRedactor.redactText(
          r'Failed at C:\Users\Alice\secret\logs\crash.txt');

      expect(redacted, contains(r'[USER_PATH]\crash.txt'));
      expect(redacted, isNot(contains('Alice')));
      expect(redacted, isNot(contains('secret')));
    });

    test('redacts absolute POSIX user paths preserving basename', () {
      final redacted = ExceptionRedactor.redactText(
          'Failed at /Users/alice/private/project/main.dart and /home/bob/.ssh/id_rsa');

      expect(redacted, contains('[USER_PATH]/main.dart'));
      expect(redacted, contains('[USER_PATH]/id_rsa'));
      expect(redacted, isNot(contains('alice')));
      expect(redacted, isNot(contains('/home/bob')));
    });

    test('redacts base64-like tokens when attached to secret-like keys', () {
      const token = 'YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo=';

      final redacted = ExceptionRedactor.redactText('access_token=$token');

      expect(redacted, contains('access_token=[REDACTED]'));
      expect(redacted, isNot(contains(token)));
    });

    test('redacts and truncates exception diagnostic fields', () {
      final diagnostics = ExceptionRedactor.redactException(
        message: 'm' * (maxExceptionMessageChars + 10),
        stack: 's' * (maxExceptionStackChars + 10),
        path: r'C:\Users\Alice\repo\main.dart?token=secret',
        metadata: <String, Object?>{
          for (var index = 0; index < maxExceptionMetadataEntries + 5; index++)
            'entry_$index': 'value_$index',
          'password': 'hunter2',
        },
      );

      expect(diagnostics.message.length, maxExceptionMessageChars);
      expect(diagnostics.stack, isNotNull);
      expect(diagnostics.stack!.length, maxExceptionStackChars);
      expect(diagnostics.path, contains(r'[USER_PATH]\main.dart'));
      expect(diagnostics.metadata.length, maxExceptionMetadataEntries);
      expect(diagnostics.metadata.values.join(' '),
          isNot(contains('value_$maxExceptionMetadataEntries')));
      expect(diagnostics.metadata.values.join(' '), isNot(contains('hunter2')));
    });
  });
}
