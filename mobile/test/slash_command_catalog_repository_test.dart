import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/adapter_models.dart';
import 'package:lan_ai_cli_control/src/data/repositories/slash_command_catalog_repository.dart';

void main() {
  test('loads each adapter once and returns cached commands', () async {
    final delegate = _FakeSlashCommandClient()
      ..responses['codex'] = const <SlashCommand>[
        SlashCommand(command: '/model', description: 'choose model'),
      ];
    final repository = SlashCommandCatalogRepository(client: delegate.load);

    final first = await repository.loadForAdapter('codex');
    final second = await repository.loadForAdapter('codex');

    expect(first.single.command, '/model');
    expect(second.single.command, '/model');
    expect(delegate.calls, const <String>['codex']);
    expect(repository.commandsForAdapter('codex').single.matchingKey, 'model');
  });

  test('caches commands separately for each workspace', () async {
    final delegate = _FakeSlashCommandClient()
      ..responses['codex|workspace-a'] = const <SlashCommand>[
        SlashCommand(command: '/alpha', description: 'workspace a'),
      ]
      ..responses['codex|workspace-b'] = const <SlashCommand>[
        SlashCommand(command: '/beta', description: 'workspace b'),
      ];
    final repository = SlashCommandCatalogRepository(client: delegate.load);

    final first = await repository.loadForAdapter(
      'codex',
      workspaceId: 'workspace-a',
    );
    final second = await repository.loadForAdapter(
      'codex',
      workspaceId: 'workspace-b',
    );

    expect(first.single.command, '/alpha');
    expect(second.single.command, '/beta');
    expect(
      repository
          .commandsForAdapter('codex', workspaceId: 'workspace-a')
          .single
          .command,
      '/alpha',
    );
    expect(
      repository
          .commandsForAdapter('codex', workspaceId: 'workspace-b')
          .single
          .command,
      '/beta',
    );
    expect(delegate.calls, const <String>[
      'codex|workspace-a',
      'codex|workspace-b',
    ]);
  });

  test('force reload increments generation and updates cache', () async {
    final delegate = _FakeSlashCommandClient()
      ..responses['codex'] = const <SlashCommand>[
        SlashCommand(command: '/model', description: 'choose model'),
      ];
    final repository = SlashCommandCatalogRepository(client: delegate.load);

    await repository.loadForAdapter('codex');
    delegate.responses['codex'] = const <SlashCommand>[
      SlashCommand(command: '/status', description: 'show status'),
    ];
    await repository.loadForAdapter('codex', force: true);

    expect(
      repository.commandsForAdapter('codex').map((item) => item.command),
      const <String>['/status'],
    );
    expect(delegate.calls, const <String>['codex', 'codex']);
  });

  test('deduplicates commands by normalized key and keeps first item',
      () async {
    final delegate = _FakeSlashCommandClient()
      ..responses['codex'] = const <SlashCommand>[
        SlashCommand(command: '/Code-Review', description: 'first'),
        SlashCommand(command: '/code-review', description: 'second'),
        SlashCommand(command: 'compact', description: 'compact'),
      ];
    final repository = SlashCommandCatalogRepository(client: delegate.load);

    await repository.loadForAdapter('codex');

    final commands = repository.commandsForAdapter('codex');
    expect(commands.map((item) => item.command), const <String>[
      '/Code-Review',
      '/compact',
    ]);
    expect(commands.first.description, 'first');
  });

  test('late response for older generation does not overwrite newer cache',
      () async {
    final first = Completer<List<SlashCommand>>();
    final second = Completer<List<SlashCommand>>();
    var call = 0;
    final repository = SlashCommandCatalogRepository(
      client: (adapter, {workspaceId}) {
        call += 1;
        return call == 1 ? first.future : second.future;
      },
    );

    final firstLoad = repository.loadForAdapter('codex', force: true);
    final secondLoad = repository.loadForAdapter('codex', force: true);
    second.complete(const <SlashCommand>[
      SlashCommand(command: '/new', description: 'new result'),
    ]);
    await secondLoad;
    first.complete(const <SlashCommand>[
      SlashCommand(command: '/old', description: 'old result'),
    ]);
    await firstLoad;

    expect(
      repository.commandsForAdapter('codex').map((item) => item.command),
      const <String>['/new'],
    );
  });

  test('load failure records error and preserves existing cache', () async {
    final delegate = _FakeSlashCommandClient()
      ..responses['codex'] = const <SlashCommand>[
        SlashCommand(command: '/model', description: 'choose model'),
      ];
    final repository = SlashCommandCatalogRepository(client: delegate.load);
    await repository.loadForAdapter('codex');

    delegate.error = StateError('network failed');

    await expectLater(
      repository.loadForAdapter('codex', force: true),
      throwsA(isA<StateError>()),
    );
    expect(repository.errorForAdapter('codex'), isA<StateError>());
    expect(repository.commandsForAdapter('codex').single.command, '/model');
  });
}

class _FakeSlashCommandClient {
  final Map<String, List<SlashCommand>> responses =
      <String, List<SlashCommand>>{};
  final List<String> calls = <String>[];
  Object? error;

  Future<List<SlashCommand>> load(String adapter, {String? workspaceId}) async {
    final key = workspaceId == null ? adapter : '$adapter|$workspaceId';
    calls.add(key);
    final currentError = error;
    if (currentError != null) throw currentError;
    return responses[key] ?? const <SlashCommand>[];
  }
}
