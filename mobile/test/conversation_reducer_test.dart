import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/conversation_reducer.dart';

void main() {
  test('ConversationViewState keeps complete final assistant message', () {
    const full =
        'Need details:\n\n1. Web scraper\n2. Data analysis\n3. Automation tool';
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'assistant.partial',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'text': 'Need details:'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'assistant.message',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'text': full,
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_1',
        'type': 'conversation.status_changed',
        'createdAt': '2026-05-03T00:00:02.000Z',
        'status': 'idle'
      }),
    ], streamOutput: false);

    expect(state.status, 'idle');
    expect(state.messages, hasLength(1));
    expect(state.messages.single.role, 'assistant');
    expect(state.messages.single.text, full);
    expect(state.messages.single.text, contains('1. Web scraper'));
  });

  test(
      'ConversationViewState treats normal assistant question as assistant text',
      () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'assistant.message',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'text': 'What should this Python script do? Please clarify.'
      }),
    ]);

    expect(state.status, 'idle');
    expect(state.messages.single.role, 'assistant');
  });

  test(
      'ConversationViewState keeps non-terminal Codex assistant message running',
      () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'conversation.status_changed',
        'createdAt': '2026-05-09T00:00:00.000Z',
        'status': 'running'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'assistant.message',
        'createdAt': '2026-05-09T00:00:01.000Z',
        'text': '我会先按当前会话要求读取一次规则。',
        'turnFinal': false
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_1',
        'type': 'tool.started',
        'createdAt': '2026-05-09T00:00:02.000Z',
        'toolUseId': 'item_1',
        'toolName': 'command_execution',
        'input': {'command': 'pwsh Get-Content'}
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 4,
        'conversationId': 'conv_1',
        'type': 'tool.output',
        'createdAt': '2026-05-09T00:00:03.000Z',
        'toolUseId': 'item_1',
        'text': '--- skill ---'
      }),
    ]);

    expect(state.status, 'running');
    expect(state.messages.map((message) => message.role),
        const <String>['assistant', 'command']);
    expect(state.messages.first.text, contains('读取一次规则'));
    expect(state.messages.last.output, contains('skill'));
  });

  test('ConversationViewState completes command when tool completion arrives',
      () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'conversation.status_changed',
        'createdAt': '2026-05-22T00:00:00.000Z',
        'status': 'running'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'tool.started',
        'createdAt': '2026-05-22T00:00:01.000Z',
        'toolUseId': 'cmd_1',
        'toolName': 'command_execution',
        'input': {'command': 'flutter test'}
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_1',
        'type': 'tool.completed',
        'createdAt': '2026-05-22T00:02:01.000Z',
        'toolUseId': 'cmd_1',
        'toolName': 'command_execution',
        'text': '120 seconds timed out',
        'exitCode': 124,
        'isError': true
      }),
    ]);

    expect(state.status, 'running');
    expect(state.messages.single.role, 'command');
    expect(state.messages.single.completed, isTrue);
    expect(state.messages.single.output, contains('timed out'));
    expect(state.messages.single.exitCode, 124);
    expect(state.messages.single.isError, isTrue);
  });

  test('ConversationViewState completes legacy Codex tool output completion',
      () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'conversation.status_changed',
        'createdAt': '2026-05-22T00:00:00.000Z',
        'status': 'running'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'tool.started',
        'createdAt': '2026-05-22T00:00:01.000Z',
        'toolUseId': 'cmd_1',
        'toolName': 'command_execution',
        'input': {'command': 'flutter test'}
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_1',
        'type': 'tool.output',
        'createdAt': '2026-05-22T00:02:01.000Z',
        'toolUseId': 'cmd_1',
        'toolName': 'command_execution',
        'text': '120 seconds timed out',
        'exitCode': 124,
        'isError': true,
        'raw': {
          'type': 'item.completed',
          'item': {
            'id': 'cmd_1',
            'type': 'command_execution',
            'status': 'failed',
            'exit_code': 124
          }
        }
      }),
    ]);

    expect(state.status, 'running');
    expect(state.messages.single.role, 'command');
    expect(state.messages.single.completed, isTrue);
    expect(state.messages.single.output, contains('timed out'));
    expect(state.messages.single.exitCode, 124);
    expect(state.messages.single.isError, isTrue);
  });

  test('ConversationViewState completes Codex turn on explicit completion', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'conversation.status_changed',
        'createdAt': '2026-05-09T00:00:00.000Z',
        'status': 'running'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'assistant.message',
        'createdAt': '2026-05-09T00:00:01.000Z',
        'text': '我是 Codex。',
        'turnFinal': false
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_1',
        'type': 'conversation.completed',
        'createdAt': '2026-05-09T00:00:02.000Z'
      }),
    ]);

    expect(state.status, 'idle');
    expect(state.messages.single.text, '我是 Codex。');
  });

  test('ConversationViewState exposes run errors after user messages', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'user.message',
        'createdAt': '2026-05-15T07:38:09.585Z',
        'text': '你是谁？',
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'run.error',
        'createdAt': '2026-05-15T07:38:10.835Z',
        'message':
            'Not inside a trusted directory and --skip-git-repo-check was not specified.',
        'exitCode': 1,
      }),
    ]);

    expect(state.status, 'failed');
    expect(
      state.messages.map((message) => message.role),
      const <String>['user', 'notice'],
    );
    expect(state.messages.last.text, contains('trusted directory'));
  });

  test('ConversationViewState preserves committed user attachments', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'user.message',
        'createdAt': '2026-05-21T04:52:19.000Z',
        'text': '这个图片里面有什么？',
        'attachments': [
          {
            'id': 'att_0_7d0b3b49',
            'name': 'screenshot.png',
            'kind': 'image',
            'mimeType': 'image/png',
            'sizeBytes': 1219716,
            'handling': 'native',
          }
        ]
      }),
    ]);

    expect(state.messages.single.role, 'user');
    expect(state.messages.single.attachments, hasLength(1));
    expect(state.messages.single.attachments.single.name, 'screenshot.png');
    expect(state.messages.single.attachments.single.kind, AttachmentKind.image);
  });

  test('ConversationViewState keeps thinking separate from final answer', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'assistant.thinking',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'text': 'The request is vague; ask for clarification.'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'assistant.message',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'text': 'Need details:\n\n- Data analysis\n- Automation'
      }),
    ]);

    expect(state.messages.map((message) => message.role),
        const <String>['thinking', 'assistant']);
    expect(state.messages.first.text, contains('request is vague'));
    expect(state.messages.last.text, contains('- Data analysis'));
  });

  test('ConversationViewState merges consecutive thinking chunks', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'assistant.thinking',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'text': 'The user is asking for an advanced Python script.'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'assistant.thinking',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'text': 'I should clarify the goal before implementing.'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_1',
        'type': 'assistant.thinking',
        'createdAt': '2026-05-03T00:00:02.000Z',
        'text': 'Let me ask one focused question.'
      }),
    ]);

    expect(state.messages, hasLength(1));
    expect(state.messages.single.role, 'thinking');
    expect(state.messages.single.text, contains('advanced Python script'));
    expect(state.messages.single.text, contains('clarify the goal'));
    expect(state.messages.single.text, contains('one focused question'));
  });

  test('ConversationViewState separates questions from approval requests', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'user.message',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'text': 'Write an advanced Python script'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'assistant.question',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'questionId': 'q1',
        'text': 'What should this Python script do?',
        'suggestions': ['Scraper', 'Data analysis']
      }),
    ]);

    expect(state.status, 'waiting_input');
    expect(state.messages.map((message) => message.role),
        const <String>['user', 'question']);
    expect(state.messages.last.suggestions,
        const <String>['Scraper', 'Data analysis']);
  });

  test('ConversationViewState keeps system notices non-blocking', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'system.notice',
        'createdAt': '2026-05-04T00:00:00.000Z',
        'text': 'Claude retry 1/3',
        'summary': 'retry'
      })
    ]);

    expect(state.status, isNot('waiting_input'));
    expect(state.status, isNot('waiting_approval'));
    expect(state.messages.single.role, 'notice');
    expect(state.messages.single.text, 'Claude retry 1/3');
  });

  test('ConversationViewState records but hides non-visible system notices',
      () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'system.notice',
        'createdAt': '2026-05-09T00:00:00.000Z',
        'text': 'Codex thread started',
        'noticeKind': 'codex_thread_started',
        'visible': false
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'system.notice',
        'createdAt': '2026-05-09T00:00:01.000Z',
        'text': 'Codex turn started',
        'noticeKind': 'codex_turn_started',
        'visible': false
      }),
    ]);

    expect(state.lastSeq, 2);
    expect(state.messages, isEmpty);
  });

  test('ConversationViewState hides Codex unknown lifecycle notices', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'system.notice',
        'createdAt': '2026-05-09T00:00:00.000Z',
        'text': 'Codex event: item.completed',
        'noticeKind': 'codex_unknown_event'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'system.notice',
        'createdAt': '2026-05-09T00:00:01.000Z',
        'text': 'Codex event: item.started'
      }),
    ]);

    expect(state.lastSeq, 2);
    expect(state.messages, isEmpty);
  });

  test('ConversationViewState routes reconnect notices to pending status', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'system.notice',
        'createdAt': '2026-05-09T00:00:00.000Z',
        'text': 'Reconnecting... 1/5 (stream disconnected before completion)'
      }),
    ]);

    expect(state.lastSeq, 1);
    expect(state.messages, isEmpty);
  });

  test('ConversationViewState projects task progress updates', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'task.progress.updated',
        'createdAt': '2026-05-10T00:00:00.000Z',
        'taskId': 'item_1',
        'source': 'codex',
        'updatedAt': '2026-05-10T00:00:01.000Z',
        'completedCount': 1,
        'totalCount': 3,
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'task_1',
            'title': 'Inspect scoped files',
            'status': 'completed'
          },
          <String, Object?>{
            'id': 'task_2',
            'title': 'Wire reducer',
            'status': 'in_progress'
          },
          <String, Object?>{
            'id': 'task_3',
            'title': 'Run tests',
            'status': 'pending'
          },
        ],
      }),
    ]);

    expect(state.messages, hasLength(1));
    final message = state.messages.single;
    expect(message.role, 'task_progress');
    expect(message.text, 'Task Progress');
    expect(message.taskId, 'item_1');
    expect(message.completedCount, 1);
    expect(message.totalCount, 3);
    expect(message.taskItems.map((item) => item.status),
        const <String>['completed', 'in_progress', 'pending']);
  });

  test('ConversationViewState upserts repeated task progress updates', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'task.progress.updated',
        'createdAt': '2026-05-10T00:00:00.000Z',
        'taskId': 'item_1',
        'completedCount': 0,
        'totalCount': 1,
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'task_1',
            'title': 'Inspect scoped files',
            'status': 'pending'
          },
        ],
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'task.progress.updated',
        'createdAt': '2026-05-10T00:00:01.000Z',
        'taskId': 'item_1',
        'completedCount': 1,
        'totalCount': 1,
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'task_1',
            'title': 'Inspect scoped files',
            'status': 'completed'
          },
        ],
      }),
    ]);

    expect(state.messages, hasLength(1));
    expect(state.messages.single.eventSeq, 2);
    expect(state.messages.single.completedCount, 1);
    expect(state.messages.single.taskItems.single.status, 'completed');
  });

  test('ConversationViewState correlates tool output by toolUseId', () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'tool.started',
        'createdAt': '2026-05-04T00:00:00.000Z',
        'toolUseId': 'toolu_a',
        'toolName': 'Bash',
        'input': {'command': 'npm test'}
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'tool.delta',
        'createdAt': '2026-05-04T00:00:01.000Z',
        'toolUseId': 'toolu_a',
        'text': 'running tests'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_1',
        'type': 'tool.output',
        'createdAt': '2026-05-04T00:00:02.000Z',
        'toolUseId': 'toolu_a',
        'text': '1 failing test',
        'exitCode': 1,
        'isError': true
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 4,
        'conversationId': 'conv_1',
        'type': 'tool.completed',
        'createdAt': '2026-05-04T00:00:03.000Z',
        'toolUseId': 'toolu_a',
        'exitCode': 1,
        'isError': true
      })
    ]);

    expect(state.messages.single.role, 'command');
    expect(state.messages.single.text, 'npm test');
    expect(state.messages.single.output, contains('running tests'));
    expect(state.messages.single.output, contains('1 failing test'));
    expect(state.messages.single.completed, true);
    expect(state.messages.single.exitCode, 1);
    expect(state.messages.single.isError, true);
  });

  test(
      'ConversationViewState keeps interleaved tool outputs separate and ignores missing ids',
      () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'tool.started',
        'createdAt': '2026-05-04T00:00:00.000Z',
        'toolUseId': 'toolu_a',
        'toolName': 'Bash',
        'input': {'command': 'npm test'}
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'tool.started',
        'createdAt': '2026-05-04T00:00:01.000Z',
        'toolUseId': 'toolu_b',
        'toolName': 'Read',
        'input': {'file_path': 'README.md'}
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_1',
        'type': 'tool.output',
        'createdAt': '2026-05-04T00:00:02.000Z',
        'toolUseId': 'toolu_b',
        'text': 'readme body'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 4,
        'conversationId': 'conv_1',
        'type': 'tool.output',
        'createdAt': '2026-05-04T00:00:03.000Z',
        'toolUseId': 'toolu_a',
        'text': 'tests passed'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 5,
        'conversationId': 'conv_1',
        'type': 'tool.output',
        'createdAt': '2026-05-04T00:00:04.000Z',
        'text': 'must not attach'
      })
    ]);

    final npm =
        state.messages.firstWhere((message) => message.text == 'npm test');
    final read = state.messages
        .firstWhere((message) => message.text.contains('README.md'));
    expect(npm.output, contains('tests passed'));
    expect(npm.output, isNot(contains('readme body')));
    expect(npm.output, isNot(contains('must not attach')));
    expect(read.output, contains('readme body'));
  });

  test('ConversationViewState preserves full AskUserQuestion display text', () {
    const questionText = '请帮我明确需求：\n\n你有什么类型的推荐吗？\n\n'
        '- 数据处理/分析 — 批量文件处理、数据清洗、爬虫\n'
        '- 自动化工具 — 系统监控、定时任务、日志分析\n'
        '- 开发工具 — 代码生成器、项目脚手架、依赖分析';
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'assistant.thinking',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'text': 'The request is vague; ask for clarification before coding.'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'assistant.question',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'questionId': 'q1',
        'text': questionText,
        'suggestions': ['数据处理/分析', '自动化工具', '开发工具']
      }),
    ]);

    expect(state.status, 'waiting_input');
    expect(state.messages.map((message) => message.role),
        const <String>['thinking', 'question']);
    expect(state.messages.last.text, questionText);
    expect(state.messages.last.text, contains('请帮我明确需求'));
    expect(state.messages.last.text, contains('开发工具'));
    expect(state.messages.last.suggestions,
        const <String>['数据处理/分析', '自动化工具', '开发工具']);
  });

  test('ConversationViewState keeps partial context when a question follows',
      () {
    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'assistant.partial',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'text':
            'Your request is broad. Please clarify:\n\n1. Web scraper\n2. Data analysis\n3. Automation'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'assistant.question',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'questionId': 'q1',
        'text': 'Need more information.'
      }),
    ], streamOutput: false);

    expect(state.status, 'waiting_input');
    expect(state.messages.map((message) => message.role),
        const <String>['assistant', 'question_hidden']);
    expect(state.messages.first.text, contains('1. Web scraper'));
    expect(state.messages.last.questionId, 'q1');
  });

  test(
      'ConversationViewState keeps complete Claude text before fallback question',
      () {
    const thinking =
        'The user is asking me to write an advanced Python script. The request is vague.';
    const firstText = '"高级脚本"范围很广，能具体说说你想实现什么功能吗？比如：\n\n'
        '- **数据处理/分析** — 批量文件处理、数据清洗、爬虫\n';
    const completeText = '"高级脚本"范围很广，能具体说说你想实现什么功能吗？比如：\n\n'
        '- **数据处理/分析** — 批量文件处理、数据清洗、爬虫\n'
        '- **自动化工具** — 系统监控、定时任务、日志分析\n'
        '- **网络/安全** — 端口扫描、API 测试、证书检查\n'
        '- **AI/ML** — 模型推理、文本处理、图像处理\n'
        '- **开发工具** — 代码生成器、项目脚手架、依赖分析\n\n'
        '你有什么具体场景或需求？';

    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'assistant.thinking',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'text': thinking
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'assistant.partial',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'text': firstText
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_1',
        'type': 'assistant.partial',
        'createdAt': '2026-05-03T00:00:02.000Z',
        'text': completeText
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 4,
        'conversationId': 'conv_1',
        'type': 'assistant.question',
        'createdAt': '2026-05-03T00:00:03.000Z',
        'questionId': 'q1',
        'text': 'Need more information.'
      }),
    ], streamOutput: false);

    expect(state.status, 'waiting_input');
    expect(state.messages.map((message) => message.role),
        const <String>['thinking', 'assistant', 'question_hidden']);
    expect(state.messages[1].text, completeText);
    expect(state.messages[1].text, contains('- **开发工具**'));
    expect(state.messages.last.questionId, 'q1');
  });

  test('ConversationViewState replaces partial text with complete result', () {
    const partial = '"高级脚本"范围很广，能具体说说你想实现什么功能吗？';
    const result = '"高级脚本"范围很广，能具体说说你想实现什么功能吗？比如：\n\n'
        '- **数据处理/分析** — 批量文件处理、数据清洗、爬虫\n'
        '- **开发工具** — 代码生成器、项目脚手架、依赖分析\n\n'
        '你有什么具体场景或需求？';

    final state = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'assistant.partial',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'text': partial
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'assistant.message',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'text': result
      }),
    ]);

    expect(state.status, 'idle');
    expect(state.messages, hasLength(1));
    expect(state.messages.single.role, 'assistant');
    expect(state.messages.single.text, result);
  });

  test(
      'ConversationViewState collapses duplicate approvals and removes resolved',
      () {
    final pending = const ConversationViewState().apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'ap1',
        'toolName': 'Bash',
        'summary': 'dir scripts'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'ap1',
        'toolName': 'Bash',
        'summary': 'dir scripts'
      }),
    ]);
    final resolved = pending.apply(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_1',
        'type': 'approval.resolved',
        'createdAt': '2026-05-03T00:00:02.000Z',
        'approvalId': 'ap1',
        'decision': 'allow'
      }),
    ]);

    expect(pending.messages.where((message) => message.role == 'approval'),
        hasLength(1));
    expect(resolved.messages.where((message) => message.role == 'approval'),
        isEmpty);
  });
}
