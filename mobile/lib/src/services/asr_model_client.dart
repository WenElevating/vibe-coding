import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AsrModelMetadata {
  const AsrModelMetadata({
    required this.version,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.downloadPath,
  });

  final String version;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final String downloadPath;

  factory AsrModelMetadata.fromJson(Map<String, Object?> json) =>
      AsrModelMetadata(
        version: json['version'] as String,
        fileName: json['fileName'] as String,
        sizeBytes: json['sizeBytes'] as int,
        sha256: json['sha256'] as String,
        downloadPath: json['downloadPath'] as String,
      );
}

class AsrModelDownloadResponse {
  const AsrModelDownloadResponse({
    required this.statusCode,
    required this.headers,
    required this.stream,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> stream;
}

class AsrModelClient {
  AsrModelClient({
    required this.baseUri,
    required this.tokenProvider,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final Uri baseUri;
  final FutureOr<String?> Function() tokenProvider;
  final http.Client _httpClient;

  Future<AsrModelMetadata> metadata() async {
    final response = await _httpClient.get(baseUri.resolve('/api/asr-model'),
        headers: await _headers());
    final decoded = _decode(response.statusCode, response.body);
    return AsrModelMetadata.fromJson(decoded);
  }

  Future<AsrModelDownloadResponse> download({int? start}) async {
    final request =
        http.Request('GET', baseUri.resolve('/api/asr-model/download'));
    request.headers.addAll(await _headers());
    if (start != null && start > 0) {
      request.headers['range'] = 'bytes=$start-';
    }
    final response = await _httpClient.send(request);
    if (response.statusCode >= 400 && response.statusCode != 416) {
      final body = await response.stream.bytesToString();
      _decode(response.statusCode, body);
    }
    return AsrModelDownloadResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        stream: response.stream);
  }

  Future<Map<String, String>> _headers() async {
    final token = await tokenProvider();
    return <String, String>{
      'content-type': 'application/json; charset=utf-8',
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  Map<String, Object?> _decode(int statusCode, String body) {
    if (body.trim().isEmpty) {
      throw AsrModelClientException(statusCode, const <String, Object?>{
        'error': 'invalid_response',
        'message': 'daemon returned an empty ASR model response body',
      });
    }
    late final Object? rawDecoded;
    try {
      rawDecoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw AsrModelClientException(statusCode, <String, Object?>{
        'error': 'invalid_response',
        'message':
            'daemon returned an invalid ASR model response: ${error.message}',
      });
    }
    if (rawDecoded is! Map<String, Object?>) {
      throw AsrModelClientException(statusCode, const <String, Object?>{
        'error': 'invalid_response',
        'message': 'daemon returned a non-object ASR model response',
      });
    }
    final decoded = rawDecoded;
    if (statusCode >= 400) throw AsrModelClientException(statusCode, decoded);
    return decoded;
  }
}

class AsrModelClientException implements Exception {
  const AsrModelClientException(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;

  String get message {
    final error = body['error'];
    if (error is Map<String, Object?>) {
      final message = error['message'];
      if (message is String) return message;
    }
    final message = body['message'];
    return message is String ? message : 'ASR model request failed';
  }

  String? get traceId {
    final error = body['error'];
    if (error is Map<String, Object?>) {
      final traceId = error['traceId'];
      if (traceId is String && traceId.isNotEmpty) return traceId;
    }
    return null;
  }

  @override
  String toString() => 'AsrModelClientException($statusCode, $body)';
}
