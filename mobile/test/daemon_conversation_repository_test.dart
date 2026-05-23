import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';

void main() {
  test('fallback watch advances cursor and does not re-emit old events',
      () async {
    final requestedAfterSeq = <String?>[];
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        requestedAfterSeq.add(request.url.queryParameters['afterSeq']);
        return http.Response(
          jsonEncode(const <String, Object?>{
            'events': <Object?>[
              <String, Object?>{
                'seq': 4,
                'conversationId': 'conv_1',
                'type': 'assistant.message',
                'createdAt': '2026-05-23T05:18:14.000Z',
                'text': 'old',
              },
              <String, Object?>{
                'seq': 6,
                'conversationId': 'conv_1',
                'type': 'assistant.message',
                'createdAt': '2026-05-23T05:18:15.000Z',
                'text': 'new',
              },
              <String, Object?>{
                'seq': 5,
                'conversationId': 'conv_1',
                'type': 'assistant.message',
                'createdAt': '2026-05-23T05:18:16.000Z',
                'text': 'also old',
              },
            ],
          }),
          200,
        );
      }),
    );
    final repository = DaemonConversationRepository(
      client: client,
      fallbackPollInterval: Duration.zero,
    );

    final events = <int>[];
    late StreamSubscription<void> subscription;
    subscription = repository
        .watchConversationEvents('conv_1', afterSeq: 5)
        .map((event) => event.seq)
        .listen(events.add);

    await waitFor(() => requestedAfterSeq.length >= 2);
    await subscription.cancel();
    client.close();

    expect(events, <int>[6]);
    expect(requestedAfterSeq.take(2), <String?>['5', '6']);
  });
}

Future<void> waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not met before timeout.');
}
