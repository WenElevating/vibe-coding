import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/workflows/workspace/create_workspace_workflow.dart';

void main() {
  test('create succeeds only after refreshed list confirms workspace',
      () async {
    const created = WorkspaceSummary(
      id: 'workspace_new',
      name: 'New',
      path: r'D:\new',
    );
    final client = FakeWorkspaceCreationClient(
      createdWorkspace: created,
      listedWorkspaces: const <WorkspaceSummary>[created],
    );
    final workflow = CreateWorkspaceWorkflow(
      client: client,
      timeout: Duration(seconds: 1),
    );

    final outcome = await workflow.create(
      path: created.path,
      name: created.name,
    );

    expect(outcome, isA<CreateWorkspaceSuccess>());
    final success = outcome as CreateWorkspaceSuccess;
    expect(success.workspace, created);
    expect(success.workspaces, const <WorkspaceSummary>[created]);
    expect(client.createCalls, 1);
    expect(client.listCalls, 1);
  });

  test('create not confirmed can retry refresh without creating again',
      () async {
    const created = WorkspaceSummary(
      id: 'workspace_new',
      name: 'New',
      path: r'D:\new',
    );
    final client = FakeWorkspaceCreationClient(
      createdWorkspace: created,
      listedWorkspaces: const <WorkspaceSummary>[],
    );
    final workflow = CreateWorkspaceWorkflow(
      client: client,
      timeout: Duration(seconds: 1),
    );

    final first = await workflow.create(
      path: created.path,
      name: created.name,
    );

    expect(first, isA<CreateWorkspaceNotConfirmed>());
    client.listedWorkspaces = const <WorkspaceSummary>[created];
    final second = await workflow.retryRefresh(created.id);

    expect(second, isA<CreateWorkspaceSuccess>());
    expect(client.createCalls, 1);
    expect(client.listCalls, 2);
  });

  test('create failure returns failure outcome', () async {
    final error = StateError('boom');
    final client = FakeWorkspaceCreationClient(createError: error);
    final workflow = CreateWorkspaceWorkflow(
      client: client,
      timeout: Duration(seconds: 1),
    );

    final outcome = await workflow.create(path: r'D:\new');

    expect(outcome, isA<CreateWorkspaceFailure>());
    expect((outcome as CreateWorkspaceFailure).error, error);
    expect(client.listCalls, 0);
  });

  test('create timeout returns timeout outcome', () async {
    final client = FakeWorkspaceCreationClient(
      createCompleter: Completer<WorkspaceSummary>(),
    );
    final workflow = CreateWorkspaceWorkflow(
      client: client,
      timeout: Duration(milliseconds: 1),
    );

    final outcome = await workflow.create(path: r'D:\new');

    expect(outcome, isA<CreateWorkspaceTimeout>());
    expect(client.listCalls, 0);
  });
}

class FakeWorkspaceCreationClient implements WorkspaceCreationClient {
  FakeWorkspaceCreationClient({
    this.createdWorkspace = const WorkspaceSummary(
      id: 'workspace_new',
      name: 'New',
      path: r'D:\new',
    ),
    this.listedWorkspaces = const <WorkspaceSummary>[],
    this.createError,
    this.createCompleter,
  });

  WorkspaceSummary createdWorkspace;
  List<WorkspaceSummary> listedWorkspaces;
  Object? createError;
  Completer<WorkspaceSummary>? createCompleter;
  int createCalls = 0;
  int listCalls = 0;

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) async {
    createCalls += 1;
    final completer = createCompleter;
    if (completer != null) return completer.future;
    final error = createError;
    if (error != null) throw error;
    return createdWorkspace;
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    listCalls += 1;
    return listedWorkspaces;
  }
}
