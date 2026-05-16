const maxExceptionMessageChars = 4096;
const maxExceptionStackChars = 16384;
const maxExceptionMetadataChars = 8192;
const maxExceptionMetadataEntries = 32;

const _redacted = '[REDACTED]';
const _redactedQuery = '[REDACTED_QUERY]';
const _userPath = '[USER_PATH]';

class RedactedExceptionDiagnostics {
  const RedactedExceptionDiagnostics({
    required this.message,
    required this.metadata,
    this.stack,
    this.path,
  });

  final String message;
  final String? stack;
  final String? path;
  final Map<String, Object?> metadata;
}

class ExceptionRedactor {
  const ExceptionRedactor._();

  static RedactedExceptionDiagnostics redactException({
    required String message,
    String? stack,
    String? path,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) =>
      RedactedExceptionDiagnostics(
        message: _truncate(redactText(message), maxExceptionMessageChars),
        stack: stack == null
            ? null
            : _truncate(redactText(stack), maxExceptionStackChars),
        path: path == null
            ? null
            : _truncate(redactText(path), maxExceptionMetadataChars),
        metadata: redactMetadata(metadata),
      );

  static Map<String, Object?> redactMetadata(Map<String, Object?> metadata) {
    final redacted = <String, Object?>{};
    var usedChars = 0;

    for (final entry in metadata.entries.take(maxExceptionMetadataEntries)) {
      final key = entry.key;
      final value = _isSecretKey(key)
          ? _redacted
          : _redactMetadataValue(entry.value, maxExceptionMetadataChars);
      final entryChars = key.length + _metadataCharLength(value);

      if (redacted.isNotEmpty &&
          usedChars + entryChars > maxExceptionMetadataChars) {
        break;
      }

      redacted[key] = value;
      usedChars += entryChars;
    }

    return redacted;
  }

  static String redactText(String value) {
    var redacted = value;
    redacted = _stripUrlQueries(redacted);
    redacted = _redactUserPaths(redacted);
    redacted = _redactBearerTokens(redacted);
    redacted = _redactKeyValueSecrets(redacted);
    return redacted;
  }

  static Object? _redactMetadataValue(Object? value, int maxChars) {
    if (value is String) {
      return _truncate(redactText(value), maxChars);
    }
    if (value is num || value is bool || value == null) {
      return value;
    }
    return _truncate(redactText(value.toString()), maxChars);
  }

  static String _redactBearerTokens(String value) => value.replaceAllMapped(
        RegExp(r'\b((?:authorization\s*:\s*)?bearer\s+)([^\s,;]+)',
            caseSensitive: false),
        (match) => '${match.group(1)}$_redacted',
      );

  static String _redactKeyValueSecrets(String value) => value.replaceAllMapped(
        RegExp(
          r'''\b(api_key|apikey|access_token|refresh_token|password|secret|token)\b(\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,;)&]+)''',
          caseSensitive: false,
        ),
        (match) {
          final rawValue = match.group(3) ?? '';
          final quote = rawValue.startsWith('"')
              ? '"'
              : rawValue.startsWith("'")
                  ? "'"
                  : '';
          final replacement =
              quote.isEmpty ? _redacted : '$quote$_redacted$quote';
          return '${match.group(1)}${match.group(2)}$replacement';
        },
      );

  static String _stripUrlQueries(String value) => value.replaceAllMapped(
        RegExp(r'https?://[^\s<>"\]\)]+', caseSensitive: false),
        (match) {
          final rawUrl = match.group(0)!;
          final uri = Uri.tryParse(rawUrl);
          if (uri == null || !uri.hasQuery) {
            return rawUrl;
          }
          final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
          final base = rawUrl.split('?').first;
          return '$base?$_redactedQuery$fragment';
        },
      );

  static String _redactUserPaths(String value) {
    var redacted = value.replaceAllMapped(
      RegExp(
          r'[A-Za-z]:(?:\\+|\/+)+Users(?:\\+|\/)+[^\s\\/]+(?:(?:\\+|\/)+[^\s\\/?#]+)+'),
      (match) {
        final path = match.group(0)!;
        final basename = path.split(RegExp(r'\\+|/+')).last;
        return r'[USER_PATH]\' '$basename';
      },
    );
    redacted = redacted.replaceAllMapped(
      RegExp(r'/(?:Users|home)/[^\s/]+(?:/[^\s/]+)+'),
      (match) {
        final path = match.group(0)!;
        final basename = path.split('/').last;
        return '$_userPath/$basename';
      },
    );
    return redacted;
  }

  static bool _isSecretKey(String key) {
    final normalized = key
        .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'),
            (match) => '${match.group(1)}_${match.group(2)}')
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'),
            (match) => '${match.group(1)}_${match.group(2)}')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .toLowerCase();
    final parts =
        normalized.split('_').where((part) => part.isNotEmpty).toSet();
    if (parts.contains('password') || parts.contains('secret')) return true;
    if (parts.contains('token')) return true;
    if (parts.contains('apikey')) return true;
    if (parts.contains('api') && parts.contains('key')) return true;
    return false;
  }

  static int _metadataCharLength(Object? value) {
    if (value is String) {
      return value.length;
    }
    return value?.toString().length ?? 0;
  }

  static String _truncate(String value, int maxChars) =>
      value.length <= maxChars ? value : value.substring(0, maxChars);
}
