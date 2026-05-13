import '../../../domain/repositories/conversation_repository.dart';
import '../../../domain/repositories/diagnostics_repository.dart';
import '../../../domain/repositories/run_repository.dart';
import '../../../domain/repositories/workspace_repository.dart';
import '../../../services/asr_model_manager.dart';

class WorkbenchDependencies {
  const WorkbenchDependencies({
    required this.asrModelManager,
    required this.conversationRepository,
    required this.diagnosticsRepository,
    required this.runRepository,
    required this.workspaceRepository,
  });

  final AsrModelManager asrModelManager;
  final ConversationRepository conversationRepository;
  final DiagnosticsRepository diagnosticsRepository;
  final RunRepository runRepository;
  final WorkspaceRepository workspaceRepository;
}
