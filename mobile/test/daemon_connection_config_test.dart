import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';

void main() {
  group('normalizeDaemonAddress', () {
    test('adds http scheme and default daemon port for host input', () {
      final normalized = normalizeDaemonAddress('127.0.0.1');

      expect(normalized.uri.toString(), 'http://127.0.0.1:4317');
      expect(normalized.input, '127.0.0.1');
    });

    test('adds default port for LAN host input', () {
      final normalized = normalizeDaemonAddress('192.168.1.23');

      expect(normalized.uri.toString(), 'http://192.168.1.23:4317');
    });

    test('preserves explicit scheme and port', () {
      final normalized = normalizeDaemonAddress('http://devbox.local:7317');

      expect(normalized.uri.toString(), 'http://devbox.local:7317');
    });

    test('accepts compact host and port', () {
      final normalized = normalizeDaemonAddress('devbox.local:7317');

      expect(normalized.uri.toString(), 'http://devbox.local:7317');
    });

    test('rejects empty address', () {
      expect(
        () => normalizeDaemonAddress('  '),
        throwsA(isA<DaemonConnectionConfigException>()
            .having(
              (error) => error.message,
              'message',
              'Enter a daemon address.',
            )
            .having(
              (error) => error.code,
              'code',
              DaemonConnectionConfigErrorCode.emptyDaemonAddress,
            )),
      );
    });

    test('rejects unsupported schemes', () {
      expect(
        () => normalizeDaemonAddress('ftp://127.0.0.1:4317'),
        throwsA(isA<DaemonConnectionConfigException>()
            .having(
              (error) => error.message,
              'message',
              'Daemon address must use http or https.',
            )
            .having(
              (error) => error.code,
              'code',
              DaemonConnectionConfigErrorCode.unsupportedDaemonAddressScheme,
            )),
      );
    });
  });

  group('normalizeManualProxy', () {
    test('normalizes compact proxy input to http uri', () {
      final proxy = normalizeManualProxy('192.168.20.18:27890');

      expect(proxy.toString(), 'http://192.168.20.18:27890');
    });

    test('preserves http proxy uri', () {
      final proxy = normalizeManualProxy('http://proxy.local:8080');

      expect(proxy.toString(), 'http://proxy.local:8080');
    });

    test('rejects empty manual proxy input', () {
      expect(
        () => normalizeManualProxy(' '),
        throwsA(isA<DaemonConnectionConfigException>()
            .having(
              (error) => error.message,
              'message',
              'Enter a proxy address.',
            )
            .having(
              (error) => error.code,
              'code',
              DaemonConnectionConfigErrorCode.emptyProxyAddress,
            )),
      );
    });
  });

  group('isLocalOrPrivateDaemonHost', () {
    test('detects loopback and private hosts', () {
      expect(isLocalOrPrivateDaemonHost('localhost'), isTrue);
      expect(isLocalOrPrivateDaemonHost('127.0.0.1'), isTrue);
      expect(isLocalOrPrivateDaemonHost('10.0.4.8'), isTrue);
      expect(isLocalOrPrivateDaemonHost('172.16.4.8'), isTrue);
      expect(isLocalOrPrivateDaemonHost('172.31.4.8'), isTrue);
      expect(isLocalOrPrivateDaemonHost('192.168.1.23'), isTrue);
    });

    test('does not treat public hosts as private', () {
      expect(isLocalOrPrivateDaemonHost('172.32.4.8'), isFalse);
      expect(isLocalOrPrivateDaemonHost('8.8.8.8'), isFalse);
      expect(isLocalOrPrivateDaemonHost('example.com'), isFalse);
    });
  });

  test('default connection config matches startup defaults', () {
    expect(DaemonConnectionConfig.fallback.addressInput, '127.0.0.1:4317');
    expect(DaemonConnectionConfig.fallback.proxyMode, DaemonProxyMode.direct);
    expect(DaemonConnectionConfig.fallback.manualProxyInput, '');
  });
}
