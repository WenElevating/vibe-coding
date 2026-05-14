enum DaemonProxyMode {
  direct,
  system,
  manual;

  String get storageValue => switch (this) {
        DaemonProxyMode.direct => 'direct',
        DaemonProxyMode.system => 'system',
        DaemonProxyMode.manual => 'manual',
      };

  String get label => switch (this) {
        DaemonProxyMode.direct => 'Direct',
        DaemonProxyMode.system => 'System proxy',
        DaemonProxyMode.manual => 'Manual proxy',
      };

  static DaemonProxyMode fromStorageValue(String? value) => switch (value) {
        'system' => DaemonProxyMode.system,
        'manual' => DaemonProxyMode.manual,
        _ => DaemonProxyMode.direct,
      };
}

class DaemonConnectionConfig {
  const DaemonConnectionConfig({
    required this.addressInput,
    required this.proxyMode,
    required this.manualProxyInput,
  });

  static const fallback = DaemonConnectionConfig(
    addressInput: '127.0.0.1:4317',
    proxyMode: DaemonProxyMode.direct,
    manualProxyInput: '',
  );

  final String addressInput;
  final DaemonProxyMode proxyMode;
  final String manualProxyInput;

  DaemonConnectionConfig copyWith({
    String? addressInput,
    DaemonProxyMode? proxyMode,
    String? manualProxyInput,
  }) =>
      DaemonConnectionConfig(
        addressInput: addressInput ?? this.addressInput,
        proxyMode: proxyMode ?? this.proxyMode,
        manualProxyInput: manualProxyInput ?? this.manualProxyInput,
      );
}

class NormalizedDaemonAddress {
  const NormalizedDaemonAddress({
    required this.input,
    required this.uri,
  });

  final String input;
  final Uri uri;
}

class DaemonConnectionConfigException implements Exception {
  const DaemonConnectionConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

NormalizedDaemonAddress normalizeDaemonAddress(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const DaemonConnectionConfigException('Enter a daemon address.');
  }

  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final parsed = Uri.tryParse(withScheme);
  if (parsed == null || parsed.host.trim().isEmpty) {
    throw const DaemonConnectionConfigException(
        'Enter a valid daemon address.');
  }
  if (parsed.scheme != 'http' && parsed.scheme != 'https') {
    throw const DaemonConnectionConfigException(
        'Daemon address must use http or https.');
  }

  final uri = parsed.hasPort
      ? parsed
      : parsed.replace(port: parsed.scheme == 'https' ? 443 : 4317);
  return NormalizedDaemonAddress(input: trimmed, uri: uri);
}

Uri normalizeManualProxy(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const DaemonConnectionConfigException('Enter a proxy address.');
  }

  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final parsed = Uri.tryParse(withScheme);
  if (parsed == null || parsed.host.trim().isEmpty || !parsed.hasPort) {
    throw const DaemonConnectionConfigException(
        'Enter a valid proxy host and port.');
  }
  if (parsed.scheme != 'http') {
    throw const DaemonConnectionConfigException('Manual proxy must use http.');
  }
  return parsed;
}

bool isLocalOrPrivateDaemonHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' || normalized == '::1') return true;
  final parts = normalized.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return false;
    octets.add(value);
  }
  if (octets.first == 127) return true;
  if (octets.first == 10) return true;
  if (octets.first == 192 && octets[1] == 168) return true;
  if (octets.first == 172 && octets[1] >= 16 && octets[1] <= 31) {
    return true;
  }
  return false;
}
