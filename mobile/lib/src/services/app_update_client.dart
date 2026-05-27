import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models/app_update_manifest.dart';

typedef AuthorizedRawGet = Future<http.Response> Function(
  String path, {
  required Map<String, String> headers,
});

typedef AuthorizedStreamSend = Future<http.StreamedResponse> Function(
  http.BaseRequest Function(Uri baseUri, Map<String, String> headers) build,
);

class AppUpdateLatestResult {
  const AppUpdateLatestResult({
    required this.notModified,
    this.etag,
    this.manifest,
  });

  final bool notModified;
  final String? etag;
  final AppUpdateManifest? manifest;
}

class AppUpdateClient {
  AppUpdateClient({
    required this.baseUri,
    required http.Client httpClient,
    required String? Function() tokenProvider,
  })  : _httpClient = httpClient,
        _tokenProvider = tokenProvider,
        _authorizedGet = null,
        _authorizedStreamSend = null;

  AppUpdateClient.authorized({
    required this.baseUri,
    required AuthorizedRawGet authorizedGet,
    required AuthorizedStreamSend authorizedStreamSend,
  })  : _authorizedGet = authorizedGet,
        _authorizedStreamSend = authorizedStreamSend,
        _httpClient = null,
        _tokenProvider = null;

  final Uri baseUri;
  final http.Client? _httpClient;
  final String? Function()? _tokenProvider;
  final AuthorizedRawGet? _authorizedGet;
  final AuthorizedStreamSend? _authorizedStreamSend;

  Future<AppUpdateLatestResult> fetchLatest({String? ifNoneMatch}) async {
    final headers = <String, String>{
      if (ifNoneMatch != null) 'if-none-match': ifNoneMatch,
    };
    final response = await _get(
      '/api/app-updates/android/latest',
      headers: headers,
    );
    if (response.statusCode == 304) {
      return AppUpdateLatestResult(
        notModified: true,
        etag: response.headers['etag'],
      );
    }
    if (response.statusCode >= 400) {
      throw AppUpdateClientException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body);
    return AppUpdateLatestResult(
      notModified: false,
      etag: response.headers['etag'],
      manifest: AppUpdateManifest.fromJson(
        Map<String, Object?>.from(decoded as Map),
      ),
    );
  }

  Future<http.StreamedResponse> openApkStream(
    Uri apkUri, {
    int? rangeStart,
    String? ifRange,
  }) {
    final sameOriginApkUri = _sameOriginApkUri(apkUri);
    final authorizedStreamSend = _authorizedStreamSend;
    if (authorizedStreamSend != null) {
      return authorizedStreamSend((_, headers) {
        return _apkRequest(
          sameOriginApkUri,
          headers: headers,
          rangeStart: rangeStart,
          ifRange: ifRange,
        );
      });
    }

    final httpClient = _httpClient;
    if (httpClient == null) {
      throw StateError('AppUpdateClient has no HTTP transport.');
    }
    return httpClient.send(
      _apkRequest(
        sameOriginApkUri,
        headers: _headers(),
        rangeStart: rangeStart,
        ifRange: ifRange,
      ),
    );
  }

  Future<http.Response> _get(
    String path, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final authorizedGet = _authorizedGet;
    if (authorizedGet != null) {
      return authorizedGet(path, headers: headers);
    }

    final httpClient = _httpClient;
    if (httpClient == null) {
      throw StateError('AppUpdateClient has no HTTP transport.');
    }
    return httpClient.get(
      baseUri.resolve(path),
      headers: <String, String>{..._headers(), ...headers},
    );
  }

  http.Request _apkRequest(
    Uri apkUri, {
    required Map<String, String> headers,
    int? rangeStart,
    String? ifRange,
  }) {
    final request = http.Request('GET', apkUri)..headers.addAll(headers);
    if (rangeStart != null && rangeStart > 0) {
      request.headers['range'] = 'bytes=$rangeStart-';
      if (ifRange != null) request.headers['if-range'] = ifRange;
    }
    return request;
  }

  Uri _sameOriginApkUri(Uri apkUri) {
    final resolved = baseUri.resolveUri(apkUri);
    if (resolved.scheme != baseUri.scheme ||
        resolved.authority != baseUri.authority) {
      throw ArgumentError.value(
        apkUri,
        'apkUri',
        'APK downloads must use the paired daemon origin.',
      );
    }
    return resolved;
  }

  Map<String, String> _headers() {
    final token = _tokenProvider?.call();
    return <String, String>{
      if (token != null) 'authorization': 'Bearer $token',
    };
  }
}

class AppUpdateClientException implements Exception {
  const AppUpdateClientException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'AppUpdateClientException($statusCode): $body';
}
