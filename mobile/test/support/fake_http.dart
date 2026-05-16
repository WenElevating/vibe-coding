import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

typedef FakeHttpHandler = FutureOr<http.StreamedResponse> Function(
    http.BaseRequest request);

class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this._handler);

  final FakeHttpHandler _handler;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) {
      throw http.ClientException(
        'Cannot send request after close.',
        request.url,
      );
    }
    requests.add(request);
    return _handler(request);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

http.StreamedResponse jsonResponse(
  Object body, {
  int statusCode = 200,
  Map<String, String>? headers,
}) {
  return textResponse(
    jsonEncode(body),
    statusCode: statusCode,
    headers: <String, String>{'content-type': 'application/json', ...?headers},
  );
}

http.StreamedResponse textResponse(
  String body, {
  int statusCode = 200,
  Map<String, String>? headers,
}) {
  final bytes = utf8.encode(body);
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    statusCode,
    contentLength: bytes.length,
    headers: <String, String>{
      'content-type': 'text/plain; charset=utf-8',
      ...?headers,
    },
  );
}
