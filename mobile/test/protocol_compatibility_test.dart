import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/approval_models.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/run_detail/run_detail_state.dart';

void main() {
  test('Conversation models parse daemon conversation payloads', () {
    final summary = ConversationSummary.fromJson(const <String, Object?>{
      'id': 'conv_1',
      'workspaceId': 'default',
      'adapter': 'claude',
      'model': 'gpt-5.5',
      'status': 'waiting_input',
      'cliSessionId': 'session_1',
      'sessionBinding': 'confirmed',
      'userMessageCount': 2,
      'protocolVersion': 2,
      'requestedPermissionMode': 'auto',
      'effectivePermissionMode': 'default',
      'permissionSupport': {
        'permissionModes': ['default', 'plan']
      },
      'capabilities': {'waitingInput': true, 'waitingApproval': true},
      'blockingItem': {
        'type': 'input_request',
        'questionId': 'q1',
        'text': 'Pick one',
        'suggestions': ['A', 'B'],
        'multiSelect': true,
        'createdAt': '2026-05-04T00:00:00.000Z',
        'expiresAt': '2026-05-04T00:01:00.000Z',
        'input': {'multiSelect': true}
      }
    });

    expect(summary.id, 'conv_1');
    expect(summary.model, 'gpt-5.5');
    expect(summary.status, 'waiting_input');
    expect(summary.sessionBinding, 'confirmed');
    expect(summary.userMessageCount, 2);
    expect(summary.protocolVersion, 2);
    expect(summary.requestedPermissionMode, 'auto');
    expect(summary.effectivePermissionMode, 'default');
    expect(summary.permissionSupport['permissionModes'], isA<List<Object?>>());
    expect(summary.blockingItem?.type, 'input_request');
    expect(summary.blockingItem?.suggestions, const <String>['A', 'B']);
    expect(summary.blockingItem?.multiSelect, true);
    expect(summary.blockingItem?.expiresAt, '2026-05-04T00:01:00.000Z');
    expect(summary.capabilities.waitingInput, true);
  });

  test('ConversationSummary defaults legacy lifecycle fields safely', () {
    final summary = ConversationSummary.fromJson(const <String, Object?>{
      'id': 'conv_legacy',
      'workspaceId': 'default',
      'adapter': 'claude',
      'status': 'interrupted',
      'capabilities': <String, Object?>{},
      'createdAt': '2026-05-08T00:00:00.000Z',
      'updatedAt': '2026-05-08T00:00:01.000Z',
    });

    expect(summary.sessionBinding, 'unknown');
    expect(summary.model, isNull);
    expect(summary.userMessageCount, 0);
  });

  test('ConversationEvent parses normalized assistant and approval events', () {
    final question = ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'type': 'assistant.question',
      'createdAt': '2026-05-03T00:00:00.000Z',
      'questionId': 'q1',
      'text': 'Pick one',
      'suggestions': ['A']
    });
    final approval = ConversationEvent.fromJson(const <String, Object?>{
      'seq': 2,
      'conversationId': 'conv_1',
      'type': 'approval.requested',
      'createdAt': '2026-05-03T00:00:01.000Z',
      'approvalId': 'ap1',
      'toolName': 'Bash',
      'summary': 'dir scripts',
      'input': {'command': 'dir scripts'}
    });

    expect(question.questionId, 'q1');
    expect(question.suggestions, const <String>['A']);
    expect(approval.approvalId, 'ap1');
    expect(approval.summary, 'dir scripts');
  });

  test('ConversationEvent parses sanitized approval request options', () {
    final event = ConversationEvent.fromJson(const <String, Object?>{
      'seq': 2,
      'conversationId': 'conv_1',
      'type': 'approval.requested',
      'createdAt': '2026-05-03T00:00:01.000Z',
      'approvalId': 'ap1',
      'toolName': 'Bash',
      'summary': 'npm test',
      'input': {'command': 'npm test'},
      'approvalOptions': {
        'kind': 'command',
        'supportsSessionScope': true,
        'supportsCancel': false,
        'denyBehavior': 'interrupt',
        'command': 'npm test',
        'extraProviderField': {'env': 'ignored by typed parser'},
      },
    });

    expect(event.approvalOptions.kind, ApprovalRequestKind.command);
    expect(event.approvalOptions.supportsSessionScope, isTrue);
    expect(event.approvalOptions.supportsCancel, isFalse);
    expect(event.approvalOptions.denyBehavior, ApprovalDenyBehavior.interrupt);
    expect(event.approvalOptions.command, 'npm test');
  });

  test('ConversationEvent parses tool correlation fields', () {
    final output = ConversationEvent.fromJson(const <String, Object?>{
      'seq': 3,
      'conversationId': 'conv_1',
      'type': 'tool.output',
      'createdAt': '2026-05-04T00:00:02.000Z',
      'toolUseId': 'toolu_a',
      'toolName': 'Bash',
      'text': '1 failing test',
      'exitCode': 1,
      'isError': true,
      'durationMs': 250
    });

    expect(output.toolUseId, 'toolu_a');
    expect(output.toolName, 'Bash');
    expect(output.exitCode, 1);
    expect(output.isError, true);
    expect(output.durationMs, 250);
  });

  test('ConversationEvent parses committed attachment metadata', () {
    final event = ConversationEvent.fromJson(const <String, Object?>{
      'seq': 4,
      'conversationId': 'conv_1',
      'type': 'user.message',
      'createdAt': '2026-05-20T00:00:00.000Z',
      'attachments': [
        {
          'id': 'att_0_abc123',
          'name': 'screenshot.png',
          'kind': 'image',
          'mimeType': 'image/png',
          'sizeBytes': 120034,
          'handling': 'native',
        },
      ],
    });

    final attachment = event.attachments.single;
    expect(attachment.id, 'att_0_abc123');
    expect(attachment.name, 'screenshot.png');
    expect(attachment.kind, AttachmentKind.image);
    expect(attachment.mimeType, 'image/png');
    expect(attachment.sizeBytes, 120034);
    expect(attachment.handling, AttachmentHandling.native);
    expect(attachment.localPath, isNull);
  });

  test('Conversation models accept loose map payload shapes', () {
    final summary = ConversationSummary.fromJson(<String, Object?>{
      'id': 'conv_loose',
      'workspaceId': 'workspace_1',
      'adapter': 'claude',
      'status': 'waiting_input',
      'capabilities': <dynamic, dynamic>{'waitingInput': true},
      'blockingItem': <dynamic, dynamic>{
        'type': 'input_request',
        'questionId': 'q1',
        'input': <dynamic, dynamic>{'multiSelect': true},
      },
    });
    final event = ConversationEvent.fromJson(<String, Object?>{
      'seq': 5,
      'conversationId': 'conv_loose',
      'type': 'task.progress',
      'createdAt': '2026-05-20T00:00:00.000Z',
      'items': <Object?>[
        <dynamic, dynamic>{
          'id': 'task_1',
          'title': 'Review data models',
          'status': 'completed',
        },
      ],
      'attachments': <Object?>[
        <dynamic, dynamic>{
          'id': 'att_1',
          'name': 'notes.txt',
          'kind': 'textDocument',
          'mimeType': 'text/plain',
          'sizeBytes': 42,
          'handling': 'text_extract',
        },
      ],
    });

    expect(summary.capabilities.waitingInput, isTrue);
    expect(summary.blockingItem?.questionId, 'q1');
    expect(summary.blockingItem?.input['multiSelect'], isTrue);
    expect(event.taskItems.single.title, 'Review data models');
    expect(event.attachments.single.kind, AttachmentKind.textDocument);
  });

  test('Attachment protocol parsers handle staged paths and fallbacks', () {
    expect(parseAttachmentKind('pdf'), AttachmentKind.pdf);
    expect(parseAttachmentKind('unknown'), AttachmentKind.unsupported);
    expect(
      parseAttachmentHandling('staged_path'),
      AttachmentHandling.stagedPath,
    );
    expect(
      parseAttachmentHandling(
        'unknown',
        fallback: AttachmentHandling.textExtract,
      ),
      AttachmentHandling.textExtract,
    );

    final defaults = AttachmentCapabilities.fromJson(
      const <String, Object?>{},
    );
    expect(defaults.image, AttachmentHandling.unsupported);
    expect(defaults.textDocument, AttachmentHandling.textExtract);
    expect(defaults.pdf, AttachmentHandling.unsupported);
  });

  test('ExtensionSummary accepts nullable daemon adapter fields', () {
    final extension = ExtensionSummary.fromJson(const <String, Object?>{
      'id': 'claude',
      'name': 'Claude',
      'version': null,
      'installed': true,
      'status': null,
      'description': null,
    });

    expect(extension.id, 'claude');
    expect(extension.name, 'Claude');
    expect(extension.version, '');
    expect(extension.installed, isTrue);
    expect(extension.status, 'unknown');
    expect(extension.description, '');
  });

  test('AdapterStatus accepts nullable status for available adapters', () {
    final adapter = AdapterStatus.fromJson(const <String, Object?>{
      'adapter': 'claude',
      'available': true,
      'status': null,
      'version': '2.1.119',
      'error': null,
      'actionable': null,
    });

    expect(adapter.adapter, 'claude');
    expect(adapter.available, isTrue);
    expect(adapter.status, 'available');
    expect(adapter.statusText, 'available');
  });

  test('AdapterStatus parses attachment capabilities and capabilityVersion',
      () {
    final status = AdapterStatus.fromJson(const <String, Object?>{
      'adapter': 'codex',
      'available': true,
      'status': 'available',
      'capabilityVersion': '4bcf6aa44f7e2e074229f9cd',
      'capabilities': {
        'attachments': {
          'image': 'native',
          'textDocument': 'text_extract',
          'pdf': 'unsupported',
        },
      },
      'models': [
        {
          'id': 'gpt-5.3-codex',
          'inputModalities': ['image', 'text'],
          'attachments': {
            'image': 'native',
            'textDocument': 'text_extract',
            'pdf': 'unsupported',
          },
        },
      ],
    });

    expect(status.capabilityVersion, '4bcf6aa44f7e2e074229f9cd');
    expect(status.attachmentCapabilities.image, AttachmentHandling.native);
    expect(
      status.models.single.inputModalities,
      const <String>['image', 'text'],
    );
    expect(
      status.models.single.attachmentCapabilities.image,
      AttachmentHandling.native,
    );
  });

  test('Daemon extension list accepts async adapter capability projection', () {
    final payload = <String, Object?>{
      'extensions': [
        {
          'id': 'opencode',
          'name': 'OpenCode',
          'version': null,
          'installed': false,
          'status': 'needs_configuration',
          'description': null,
          'profile': null,
        },
        {
          'id': 'synthetic-jsonl',
          'name': 'Synthetic Jsonl',
          'version': 'synthetic',
          'installed': true,
          'status': 'available',
          'description': 'Synthetic Jsonl integration',
        },
      ],
    };

    final extensions = (payload['extensions'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(ExtensionSummary.fromJson)
        .toList();

    expect(extensions, hasLength(2));
    expect(extensions.first.description, '');
    expect(extensions.first.version, '');
  });

  test('AgentEvent parses coding workbench run and approval events', () {
    final events = [
      AgentEvent.fromJson(const <String, Object?>{
        'type': 'run.started',
        'seq': 1,
        'runId': 'run_1',
        'createdAt': '2026-05-01T13:00:00.000Z',
      }),
      AgentEvent.fromJson(const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 2,
        'runId': 'run_1',
        'createdAt': '2026-05-01T13:00:01.000Z',
        'text': '我会先检查项目结构',
      }),
      AgentEvent.fromJson(const <String, Object?>{
        'type': 'tool.output',
        'seq': 3,
        'runId': 'run_1',
        'createdAt': '2026-05-01T13:00:02.000Z',
        'name': 'shell',
        'text': 'flutter analyze',
      }),
      AgentEvent.fromJson(const <String, Object?>{
        'type': 'approval.required',
        'seq': 4,
        'runId': 'run_1',
        'createdAt': '2026-05-01T13:00:03.000Z',
        'approvalId': 'approval_1',
        'text': '允许写入 lib/main.dart?',
      }),
      AgentEvent.fromJson(const <String, Object?>{
        'type': 'run.completed',
        'seq': 5,
        'runId': 'run_1',
        'createdAt': '2026-05-01T13:00:04.000Z',
      }),
    ];

    expect(events.map((event) => event.type), contains('assistant.delta'));
    expect(events[3].approvalId, 'approval_1');
    expect(events.last.type, 'run.completed');
  });

  test('AgentEvent preserves raw Claude stream payload for UI filtering', () {
    final event = AgentEvent.fromJson(const <String, Object?>{
      'type': 'raw.output',
      'seq': 71,
      'runId': 'run_1',
      'createdAt': '2026-05-01T13:00:04.000Z',
      'text':
          '{"type":"assistant","message":{"content":[{"type":"text","text":"你好，我是 Claude"}]}}',
    });

    expect(event.type, 'raw.output');
    expect(event.text, contains('message'));
  });

  test('AgentEvent preserves final Claude result payload for non-stream UI',
      () {
    final event = AgentEvent.fromJson(const <String, Object?>{
      'type': 'assistant.delta',
      'seq': 72,
      'runId': 'run_1',
      'createdAt': '2026-05-01T13:00:05.000Z',
      'text': '',
      'raw': {
        'type': 'result',
        'result': '你好，我是 Claude。',
      },
    });

    expect(event.type, 'assistant.delta');
    expect(event.raw['raw'], isA<Map<String, Object?>>());
  });

  test('RunDetailState stays terminal when late raw events arrive after result',
      () {
    final completed = AgentEvent.fromJson(const <String, Object?>{
      'type': 'run.completed',
      'seq': 3,
      'runId': 'run_1',
      'createdAt': '2026-05-01T13:00:06.000Z',
      'raw': {
        'type': 'result',
        'result': '完成',
      },
    });
    final lateNoise = AgentEvent.fromJson(const <String, Object?>{
      'type': 'raw.output',
      'seq': 4,
      'runId': 'run_1',
      'createdAt': '2026-05-01T13:00:07.000Z',
      'text': '',
      'raw': {
        'type': 'system',
        'subtype': 'status',
        'status': 'requesting',
      },
    });

    final state =
        const RunDetailState(connectionState: RunConnectionState.connected)
            .mergeEvents(<AgentEvent>[completed, lateNoise]);

    expect(isTerminalAgentEventType(completed.type), isTrue);
    expect(isTerminalAgentEventType(lateNoise.type), isFalse);
    expect(state.lastSeq, 4);
    expect(state.connectionState, RunConnectionState.disconnected);
  });

  test('RunDetailState clears approvals after approval.responded', () {
    final required = AgentEvent.fromJson(const <String, Object?>{
      'type': 'approval.required',
      'seq': 1,
      'runId': 'run_approval',
      'createdAt': '2026-05-03T00:00:00.000Z',
      'approvalId': 'approval_1',
      'toolName': 'Write',
    });
    final responded = AgentEvent.fromJson(const <String, Object?>{
      'type': 'approval.responded',
      'seq': 2,
      'runId': 'run_approval',
      'createdAt': '2026-05-03T00:00:01.000Z',
      'approvalId': 'approval_1',
      'decision': 'allow',
    });

    final state =
        const RunDetailState().mergeEvents(<AgentEvent>[required, responded]);

    expect(state.pendingApprovalCount, 0);
  });

  test('FileContent parses daemon payload used by code preview', () {
    final content = FileContent.fromJson(const <String, Object?>{
      'workspaceId': 'workspace_1',
      'path': 'lib/main.dart',
      'binary': false,
      'tooLarge': false,
      'size': 21,
      'content': 'void main() {}',
      'language': 'dart',
    });

    expect(content.path, 'lib/main.dart');
    expect(content.binary, isFalse);
    expect(content.content, contains('main'));
  });

  test('legacy optional daemon payload fields use safe defaults', () {
    final shortcut = ShortcutCommand.fromJson(const <String, Object?>{
      'id': 'review',
      'label': 'Review',
      'prompt': 'Review recent changes.',
    });
    final git = GitStatusSummary.fromJson(const <String, Object?>{
      'workspaceId': 'workspace_1',
      'clean': true,
    });
    final diagnostics = CodeDiagnosticsSummary.fromJson(const <String, Object?>{
      'workspaceId': 'workspace_1',
      'available': false,
    });
    final bundle = DiagnosticBundleSummary.fromJson(const <String, Object?>{
      'bundleId': 'bundle_1',
      'createdAt': '2026-05-27T00:00:00.000Z',
      'path': r'D:\tmp\bundle.zip',
      'redacted': true,
    });
    final smoke = SmokeTestResult.fromJson(const <String, Object?>{
      'ok': true,
      'adapter': 'synthetic-jsonl',
    });

    expect(shortcut.tool, 'claude');
    expect(git.files, isEmpty);
    expect(diagnostics.diagnostics, isEmpty);
    expect(bundle.items, isEmpty);
    expect(smoke.events, 0);
  });

  test('filters Claude SDK hook protocol JSON from visible messages', () {
    final event = AgentEvent.fromJson(const <String, Object?>{
      'type': 'raw.output',
      'seq': 7,
      'runId': 'run_1',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'text': '{"continue":true,"suppressOutput":true}'
    });

    expect(event.text, contains('suppressOutput'));
  });
}
