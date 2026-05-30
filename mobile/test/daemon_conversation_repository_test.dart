import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/services/notification_service.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';

void main() {
  test('watchConversationEvents delegates to notification service', () async {
    var fetchedEvents = false;
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        fetchedEvents = true;
        return http.Response(
          jsonEncode(const <String, Object?>{'events': <Object?>[]}),
          200,
        );
      }),
    );
    final notificationService = _FakeNotificationService();
    final repository = DaemonConversationRepository(
      client: client,
      notificationService: notificationService,
    );

    final events = <ConversationEvent>[];
    late StreamSubscription<void> subscription;
    subscription = repository
        .watchConversationEvents('conv_1', afterSeq: 5)
        .listen(events.add);
    notificationService.controller.add(ConversationEvent(
      seq: 6,
      conversationId: 'conv_1',
      type: 'assistant.message',
      createdAt: DateTime.parse('2026-05-23T05:18:15.000Z'),
      text: 'new',
    ));

    await waitFor(() => events.length == 1);
    await subscription.cancel();
    client.close();

    expect(fetchedEvents, isFalse);
    expect(notificationService.calls, <String>['conv_1:5']);
    expect(notificationService.cancelled, isTrue);
    expect(events.single.seq, 6);
  });

  test('fetchConversationEventPage delegates to daemon client', () async {
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/conversations/conv_1/events');
        expect(request.url.queryParameters, const <String, String>{
          'beforeSeq': '7',
          'limit': '2',
        });
        return http.Response(
          jsonEncode(const <String, Object?>{
            'events': <Object?>[
              <String, Object?>{
                'seq': 5,
                'conversationId': 'conv_1',
                'type': 'assistant.message',
                'createdAt': '2026-05-30T00:00:00.000Z',
                'text': 'older',
              },
              <String, Object?>{
                'seq': 6,
                'conversationId': 'conv_1',
                'type': 'assistant.message',
                'createdAt': '2026-05-30T00:00:01.000Z',
                'text': 'newer',
              },
            ],
            'page': <String, Object?>{
              'mode': 'before',
              'oldestSeq': 5,
              'newestSeq': 6,
              'hasMoreBefore': false,
            },
          }),
          200,
        );
      }),
    );
    final repository = DaemonConversationRepository(
      client: client,
      notificationService: _FakeNotificationService(),
    );
    addTearDown(client.close);

    final page = await repository.fetchConversationEventPage(
      'conv_1',
      beforeSeq: 7,
      limit: 2,
    );

    expect(page.events.map((event) => event.seq), const <int>[5, 6]);
    expect(page.oldestSeq, 5);
    expect(page.newestSeq, 6);
    expect(page.hasMoreBefore, isFalse);
  });

  test('conversation mutation errors map daemon details to repository errors',
      () async {
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode(const <String, Object?>{
            'error': <String, Object?>{
              'code': 'capability_stale',
              'message': 'Refresh capabilities before retrying.',
            },
          }),
          409,
        );
      }),
    );
    final repository = DaemonConversationRepository(
      client: client,
      notificationService: _FakeNotificationService(),
    );
    addTearDown(client.close);

    final actions = <Future<void> Function()>[
      () => repository
          .answerConversationQuestion('conv_1', 'question_1', 'yes')
          .then((_) {}),
      () => repository
          .respondConversationApproval('conv_1', 'approval_1', 'approve')
          .then((_) {}),
      () => repository.cancelConversation('conv_1').then((_) {}),
    ];

    for (final action in actions) {
      await expectLater(
        action(),
        throwsA(
          isA<ConversationRepositoryException>()
              .having((error) => error.statusCode, 'statusCode', 409)
              .having((error) => error.code, 'code', 'capability_stale')
              .having((error) => error.message, 'message',
                  'Refresh capabilities before retrying.')
              .having(
                (error) => error.cause,
                'cause',
                isA<DaemonClientException>(),
              ),
        ),
      );
    }
  });
}

class _FakeNotificationService implements NotificationService {
  late final StreamController<ConversationEvent> controller =
      StreamController<ConversationEvent>(onCancel: () {
    cancelled = true;
  });
  final List<String> calls = <String>[];
  bool cancelled = false;

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) {
    calls.add('$conversationId:$afterSeq');
    return controller.stream;
  }
}

Future<void> waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not met before timeout.');
}
